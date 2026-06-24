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
    return GridView.builder(
      padding: EdgeInsets.all(spacing),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 1,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      ),
      itemCount: memes.length,
      itemBuilder: (ctx, i) => MemeCard(meme: memes[i]),
    );
  }
}
