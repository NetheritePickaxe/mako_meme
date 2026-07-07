import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/settings_provider.dart';
import 'meme_card.dart';

class MemeGrid extends StatelessWidget {
  final List<Meme> memes;
  final double spacing;
  final void Function(Meme dragged, Meme target)? onReorder;

  const MemeGrid({
    super.key,
    required this.memes,
    this.spacing = 8.0,
    this.onReorder,
  });

  int _resolveCols(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    if (settings.gridColumns > 0) return settings.gridColumns;
    // 自动：根据宽度
    final width = MediaQuery.sizeOf(context).width;
    return width > 1200 ? 6 : width > 900 ? 5 : width > 600 ? 4 : width > 400 ? 3 : 2;
  }

  @override
  Widget build(BuildContext context) {
    if (memes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('还没有表情包', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Text('点击右下角 + 导入', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    final cols = _resolveCols(context);

    // 统一使用瀑布流布局，支持文字自适应高度 + 图片变高
    return MasonryGridView.count(
      crossAxisCount: cols,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      padding: EdgeInsets.all(spacing),
      itemCount: memes.length,
      itemBuilder: (ctx, i) => MemeCard(
        meme: memes[i],
        onReorder: onReorder,
      ),
    );
  }
}
