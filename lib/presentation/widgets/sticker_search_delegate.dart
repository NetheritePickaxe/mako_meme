import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../providers/sticker_providers.dart';
import '../../shared/widgets/sticker_image.dart';
import '../widgets/sticker_preview.dart';

/// 全局搜索代理
class StickerSearchDelegate extends SearchDelegate<String> {
  final WidgetRef ref;

  StickerSearchDelegate(this.ref);

  @override
  String get searchFieldLabel => '搜索表情包或表情...';

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults(context);

  Widget _buildSearchResults(BuildContext context) {
    if (query.length < 2) {
      return Center(
        child: Text(
          '输入至少两个字符开始搜索',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
              ),
        ),
      );
    }

    final repo = ref.read(stickerRepositoryProvider);

    return StreamBuilder<List<StickerData>>(
      stream: repo.searchStickers(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data ?? [];
        if (results.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off,
                    size: 48,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(100)),
                const SizedBox(height: 8),
                Text('没有找到匹配的表情',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          );
        }

        // 按 packId 分组
        final grouped = <String, List<StickerData>>{};
        for (final s in results) {
          grouped.putIfAbsent(s.packId, () => []).add(s);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: grouped.length,
          itemBuilder: (context, index) {
            final packId = grouped.keys.elementAt(index);
            final stickers = grouped[packId]!;

            return FutureBuilder<StickerPackData?>(
              future: repo.getPack(packId),
              builder: (context, snap) {
                final packName = snap.data?.name ?? '未知表情包';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(packName,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  )),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: stickers.length,
                      itemBuilder: (context, i) {
                        final s = stickers[i];
                        return GestureDetector(
                          onTap: () {
                            close(context, '');
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    StickerPreviewScreen(sticker: s),
                              ),
                            );
                          },
                          child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: StickerImage(
                                  sticker: s,
                                  repo: repo,
                                  fit: BoxFit.cover,
                                ),
                              ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
