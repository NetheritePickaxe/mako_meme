import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/locale_provider.dart';
import 'meme_card.dart';

class MemeGrid extends StatelessWidget {
  final List<Meme> memes;
  final double spacing;
  final void Function(Meme dragged, Meme target)? onReorder;
  final bool previewMode;

  const MemeGrid({
    super.key,
    required this.memes,
    this.spacing = 8.0,
    this.onReorder,
    this.previewMode = false,
  });

  int _resolveCols(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (settings.gridColumns > 0) return settings.gridColumns;
    // 自动：根据宽度
    final width = MediaQuery.sizeOf(context).width;
    return width > 1200 ? 6 : width > 900 ? 5 : width > 600 ? 4 : width > 400 ? 3 : 2;
  }

  @override
  Widget build(BuildContext context) {
    if (memes.isEmpty) {
      final l10n = context.read<LocaleProvider>().l10n;
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 64, color: cs.outline),
            const SizedBox(height: 16),
            Text(l10n.tr('no_memes'), style: TextStyle(fontSize: 18, color: cs.outline)),
            const SizedBox(height: 8),
            Text(l10n.tr('tap_plus'), style: TextStyle(fontSize: 14, color: cs.outline.withValues(alpha: 0.7))),
          ],
        ),
      );
    }

    final cols = _resolveCols(context);
    final previewMemeId = previewMode
        ? context.watch<MemeProvider>().previewMeme?.id
        : null;

    // 统一使用瀑布流布局，支持文字自适应高度 + 图片变高
    return MasonryGridView.count(
      crossAxisCount: cols,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      padding: EdgeInsets.all(spacing),
      itemCount: memes.length,
      itemBuilder: (ctx, i) => MemeCard(
        key: ValueKey(memes[i].id),
        meme: memes[i],
        onReorder: onReorder,
        previewMode: previewMode,
        isPreviewSelected: previewMemeId == memes[i].id,
      ),
    );
  }
}
