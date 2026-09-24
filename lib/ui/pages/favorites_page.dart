import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/library_providers.dart';
import '../widgets/page_header.dart';
import '../widgets/track_explorer.dart';

/// 收藏页：只展示已收藏的曲目，其余交互与曲库一致。
class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count =
        ref.watch(favoritesTracksProvider).valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageHeader(
              title: '我的喜欢',
              hint: count == 0 ? '点曲目右侧的 ♥ 把喜欢的歌收进来' : '$count 首 · 收藏只存在本机',
            ),
            Expanded(
              child: TrackExplorer(
                tracksProvider: favoritesTracksProvider,
                filterProvider: favoritesFilterProvider,
                showScope: false,
                emptyTitle: '还没有收藏',
                emptyMessage: '在曲库里点曲目右侧的 ♥ 就能把喜欢的歌收进来。',
                emptyActionLabel: '去曲库',
                emptyActionRoute: '/library',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
