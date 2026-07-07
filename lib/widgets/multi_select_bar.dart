import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../l10n/l10n.dart';

class MultiSelectBar extends StatelessWidget {
  const MultiSelectBar({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MemeProvider>();
    final l10n = context.watch<LocaleProvider>().l10n;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.select_all, size: 18),
            label: Text(l10n.tr('select_all')),
            onPressed: () => prov.selectAll(),
          ),
          TextButton.icon(
            icon: const Icon(Icons.deselect, size: 18),
            label: Text(l10n.tr('cancel')),
            onPressed: () => prov.deselectAll(),
          ),
          const Spacer(),
          if (prov.selected.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.folder_open, size: 20),
              tooltip: l10n.tr('move_to_folder'),
              onPressed: () => _showMoveDialog(context, prov, l10n),
            ),
            IconButton(
              icon: const Icon(Icons.label_outline, size: 20),
              tooltip: l10n.tr('change_category'),
              onPressed: () => _showTypeDialog(context, prov, l10n),
            ),
            IconButton(
              icon: const Icon(Icons.ios_share, size: 20),
              tooltip: l10n.tr('export_selected'),
              onPressed: () => _exportSelected(context, prov, l10n),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              tooltip: l10n.tr('delete_selected'),
              onPressed: () => _confirmDelete(context, prov, l10n),
            ),
          ],
        ],
      ),
    );
  }

  void _showMoveDialog(BuildContext ctx, MemeProvider prov, L10n l10n) {
    showDialog(
      context: ctx,
      builder: (dCtx) => SimpleDialog(
        title: Text(l10n.tr('move_to_folder')),
        children: [
          SimpleDialogOption(
            onPressed: () { prov.moveSelectedToFolder(null); Navigator.pop(dCtx); },
            child: Text(l10n.tr('all_folders')),
          ),
          ...prov.folders.map((f) => SimpleDialogOption(
            onPressed: () { prov.moveSelectedToFolder(f.id); Navigator.pop(dCtx); },
            child: Text(f.name),
          )),
        ],
      ),
    );
  }

  void _showTypeDialog(BuildContext ctx, MemeProvider prov, L10n l10n) {
    final types = [
      {'type': Meme.typeEmoji, 'label': l10n.tr('type_emoji'), 'icon': Icons.face},
      {'type': Meme.typeGif, 'label': l10n.tr('type_gif'), 'icon': Icons.gif},
      {'type': Meme.typeImage, 'label': l10n.tr('type_image'), 'icon': Icons.image},
      {'type': Meme.typeText, 'label': l10n.tr('type_text'), 'icon': Icons.text_fields},
      {'type': Meme.typePortrait, 'label': l10n.tr('type_portrait'), 'icon': Icons.portrait},
      {'type': Meme.typeCg, 'label': l10n.tr('type_cg'), 'icon': Icons.photo_library},
      {'type': Meme.typeCharacterCard, 'label': l10n.tr('type_character_card'), 'icon': Icons.person_outline},
    ];

    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('change_category')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: types.map((t) {
            final type = t['type'] as String;
            final label = t['label'] as String;
            final icon = t['icon'] as IconData;
            return ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () {
                prov.setSelectedType(type);
                Navigator.pop(dCtx);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
        ],
      ),
    );
  }

  Future<void> _exportSelected(BuildContext ctx, MemeProvider prov, L10n l10n) async {
    try {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l10n.tr('selected_memes', args: {'count': prov.selected.length.toString()}))),
      );
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(l10n.tr('operation_failed', args: {'error': e.toString()}))),
        );
      }
    }
  }

  void _confirmDelete(BuildContext ctx, MemeProvider prov, L10n l10n) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('delete_meme_title')),
        content: Text(l10n.tr('delete_selected_confirm', args: {'count': prov.selected.length.toString()})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: Text(l10n.tr('delete'))),
        ],
      ),
    );
    if (confirm == true) await prov.deleteSelected();
  }
}
