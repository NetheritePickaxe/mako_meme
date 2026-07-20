import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../services/character_card_service.dart';

class CharacterCardEditorScreen extends StatefulWidget {
  final Meme meme;

  const CharacterCardEditorScreen({super.key, required this.meme});

  @override
  State<CharacterCardEditorScreen> createState() => _CharacterCardEditorScreenState();
}

class _CharacterCardEditorScreenState extends State<CharacterCardEditorScreen> {
  late Map<String, dynamic> _cardData;
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _personalityCtrl = TextEditingController();
  final _scenarioCtrl = TextEditingController();
  final _firstMesCtrl = TextEditingController();
  final _mesExampleCtrl = TextEditingController();
  final _systemPromptCtrl = TextEditingController();
  final _postHistoryCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _creatorCtrl = TextEditingController();
  final _charVersionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cardData = widget.meme.characterData != null
        ? Map<String, dynamic>.from(widget.meme.characterData!)
        : CharacterCardService.createEmptyCard();

    _nameCtrl.text = _cardData['name'] as String? ?? '';
    _descCtrl.text = _cardData['description'] as String? ?? '';
    _personalityCtrl.text = _cardData['personality'] as String? ?? '';
    _scenarioCtrl.text = _cardData['scenario'] as String? ?? '';
    _firstMesCtrl.text = _cardData['first_mes'] as String? ?? '';
    _mesExampleCtrl.text = _cardData['mes_example'] as String? ?? '';
    _systemPromptCtrl.text = _cardData['system_prompt'] as String? ?? '';
    _postHistoryCtrl.text = _cardData['post_history_instructions'] as String? ?? '';
    _notesCtrl.text = _cardData['notes'] as String? ?? '';
    _creatorCtrl.text = _cardData['creator'] as String? ?? '';
    _charVersionCtrl.text = _cardData['character_version'] as String? ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _personalityCtrl.dispose();
    _scenarioCtrl.dispose();
    _firstMesCtrl.dispose();
    _mesExampleCtrl.dispose();
    _systemPromptCtrl.dispose();
    _postHistoryCtrl.dispose();
    _notesCtrl.dispose();
    _creatorCtrl.dispose();
    _charVersionCtrl.dispose();
    super.dispose();
  }

  void _save() async {
    _cardData['name'] = _nameCtrl.text.trim();
    _cardData['description'] = _descCtrl.text;
    _cardData['personality'] = _personalityCtrl.text;
    _cardData['scenario'] = _scenarioCtrl.text;
    _cardData['first_mes'] = _firstMesCtrl.text;
    _cardData['mes_example'] = _mesExampleCtrl.text;
    _cardData['system_prompt'] = _systemPromptCtrl.text;
    _cardData['post_history_instructions'] = _postHistoryCtrl.text;
    _cardData['notes'] = _notesCtrl.text;
    _cardData['creator'] = _creatorCtrl.text.trim();
    _cardData['character_version'] = _charVersionCtrl.text.trim();

    final sanitized = CharacterCardService.sanitizeCard(_cardData);
    await context.read<MemeProvider>().updateCharacterData(widget.meme.id, sanitized);

    if (mounted) {
      Navigator.pop(context);
    }
  }

  /// 区块：标题 + 多行输入框，标题右侧带全屏编辑按钮
  Widget _section(
    String title,
    TextEditingController controller, {
    int minLines = 4,
    int maxLines = 8,
    String? label,
    bool fullscreen = true,
  }) {
    final theme = Theme.of(context);
    final l10n = context.read<LocaleProvider>().l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (fullscreen)
                IconButton(
                  icon: const Icon(Icons.open_in_full, size: 18),
                  tooltip: l10n.tr('fullscreen_edit'),
                  onPressed: () => _openFullscreen(title, controller),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            minLines: minLines,
            maxLines: maxLines,
            decoration: InputDecoration(
              labelText: label ?? title,
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 单行/紧凑输入框：用于并排的元信息字段，无全屏按钮
  Widget _textField(
    String label,
    TextEditingController controller, {
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  /// 全屏编辑长文本
  Future<void> _openFullscreen(String title, TextEditingController controller) async {
    final l10n = context.read<LocaleProvider>().l10n;
    final draft = TextEditingController(text: controller.text);
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (ctx) => _FullscreenTextEditor(
          title: title,
          controller: draft,
          saveLabel: l10n.tr('save'),
        ),
      ),
    );
    if (result != null) {
      controller.text = result;
      setState(() {});
    }
    draft.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.watch<LocaleProvider>().l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('character_card_editor')),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(l10n.tr('save')),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            _section(l10n.tr('char_name'), _nameCtrl, minLines: 1, maxLines: 2, label: l10n.tr('char_name'), fullscreen: false),
            _section(l10n.tr('char_description'), _descCtrl, minLines: 6, maxLines: 12, label: l10n.tr('char_description_hint')),
            _section(l10n.tr('char_personality'), _personalityCtrl, minLines: 5, maxLines: 10, label: l10n.tr('char_personality_hint')),
            _section(l10n.tr('char_scenario'), _scenarioCtrl, minLines: 5, maxLines: 10, label: l10n.tr('char_scenario_hint')),
            _section(l10n.tr('char_first_mes'), _firstMesCtrl, minLines: 5, maxLines: 12, label: l10n.tr('char_first_mes_hint')),
            _section(l10n.tr('char_mes_example'), _mesExampleCtrl, minLines: 6, maxLines: 14, label: l10n.tr('char_mes_example_hint')),
            _section(l10n.tr('char_system_prompt'), _systemPromptCtrl, minLines: 4, maxLines: 10),
            _section(l10n.tr('char_post_history_instructions'), _postHistoryCtrl, minLines: 4, maxLines: 10),
            _section(l10n.tr('char_notes'), _notesCtrl, minLines: 3, maxLines: 8),
            // 元信息：作者 / 角色卡版本
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: _textField(l10n.tr('char_creator'), _creatorCtrl)),
                  const SizedBox(width: 12),
                  Expanded(child: _textField(l10n.tr('char_character_version'), _charVersionCtrl)),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _save,
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
        child: const Icon(Icons.save),
      ),
    );
  }
}

/// 全屏长文本编辑器：支持系统返回键确认（返回时自动保存草稿）
class _FullscreenTextEditor extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final String saveLabel;

  const _FullscreenTextEditor({
    required this.title,
    required this.controller,
    required this.saveLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(saveLabel),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: controller,
          maxLines: null,
          expands: true,
          autofocus: true,
          textAlignVertical: TextAlignVertical.top,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ),
    );
  }
}
