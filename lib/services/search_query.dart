import 'package:fuzzy/fuzzy.dart';
import '../models/meme.dart';
import '../models/folder.dart';

/// 搜索 DSL：支持 `/[选择器]` 命令模式和增强的普通搜索。
///
/// ## 命令模式
/// 以 `/` 开头，后跟 `[...]` 选择器。例：`/[type=图片,@=文件夹1,tag=开心]`
///
/// ### 选择器语法
/// - 多个条件用逗号 `,` 分隔，AND 语义
/// - `key op value`，op ∈ {`=`, `≈`, `~`}，默认 `=`
/// - `!` 前缀反选：`tag=!喜欢`、`type=!表情包`
/// - `tag`、`type`、`@` 可多值（OR 语义）：`tag={开心,喜欢}` 或 `tag=开心,tag=喜欢`
/// - `name`、`x`/`w`、`y`/`h`、`xy`/`wh` 不可多值（后者覆盖）
///
/// ### 支持的 key
/// | key | 别名 | 说明 | 默认 op | 多值 |
/// |-----|------|------|---------|------|
/// | type | - | 类型（emoji/gif/image/text/portrait/cg/character_card） | = | 是 |
/// | tag | # | 标签 | = | 是 |
/// | @ | folder | 文件夹名 | = | 是 |
/// | name | - | 文件名 | ~ | 否 |
/// | x | w | 宽度（像素） | = | 否 |
/// | y | h | 高度（像素） | = | 否 |
/// | xy | wh | 宽高比（如 16:9） | = | 否 |
/// | regex | - | 正则匹配 name | - | 否 |
///
/// ### 操作符
/// - `=` 精确匹配（type/tag/尺寸/比例）
/// - `~` 包含匹配（name 默认）
/// - `≈` 模糊匹配（fuzzy）
///
/// ## 普通模式
/// 不以 `/` 开头。支持：
/// - `*` 任意字符序列、`?` 单个字符（通配符）
/// - `#tag` 按标签搜索
/// - `@folder` 按文件夹名搜索
/// - 否则走 fuzzy 搜索（name + tags）
class SearchQuery {
  /// 解析搜索字符串，返回匹配函数。
  /// [folders] 用于 `@folder` 名称→ID 映射。
  static bool Function(Meme) parse(String query, List<MemeFolder> folders) {
    final q = query.trim();
    if (q.isEmpty) return (_) => true;

    if (q.startsWith('/')) {
      return _parseCommand(q.substring(1), folders);
    }
    return _parsePlain(q, folders);
  }

  // ===== 命令模式 =====

  static bool Function(Meme) _parseCommand(String s, List<MemeFolder> folders) {
    s = s.trim();
    // 提取所有 [...] 选择器（可能有多个，之间是 AND）
    final conditions = <_Condition>[];
    int i = 0;
    while (i < s.length) {
      if (s[i] == '[') {
        final end = _findMatchingBracket(s, i);
        if (end == -1) break;
        final inner = s.substring(i + 1, end);
        conditions.addAll(_parseConditions(inner, folders));
        i = end + 1;
      } else {
        i++;
      }
    }
    if (conditions.isEmpty) return (_) => true;
    return (m) => conditions.every((c) => c.match(m));
  }

  /// 找到 `[` 对应的 `]`（考虑嵌套 `{}`）
  static int _findMatchingBracket(String s, int start) {
    int depth = 0;
    for (int i = start; i < s.length; i++) {
      final ch = s[i];
      if (ch == '[') {
        depth++;
      } else if (ch == ']') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// 解析选择器内的条件列表（逗号分隔，但 `{...}` 内的逗号不算分隔符）
  static List<_Condition> _parseConditions(String inner, List<MemeFolder> folders) {
    final parts = _splitTopLevel(inner, ',');
    final conditions = <_Condition>[];
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final cond = _parseCondition(trimmed, folders);
      if (cond != null) conditions.add(cond);
    }
    return conditions;
  }

  /// 按分隔符拆分，但忽略 `{...}` 内的分隔符
  static List<String> _splitTopLevel(String s, String sep) {
    final result = <String>[];
    final buf = StringBuffer();
    int braceDepth = 0;
    int i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (ch == '{') {
        braceDepth++;
        buf.write(ch);
      } else if (ch == '}') {
        if (braceDepth > 0) braceDepth--;
        buf.write(ch);
      } else if (braceDepth == 0 && s.startsWith(sep, i)) {
        result.add(buf.toString());
        buf.clear();
        i += sep.length;
        continue;
      } else {
        buf.write(ch);
      }
      i++;
    }
    if (buf.isNotEmpty) result.add(buf.toString());
    return result;
  }

  /// 解析单个条件：`[!]key[op]value` 或 `[!]key=value{v1,v2}`
  static _Condition? _parseCondition(String s, List<MemeFolder> folders) {
    bool negate = false;
    int i = 0;
    if (s.startsWith('!')) {
      negate = true;
      i = 1;
    }
    s = s.substring(i).trim();

    // 解析 key
    final keyMatch = RegExp(r'^([a-zA-Z@#]+)').firstMatch(s);
    if (keyMatch == null) return null;
    final keyStr = keyMatch.group(1)!.toLowerCase();
    s = s.substring(keyMatch.end);

    // 解析 op（可选）
    String op = '=';
    if (s.startsWith('≈')) {
      op = '≈';
      s = s.substring(1);
    } else if (s.startsWith('~')) {
      op = '~';
      s = s.substring(1);
    } else if (s.startsWith('=')) {
      op = '=';
      s = s.substring(1);
    }
    s = s.trim();
    if (s.isEmpty) return null;

    // 解析 value（可能是 {v1,v2} 或单个值）
    List<String> values;
    if (s.startsWith('{') && s.endsWith('}')) {
      values = _splitTopLevel(s.substring(1, s.length - 1), ',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      values = [s];
    }

    final key = _normalizeKey(keyStr);
    if (key == null) return null;

    return _Condition(
      key: key,
      op: op,
      values: values,
      negate: negate,
      folders: folders,
    );
  }

  /// key 别名归一化
  static _ConditionKey? _normalizeKey(String k) {
    switch (k) {
      case 'type':
        return _ConditionKey.type;
      case 'tag':
      case '#':
        return _ConditionKey.tag;
      case '@':
      case 'folder':
        return _ConditionKey.folder;
      case 'name':
        return _ConditionKey.name;
      case 'x':
      case 'w':
        return _ConditionKey.width;
      case 'y':
      case 'h':
        return _ConditionKey.height;
      case 'xy':
      case 'wh':
        return _ConditionKey.ratio;
      case 'regex':
        return _ConditionKey.regex;
      default:
        return null;
    }
  }

  // ===== 普通模式 =====

  static bool Function(Meme) _parsePlain(String q, List<MemeFolder> folders) {
    // #tag 搜索
    if (q.startsWith('#')) {
      final tagQuery = q.substring(1).toLowerCase();
      return (m) => m.tags.any((t) => _wildcardMatch(t.toLowerCase(), tagQuery));
    }
    // @folder 搜索
    if (q.startsWith('@')) {
      final folderQuery = q.substring(1).toLowerCase();
      final matchedFolderIds = folders
          .where((f) =>
              f.name.toLowerCase().contains(folderQuery) ||
              _wildcardMatch(f.name.toLowerCase(), folderQuery))
          .map((f) => f.id)
          .toSet();
      return (m) => m.folderId != null && matchedFolderIds.contains(m.folderId);
    }
    // 通配符搜索（含 * 或 ?）
    if (q.contains('*') || q.contains('?')) {
      final pattern = q.toLowerCase();
      return (m) =>
          _wildcardMatch(m.name.toLowerCase(), pattern) ||
          m.tags.any((t) => _wildcardMatch(t.toLowerCase(), pattern));
    }
    // fuzzy 搜索（默认）
    // 注意：fuzzy 需要预构建索引，这里返回一个闭包，在调用时构建
    // 为性能考虑，调用方应缓存。这里简单实现：每次调用做 contains + fuzzy
    return (m) {
      final haystack = '${m.name} ${m.tags.join(' ')}'.toLowerCase();
      final needle = q.toLowerCase();
      // 先快速 contains 检查
      if (haystack.contains(needle)) return true;
      // 再走 fuzzy
      final fuse = Fuzzy([haystack], options: FuzzyOptions(threshold: 0.3));
      final results = fuse.search(needle);
      return results.any((r) => r.score < 0.7);
    };
  }

  /// 通配符匹配：`*` 匹配任意字符序列，`?` 匹配单个字符
  static bool _wildcardMatch(String text, String pattern) {
    if (!pattern.contains('*') && !pattern.contains('?')) {
      return text.contains(pattern);
    }
    // 构建正则
    final sb = StringBuffer('^');
    for (int i = 0; i < pattern.length; i++) {
      final ch = pattern[i];
      if (ch == '*') {
        sb.write('.*');
      } else if (ch == '?') {
        sb.write('.');
      } else {
        sb.write(RegExp.escape(ch));
      }
    }
    sb.write(r'$');
    return RegExp(sb.toString(), caseSensitive: false).hasMatch(text);
  }
}

/// 条件 key 枚举
enum _ConditionKey { type, tag, folder, name, width, height, ratio, regex }

/// 单个匹配条件
class _Condition {
  final _ConditionKey key;
  final String op; // =, ~, ≈
  final List<String> values;
  final bool negate;
  final List<MemeFolder> folders;

  _Condition({
    required this.key,
    required this.op,
    required this.values,
    required this.negate,
    required this.folders,
  });

  bool match(Meme m) {
    final result = _matchInner(m);
    return negate ? !result : result;
  }

  bool _matchInner(Meme m) {
    switch (key) {
      case _ConditionKey.type:
        // type 支持中文别名
        return values.any((v) => _matchType(m.type, v));
      case _ConditionKey.tag:
        return values.any((v) => m.tags.any((t) => _matchValue(t, v, op)));
      case _ConditionKey.folder:
        // @=文件夹名，匹配 folderId
        final matchedFolderIds = <String>{};
        for (final v in values) {
          for (final f in folders) {
            if (_matchValue(f.name, v, op)) {
              matchedFolderIds.add(f.id);
            }
          }
        }
        return m.folderId != null && matchedFolderIds.contains(m.folderId);
      case _ConditionKey.name:
        // name 不可多值，取第一个
        return _matchValue(m.name, values.first, op);
      case _ConditionKey.width:
        return _matchInt(m.width, values.first);
      case _ConditionKey.height:
        return _matchInt(m.height, values.first);
      case _ConditionKey.ratio:
        return _matchRatio(m.width, m.height, values.first);
      case _ConditionKey.regex:
        return _matchRegex(m.name, values.first);
    }
  }

  /// 类型匹配（支持中文别名）
  static bool _matchType(String memeType, String query) {
    final q = query.toLowerCase().trim();
    // 英文常量直接比较
    if (memeType == q) return true;
    // 中文别名
    const cnMap = {
      '表情': Meme.typeEmoji,
      '表情包': Meme.typeEmoji,
      'gif': Meme.typeGif,
      '动图': Meme.typeGif,
      '图片': Meme.typeImage,
      '文字': Meme.typeText,
      '立绘': Meme.typePortrait,
      'cg': Meme.typeCg,
      '角色卡': Meme.typeCharacterCard,
    };
    final mapped = cnMap[q];
    return mapped != null && mapped == memeType;
  }

  /// 按 op 匹配字符串
  static bool _matchValue(String target, String query, String op) {
    final t = target.toLowerCase();
    final q = query.toLowerCase();
    switch (op) {
      case '=':
        return t == q;
      case '~':
        return t.contains(q);
      case '≈':
        final fuse = Fuzzy([t], options: FuzzyOptions(threshold: 0.3));
        final results = fuse.search(q);
        return results.any((r) => r.score < 0.7);
      default:
        return t.contains(q);
    }
  }

  /// 精确整数匹配
  static bool _matchInt(int target, String query) {
    final q = int.tryParse(query.trim());
    if (q == null) return false;
    return target == q;
  }

  /// 比例匹配，支持 `16:9` 或 `1.78` 形式
  static bool _matchRatio(int width, int height, String query) {
    if (width <= 0 || height <= 0) return false;
    final memeRatio = width / height;
    final q = query.trim();
    if (q.contains(':')) {
      final parts = q.split(':');
      if (parts.length != 2) return false;
      final w = int.tryParse(parts[0]);
      final h = int.tryParse(parts[1]);
      if (w == null || h == null || h == 0) return false;
      return (memeRatio - w / h).abs() < 0.01;
    }
    final targetRatio = double.tryParse(q);
    if (targetRatio == null || targetRatio == 0) return false;
    return (memeRatio - targetRatio).abs() < 0.01;
  }

  /// 正则匹配
  static bool _matchRegex(String target, String pattern) {
    try {
      return RegExp(pattern, caseSensitive: false).hasMatch(target);
    } catch (_) {
      return false;
    }
  }
}
