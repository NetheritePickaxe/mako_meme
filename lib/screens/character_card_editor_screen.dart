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
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _personalityCtrl.dispose();
    _scenarioCtrl.dispose();
    _firstMesCtrl.dispose();
    _mesExampleCtrl.dispose();
    super.dispose();
  }

  void _save() async {
    _cardData['name'] = _nameCtrl.text.trim();
    _cardData['description'] = _descCtrl.text.trim();
    _cardData['personality'] = _personalityCtrl.text.trim();
    _cardData['scenario'] = _scenarioCtrl.text.trim();
    _cardData['first_mes'] = _firstMesCtrl.text.trim();
    _cardData['mes_example'] = _mesExampleCtrl.text.trim();

    final sanitized = CharacterCardService.sanitizeCard(_cardData);
    await context.read<MemeProvider>().updateCharacterData(widget.meme.id, sanitized);

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _textField(String label, TextEditingController controller, {int maxLines = 3}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
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
            _section(l10n.tr('char_name'), _textField(l10n.tr('char_name'), _nameCtrl, maxLines: 1)),
            _section(l10n.tr('char_description'), _textField(l10n.tr('char_description_hint'), _descCtrl, maxLines: 5)),
            _section(l10n.tr('char_personality'), _textField(l10n.tr('char_personality_hint'), _personalityCtrl, maxLines: 5)),
            _section(l10n.tr('char_scenario'), _textField(l10n.tr('char_scenario_hint'), _scenarioCtrl, maxLines: 5)),
            _section(l10n.tr('char_first_mes'), _textField(l10n.tr('char_first_mes_hint'), _firstMesCtrl, maxLines: 3)),
            _section(l10n.tr('char_mes_example'), _textField(l10n.tr('char_mes_example_hint'), _mesExampleCtrl, maxLines: 8)),
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
