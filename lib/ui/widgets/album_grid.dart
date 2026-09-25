import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/album_cover.dart';
import '../../domain/entities/track.dart';
import '../../domain/services/library_grouping.dart';
import '../providers/library_providers.dart';
import '../providers/playback_providers.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';

/// 专辑的艺术家标签。
///
/// 一位歌手就用他；出现两位以上是**合辑** —— 把第一首的演唱者当整张专辑的
/// 艺术家是错的（合辑里每首歌的人都不同，用户会以为分组串了）。
/// 一个都没有时说「未知艺术家」。
///
/// 卡片墙与专辑详情页共用它，两处显示的名字才不会不一致。
String albumArtistLabel(Iterable<Track> tracks) {
  final artists = <String>{};
  for (final t in tracks) {
    final a = t.displayArtist;
    if (a != null && a.isNotEmpty) artists.add(a);
  }
  if (artists.length == 1) return artists.first;
  if (artists.isEmpty) return LibraryGrouping.unknownArtist;
  return '合辑';
}

/// 专辑视图：封面卡片墙。
///
/// **只用于专辑分组**：[TrackGroup.key] 在专辑分组下就是目录路径，而封面
/// 是按目录存的，所以 `covers[group.key]` 能直接取到。列表 / 艺术家视图
/// 仍然走 [TrackGroupListView]（组头 + 曲目行）。
///
/// 卡片尺寸是**算出来的**而不是交给 `maxCrossAxisExtent`：卡片的文字区高度
/// 与宽度无关（两行文字），而封面是正方形，所以「高 = 宽 + 文字区」这个
/// 关系必须自己表达。用固定 `childAspectRatio` 近似的话，在某个窗口宽度上
/// 必然差几个像素 —— 那就是黄黑条纹。
class AlbumGridView extends ConsumerWidget {
  const AlbumGridView({
    super.key,
    required this.groups,
    required this.onOpen,
  });

  /// 专辑分组（`LibraryGrouping.group(tracks, LibraryGroupMode.album)` 的结果）
  final List<TrackGroup> groups;

  /// 点开一张专辑
  final void Function(TrackGroup group) onOpen;

  static const double _hPadding = 22;
  static const double _gap = 16;
  static const double _targetTileWidth = 176;

  // 文字区的构成，逐项写出来是为了让它和 [_captionHeight] 的算法
  // 与卡片里的实际排版**一一对应** —— 对不上就是溢出。
  static const double _coverToText = 8;
  static const double _titleSize = 13.5;
  static const double _subtitleSize = 11;
  static const double _textLineHeight = 1.3;
  static const double _titleToSubtitle = 2;
  static const double _slack = 2;

  /// 卡片文字区的高度。
  ///
  /// 按**用户当前的字号设置**算（`TextScaler`），不是写死一个像素值：
  /// 系统字号调大后文字会变高，写死的高度就会溢出；按比例算则卡片整体
  /// 变高、文字照常放大，两边都不亏。
  static double _captionHeight(TextScaler scaler) =>
      _coverToText +
      scaler.scale(_titleSize) * _textLineHeight +
      _titleToSubtitle +
      scaler.scale(_subtitleSize) * _textLineHeight +
      _slack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final covers = ref.watch(albumCoversProvider).valueOrNull ??
        const <String, AlbumCover>{};
    final scaler = MediaQuery.textScalerOf(context);
    final player = ref.read(playerProvider.notifier);

    return LayoutBuilder(
      builder: (context, box) {
        final avail = box.maxWidth - _hPadding * 2;
        // 按目标宽度算列数。窗口是可拖动的，列数必须跟着变 ——
        // 固定列数会让窗口一窄卡片就被压扁。
        final columns = avail <= 0
            ? 1
            : (avail / _targetTileWidth).round().clamp(1, 10);
        final tileW = avail <= 0
            ? _targetTileWidth
            : (avail - _gap * (columns - 1)) / columns;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(_hPadding, 2, _hPadding, 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 18,
            crossAxisSpacing: _gap,
            childAspectRatio: tileW / (tileW + _captionHeight(scaler)),
          ),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            return _AlbumCard(
              group: group,
              cover: covers[group.key],
              onOpen: () => onOpen(group),
              // 点卡片上的播放键 = 从第一首开始放这一整张
              onPlay: () =>
                  player.playFrom(group.tracks, group.tracks.first),
            );
          },
        );
      },
    );
  }
}

class _AlbumCard extends StatefulWidget {
  const _AlbumCard({
    required this.group,
    required this.cover,
    required this.onOpen,
    required this.onPlay,
  });

  final TrackGroup group;
  final AlbumCover? cover;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  State<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<_AlbumCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final provider =
        group.tracks.isEmpty ? kLibraryProvider : group.tracks.first.provider;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // opaque：封面下方的空白区也要能点开，否则点卡片边缘没反应
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverImage(provider: provider, cover: widget.cover),
                  if (group.hasCueSegments)
                    const Positioned(left: 8, top: 8, child: _CueBadge()),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _HoverPlayButton(
                      visible: _hovered,
                      onPressed: widget.onPlay,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AlbumGridView._coverToText),
            Text(
              group.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: AlbumGridView._titleSize,
                height: AlbumGridView._textLineHeight,
                fontWeight: FontWeight.w600,
                color: AppTheme.text,
              ),
            ),
            const SizedBox(height: AlbumGridView._titleToSubtitle),
            Text(
              '${albumArtistLabel(group.tracks)} · ${group.length} 首',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: AlbumGridView._subtitleSize,
                height: AlbumGridView._textLineHeight,
                color: AppTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面左上角的 CUE 标记。
///
/// 方案 A 里 CUE 的信息原本在分组头上（`WAV · CUE 分轨` 的描边 chip），
/// 卡片墙没有分组头了，但这条信息不能丢 —— 它解释了「为什么这张专辑的
/// 曲目名和文件名对不上」。卡片上位置有限，所以只留 `CUE` 三个字母，
/// 完整说法交给悬停提示与详情页。
class _CueBadge extends StatelessWidget {
  const _CueBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '这张专辑由一张整轨 + .cue 切分而成\n'
          '点开可以看每一轨，也可以用「整轨连播」按原样听',
      waitDuration: const Duration(milliseconds: 350),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          // 深底而不是浅底：标记要压在任意一张封面上，浅色底遇到浅色封面就糊了
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppTheme.cue.withValues(alpha: 0.8)),
        ),
        child: const Text(
          'CUE',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            height: 1.2,
            letterSpacing: 0.4,
            color: AppTheme.cue,
          ),
        ),
      ),
    );
  }
}

/// 悬停时才出现的播放键。
///
/// 常驻的话每张卡片上都有一个大按钮，卡片墙会变得很吵；而「点开专辑」
/// 与「直接播放这张专辑」是两个不同的意图，前者点击面积是整个卡片，
/// 后者必须另给一个明确的落点。
class _HoverPlayButton extends StatelessWidget {
  const _HoverPlayButton({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // 不可见时必须忽略指针：否则鼠标划过封面右下角会点到「看不见的按钮」
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 140),
        child: Tooltip(
          message: '播放这张专辑',
          child: Material(
            color: AppTheme.accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: const SizedBox(
                width: 34,
                height: 34,
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
