import 'package:flutter/gestures.dart' show DragStartBehavior;
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
///
/// **窄窗口下要主动让位**：这一行全是写死的宽度 —— 两侧内边距 18×2、封面 44、
/// 曲目块 190、控制区约 208、三处 16 的间距，合计 526；进度条两端还有两个
/// 时间文本（测试字体下各 44）。600 宽实测**溢出 59px**。
/// 所以窄于 [_compactWidth] 时收两处：
///
///   1. 曲目块 190 → 130（标题本来就是省略号，收窄只是少显示几个字）；
///   2. 砍掉进度条两端的时间文本 —— 细条本身已经表达了进度，
///      时间是最可以先放下的信息，而它占的宽度却和曲目块一个量级。
///
/// 阈值取 740 而不是实测的临界值：`flutter_test` 的字体每个字符都是满 em
/// 方块，同一串数字比真实字体（PingFang SC）宽近一倍，按真实字体的临界值
/// 设阈值会让单测在阈值上方仍然溢出。740 对两边都安全，而真实字体下
/// 740 宽时整行本来就放得下，等于没有额外牺牲。
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  /// 窄于此宽度时收曲目块、砍进度条两端的时间。见类注释。
  static const double _compactWidth = 740;

  /// 曲目块宽度：常规 / 紧凑。
  static const double _nowWidth = 190;
  static const double _nowWidthCompact = 130;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _compactWidth;
          return Row(
            children: [
              _Cover(track: track),
              const SizedBox(width: 16),
              SizedBox(
                width: compact ? _nowWidthCompact : _nowWidth,
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
                  showTimes: !compact,
                ),
              ),
            ],
          );
        },
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
///
/// 四个坑都是实测踩出来的，**别改回去**：
///
///   1. **命中区不能只有 4px。** 视觉上要细，命中区要厚：外面套一层 20px 的
///      透明带，细条在其中垂直居中。命中区等于 4px 时鼠标几乎点不中，
///      用户看到的现象就是「进度条拖不动」。
///   2. **宽度必须来自 `LayoutBuilder`。** 原先用 `context.findRenderObject()`
///      取宽度，拿到的是本组件最外层 `Row` 的 RenderObject —— 它把左右两段
///      时间文本也算进去了，于是 `dx / width` 恒小于真实比例，拖到最右边
///      也只跳到中途（「够不到尾部」）。
///   3. **拖动过程中不要逐帧下发 seek。** 夸克直链每次 seek 都要重新拉流，
///      连发会把网络和播放器一起打爆。这里拖动只做本地预览，松手（或单击）
///      才下发一次。
///   4. **手势要用 `DragStartBehavior.down`，松手位置要读 `DragEndDetails`。**
///      默认的 `start` 行为会跳过第一次移动，快速拖动只产生一个 move 事件时
///      一次 update 都不会来，松手就成了空操作（见 `monodrag.dart` 里
///      `localUpdateDelta == Offset.zero` 那个分支）。
class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar({
    required this.position,
    required this.total,
    required this.ratio,
    required this.enabled,
    required this.showTimes,
  });

  final Duration position;
  final Duration total;
  final double ratio;
  final bool enabled;

  /// 是否显示两端的时间文本。
  ///
  /// 窄窗口下关掉（见 `PlayerBar` 的类注释）：这两个文本一共要占约 88px
  /// （测试字体口径），比曲目块还宽，而细条本身已经表达了进度。
  /// 关掉时细条铺满整行，拖拽比例仍然按**细条自己的宽度**算，
  /// 所以拖动精度反而更高。
  final bool showTimes;

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  /// 命中区高度。视觉上的细条仍然只有 4px，多出来的部分是透明的。
  static const double _hitHeight = 20;

  /// 拖动中的进度（0..1）。非 null 表示手还按着 —— 这期间忽略外部流入的
  /// [position]，否则播放位置流会把刚拖到的位置拽回去，手感像「拖不动」。
  double? _dragRatio;

  @override
  Widget build(BuildContext context) {
    final total = widget.total;
    final seekable = widget.enabled && total > Duration.zero;
    final dragRatio = _dragRatio;
    final ratio = (dragRatio ?? widget.ratio).clamp(0.0, 1.0);
    // 拖动时左侧时间跟着手指走，否则用户不知道自己正跳到哪儿
    final shown = dragRatio == null
        ? widget.position
        : Duration(milliseconds: (total.inMilliseconds * ratio).round());

    return Row(
      children: [
        if (widget.showTimes) ...[
          Text(
            formatDuration(shown),
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.dim,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: SizedBox(
            height: _hitHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 命中区与细条等宽，所以这里的 maxWidth 就是「拖到 1.0」的基准
                final width = constraints.maxWidth;
                final bar = _SeekTrack(width: width, ratio: ratio);
                if (!seekable) return Center(child: bar);

                double ratioAt(double dx) =>
                    width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // 默认的 `start` 行为会**跳过第一次移动**（见 monodrag.dart 的
                  // `localUpdateDelta == Offset.zero` 分支）：快速拖动只产生一个
                  // move 事件时，update 一次都不会触发，松手就成了空操作。
                  // 用 `down` 让第一次 update 就落在按下的位置。
                  dragStartBehavior: DragStartBehavior.down,
                  // 单击直接跳
                  onTapUp: (d) => _commit(ratioAt(d.localPosition.dx)),
                  // 拖动先本地预览，松手才真正下发
                  onHorizontalDragUpdate: (d) =>
                      setState(() => _dragRatio = ratioAt(d.localPosition.dx)),
                  // 松手位置以 DragEndDetails 为准：它不依赖 update 有没有触发过
                  onHorizontalDragEnd: (d) => _commit(ratioAt(d.localPosition.dx)),
                  onHorizontalDragCancel: () {
                    if (_dragRatio != null) setState(() => _dragRatio = null);
                  },
                  child: Center(child: bar),
                );
              },
            ),
          ),
        ),
        if (widget.showTimes) ...[
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
      ],
    );
  }

  /// 按比例下发 seek，并退出「拖动中」状态。
  void _commit(double ratio) {
    if (_dragRatio != null) setState(() => _dragRatio = null);
    final total = widget.total;
    if (total <= Duration.zero) return;
    ref.read(playerProvider.notifier).seek(
          Duration(
            milliseconds: (total.inMilliseconds * ratio.clamp(0.0, 1.0)).round(),
          ),
        );
  }
}

/// 只有 4px 的细条本体：全长轨道 + 左侧渐变已播段。
///
/// [width] 必须由外面显式传进来 —— 它上面套着 `Center`，拿到的是松约束，
/// 不给宽会塌成 0（整条轨道底色就消失了）。
class _SeekTrack extends StatelessWidget {
  const _SeekTrack({required this.width, required this.ratio});

  final double width;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        width: width,
        height: 4,
        color: AppTheme.panel3,
        child: FractionallySizedBox(
          widthFactor: ratio.clamp(0.0, 1.0),
          alignment: Alignment.centerLeft,
          child: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppTheme.brandGradient),
          ),
        ),
      ),
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
