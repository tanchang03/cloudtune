import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/adapters/library_repository.dart';
import '../providers/library_providers.dart';
import '../providers/new_songs_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/clear_library.dart';
import '../widgets/page_header.dart';
import '../widgets/track_explorer.dart';

/// 曲库页：搜索、范围筛选、分组、排序、随机播放、点播。
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  static const Map<TrackSort, String> _sortLabels = {
    TrackSort.nameAsc: '文件名',
    TrackSort.artistAsc: '艺术家',
    TrackSort.albumAsc: '专辑',
    TrackSort.sizeDesc: '体积（大→小）',
    TrackSort.recentlyIndexed: '最近入库',
    TrackSort.mostPlayed: '播放最多',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(libraryStatsProvider).valueOrNull;
    final hint = stats == null || stats.trackCount == 0
        ? '跨网盘聚合的音乐库 · 不下载、不搬家'
        : '${stats.trackCount} 首 · ${stats.playableCount} 首确认可播'
            ' · ${formatBytes(stats.totalBytes)} · 索引存于本机';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageHeader(
              title: '音乐库',
              hint: hint,
              actions: const [
                _MarkSeenButton(),
                _SortMenu(),
                _LibraryMenu(),
              ],
            ),
            Expanded(
              child: TrackExplorer(
                tracksProvider: libraryTracksProvider,
                filterProvider: libraryFilterProvider,
                showScope: true,
                emptyTitle: '曲库还是空的',
                emptyMessage: '先去「扫描」把网盘里的音乐建成本地索引，也可以直接搜索。',
                emptyActionLabel: '去扫描',
                emptyActionRoute: '/scan',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 页头右上角的「标记 N 首已看」。
///
/// 只在确实有新歌（计数 > 0）时出现：点一下把「新歌」水位设为现在，
/// 侧边栏红点与曲目标题上的「新」标签随之消失。水位写进设置，重启后依然有效。
class _MarkSeenButton extends ConsumerWidget {
  const _MarkSeenButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newCount = ref.watch(newSongsCountProvider).valueOrNull ?? 0;
    if (newCount <= 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: scheme.error),
      icon: const Icon(Icons.check_circle_outline, size: 16),
      label: Text('标记 $newCount 首已看'),
      onPressed: () =>
          ref.read(newSongsSeenAtProvider.notifier).markSeen(),
    );
  }
}

class _SortMenu extends ConsumerWidget {
  const _SortMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(libraryFilterProvider).sort;
    return PopupMenuButton<TrackSort>(
      icon: const Icon(Icons.sort),
      tooltip: '排序',
      initialValue: sort,
      onSelected: (s) => ref.read(libraryFilterProvider.notifier).setSort(s),
      itemBuilder: (context) => [
        for (final entry in LibraryPage._sortLabels.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
    );
  }
}

/// 页头右上角的「更多」。
///
/// 清空是破坏性操作，不做成裸露的图标按钮 —— 藏在菜单里多一次点击，
/// 换来的是不会误触。确认弹窗仍由 [confirmAndClearLibrary] 兜底。
class _LibraryMenu extends ConsumerWidget {
  const _LibraryMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hasTracks = (ref.watch(libraryStatsProvider).valueOrNull?.trackCount ?? 0) > 0;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: '更多',
      onSelected: (value) {
        if (value == 'clear') confirmAndClearLibrary(context, ref);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'clear',
          // 曲库本来就空时禁用，避免「清空了个寂寞」的困惑
          enabled: hasTracks,
          child: Row(
            children: [
              Icon(
                Icons.delete_sweep_outlined,
                size: 18,
                color: hasTracks ? scheme.error : AppTheme.dim,
              ),
              const SizedBox(width: 10),
              Text(
                '清空音乐库',
                style: TextStyle(
                  color: hasTracks ? null : AppTheme.dim,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
