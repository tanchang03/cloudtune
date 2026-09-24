import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/track.dart';
import '../providers/library_providers.dart';
import '../providers/playback_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/playback_mode_button.dart';
import '../widgets/page_back_button.dart';

/// 播放器页（全屏）。
///
/// 进度条拖动时暂停订阅流、本地暂存位置，松手才下发 seek，
/// 避免「流回灌」与手指拖动打架导致进度条乱跳。
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  bool _dragging = false;
  double _dragSeconds = 0;

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
    final duration = ref.watch(playbackDurationProvider).valueOrNull;
    final playing = ref.watch(playbackPlayingProvider).valueOrNull ?? false;
    final favorites = ref.watch(favoriteIdsProvider).valueOrNull ?? const <String>{};
    final isFavorite = favorites.contains(track.id);

    final maxSec = (duration?.inSeconds ?? 0).toDouble();
    final shownSec = _dragging ? _dragSeconds : position.inSeconds.toDouble();
    final sliderMax = maxSec <= 0 ? 1.0 : maxSec;
    final sliderValue = shownSec.clamp(0.0, sliderMax).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        children: [
          const SizedBox(height: 12),
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
          const SizedBox(height: 24),
          Row(
            children: [
              Text(formatDuration(position),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              Expanded(
                child: Slider(
                  value: sliderValue,
                  max: sliderMax,
                  onChanged: maxSec <= 0
                      ? null
                      : (v) {
                          setState(() {
                            _dragging = true;
                            _dragSeconds = v;
                          });
                        },
                  onChangeEnd: (v) {
                    _dragging = false;
                    ref.read(playerProvider.notifier).seek(Duration(seconds: v.toInt()));
                  },
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
          const Spacer(),
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
