import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/audio_formats.dart';
import '../../domain/entities/capabilities.dart';
import '../../domain/entities/track.dart';
import '../../domain/services/library_grouping.dart';
import '../providers/playback_providers.dart';
import '../theme/app_theme.dart';
import 'cue_chip.dart';
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
    // 分段行的体积/码率要按整轨口径算（见 TrackTile.imageDurationMs）
    final imageDurations = LibraryGrouping.cueImageDurationsOf(tracks);

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
          imageDurationMs: imageDurations[track.remoteId],
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

    // 分段行的体积/码率要按整轨口径算（见 TrackTile.imageDurationMs）。
    // 整轨总时长按 `remoteId` 查，一张整轨的所有分段共用同一个值，
    // 所以整表算一次即可 —— 不必每建一行就还原一次整轨。
    final imageDurations = <String, int>{};
    for (final group in groups) {
      imageDurations.addAll(group.cueImageDurations);
    }

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
              // 「整轨连播」的队列是**整轨文件本身**，不是切出来的分段 ——
              // 后者之间要重新取链、重新装载，接缝处必然有停顿
              onPlayWholeImages: () {
                final images = group.cueImages;
                if (images.isEmpty) return;
                player.playFrom(images, images.first);
              },
            ),
          _TrackRow(:final group, :final track) => TrackTile(
              track: track,
              capabilities: capabilities,
              imageDurationMs: imageDurations[track.remoteId],
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

/// 组头：组名 + CUE 分轨标记 + 曲目数 + 「播放这一组」+「整轨连播」。
///
/// 组名用 `Expanded` 包住并省略，所以无论专辑名多长都不会把这一行撑破。
/// CUE 标记与「整轨连播」只在**这一组确实由 CUE 整轨切出来**时出现，
/// 普通专辑的组头与以前一模一样 —— 这是 方案 A 的核心：
/// CUE 只体现在组头这一处，组内每一行都是普通的曲目行。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.onPlay,
    required this.onPlayWholeImages,
  });

  final TrackGroup group;
  final VoidCallback onPlay;

  /// 「整轨连播」：把这一组的整轨文件按原样连续播放，不按 CUE 切轨。
  final VoidCallback onPlayWholeImages;

  @override
  Widget build(BuildContext context) {
    final segments = group.cueSegments;
    // 容器格式取第一段所在的那个整轨文件 —— 一张专辑的整轨恒为同一种容器，
    // 逐行去读反而会在「同目录混了 WAV 与 FLAC 整轨」时给出自相矛盾的标记
    final format = segments.isEmpty ? null : formatLabelOf(segments.first.name);
    final images = segments.isEmpty ? const <Track>[] : group.cueImages;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 4, 2),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
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
                if (format != null) ...[
                  const SizedBox(width: 8),
                  CueChip(format: format, compact: true),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${group.length} 首',
            style: const TextStyle(fontSize: 10.5, color: AppTheme.dim),
          ),
          if (images.isNotEmpty)
            _WholeImageButton(images: images, onPressed: onPlayWholeImages),
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

/// 「整轨连播」：把整轨文件当一首连续播放，不按 CUE 切轨。
///
/// 为什么这个退路是必要的：切轨点是**推算**出来的（CUE 的时间码 + 整轨时长），
/// 遇到错的分轨点、或现场专辑那种本来就无缝衔接的录音，用户需要一条
/// 「原样听」的路；而且分段之间要重新取链、重新装载，接缝处必然有停顿，
/// 整轨连播则是一条流到底。
class _WholeImageButton extends StatelessWidget {
  const _WholeImageButton({required this.images, required this.onPressed});

  final List<Track> images;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final single = images.length == 1 ? images.first : null;

    return Tooltip(
      message: single == null
          ? '这一组有 ${images.length} 张整轨，按顺序连续播放，不按 CUE 切轨'
          : '把整轨当成一首连续播放，不按 CUE 切轨\n'
              '${single.name} · ${formatBytes(single.sizeBytes)} · '
              '${formatDuration(single.duration)}',
      waitDuration: const Duration(milliseconds: 350),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.cue,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          // 组头一行已经很挤，默认的 64×36 最小尺寸会把这一行顶高一大截
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.playlist_play, size: 15),
        label: const Text('整轨连播', style: TextStyle(fontSize: 10.5)),
      ),
    );
  }
}
