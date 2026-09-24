import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/remote/quark/quark_adapter.dart';
import '../../domain/entities/track.dart';
import '../../domain/services/library_grouping.dart';
import '../../domain/services/playback_queue.dart';
import '../providers/library_providers.dart';
import '../providers/playback_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/track_list.dart';

/// 曲库 / 收藏共用的浏览体。
///
/// 搜索框、范围筛选、分组切换、列表、随机播放都收在这里，两个页面只传入各自的
/// provider 与空状态文案，避免重复实现同一套交互。
/// 视觉对齐设计原型：`.searchbar` / `.chips` / `.desk-list`。
class TrackExplorer extends ConsumerWidget {
  const TrackExplorer({
    super.key,
    required this.tracksProvider,
    required this.filterProvider,
    this.showScope = true,
    required this.emptyTitle,
    required this.emptyMessage,
    this.emptyActionLabel,
    this.emptyActionRoute,
  });

  final AutoDisposeFutureProvider<List<Track>> tracksProvider;
  final NotifierProvider<LibraryFilterNotifier, LibraryFilter> filterProvider;
  final bool showScope;
  final String emptyTitle;
  final String emptyMessage;
  final String? emptyActionLabel;
  final String? emptyActionRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final tracksAsync = ref.watch(tracksProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _SearchBar(filterProvider: filterProvider, keyword: filter.keyword),
        _FilterBar(
          filterProvider: filterProvider,
          scope: filter.scope,
          group: filter.group,
          showScope: showScope,
        ),
        Expanded(
          child: tracksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('加载失败：$e', style: TextStyle(color: scheme.error)),
            ),
            data: (tracks) {
              if (tracks.isEmpty) {
                return EmptyState(
                  icon: Icons.library_music_outlined,
                  title: emptyTitle,
                  message: emptyMessage,
                  action: emptyActionLabel == null || emptyActionRoute == null
                      ? null
                      : FilledButton.icon(
                          onPressed: () => context.go(emptyActionRoute!),
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(emptyActionLabel!),
                        ),
                );
              }

              // 分组是视图态，渲染前现算。平铺模式下 `group` 直接原样返回，
              // 所以两条路径共用同一个列表组件，不必在这里分叉。
              final groups = LibraryGrouping.group(tracks, filter.group);

              return Column(
                children: [
                  _ListHeader(
                    count: tracks.length,
                    detail: filter.group == LibraryGroupMode.none
                        ? null
                        : '${groups.length} ${filter.group.groupNoun}',
                    onShuffle: () =>
                        _startPlayback(ref, tracks, PlaybackMode.shuffle),
                    onSequential: () =>
                        _startPlayback(ref, tracks, PlaybackMode.sequential),
                  ),
                  Expanded(
                    child: TrackGroupListView(
                      groups: groups,
                      capabilities: QuarkAdapter.quarkCapabilities,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// 列表头的两个播放入口。
  ///
  /// 两者做的是同一件事：**把眼前这份列表设成播放队列**。区别只在起点和
  /// 推进方式 —— 随机是随机起点 + 随机次序，顺序是列表第一首 + 列表次序。
  ///
  /// 所以「顺序播放」播的一定是用户此刻看到的顺序：搜索、范围筛选、排序
  /// 都已经体现在 [tracks] 里了，分组视图下点组头的播放键也走同一个队列。
  void _startPlayback(WidgetRef ref, List<Track> tracks, PlaybackMode mode) {
    if (tracks.isEmpty) return;
    final player = ref.read(playerProvider.notifier);
    // 先定模式再设队列：playFrom 会替换曲池，但不碰模式
    player.setMode(mode);
    final pick = mode.isShuffle
        ? tracks[Random().nextInt(tracks.length)]
        : tracks.first;
    player.playFrom(tracks, pick);
  }
}

/// 列表上方的「共 N 首 / 随机播放 / 顺序播放」。
class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.count,
    required this.onShuffle,
    required this.onSequential,
    this.detail,
  });

  final int count;

  /// 附加说明，分组时用来显示「47 张专辑」
  final String? detail;

  final VoidCallback onShuffle;

  final VoidCallback onSequential;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 14, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              detail == null ? '$count 首' : '$count 首 · $detail',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
            ),
          ),
          _PlayOrderButton(
            icon: Icons.shuffle,
            label: '随机播放',
            tooltip: '把当前列表打乱后随机播放',
            onPressed: onShuffle,
          ),
          _PlayOrderButton(
            icon: Icons.playlist_play,
            label: '顺序播放',
            tooltip: '按当前列表顺序，从第一首开始播',
            onPressed: onSequential,
          ),
        ],
      ),
    );
  }
}

/// 列表头的一个播放入口。
///
/// 两个按钮的样式必须完全一致：随机是用户更常用的那个，但顺序播放不是
/// 「次要操作」，把它画小一号会让人以为它只是个补充说明。
///
/// 两个按钮都是「开始播放」，不是「切换播放顺序」—— 所以顺序播放会从列表
/// 第一首开始，而不是接着当前这首往下走。想在播放中换顺序而不打断，
/// 用播放条上那颗模式按钮。
class _PlayOrderButton extends StatelessWidget {
  const _PlayOrderButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.accent,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 11.5)),
      ),
    );
  }
}

/// 搜索框，对齐原型 `.searchbar`。
class _SearchBar extends ConsumerStatefulWidget {
  const _SearchBar({required this.filterProvider, required this.keyword});

  final NotifierProvider<LibraryFilterNotifier, LibraryFilter> filterProvider;
  final String keyword;

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<_SearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.keyword);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 16, color: AppTheme.dim),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 13, color: AppTheme.text),
                decoration: const InputDecoration(
                  hintText: '跨网盘搜索歌曲、歌手、专辑…',
                  hintStyle: TextStyle(fontSize: 13, color: AppTheme.dim),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) =>
                    ref.read(widget.filterProvider.notifier).setKeyword(v),
              ),
            ),
            if (_controller.text.isNotEmpty)
              IconButton(
                tooltip: '清空',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 14, color: AppTheme.dim),
                onPressed: () {
                  _controller.clear();
                  ref.read(widget.filterProvider.notifier).setKeyword('');
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// 搜索框下面的一行：左边范围筛选，右边分组方式。
///
/// 合成一行是为了不额外占高度 —— 两个 chip 加一个三段的切换控件
/// 加起来约 280px，任何窗口宽度都放得下，所以不需要换行兜底。
/// 收藏页不显示范围筛选（那里本来就是「只看收藏」），只留分组切换。
class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.filterProvider,
    required this.scope,
    required this.group,
    required this.showScope,
  });

  final NotifierProvider<LibraryFilterNotifier, LibraryFilter> filterProvider;
  final LibraryScope scope;
  final LibraryGroupMode group;
  final bool showScope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(filterProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 13),
      child: Row(
        children: [
          if (showScope)
            for (final s in LibraryScope.values) ...[
              _FilterChip(
                label: s.label,
                selected: scope == s,
                onTap: () => notifier.setScope(s),
              ),
              const SizedBox(width: 7),
            ],
          const Spacer(),
          _GroupSwitch(
            selected: group,
            onChanged: notifier.setGroup,
          ),
        ],
      ),
    );
  }
}

/// 分组方式切换：列表 / 艺术家 / 专辑。
class _GroupSwitch extends StatelessWidget {
  const _GroupSwitch({required this.selected, required this.onChanged});

  final LibraryGroupMode selected;
  final ValueChanged<LibraryGroupMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in LibraryGroupMode.values)
            _Segment(
              label: mode.label,
              selected: selected == mode,
              onTap: () => onChanged(mode),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppTheme.accent.withValues(alpha: 0.15)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? const Color(0xFFA9C3FF) : AppTheme.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.accent.withValues(alpha: 0.15) : AppTheme.panel,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppTheme.accent.withValues(alpha: 0.45)
                  : AppTheme.line,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? const Color(0xFFA9C3FF) : AppTheme.muted,
            ),
          ),
        ),
      ),
    );
  }
}
