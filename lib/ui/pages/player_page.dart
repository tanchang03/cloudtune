import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/track.dart';
import '../providers/library_providers.dart';
import '../providers/playback_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/lyrics_panel.dart';
import '../widgets/playback_mode_button.dart';
import '../widgets/page_back_button.dart';

/// 播放器页（全屏）。
///
/// 进度条拖动时本地暂存位置、松手才下发 seek，避免「流回灌」与手指拖动
/// 打架导致进度条乱跳；左侧时间在拖动期间也跟着手指走。
///
/// 时长取「播放器声明的时长」，拿不到时兜底到曲目元数据 —— 详见
/// [_PlayerPageState._buildBody] 里的注释。
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  bool _dragging = false;

  /// 拖动中暂存的位置（毫秒）。用毫秒而不是秒：秒级粒度对一首 3 分钟的曲子
  /// 只有 180 档，拖起来一跳一跳的。
  double _dragMs = 0;

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final track = player.current;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // 系统标题栏已经被抹掉（见 macos/Runner/MainFlutterWindow.swift），
          // 返回入口得自己给。刻意比 AppBar 的 56 矮：顶上已经有一条虚拟标题栏，
          // 再压一条 56 的会很挤，这里把纵向空间还给内容。
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Row(
              children: [
                PageBackButton(icon: Icons.expand_more, tooltip: '收起'),
              ],
            ),
          ),
          Expanded(
            child: track == null
                ? EmptyState(
                    icon: Icons.play_circle_outline,
                    title: '还没有在播放',
                    message: '去曲库挑一首，或点随机播放。',
                    action: FilledButton.icon(
                      onPressed: () => context.go('/library'),
                      icon: const Icon(Icons.library_music),
                      label: const Text('去曲库'),
                    ),
                  )
                : _buildBody(player: player, track: track, scheme: scheme),
          ),
        ],
      ),
    );
  }

  Widget _buildBody({
    required PlayerState player,
    required Track track,
    required ColorScheme scheme,
  }) {
    final position = ref.watch(playbackPositionProvider).valueOrNull ?? Duration.zero;
    // 时长兜底到曲目自带的元数据：DSF 这类容器、以及刚装载还没探到时长的时候，
    // 播放器会报 `null` 甚至 `0`。只认播放器的话进度条会被整条禁用 ——
    // 用户看到的现象就是「进度条拖不动」。
    final duration =
        ref.watch(playbackDurationProvider).valueOrNull ?? track.duration;
    final playing = ref.watch(playbackPlayingProvider).valueOrNull ?? false;
    final favorites = ref.watch(favoriteIdsProvider).valueOrNull ?? const <String>{};
    final isFavorite = favorites.contains(track.id);

    final maxMs = (duration?.inMilliseconds ?? 0).toDouble();
    final shownMs = _dragging ? _dragMs : position.inMilliseconds.toDouble();
    final sliderMax = maxMs <= 0 ? 1.0 : maxMs;
    final sliderValue = shownMs.clamp(0.0, sliderMax).toDouble();
    // 时长未知就无从把「拖到哪儿」换算成时间，只能禁用；三个回调必须一起为
    // null，否则会留下「松手却不会跳」的死代码。
    final canSeek = maxMs > 0;

    // 点歌词跳过去。时长未知时**不给**这个回调：滑块都拖不动，
    // 歌词行却点得动、点完什么也不发生，是更难解释的一种状态。
    final onSeek = canSeek
        ? (Duration at) => ref.read(playerProvider.notifier).seek(at)
        : null;

    // 宽屏左右两栏（左封面、右歌词），窄屏退回原型那套居中一列。
    //
    // 为什么值得分两套：播放页是**顶层全屏路由**（没有侧栏、没有播放条），
    // 宽度就是整个窗口，而窗口最小 1060 —— 居中一列时封面左右各空着
    // 300 多像素，同时歌词只能挤在封面下面那 190px 里。实测（1060×754）：
    // 挤在下面约 190px（≈7 行），左右两栏则能拿到 530px（≈20 行）。
    // 「滚动播出」这件事在 7 行的高度里是不成立的。
    final wide = AppTheme.isWide(context);
    final head = _TrackHead(track: track);
    final lyrics = LyricsPanel(track: track, onSeek: onSeek);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        children: [
          Expanded(
            child: wide
                ? Row(
                    children: [
                      SizedBox(width: 300, child: Center(child: head)),
                      const SizedBox(width: 28),
                      Expanded(child: lyrics),
                    ],
                  )
                : Column(
                    children: [
                      const SizedBox(height: 12),
                      head,
                      const SizedBox(height: 16),
                      Expanded(child: lyrics),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // 拖动时左侧时间跟着手指走，否则用户不知道自己正跳到哪儿
              Text(formatDuration(Duration(milliseconds: shownMs.round())),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              Expanded(
                child: Slider(
                  value: sliderValue,
                  max: sliderMax,
                  onChangeStart: canSeek
                      ? (v) => setState(() {
                            _dragging = true;
                            _dragMs = v;
                          })
                      : null,
                  onChanged: canSeek
                      ? (v) => setState(() {
                            _dragging = true;
                            _dragMs = v;
                          })
                      : null,
                  onChangeEnd: canSeek
                      ? (v) {
                          setState(() => _dragging = false);
                          ref
                              .read(playerProvider.notifier)
                              .seek(Duration(milliseconds: v.round()));
                        }
                      : null,
                ),
              ),
              Text(formatDuration(duration),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
          if (player.notice != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (player.noticeIsProblem ? scheme.error : scheme.primary)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    player.noticeIsProblem
                        ? Icons.warning_amber_outlined
                        : Icons.info_outline,
                    size: 16,
                    color: player.noticeIsProblem ? scheme.error : scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      player.notice!,
                      style: TextStyle(
                        fontSize: 12,
                        color: player.noticeIsProblem ? scheme.error : scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 与播放条上那颗是同一个控件：单击切顺序/随机，右键选单曲循环
              const PlaybackModeButton(size: 48, iconSize: 26),
              IconButton(
                icon: const Icon(Icons.skip_previous),
                tooltip: '上一首',
                onPressed: () => ref.read(playerProvider.notifier).previous(),
              ),
              IconButton(
                iconSize: 56,
                icon: player.busy
                    ? const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                tooltip: playing ? '暂停' : '播放',
                onPressed: () => ref.read(playerProvider.notifier).togglePlay(),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                tooltip: '下一首',
                onPressed: () => ref.read(playerProvider.notifier).next(),
              ),
              IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? scheme.error : null,
                ),
                tooltip: isFavorite ? '取消收藏' : '收藏',
                onPressed: () => ref
                    .read(favoriteActionsProvider)
                    .toggle(track.id, value: !isFavorite),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// 封面 + 曲名 + 艺术家。
///
/// 单独抽出来是因为宽屏把它放在左栏、窄屏放在最上面 —— 同一份内容
/// 出现两次实现，迟早会只改一边（原型 `.p-cover` + `.p-title`）。
class _TrackHead extends StatelessWidget {
  const _TrackHead({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 原型 .p-cover：250×250 圆角 26，蓝→紫→粉 140° 渐变
        AlbumArt(
          provider: track.provider,
          size: 250,
          radius: 26,
          showBadge: false,
          iconSize: 64,
          gradient: const LinearGradient(
            begin: Alignment(-0.77, -1),
            end: Alignment(0.77, 1),
            colors: [
              Color(0xFF3A63D8),
              Color(0xFF8B4DE0),
              Color(0xFFD8498C),
            ],
            stops: [0, 0.55, 1],
          ),
        ),
        const SizedBox(height: 28),
        Text(
          track.displayTitle,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Text(
          track.displaySubtitle.isEmpty ? '未知艺术家' : track.displaySubtitle,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
