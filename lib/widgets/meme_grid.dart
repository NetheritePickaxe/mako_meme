import 'package:flutter/material.dart';
import '../models/meme.dart';
import 'meme_card.dart';

class MemeGrid extends StatelessWidget {
  final List<Meme> memes;
  final double spacing;

  const MemeGrid({super.key, required this.memes, this.spacing = 8.0});

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w > 1200 ? 8 : w > 900 ? 6 : w > 600 ? 4 : w > 400 ? 3 : 2;
        return GridView.builder(
          padding: EdgeInsets.all(spacing),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: 1,
          ),
          itemCount: memes.length,
          itemBuilder: (ctx, i) => MemeCard(meme: memes[i]),
        );
      },
    );
  }
}
