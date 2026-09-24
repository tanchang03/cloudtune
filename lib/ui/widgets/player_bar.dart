import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/track.dart';
import '../providers/library_providers.dart';
import '../providers/playback_providers.dart';
import '../theme/app_theme.dart';
import 'album_art.dart';
import 'note_glyph.dart';
import 'playback_mode_button.dart';

/// 常驻底部的播放条，1:1 对齐设计原型 `.playerbar`（高 74）。
///
/// 列序：封面 44 → 当前曲目（宽 190）→ 控制区 → 进度条。
/// 没有曲目时也占位（只是控件置灰），否则播第一首歌时整个窗口会往下跳一截。
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final track = player.current;
    final playing = ref.watch(playbackPlayingProvider).valueOrNull ?? false;
    final position =
        ref.watch(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final total = ref.watch(playbackDurationProvider).valueOrNull ??
        track?.duration ??
        Duration.zero;

    final enabled = track != null;
    final ratio = total > Duration.zero
        ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      height: AppTheme.playerBarHeight,
      decoration: const BoxDecoration(
        color: AppTheme.panel,
        border: Border(top: BorderSide(color: AppTheme.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          _Cover(track: track),
          const SizedBox(width: 16),
          SizedBox(
            width: 190,
            child: _NowPlaying(track: track, notice: player.notice),
          ),
          const SizedBox(width: 16),
          _Controls(
            enabled: enabled,
            playing: playing,
            busy: player.busy,
            track: track,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _SeekBar(
              position: position,
              total: total,
              ratio: ratio,
              enabled: enabled,
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.coverRadius),
        child: Container(
          width: 44,
          height: 44,
          color: AppTheme.panel3,
          alignment: Alignment.center,
          child: const NoteGlyph(size: 16, color: AppTheme.dim),
        ),
      );
    }
    return AlbumArt(provider: t.provider, size: 44);
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.track, required this.notice});

  final Track? track;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null) {
      return const Text(
        '未在播放',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: AppTheme.dim),
      );
    }

    // 出问题（续链、跳过）时优先把原因露出来 —— 用户此刻最需要的不是艺术家名
    final subtitle =
        t.displaySubtitle.isEmpty ? t.name : t.displaySubtitle;
    final second = notice ?? '$subtitle · ${t.provider.shortName}';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push('/player'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            second,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: notice != null ? AppTheme.warn : AppTheme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({
    required this.enabled,
    required this.playing,
    required this.busy,
    required this.track,
  });

  final bool enabled;
  final bool playing;
  final bool busy;
  final Track? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(playerProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 播放顺序是偏好而不是走带控制，所以不随「有没有歌在播」置灰
        const PlaybackModeButton(),
        const SizedBox(width: 8),
        _CtrlButton(
          icon: Icons.skip_previous,
          size: 34,
          iconSize: 19,
          tooltip: '上一首',
          onPressed: enabled ? notifier.previous : null,
        ),
        const SizedBox(width: 8),
        // 主播放键：原型 .ctrl .main，40×40 品牌渐变
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accent.withValues(alpha: enabled ? 0.32 : 0.0),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: IconButton(
            tooltip: playing ? '暂停' : '播放',
            padding: EdgeInsets.zero,
            onPressed: enabled ? notifier.togglePlay : null,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    size: 17,
                    color: Colors.white,
                  ),
          ),
        ),
        const SizedBox(width: 8),
        _CtrlButton(
          icon: Icons.skip_next,
          size: 34,
          iconSize: 19,
          tooltip: '下一首',
          onPressed: enabled ? notifier.next : null,
        ),
        const SizedBox(width: 8),
        _FavoriteButton(track: track),
      ],
    );
  }
}

class _CtrlButton extends StatelessWidget {
  const _CtrlButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: iconSize,
          color: onPressed == null ? AppTheme.dim : AppTheme.text,
        ),
      ),
    );
  }
}

/// 进度条。原型里是静态的，这里做成可拖拽 —— 4px 细条本来就该能拖，
/// 视觉上仍然是「细条 + 渐变已播段」，不加滑块圆点。
class _SeekBar extends ConsumerWidget {
  const _SeekBar({
    required this.position,
    required this.total,
    required this.ratio,
    required this.enabled,
  });

  final Duration position;
  final Duration total;
  final double ratio;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 4,
        child: FractionallySizedBox(
          widthFactor: ratio,
          alignment: Alignment.centerLeft,
          child: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppTheme.brandGradient),
          ),
        ),
      ),
    );

    return Row(
      children: [
        Text(
          formatDuration(position),
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.dim,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.panel3,
              borderRadius: BorderRadius.circular(99),
            ),
            child: enabled
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) {
                      final box = context.findRenderObject() as RenderBox?;
                      final width = box?.size.width ?? 0;
                      if (width <= 0 || total <= Duration.zero) return;
                      final r =
                          (details.localPosition.dx / width).clamp(0.0, 1.0);
                      ref.read(playerProvider.notifier).seek(
                            Duration(
                              milliseconds: (total.inMilliseconds * r).round(),
                            ),
                          );
                    },
                    child: bar,
                  )
                : bar,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          formatDuration(total),
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.dim,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _FavoriteButton extends ConsumerWidget {
  const _FavoriteButton({required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = track;
    final favorites =
        ref.watch(favoriteIdsProvider).valueOrNull ?? const <String>{};
    final on = t != null && favorites.contains(t.id);

    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        tooltip: on ? '取消收藏' : '收藏',
        padding: EdgeInsets.zero,
        onPressed: t == null
            ? null
            : () => ref
                .read(favoriteActionsProvider)
                .toggle(t.id, value: !on),
        icon: Icon(
          on ? Icons.favorite : Icons.favorite_border,
          size: 18,
          color: on
              ? AppTheme.heart
              : (t == null ? AppTheme.dim : AppTheme.muted),
        ),
      ),
    );
  }
}
