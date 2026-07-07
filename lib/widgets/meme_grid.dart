import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/meme.dart';
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

  /// 是否全部为表情/文字类型（方形卡片）
  bool get _allSquare => memes.every(
        (m) => m.type == Meme.typeEmoji || m.type == Meme.typeText,
      );

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

    // 全部为表情/文字 → 常规方形网格
    if (_allSquare) {
      return GridView.builder(
        padding: EdgeInsets.all(spacing),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          childAspectRatio: 1,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
        ),
        itemCount: memes.length,
        itemBuilder: (ctx, i) => MemeCard(
          meme: memes[i],
          onReorder: onReorder,
        ),
      );
    }

    // 含图片 → 瀑布流布局（变高卡片）
    return MasonryGridView.maxCrossAxisExtent(
      maxCrossAxisExtent: 160,
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
