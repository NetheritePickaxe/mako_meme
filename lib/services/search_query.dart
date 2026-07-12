import 'package:fuzzy/fuzzy.dart';
import '../models/meme.dart';
import '../models/folder.dart';

// ============================================================
// 命令定义 — 用于帮助和补全
// ============================================================

/// 单个命令的定义信息
class CommandDef {
  final String name;
  final List<String> aliases;
  final String description;
  final String usage;
  final List<String> examples;
  final bool multiValue;
  final bool hasValueSuggestions; // 是否有预定义的值建议

  const CommandDef({
    required this.name,
    required this.aliases,
    required this.description,
    required this.usage,
    required this.examples,
    required this.multiValue,
    this.hasValueSuggestions = false,
  });

  /// 所有命令定义
  static const all = [
    CommandDef(
      name: 'type',
      aliases: [],
      description: '类型或文件后缀。支持中文别名（表情/gif/图片/文字/立绘/CG/角色卡）或后缀（.png/.ico 等）',
      usage: 'type=<类型|后缀>',
      examples: ['type=图片', 'type=.png', 'type=!表情包', 'type={gif,image}'],
      multiValue: true,
      hasValueSuggestions: true,
    ),
    CommandDef(
      name: 'tag',
      aliases: ['#'],
      description: '标签匹配。支持多值和反选',
      usage: 'tag=<标签名>',
      examples: ['tag=开心', 'tag={开心,喜欢}', 'tag=!讨厌'],
      multiValue: true,
      hasValueSuggestions: true,
    ),
    CommandDef(
      name: '@',
      aliases: ['folder'],
      description: '文件夹名匹配。支持多值',
      usage: '@=<文件夹名>',
      examples: ['@=文件夹1', 'folder=我的收藏', '@={文件夹1,文件夹2}'],
      multiValue: true,
      hasValueSuggestions: true,
    ),
    CommandDef(
      name: 'name',
      aliases: [],
      description: '文件名匹配。默认 ~ 包含匹配，可用 =精确 ≈模糊',
      usage: 'name[op]<文件名>',
      examples: ['name~这是', 'name=精确名', 'name≈表情'],
      multiValue: false,
    ),
    CommandDef(
      name: 'x',
      aliases: [],
      description: '横向（宽度）像素。支持范围(..)和单位(cm/mm/in/pt)',
      usage: 'x=<数值>[..<数值>][单位]',
      examples: ['x=100', 'x=100..', 'x=..100', 'x=50..100', 'x=30cm'],
      multiValue: false,
    ),
    CommandDef(
      name: 'y',
      aliases: [],
      description: '竖向（高度）像素。支持范围(..)和单位',
      usage: 'y=<数值>[..<数值>][单位]',
      examples: ['y=100', 'y=..200', 'y=50..100mm'],
      multiValue: false,
    ),
    CommandDef(
      name: 'w',
      aliases: [],
      description: '较长边像素（max(宽,高)）。支持范围和单位',
      usage: 'w=<数值>[..<数值>][单位]',
      examples: ['w=1920', 'w=1000..', 'w=10..50cm'],
      multiValue: false,
    ),
    CommandDef(
      name: 'h',
      aliases: [],
      description: '较短边像素（min(宽,高)）。支持范围和单位',
      usage: 'h=<数值>[..<数值>][单位]',
      examples: ['h=1080', 'h=..500', 'h=5..20cm'],
      multiValue: false,
    ),
    CommandDef(
      name: 'xy',
      aliases: [],
      description: '宽高比（宽:高）。=精确 ≈模糊。横向>1 竖向<1',
      usage: 'xy[op]<宽:高|比值>',
      examples: ['xy=16:9', 'xy≈2:1', 'xy≈1:2', 'xy=1.78'],
      multiValue: false,
    ),
    CommandDef(
      name: 'wh',
      aliases: [],
      description: '长短边比（max:min，始终≥1）。=精确 ≈模糊',
      usage: 'wh[op]<长:短|比值>',
      examples: ['wh=16:9', 'wh≈2:1', 'wh=1.78'],
      multiValue: false,
    ),
    CommandDef(
      name: 'regex',
      aliases: [],
      description: '正则匹配文件名',
      usage: 'regex=<正则表达式>',
      examples: ['regex=.*表情.*', 'regex=^IMG_\\d+'],
      multiValue: false,
    ),
  ];

  /// 按名称或别名查找
  static CommandDef? find(String key) {
    final k = key.toLowerCase();
    for (final c in all) {
      if (c.name == k || c.aliases.contains(k)) return c;
    }
    return null;
  }
}

/// 补全建议项
class SearchSuggestion {
  final String display;
  final String insert;
  final String? description;
  const SearchSuggestion(this.display, this.insert, {this.description});
}

// ============================================================
// 搜索 DSL 主类
// ============================================================

/// 搜索 DSL：支持 `/[选择器]` 命令模式和增强的普通搜索。
class SearchQuery {
  /// 解析搜索字符串，返回匹配函数。
  static bool Function(Meme) parse(String query, List<MemeFolder> folders) {
    final q = query.trim();
    if (q.isEmpty || isHelpRequest(q) || isCommandHelpRequest(q) != null) {
      return (_) => true;
    }
    if (q.startsWith('/')) {
      return _parseCommand(q.substring(1), folders);
    }
    return _parsePlain(q, folders);
  }

  // ===== 帮助检测 =====

  /// 是否为完整帮助请求（/? 或 /help 或 /？）
  static bool isHelpRequest(String query) {
    final q = query.trim();
    return q == '/?' || q == '/？' || q == '/help';
  }

  /// 是否为单个命令帮助请求（如 /tag ? 或 /tag?）
  /// 返回命令名，如果不是则返回 null
  static String? isCommandHelpRequest(String query) {
    final q = query.trim();
    // /tag ? 或 /tag? 或 /tag ？或 /tag？
    final match = RegExp(r'^/(\w+)\s*[?？]\s*$').firstMatch(q);
    if (match != null) {
      final cmd = match.group(1)!.toLowerCase();
      if (CommandDef.find(cmd) != null) return cmd;
    }
    return null;
  }

  /// 生成完整帮助文本
  static String generateHelpText() {
    final sb = StringBuffer();
    sb.writeln('搜索命令帮助');
    sb.writeln('=' * 40);
    sb.writeln();
    sb.writeln('命令模式：/[选择器]');
    sb.writeln('多个条件用逗号分隔（AND），多值用 {a,b}（OR）');
    sb.writeln('! 前缀反选，= 精确，~ 包含，≈ 模糊');
    sb.writeln('范围：100..（≥）、..100（≤）、50..100（之间）');
    sb.writeln('单位：px(默认) cm mm in pt');
    sb.writeln();
    for (final cmd in CommandDef.all) {
      sb.writeln('─' * 30);
      sb.writeln('  ${cmd.name}${cmd.aliases.isNotEmpty ? " (别名: ${cmd.aliases.join(', ')})" : ""}');
      sb.writeln('  ${cmd.description}');
      sb.writeln('  用法: ${cmd.usage}');
      sb.writeln('  示例:');
      for (final ex in cmd.examples) {
        sb.writeln('    $ex');
      }
      sb.writeln('  多值: ${cmd.multiValue ? "是" : "否"}');
      sb.writeln();
    }
    sb.writeln('─' * 30);
    sb.writeln('普通搜索（不以 / 开头）:');
    sb.writeln('  * 任意字符序列，? 单个字符');
    sb.writeln('  #标签  按标签搜索');
    sb.writeln('  @文件夹  按文件夹搜索');
    sb.writeln('  纯文本  fuzzy 模糊匹配');
    return sb.toString();
  }

  /// 生成单个命令帮助文本
  static String generateCommandHelpText(String cmdName) {
    final cmd = CommandDef.find(cmdName);
    if (cmd == null) return '未知命令: $cmdName';
    final sb = StringBuffer();
    sb.writeln('命令: ${cmd.name}${cmd.aliases.isNotEmpty ? " (别名: ${cmd.aliases.join(', ')})" : ""}');
    sb.writeln('=' * 30);
    sb.writeln(cmd.description);
    sb.writeln();
    sb.writeln('用法: ${cmd.usage}');
    sb.writeln('多值: ${cmd.multiValue ? "是（可用 {a,b} 或重复出现）" : "否（重复时后者覆盖）"}');
    sb.writeln();
    sb.writeln('示例:');
    for (final ex in cmd.examples) {
      sb.writeln('  $ex');
    }
    return sb.toString();
  }

  // ===== 自动补全 =====

  /// 根据当前输入返回补全建议。
  /// [allTags] 所有标签，[folders] 所有文件夹
  static List<SearchSuggestion> getSuggestions(
    String query,
    List<String> allTags,
    List<MemeFolder> folders,
  ) {
    final q = query.trim();
    if (!q.startsWith('/')) return [];

    // 帮助请求不补全
    if (isHelpRequest(q) || isCommandHelpRequest(q) != null) return [];

    // 提取 / 之后的内容，去掉方括号
    var afterSlash = q.substring(1);
    // 去掉所有方括号，简化处理
    afterSlash = afterSlash.replaceAll('[', '').replaceAll(']', '');

    // 按逗号分割（忽略 {} 内的），取最后一部分
    final parts = _splitTopLevel(afterSlash, ',');
    if (parts.isEmpty) return [];
    final lastPart = parts.last.trim();

    // 检测是否有 ! 前缀
    bool negate = false;
    String keyInput = lastPart;
    if (keyInput.startsWith('!')) {
      negate = true;
      keyInput = keyInput.substring(1);
    }

    // 检测是否已有操作符
    final opMatch = RegExp(r'^([a-zA-Z@#]+)\s*[=≈~]').firstMatch(keyInput);
    if (opMatch == null) {
      // 正在输入 key，建议 key
      final keyStr = keyInput.toLowerCase();
      final prefix = negate ? '!' : '';
      return CommandDef.all
          .where((c) => c.name.startsWith(keyStr) || c.aliases.any((a) => a.startsWith(keyStr)))
          .map((c) => SearchSuggestion(
                '$prefix${c.name}',
                '$prefix${c.name}=',
                description: c.description,
              ))
          .toList();
    }

    // 已有操作符，建议 value
    final keyStr = opMatch.group(1)!.toLowerCase();
    final opIdx = keyInput.indexOf(RegExp(r'[=≈~]'));
    final valuePart = keyInput.substring(opIdx + 1);

    return _getValueSuggestions(keyStr, valuePart, allTags, folders);
  }

  static List<SearchSuggestion> _getValueSuggestions(
    String keyStr,
    String valuePart,
    List<String> allTags,
    List<MemeFolder> folders,
  ) {
    final cmd = CommandDef.find(keyStr);
    if (cmd == null) return [];

    // 去掉 ! 前缀（value 部分不应该有 !）
    final v = valuePart.replaceAll('!', '').toLowerCase();

    switch (cmd.name) {
      case 'type':
        const typeValues = [
          '表情', 'gif', '图片', '文字', '立绘', 'cg', '角色卡',
          '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.bmp',
        ];
        return typeValues
            .where((t) => t.toLowerCase().startsWith(v))
            .map((t) => SearchSuggestion(t, t))
            .toList();
      case 'tag':
      case '#':
        return allTags
            .where((t) => t.toLowerCase().startsWith(v))
            .map((t) => SearchSuggestion(t, t))
            .toList();
      case '@':
      case 'folder':
        return folders
            .map((f) => f.name)
            .where((n) => n.toLowerCase().startsWith(v))
            .map((n) => SearchSuggestion(n, n))
            .toList();
      case 'xy':
      case 'wh':
        const ratios = ['1:1', '4:3', '3:2', '16:9', '9:16', '2:1', '1:2', '3:4', '4:5', '21:9'];
        return ratios
            .where((r) => r.startsWith(v))
            .map((r) => SearchSuggestion(r, r))
            .toList();
      default:
        return [];
    }
  }

  /// 获取补全用的原始分割部分（公开方法，供搜索框 UI 使用）
  static List<String> getSuggestionsRawParts(String query) {
    if (!query.startsWith('/')) return [];
    var afterSlash = query.substring(1);
    afterSlash = afterSlash.replaceAll('[', '').replaceAll(']', '');
    return _splitTopLevel(afterSlash, ',');
  }

  // ===== 命令模式解析 =====

  static bool Function(Meme) _parseCommand(String s, List<MemeFolder> folders) {
    s = s.trim();
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

  /// 按分隔符拆分，但忽略 {...} 内的分隔符
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

  static _Condition? _parseCondition(String s, List<MemeFolder> folders) {
    bool negate = false;
    if (s.startsWith('!')) {
      negate = true;
      s = s.substring(1).trim();
    }

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

    // 解析 value
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
        return _ConditionKey.width;
      case 'y':
        return _ConditionKey.height;
      case 'w':
        return _ConditionKey.longSide;
      case 'h':
        return _ConditionKey.shortSide;
      case 'xy':
        return _ConditionKey.ratioXY;
      case 'wh':
        return _ConditionKey.ratioWH;
      case 'regex':
        return _ConditionKey.regex;
      default:
        return null;
    }
  }

  // ===== 普通模式 =====

  static bool Function(Meme) _parsePlain(String q, List<MemeFolder> folders) {
    if (q.startsWith('#')) {
      final tagQuery = q.substring(1).toLowerCase();
      return (m) => m.tags.any((t) => _wildcardMatch(t.toLowerCase(), tagQuery));
    }
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
    if (q.contains('*') || q.contains('?')) {
      final pattern = q.toLowerCase();
      return (m) =>
          _wildcardMatch(m.name.toLowerCase(), pattern) ||
          m.tags.any((t) => _wildcardMatch(t.toLowerCase(), pattern));
    }
    return (m) {
      final haystack = '${m.name} ${m.tags.join(' ')}'.toLowerCase();
      final needle = q.toLowerCase();
      if (haystack.contains(needle)) return true;
      final fuse = Fuzzy([haystack], options: FuzzyOptions(threshold: 0.3));
      final results = fuse.search(needle);
      return results.any((r) => r.score < 0.7);
    };
  }

  static bool _wildcardMatch(String text, String pattern) {
    if (!pattern.contains('*') && !pattern.contains('?')) {
      return text.contains(pattern);
    }
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

// ============================================================
// 内部类
// ============================================================

enum _ConditionKey {
  type, tag, folder, name,
  width, height,         // x, y
  longSide, shortSide,   // w, h
  ratioXY, ratioWH,      // xy, wh
  regex,
}

class _Condition {
  final _ConditionKey key;
  final String op;
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
        return values.any((v) => _matchType(m, v));
      case _ConditionKey.tag:
        return values.any((v) => m.tags.any((t) => _matchString(t, v, op)));
      case _ConditionKey.folder:
        final matchedFolderIds = <String>{};
        for (final v in values) {
          for (final f in folders) {
            if (_matchString(f.name, v, op)) {
              matchedFolderIds.add(f.id);
            }
          }
        }
        return m.folderId != null && matchedFolderIds.contains(m.folderId);
      case _ConditionKey.name:
        return _matchString(m.name, values.first, op);
      case _ConditionKey.width:
        final matcher = _DimensionMatcher.parse(values.first);
        return matcher != null && matcher.match(m.width);
      case _ConditionKey.height:
        final matcher = _DimensionMatcher.parse(values.first);
        return matcher != null && matcher.match(m.height);
      case _ConditionKey.longSide:
        final matcher = _DimensionMatcher.parse(values.first);
        if (matcher == null) return false;
        final longSide = m.width > m.height ? m.width : m.height;
        return matcher.match(longSide);
      case _ConditionKey.shortSide:
        final matcher = _DimensionMatcher.parse(values.first);
        if (matcher == null) return false;
        final shortSide = m.width > m.height ? m.height : m.width;
        return matcher.match(shortSide);
      case _ConditionKey.ratioXY:
        return _matchRatio(m.width, m.height, values.first, op, false);
      case _ConditionKey.ratioWH:
        return _matchRatio(m.width, m.height, values.first, op, true);
      case _ConditionKey.regex:
        return _matchRegex(m.name, values.first);
    }
  }

  /// 类型匹配：支持中文别名 + 文件后缀
  static bool _matchType(Meme m, String query) {
    final q = query.toLowerCase().trim();
    // 文件后缀匹配（以 . 开头）
    if (q.startsWith('.')) {
      if (m.filePath.isEmpty) return false;
      final ext = m.filePath.toLowerCase();
      // filePath 格式: memes/uuid.png
      final dotIdx = ext.lastIndexOf('.');
      if (dotIdx == -1) return false;
      final fileExt = ext.substring(dotIdx);
      return fileExt == q;
    }
    // 英文常量
    if (m.type == q) return true;
    // 中文别名
    const cnMap = {
      '表情': Meme.typeEmoji, '表情包': Meme.typeEmoji,
      '动图': Meme.typeGif,
      '图片': Meme.typeImage,
      '文字': Meme.typeText,
      '立绘': Meme.typePortrait,
      '角色卡': Meme.typeCharacterCard,
    };
    final mapped = cnMap[q];
    return mapped != null && mapped == m.type;
  }

  /// 按 op 匹配字符串
  static bool _matchString(String target, String query, String op) {
    final t = target.toLowerCase();
    final q = query.toLowerCase();
    switch (op) {
      case '=':
        return t == q;
      case '~':
        return t.contains(q);
      case '≈':
        final fuse = Fuzzy([t], options: FuzzyOptions(threshold: 0.3));
        return fuse.search(q).any((r) => r.score < 0.7);
      default:
        return t.contains(q);
    }
  }

  /// 比例匹配
  /// [isWH] true=wh(长短边比,始终≥1), false=xy(宽高比)
  static bool _matchRatio(int width, int height, String query, String op, bool isWH) {
    if (width <= 0 || height <= 0) return false;
    final actualRatio = isWH
        ? (width > height ? width / height : height / width)
        : width / height;

    final q = query.trim();
    double? targetRatio;

    if (q.contains(':')) {
      final parts = q.split(':');
      if (parts.length != 2) return false;
      final w = double.tryParse(parts[0]);
      final h = double.tryParse(parts[1]);
      if (w == null || h == null || h == 0) return false;
      targetRatio = w / h;
    } else {
      targetRatio = double.tryParse(q);
    }
    if (targetRatio == null || targetRatio == 0) return false;

    switch (op) {
      case '≈':
        // 模糊匹配：容差为目标值的 15%
        final tolerance = (targetRatio * 0.15).abs();
        return (actualRatio - targetRatio).abs() <= tolerance;
      default:
        // 精确匹配
        return (actualRatio - targetRatio).abs() < 0.01;
    }
  }

  static bool _matchRegex(String target, String pattern) {
    try {
      return RegExp(pattern, caseSensitive: false).hasMatch(target);
    } catch (_) {
      return false;
    }
  }
}

/// 尺寸匹配器：支持范围(..)和单位转换(cm/mm/in/pt)
class _DimensionMatcher {
  final int? minPx;
  final int? maxPx;

  _DimensionMatcher({this.minPx, this.maxPx});

  /// 单位→像素转换系数（基于 96 DPI）
  static const _unitMultipliers = <String, double>{
    'px': 1.0,
    'in': 96.0,
    'cm': 37.795275590551, // 96 / 2.54
    'mm': 3.7795275590551, // 96 / 25.4
    'pt': 1.3333333333333, // 96 / 72
  };

  static _DimensionMatcher? parse(String input) {
    final raw = input.trim();

    // 提取单位后缀
    String unit = 'px';
    String numPart = raw;
    for (final u in ['cm', 'mm', 'in', 'pt']) {
      if (raw.toLowerCase().endsWith(u)) {
        unit = u;
        numPart = raw.substring(0, raw.length - u.length).trim();
        break;
      }
    }
    final multiplier = _unitMultipliers[unit] ?? 1.0;

    // 解析范围
    if (numPart.contains('..')) {
      final parts = numPart.split('..');
      if (parts.length != 2) return null;
      int? minPx;
      int? maxPx;
      if (parts[0].isNotEmpty) {
        final v = double.tryParse(parts[0]);
        if (v == null) return null;
        minPx = (v * multiplier).round();
      }
      if (parts[1].isNotEmpty) {
        final v = double.tryParse(parts[1]);
        if (v == null) return null;
        maxPx = (v * multiplier).round();
      }
      // 全为空（如 ".."）→ 无效
      if (minPx == null && maxPx == null) return null;
      return _DimensionMatcher(minPx: minPx, maxPx: maxPx);
    }

    // 精确值
    final v = double.tryParse(numPart);
    if (v == null) return null;
    final px = (v * multiplier).round();
    return _DimensionMatcher(minPx: px, maxPx: px);
  }

  bool match(int value) {
    if (minPx != null && value < minPx!) return false;
    if (maxPx != null && value > maxPx!) return false;
    return true;
  }
}
