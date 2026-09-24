import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/capabilities.dart';
import '../../domain/entities/track.dart';
import '../../domain/services/library_grouping.dart';
import '../providers/playback_providers.dart';
import '../theme/app_theme.dart';
import 'track_tile.dart';

/// 一个可滚动的曲目列表。点哪首都从「当前列表」开始播放。
///
/// 宽屏时首行是列头（标题 / 来源 / 网盘路径 / 格式·品质 / 大小 / 时长），
/// 与曲目行的列宽严格一致，否则列头会对不上 ——
/// 两边的宽度都读 `AppTheme` 里的同一批令牌，改一处必须改两处的情况已经不存在了。
class TrackListView extends ConsumerWidget {
  const TrackListView({
    super.key,
    required this.tracks,
    required this.capabilities,
  });

  final List<Track> tracks;
  final Capabilities capabilities;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = AppTheme.isWide(context);

    return ListView.builder(
      // 曲目行自带 8px 横向内边距，这里补 6px 凑成设计稿 .desk-list 的 14px
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
      itemCount: tracks.length + (wide ? 1 : 0),
      itemBuilder: (context, index) {
        if (wide) {
          if (index == 0) return const _ColumnHeader();
          index -= 1;
        }
        final track = tracks[index];
        return TrackTile(
          track: track,
          capabilities: capabilities,
          onPlay: () =>
              ref.read(playerProvider.notifier).playFrom(tracks, track),
        );
      },
    );
  }
}

/// 列头，对齐原型 `.dhead`：10.5px dim、字距 .5、字重 600。
class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader();

  static const TextStyle _style = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: AppTheme.dim,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          const SizedBox(width: AppTheme.coverSize),
          const SizedBox(width: AppTheme.rowGap),
          const Expanded(flex: 3, child: Text('标题 / 艺术家', style: _style)),
          const SizedBox(width: AppTheme.rowGap),
          const SizedBox(
            width: AppTheme.sourceColWidth,
            child: Text('来源', style: _style),
          ),
          const SizedBox(width: AppTheme.rowGap),
          const Expanded(flex: 2, child: Text('网盘路径', style: _style)),
          const SizedBox(width: AppTheme.rowGap),
          // 标题写「格式 / 品质」而不是只写「品质」：这一列里 chip 是格式、
          // 后面的文字是品质，标题得让人一眼知道两种信息都在这儿
          const SizedBox(
            width: AppTheme.qualityColWidth,
            child: Text('格式 / 品质', style: _style),
          ),
          const SizedBox(width: AppTheme.rowGap),
          const SizedBox(
            width: AppTheme.sizeColWidth,
            child: Text('大小', textAlign: TextAlign.right, style: _style),
          ),
          const SizedBox(width: AppTheme.rowGap),
          const SizedBox(
            width: 56,
            child: Text('时长', textAlign: TextAlign.right, style: _style),
          ),
          const SizedBox(width: AppTheme.rowGap),
          const SizedBox(width: 30),
        ],
      ),
    );
  }
}

/// 分组视图：组头 + 组内曲目行。
///
/// 组头与曲目行被**拍平进同一个 `ListView`**，而不是「外层列表里套内层列表」——
/// 嵌套的滚动区高度不受控，正是布局溢出的常见来源。
///
/// 组内播放时把**整组**当播放队列，所以在专辑视图里点一首歌，
/// 后面接着放的就是这张专辑的下一首。
///
/// [groups] 里 `title` 为空的分组不画组头，因此平铺模式（列表）
/// 复用同一个组件，调用方不必分叉。
class TrackGroupListView extends ConsumerWidget {
  const TrackGroupListView({
    super.key,
    required this.groups,
    required this.capabilities,
  });

  final List<TrackGroup> groups;
  final Capabilities capabilities;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = AppTheme.isWide(context);

    final rows = <_GroupedRow>[
      for (final group in groups) ...[
        if (group.title.isNotEmpty) _HeaderRow(group),
        for (final track in group.tracks) _TrackRow(group: group, track: track),
      ],
    ];

    return ListView.builder(
      // 曲目行自带 8px 横向内边距，这里补 6px 凑成设计稿 .desk-list 的 14px
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
      itemCount: rows.length + (wide ? 1 : 0),
      itemBuilder: (context, index) {
        if (wide) {
          if (index == 0) return const _ColumnHeader();
          index -= 1;
        }
        final player = ref.read(playerProvider.notifier);
        return switch (rows[index]) {
          _HeaderRow(:final group) => _GroupHeader(
              group: group,
              onPlay: () =>
                  player.playFrom(group.tracks, group.tracks.first),
            ),
          _TrackRow(:final group, :final track) => TrackTile(
              track: track,
              capabilities: capabilities,
              onPlay: () => player.playFrom(group.tracks, track),
            ),
        };
      },
    );
  }
}

/// 分组视图里的一行：要么是组头，要么是曲目。
sealed class _GroupedRow {
  const _GroupedRow();
}

class _HeaderRow extends _GroupedRow {
  const _HeaderRow(this.group);

  final TrackGroup group;
}

class _TrackRow extends _GroupedRow {
  const _TrackRow({required this.group, required this.track});

  final TrackGroup group;
  final Track track;
}

/// 组头：组名 + 曲目数 + 「播放这一组」。
///
/// 组名用 `Expanded` 包住并省略，所以无论专辑名多长都不会把这一行撑破。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.onPlay});

  final TrackGroup group;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 4, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.text,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${group.length} 首',
            style: const TextStyle(fontSize: 10.5, color: AppTheme.dim),
          ),
          IconButton(
            tooltip: '播放这一组',
            visualDensity: VisualDensity.compact,
            iconSize: 17,
            color: AppTheme.accent,
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ],
      ),
    );
  }
}
