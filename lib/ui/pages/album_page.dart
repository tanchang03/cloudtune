import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/audio_formats.dart';
import '../../data/remote/quark/quark_adapter.dart';
import '../../domain/entities/album_cover.dart';
import '../../domain/entities/track.dart';
import '../../domain/services/library_grouping.dart';
import '../../domain/services/playback_queue.dart';
import '../providers/library_providers.dart';
import '../providers/playback_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/album_grid.dart';
import '../widgets/cover_image.dart';
import '../widgets/cue_chip.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_back_button.dart';
import '../widgets/player_bar.dart';
import '../widgets/track_list.dart';

/// 专辑详情页：一张专辑的封面、信息与曲目。
///
/// 全屏 push 页（与「诊断日志」同一路数），不进侧栏分支 ——
/// 它是从专辑卡片点进来的一层，返回键回到卡片墙。
///
/// 曲目按**目录**取（[dirPath]），不按专辑名：专辑名是从目录名猜的，
/// 两张同名专辑（`... [16B-44.1kHz]` 与 `... [24B-48kHz]`）按名字查会混在一起，
/// 而用户点开的显然是其中一张。
class AlbumPage extends ConsumerWidget {
  const AlbumPage({super.key, required this.dirPath, this.albumTitle});

  /// 归一化后的专辑目录路径（不带结尾斜杠）
  final String dirPath;

  /// 卡片带过来的专辑名。
  ///
  /// 为什么要传：专辑名在卡片墙上是**消歧后**的（同名专辑会补上
  /// `· [16B-44.1kHz]` 之类的标记，见 `LibraryGrouping._disambiguate`），
  /// 那个结果需要看到整个曲库才能算出来，这一页只有一张专辑的曲目，
  /// 复现不了。不传时退回目录名推断，所以直接进这一页也不会显示空白。
  final String? albumTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(albumTracksProvider(dirPath));
    final covers = ref.watch(albumCoversProvider).valueOrNull ??
        const <String, AlbumCover>{};
    final scheme = Theme.of(context).colorScheme;

    final title = albumTitle ??
        folderAlbumName(lastPathSegment(dirPath)) ??
        LibraryGrouping.unknownAlbum;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // 返回键**常驻**：加载中、出错、空专辑时都要能退出去。
                  // 放进下面的内容里会让「正在加载」变成一个走不掉的页面。
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 10, 22, 0),
                    child: Row(children: [PageBackButton()]),
                  ),
                  Expanded(
                    child: tracksAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(
                        child: Text(
                          '加载失败：$e',
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                      data: (tracks) {
                        if (tracks.isEmpty) {
                          return const EmptyState(
                            icon: Icons.album_outlined,
                            title: '这张专辑现在是空的',
                            message: '曲目可能已经在网盘上被删掉或移走了。'
                                '重新扫一次曲库就会同步。',
                          );
                        }
                        return Column(
                          children: [
                            _AlbumHero(
                              title: title,
                              tracks: tracks,
                              cover: covers[dirPath],
                            ),
                            Expanded(
                              child: TrackGroupListView(
                                // 组名为空 → 不画组头，这一页的「组头」就是上面那块
                                groups: [
                                  TrackGroup(
                                    key: dirPath,
                                    title: '',
                                    tracks: tracks,
                                  ),
                                ],
                                capabilities: QuarkAdapter.quarkCapabilities,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 播放条要**自己挂**，不能指望外壳。
          //
          // 这一页是顶级全屏路由（见 `app_router.dart`），进来之后
          // `AppShell` 整个不在树上，而播放条是外壳的一部分（宽屏在
          // `Column` 末尾、窄屏在 `bottomNavigationBar` 里）—— 不挂的话，
          // 从这一页点播放会「没有任何反馈」：歌响了，但界面上找不到
          // 暂停键、进度和当前曲目，得退回曲库才看得到。
          //
          // 所以**全屏页要自己把播放条摆上**。`/player` 是例外：它本身
          // 就是播放器，再叠一条只会多出一套重复的走带控制。
          const PlayerBar(),
        ],
      ),
    );
  }
}

/// 专辑页头：大封面 + 专辑名 / 艺术家 / 统计 + 三个播放入口。
class _AlbumHero extends ConsumerWidget {
  const _AlbumHero({
    required this.title,
    required this.tracks,
    required this.cover,
  });

  final String title;
  final List<Track> tracks;
  final AlbumCover? cover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = AppTheme.isWide(context);
    // 窄窗口把封面收小：这一行里还要放专辑名与三个按钮，
    // 封面按 132 占位的话信息列会被压到只剩几个字。
    final coverSize = wide ? 132.0 : 92.0;

    final provider =
        tracks.isEmpty ? kLibraryProvider : tracks.first.provider;
    final segments = LibraryGrouping.cueSegmentsOf(tracks);
    // 容器格式取第一段所在的整轨文件，理由同分组头：一张专辑的整轨
    // 恒为同一种容器，逐行去读反而会给出自相矛盾的标记
    final format = segments.isEmpty ? null : formatLabelOf(segments.first.name);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: coverSize,
            height: coverSize,
            child: CoverImage(
              provider: provider,
              cover: cover,
              radius: 14,
              iconRatio: 0.34,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  albumArtistLabel(tracks),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppTheme.muted),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _metaLine(tracks),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppTheme.dim),
                      ),
                    ),
                    if (format != null) ...[
                      const SizedBox(width: 8),
                      CueChip(format: format),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // Wrap 而不是 Row：窄窗口下三个按钮放不下时要能换行，
                // 而不是把这一行挤到溢出
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroButton(
                      icon: Icons.play_arrow_rounded,
                      label: '播放全部',
                      tooltip: '从这张专辑的第一首开始，按顺序播完整张',
                      primary: true,
                      onPressed: () => _playFrom(ref, tracks, tracks.first),
                    ),
                    _HeroButton(
                      icon: Icons.shuffle,
                      label: '随机播放',
                      tooltip: '把这张专辑打乱后随机播放',
                      onPressed: () => _playFrom(
                        ref,
                        tracks,
                        tracks[Random().nextInt(tracks.length)],
                        mode: PlaybackMode.shuffle,
                      ),
                    ),
                    if (segments.isNotEmpty)
                      _HeroButton(
                        icon: Icons.playlist_play,
                        label: '整轨连播',
                        tooltip: '把整轨文件当一首连续播放，不按 CUE 切轨',
                        accent: AppTheme.cue,
                        onPressed: () {
                          final images = LibraryGrouping.cueImagesOf(tracks);
                          if (images.isEmpty) return;
                          _playFrom(ref, images, images.first);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 把这份曲目设成播放队列并从 [start] 开始。
  ///
  /// 与列表头的两个播放入口同一套语义：**队列就是眼前这一张专辑**，
  /// 所以播到最后一首不会串到别的专辑去。
  void _playFrom(
    WidgetRef ref,
    List<Track> queue,
    Track start, {
    PlaybackMode? mode,
  }) {
    final player = ref.read(playerProvider.notifier);
    // 先定模式再设队列：playFrom 会替换曲池，但不碰模式
    if (mode != null) player.setMode(mode);
    player.playFrom(queue, start);
  }

  /// `12 首 · 52:31 · 356 MB`，拿不到的项直接不显示。
  ///
  /// 体积用 [LibraryGrouping.totalSizeOf] 而不是把 `sizeBytes` 相加 ——
  /// 整轨切出的每一段都带着整轨体积，直接相加会把一张专辑算成十几张的体积。
  static String _metaLine(List<Track> tracks) {
    final parts = <String>['${tracks.length} 首'];
    final duration = formatDuration(
      Duration(milliseconds: LibraryGrouping.totalDurationMsOf(tracks)),
    );
    if (duration != '--:--') parts.add(duration);
    final bytes = formatBytes(LibraryGrouping.totalSizeOf(tracks));
    if (bytes != '未知') parts.add(bytes);
    return parts.join(' · ');
  }
}

/// 专辑页头的一个播放入口。
class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.primary = false,
    this.accent,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  /// 主操作（「播放全部」）用实心按钮，其余用描边 ——
  /// 三个按钮长得一模一样时用户得读三遍文字才知道点哪个。
  final bool primary;

  /// 覆盖强调色（「整轨连播」用 CUE 色，与卡片上的标记同一口径）
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppTheme.accent;
    final style = TextButton.styleFrom(
      foregroundColor: primary ? Colors.white : color,
      backgroundColor: primary ? AppTheme.accent : null,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );

    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        style: style,
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
