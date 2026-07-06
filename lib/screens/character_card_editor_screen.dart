import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('角色卡编辑器'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            _section('角色名称', _textField('角色名称', _nameCtrl, maxLines: 1)),
            _section('外貌描述', _textField('描述角色的外貌特征、背景故事等', _descCtrl, maxLines: 5)),
            _section('性格设定', _textField('描述角色的性格、行为模式、语言风格', _personalityCtrl, maxLines: 5)),
            _section('场景设定', _textField('对话开始的场景和情境', _scenarioCtrl, maxLines: 5)),
            _section('开场白', _textField('角色的第一句话', _firstMesCtrl, maxLines: 3)),
            _section('对话示例', _textField('示例对话，使用 {{user}} 和 {{char}} 作为占位符', _mesExampleCtrl, maxLines: 8)),
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
