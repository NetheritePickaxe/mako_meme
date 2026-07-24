import 'package:fuzzy/fuzzy.dart';
import '../models/meme.dart';
import '../models/folder.dart';

// ============================================================
// 解析结果类型
// ============================================================

/// 搜索查询的解析结果。
/// 分为三种：普通搜索、纯选择器筛选、命令（执行操作）。
sealed class ParseResult {
  const ParseResult();

  /// 转为匹配函数（命令类型返回匹配选择器部分，用于预览将要影响的 meme）
  bool Function(Meme) asMatcher(List<MemeFolder> folders);
}

/// 普通搜索：fuzzy / 通配符 / #tag / @folder
class PlainSearch extends ParseResult {
  final String query;
  const PlainSearch(this.query);

  @override
  bool Function(Meme) asMatcher(List<MemeFolder> folders) =>
      SearchQuery._matchPlain(query, folders);
}

/// 纯选择器筛选：`[x=100,type=图片]`
class SelectorSearch extends ParseResult {
  final List<Condition> conditions;
  const SelectorSearch(this.conditions);

  @override
  bool Function(Meme) asMatcher(List<MemeFolder> folders) =>
      (m) => conditions.every((c) => c.match(m));
}

/// 命令：`/tag [选择器] add 喜欢`
class CommandSearch extends ParseResult {
  final String command; // tag / help
  final List<Condition> selector; // 选择器条件（可能为空=全部）
  final String action; // add / remove / set 等
  final List<String> args; // 命令参数

  const CommandSearch({
    required this.command,
    required this.selector,
    required this.action,
    required this.args,
  });

  @override
  bool Function(Meme) asMatcher(List<MemeFolder> folders) =>
      (m) => selector.every((c) => c.match(m));
}

// ============================================================
// 定义 — 用于帮助和补全
// ============================================================

/// 选择器内可用的条件 key（不含 # @，它们是独立前缀）
class SelectorKey {
  final String name;
  final String description;
  final String usage;
  final List<String> examples;
  final bool multiValue;

  const SelectorKey({
    required this.name,
    required this.description,
    required this.usage,
    required this.examples,
    required this.multiValue,
  });

  static const all = [
    SelectorKey(
      name: 'type',
      description: '类型或文件后缀。中文别名：表情/gif/图片/文字/立绘/CG/角色卡；后缀以 . 开头',
      usage: '[!]type(=|~|≈)(<类型>|<.后缀>|{<类型列表>})',
      examples: ['type=图片', 'type=.png', '!type=表情包', 'type={gif,image}'],
      multiValue: true,
    ),
    SelectorKey(
      name: 'tag',
      description: '标签。= 与匹配（含所有值），~ 或匹配（含任一，需{列表}），≈ 模糊或匹配（需{列表}），单值仅 =',
      usage: '[!]tag(=|~|≈)(<标签名>|{<标签列表>})',
      examples: ['tag=开心', 'tag={开心,喜欢}', 'tag~{开心,喜欢}', '!tag=讨厌'],
      multiValue: true,
    ),
    SelectorKey(
      name: 'folder',
      description: '文件夹名匹配（选择器内用 folder=，独立前缀用 @）',
      usage: '[!]folder(=|~|≈)(<文件夹名>|{<文件夹列表>})',
      examples: ['folder=文件夹1', 'folder={文件夹1,文件夹2}'],
      multiValue: true,
    ),
    SelectorKey(
      name: 'name',
      description: '文件名。= 精确，~ 包含，≈ 模糊',
      usage: '[!]name(=|~|≈)<文件名>',
      examples: ['name~这是', 'name=精确名', 'name≈表情'],
      multiValue: false,
    ),
    SelectorKey(
      name: 'x',
      description: '横向（宽度）像素。.. 表示范围，单位默认 px',
      usage: '[!]x(=|~|≈)<数值>[..<数值>][cm|mm|in|pt]',
      examples: ['x=100', 'x=100..', 'x=..100', 'x=50..100', 'x=30cm'],
      multiValue: false,
    ),
    SelectorKey(
      name: 'y',
      description: '竖向（高度）像素。.. 表示范围，单位默认 px',
      usage: '[!]y(=|~|≈)<数值>[..<数值>][cm|mm|in|pt]',
      examples: ['y=100', 'y=..200', 'y=50..100mm'],
      multiValue: false,
    ),
    SelectorKey(
      name: 'w',
      description: '较长边像素 max(宽,高)。.. 表示范围，单位默认 px',
      usage: '[!]w(=|~|≈)<数值>[..<数值>][cm|mm|in|pt]',
      examples: ['w=1920', 'w=1000..', 'w=10..50cm'],
      multiValue: false,
    ),
    SelectorKey(
      name: 'h',
      description: '较短边像素 min(宽,高)。.. 表示范围，单位默认 px',
      usage: '[!]h(=|~|≈)<数值>[..<数值>][cm|mm|in|pt]',
      examples: ['h=1080', 'h=..500', 'h=5..20cm'],
      multiValue: false,
    ),
    SelectorKey(
      name: 'xy',
      description: '宽高比（宽:高）。= 精确，≈ 模糊（15% 容差）。横向>1 竖向<1',
      usage: '[!]xy(=|≈)(<宽:高>|<比值>)',
      examples: ['xy=16:9', 'xy≈2:1', 'xy≈1:2', 'xy=1.78'],
      multiValue: false,
    ),
    SelectorKey(
      name: 'wh',
      description: '长短边比（max:min，始终≥1）。= 精确，≈ 模糊',
      usage: '[!]wh(=|≈)(<长:短>|<比值>)',
      examples: ['wh=16:9', 'wh≈2:1', 'wh=1.78'],
      multiValue: false,
    ),
    SelectorKey(
      name: 'regex',
      description: '正则匹配文件名',
      usage: '[!]regex=<正则表达式>',
      examples: ['regex=.*表情.*', 'regex=^IMG_\\d+'],
      multiValue: false,
    ),
  ];

  static SelectorKey? find(String key) {
    final k = key.toLowerCase();
    for (final c in all) {
      if (c.name == k) return c;
    }
    return null;
  }
}

/// 顶层命令定义（/tag, /help 等）
class TopCommandDef {
  final String name;
  final String description;
  final String usage;
  final List<String> examples;

  const TopCommandDef({
    required this.name,
    required this.description,
    required this.usage,
    required this.examples,
  });

  static const all = [
    TopCommandDef(
      name: 'tag',
      description: '批量添加/移除标签。用选择器筛选目标 meme，未给选择器时作用于全部（别名 t）',
      usage: '/tag [<选择器>] (add|remove) <标签名>',
      examples: ['/tag [xy=1:2] add 竖图', '/t [xy=2:1] remove 喜欢', '/tag [type=图片] add 图片'],
    ),
    TopCommandDef(
      name: 'help',
      description: '显示帮助。/? 或 /help 看全部，/<命令> ? 看该命令帮助（别名 h）',
      usage: '(/?|/help) 或 /<命令> ?',
      examples: ['/?', '/help', '/tag ?'],
    ),
  ];

  static TopCommandDef? find(String name) {
    for (final c in all) {
      if (c.name == name) return c;
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

/// 搜索 DSL：支持三种语法
/// 1. 普通搜索：fuzzy、*? 通配符、#tag、@folder
/// 2. 纯选择器：`[x=100,type=图片]` 高级筛选
/// 3. 命令：`/tag [选择器] add 喜欢` 批量操作
class SearchQuery {
  /// 解析查询，返回 [ParseResult]。
  static ParseResult parse(String query, List<MemeFolder> folders) {
    final q = query.trim();
    if (q.isEmpty) return PlainSearch('');
    if (q.startsWith('/')) {
      return _parseCommand(q.substring(1), folders);
    }
    if (q.startsWith('[')) {
      final conditions = _extractSelectors(q, folders);
      return SelectorSearch(conditions);
    }
    return PlainSearch(q);
  }

  // ===== 帮助检测 =====

  static bool isHelpRequest(String query) {
    final q = query.trim();
    return q == '/?' || q == '/？' || q == '/help';
  }

  static String? isCommandHelpRequest(String query) {
    final q = query.trim();
    final match = RegExp(r'^/(\w+)\s*[?？]\s*$').firstMatch(q);
    if (match != null) {
      final cmd = match.group(1)!.toLowerCase();
      if (TopCommandDef.find(cmd) != null) return cmd;
    }
    return null;
  }

  static String generateHelpText() {
    final sb = StringBuffer();
    sb.writeln('搜索语法帮助');
    sb.writeln('=' * 40);
    sb.writeln();
    sb.writeln('【参数术语】');
    sb.writeln('  <参数>     需替换为合适的值');
    sb.writeln('  [输入项]   可选');
    sb.writeln('  (a|b)      必选其一');
    sb.writeln('  [a|b]      可选其一，可省略');
    sb.writeln('  其余字面量原样输入');
    sb.writeln();
    sb.writeln('【三种语法】');
    sb.writeln('1. 普通搜索：<文字>  支持 * ? 通配符');
    sb.writeln('   #<标签>    按标签搜（独立前缀，不在选择器内）');
    sb.writeln('   @<文件夹>  按文件夹搜（独立前缀，不在选择器内）');
    sb.writeln('2. 选择器：[<条件>,<条件>,...]  高级筛选');
    sb.writeln('3. 命令：/命令 [<选择器>] 操作 <参数>');
    sb.writeln();
    sb.writeln('【操作符】(=|~|≈)  = 精确 | ~ 包含或OR | ≈ 模糊');
    sb.writeln('【反选】!  置于条件前，如 !type=表情包');
    sb.writeln('【范围】<数值>..<数值>  如 100.. (≥) | ..100 (≤) | 50..100');
    sb.writeln('【单位】[cm|mm|in|pt]  默认 px');
    sb.writeln();
    sb.writeln('── 顶层命令 ──');
    for (final cmd in TopCommandDef.all) {
      sb.writeln('  ${cmd.usage}');
      sb.writeln('    ${cmd.description}');
      sb.writeln('    示例: ${cmd.examples.join(" | ")}');
      sb.writeln();
    }
    sb.writeln('── 选择器条件 ──');
    for (final key in SelectorKey.all) {
      sb.writeln('  ${key.name}${key.multiValue ? " (多值)" : ""}');
      sb.writeln('    用法: ${key.usage}');
      sb.writeln('    说明: ${key.description}');
      sb.writeln('    示例: ${key.examples.join(" | ")}');
      sb.writeln();
    }
    return sb.toString();
  }

  static String generateCommandHelpText(String cmdName) {
    final cmd = TopCommandDef.find(cmdName);
    if (cmd == null) return '未知命令: $cmdName';
    final sb = StringBuffer();
    sb.writeln('命令: ${cmd.name}');
    sb.writeln('=' * 30);
    sb.writeln(cmd.description);
    sb.writeln();
    sb.writeln('用法: ${cmd.usage}');
    sb.writeln();
    sb.writeln('示例:');
    for (final ex in cmd.examples) {
      sb.writeln('  $ex');
    }
    return sb.toString();
  }

  // ===== 自动补全 =====

  static List<SearchSuggestion> getSuggestions(
    String query,
    List<String> allTags,
    List<MemeFolder> folders,
  ) {
    final q = query.trim();
    if (q.isEmpty) return [];
    if (isHelpRequest(q) || isCommandHelpRequest(q) != null) return [];

    if (q.startsWith('/')) {
      return _getCommandSuggestions(q.substring(1), allTags, folders);
    }
    if (q.startsWith('[')) {
      return _getSelectorSuggestions(q, allTags, folders);
    }
    // Plain text: #tag / @folder 补全（支持逗号多值）
    final segments = q.split(',');
    final last = segments.last.trim();
    if (last.startsWith('#')) {
      return _getHashTagSuggestions(last.substring(1), allTags);
    }
    if (last.startsWith('@')) {
      return _getAtFolderSuggestions(last.substring(1), folders);
    }
    return [];
  }

  static List<SearchSuggestion> _getCommandSuggestions(
    String afterSlash,
    List<String> allTags,
    List<MemeFolder> folders,
  ) {
    final parts = afterSlash.split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) {
      return [
        ...TopCommandDef.all
            .map((c) => SearchSuggestion(c.name, '/${c.name} ', description: c.description)),
        const SearchSuggestion('t', '/t ', description: '批量添加/移除标签'),
        const SearchSuggestion('h', '/h ', description: '显示帮助'),
      ];
    }

    // 只输入了命令名，补全命令（含别名）
    if (parts.length == 1) {
      final cmd = parts[0].toLowerCase();
      final resolved = _resolveCommandAlias(cmd);
      if (resolved != cmd) {
        return [SearchSuggestion(resolved, '/$resolved ', description: TopCommandDef.find(resolved)?.description)];
      }
      return TopCommandDef.all
          .where((c) => c.name.startsWith(cmd))
          .map((c) => SearchSuggestion(c.name, '/${c.name} ', description: c.description))
          .toList();
    }

    // /tag 后面补全 add/remove
    final resolvedCmd = _resolveCommandAlias(parts[0].toLowerCase());
    if (resolvedCmd == 'tag' && parts.length == 2) {
      final a = parts[1].toLowerCase();
      if (a.isEmpty) return [];
      final actions = ['add', 'remove'];
      return actions
          .where((act) => act.startsWith(a))
          .map((act) => SearchSuggestion(act, act, description: act == 'add' ? '添加标签' : '移除标签'))
          .toList();
    }

    // /tag [selector] add|remove 后面补全标签
    if (resolvedCmd == 'tag' && parts.length >= 3) {
      final action = parts[parts.length - 2];
      if (action == 'add' || action == 'remove') {
        final last = parts.last.toLowerCase();
        if (last.isEmpty) return [];
        return allTags
            .where((t) => t.toLowerCase().startsWith(last))
            .map((t) => SearchSuggestion(t, t))
            .toList();
      }
    }

    return [];
  }

  static List<SearchSuggestion> _getSelectorSuggestions(
    String q,
    List<String> allTags,
    List<MemeFolder> folders,
  ) {
    var inner = q.replaceAll('[', '').replaceAll(']', '');
    final parts = _splitTopLevel(inner, ',');
    if (parts.isEmpty) return [];
    final lastPart = parts.last.trim();

    bool negate = false;
    String keyInput = lastPart;
    if (keyInput.startsWith('!')) {
      negate = true;
      keyInput = keyInput.substring(1);
    }

    final opMatch = RegExp(r'^([a-zA-Z]+)\s*[=≈~]').firstMatch(keyInput);
    if (opMatch == null) {
      final keyStr = keyInput.toLowerCase();
      final prefix = negate ? '!' : '';
      return SelectorKey.all
          .where((c) => c.name.startsWith(keyStr))
          .map((c) => SearchSuggestion(
                '$prefix${c.name}',
                '$prefix${c.name}=',
                description: c.description,
              ))
          .toList();
    }

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
    final key = SelectorKey.find(keyStr);
    if (key == null) return [];
    final v = valuePart.replaceAll('!', '').toLowerCase();

    switch (key.name) {
      case 'type':
        const typeValues = [
          '表情', 'gif', '图片', '文字', '立绘', 'cg', '角色卡',
          '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.bmp',
          'suki',
        ];
        return typeValues
            .where((t) => t.toLowerCase().startsWith(v))
            .map((t) => SearchSuggestion(t, t))
            .toList();
      case 'tag':
        return allTags
            .where((t) => t.toLowerCase().startsWith(v))
            .map((t) => SearchSuggestion(t, t))
            .toList();
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

  static List<SearchSuggestion> _getHashTagSuggestions(String input, List<String> allTags) {
    if (input.isEmpty) return [];
    final lower = input.toLowerCase();
    return allTags
        .where((t) => t.toLowerCase().contains(lower))
        .take(10)
        .map((t) => SearchSuggestion('#$t', '#$t,'))
        .toList();
  }

  static List<SearchSuggestion> _getAtFolderSuggestions(String input, List<MemeFolder> folders) {
    if (input.isEmpty) return [];
    final lower = input.toLowerCase();
    return folders
        .where((f) => f.name.toLowerCase().contains(lower))
        .take(10)
        .map((f) => SearchSuggestion('@${f.name}', '@${f.name},'))
        .toList();
  }

  /// 获取补全用的原始分割部分（公开方法）
  static List<String> getSuggestionsRawParts(String query) {
    if (query.startsWith('/')) {
      final afterSlash = query.substring(1);
      return afterSlash.split(RegExp(r'\s+'));
    }
    var inner = query.replaceAll('[', '').replaceAll(']', '');
    return _splitTopLevel(inner, ',');
  }

  // ===== 校验 =====

  /// 校验语法，返回错误信息（null 表示无错误）。
  static String? validate(String query, List<MemeFolder> folders) {
    final q = query.trim();
    if (q.isEmpty) return null;
    if (isHelpRequest(q) || isCommandHelpRequest(q) != null) return null;

    if (q.startsWith('/')) {
      return _validateCommand(q.substring(1), folders);
    }
    if (q.startsWith('[')) {
      return _validateSelectorOnly(q, folders);
    }
    return null;
  }

  static String? _validateCommand(String afterSlash, List<MemeFolder> folders) {
    final parts = afterSlash.split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '命令为空';

    final cmd = _resolveCommandAlias(parts[0].toLowerCase());
    final cmdDef = TopCommandDef.find(cmd);
    if (cmdDef == null) return '未知命令: "$cmd"';

    if (cmd == 'help') return null;

    if (cmd == 'tag') {
      if (parts.length < 4) {
        return 'tag 命令格式: /tag [选择器] add|remove <标签名>';
      }
      // 校验选择器
      for (final p in parts) {
        if (p.startsWith('[')) {
          final end = _findMatchingBracket(p, 0);
          if (end == -1) return '选择器方括号未闭合';
          final inner = p.substring(1, end);
          final err = _validateSelectorInner(inner, folders);
          if (err != null) return err;
        }
      }
      final action = parts[parts.length - 2];
      if (action != 'add' && action != 'remove') {
        return '未知操作: "$action"，应为 add 或 remove';
      }
      final tagname = parts.last;
      if (tagname.isEmpty) return '标签名不能为空';
      return null;
    }

    return null;
  }

  static String? _validateSelectorOnly(String q, List<MemeFolder> folders) {
    int i = 0;
    while (i < q.length) {
      if (q[i] == '[') {
        final end = _findMatchingBracket(q, i);
        if (end == -1) return '方括号未闭合，缺少 ]';
        final inner = q.substring(i + 1, end);
        final err = _validateSelectorInner(inner, folders);
        if (err != null) return err;
        i = end + 1;
      } else {
        i++;
      }
    }
    return null;
  }

  static String? _validateSelectorInner(String inner, List<MemeFolder> folders) {
    final parts = _splitTopLevel(inner, ',');
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final err = _validateCondition(trimmed);
      if (err != null) return err;
    }
    return null;
  }

  static String? _validateCondition(String s) {
    if (s.startsWith('!')) s = s.substring(1).trim();
    if (s.isEmpty) return '条件为空';

    final keyMatch = RegExp(r'^([a-zA-Z]+)').firstMatch(s);
    if (keyMatch == null) return '无法解析条件: "$s"，选择器内不支持 # @';
    final keyStr = keyMatch.group(1)!.toLowerCase();
    s = s.substring(keyMatch.end);

    String op = '=';
    if (s.startsWith('≈')) { op = '≈'; s = s.substring(1); }
    else if (s.startsWith('~')) { op = '~'; s = s.substring(1); }
    else if (s.startsWith('=')) { op = '='; s = s.substring(1); }
    s = s.trim();
    if (s.isEmpty) return '"$keyStr" 缺少值';

    List<String> values;
    if (s.startsWith('{') && s.endsWith('}')) {
      values = _splitTopLevel(s.substring(1, s.length - 1), ',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (values.isEmpty) return '"$keyStr" 的值列表为空';
    } else {
      values = [s];
    }

    final key = _normalizeKey(keyStr);
    if (key == null) return '未知条件: "$keyStr"（选择器内不支持 # @，请用 folder= 代替 @）';

    if (key == ConditionKey.tag && op == '~' && values.length == 1) {
      return 'tag 使用 ~ 时需要多值（如 tag~{开心,喜欢}），单值请用 tag=开心';
    }

    const multiValueKeys = [
      ConditionKey.tag, ConditionKey.type, ConditionKey.folder,
    ];
    if (!multiValueKeys.contains(key) && values.length > 1) {
      return '"$keyStr" 不支持多值';
    }

    if (key == ConditionKey.width || key == ConditionKey.height ||
        key == ConditionKey.longSide || key == ConditionKey.shortSide) {
      for (final v in values) {
        if (_DimensionMatcher.parse(v) == null) {
          return '"$keyStr" 的值 "$v" 无效，应为数值或范围（如 100, 100.., ..100, 50..100cm）';
        }
      }
    }

    if (key == ConditionKey.ratioXY || key == ConditionKey.ratioWH) {
      for (final v in values) {
        if (!_isValidRatioValue(v)) {
          return '"$keyStr" 的值 "$v" 无效，应为比例（如 16:9）或数值（如 1.78）';
        }
      }
    }

    if (key == ConditionKey.regex) {
      for (final v in values) {
        try {
          RegExp(v);
        } catch (_) {
          return '无效的正则表达式: "$v"';
        }
      }
    }

    return null;
  }

  static bool _isValidRatioValue(String v) {
    v = v.trim();
    if (v.contains(':')) {
      final parts = v.split(':');
      if (parts.length != 2) return false;
      return double.tryParse(parts[0]) != null && double.tryParse(parts[1]) != null;
    }
    return double.tryParse(v) != null;
  }

  // ===== 命令解析 =====

  static ParseResult _parseCommand(String afterSlash, List<MemeFolder> folders) {
    final parts = afterSlash.split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return PlainSearch('');

    final cmd = _resolveCommandAlias(parts[0].toLowerCase());
    if (cmd == 'help' || cmd == '?') {
      return const CommandSearch(command: 'help', selector: [], action: '', args: []);
    }

    if (cmd == 'tag') {
      List<Condition> selector = [];
      String action = '';
      List<String> args = [];

      for (final p in parts.sublist(1)) {
        if (p.startsWith('[')) {
          final end = _findMatchingBracket(p, 0);
          if (end != -1) {
            final inner = p.substring(1, end);
            selector.addAll(_parseConditions(inner, folders));
          }
        } else if (action.isEmpty && (p == 'add' || p == 'remove')) {
          action = p;
        } else if (action.isNotEmpty) {
          args.add(p);
        }
      }

      return CommandSearch(
        command: 'tag',
        selector: selector,
        action: action,
        args: args,
      );
    }

    return PlainSearch('');
  }

  /// 从字符串中提取所有选择器条件
  static List<Condition> _extractSelectors(String s, List<MemeFolder> folders) {
    final conditions = <Condition>[];
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
    return conditions;
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

  static List<Condition> _parseConditions(String inner, List<MemeFolder> folders) {
    final parts = _splitTopLevel(inner, ',');
    final conditions = <Condition>[];
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

  static Condition? _parseCondition(String s, List<MemeFolder> folders) {
    bool negate = false;
    if (s.startsWith('!')) {
      negate = true;
      s = s.substring(1).trim();
    }

    final keyMatch = RegExp(r'^([a-zA-Z]+)').firstMatch(s);
    if (keyMatch == null) return null;
    final keyStr = keyMatch.group(1)!.toLowerCase();
    s = s.substring(keyMatch.end);

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

    return Condition(
      key: key,
      op: op,
      values: values,
      negate: negate,
      folders: folders,
    );
  }

  static ConditionKey? _normalizeKey(String k) {
    switch (k) {
      case 'type':
        return ConditionKey.type;
      case 'tag':
        return ConditionKey.tag;
      case 'folder':
        return ConditionKey.folder;
      case 'name':
        return ConditionKey.name;
      case 'x':
        return ConditionKey.width;
      case 'y':
        return ConditionKey.height;
      case 'w':
        return ConditionKey.longSide;
      case 'h':
        return ConditionKey.shortSide;
      case 'xy':
        return ConditionKey.ratioXY;
      case 'wh':
        return ConditionKey.ratioWH;
      case 'regex':
        return ConditionKey.regex;
      default:
        return null;
    }
  }

  /// 命令别名映射：短命令 → 真实命令名
  static String _resolveCommandAlias(String cmd) {
    switch (cmd) {
      case 't':
        return 'tag';
      case 'h':
        return 'help';
      default:
        return cmd;
    }
  }

  // ===== 普通模式匹配（公开给 PlainSearch） =====

  static bool Function(Meme) _matchPlain(String q, List<MemeFolder> folders) {
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

enum ConditionKey {
  type, tag, folder, name,
  width, height,         // x, y
  longSide, shortSide,   // w, h
  ratioXY, ratioWH,      // xy, wh
  regex,
}

class Condition {
  final ConditionKey key;
  final String op;
  final List<String> values;
  final bool negate;
  final List<MemeFolder> folders;

  Condition({
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
      case ConditionKey.type:
        return values.any((v) => _matchType(m, v));
      case ConditionKey.tag:
        switch (op) {
          case '=':
            return values.every((v) => m.tags.any((t) => _matchString(t, v, '=')));
          case '~':
            return values.any((v) => m.tags.any((t) => _matchString(t, v, '=')));
          case '≈':
            return values.any((v) => m.tags.any((t) => _matchString(t, v, '≈')));
          default:
            return values.every((v) => m.tags.any((t) => _matchString(t, v, '=')));
        }
      case ConditionKey.folder:
        final matchedFolderIds = <String>{};
        for (final v in values) {
          for (final f in folders) {
            if (_matchString(f.name, v, op)) {
              matchedFolderIds.add(f.id);
            }
          }
        }
        return m.folderId != null && matchedFolderIds.contains(m.folderId);
      case ConditionKey.name:
        return _matchString(m.name, values.first, op);
      case ConditionKey.width:
        final matcher = _DimensionMatcher.parse(values.first);
        return matcher != null && matcher.match(m.width);
      case ConditionKey.height:
        final matcher = _DimensionMatcher.parse(values.first);
        return matcher != null && matcher.match(m.height);
      case ConditionKey.longSide:
        final matcher = _DimensionMatcher.parse(values.first);
        if (matcher == null) return false;
        final longSide = m.width > m.height ? m.width : m.height;
        return matcher.match(longSide);
      case ConditionKey.shortSide:
        final matcher = _DimensionMatcher.parse(values.first);
        if (matcher == null) return false;
        final shortSide = m.width > m.height ? m.height : m.width;
        return matcher.match(shortSide);
      case ConditionKey.ratioXY:
        return _matchRatio(m.width, m.height, values.first, op, false);
      case ConditionKey.ratioWH:
        return _matchRatio(m.width, m.height, values.first, op, true);
      case ConditionKey.regex:
        return _matchRegex(m.name, values.first);
    }
  }

  static bool _matchType(Meme m, String query) {
    final q = query.toLowerCase().trim();
    // suki: 收藏 + 表情（type=suki 匹配 isFavorite && type=emoji）
    if (q == 'suki') {
      return m.isFavorite && m.type == Meme.typeEmoji;
    }
    if (q.startsWith('.')) {
      if (m.filePath.isEmpty) return false;
      final ext = m.filePath.toLowerCase();
      final dotIdx = ext.lastIndexOf('.');
      if (dotIdx == -1) return false;
      return ext.substring(dotIdx) == q;
    }
    if (m.type == q) return true;
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
        final tolerance = (targetRatio * 0.15).abs();
        return (actualRatio - targetRatio).abs() <= tolerance;
      default:
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

  static const _unitMultipliers = <String, double>{
    'px': 1.0,
    'in': 96.0,
    'cm': 37.795275590551,
    'mm': 3.7795275590551,
    'pt': 1.3333333333333,
  };

  static _DimensionMatcher? parse(String input) {
    final raw = input.trim();

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
      if (minPx == null && maxPx == null) return null;
      return _DimensionMatcher(minPx: minPx, maxPx: maxPx);
    }

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
