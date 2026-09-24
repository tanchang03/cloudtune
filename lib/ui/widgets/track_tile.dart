import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/audio_formats.dart';
import '../../domain/entities/capabilities.dart';
import '../../domain/entities/playability.dart';
import '../../domain/entities/track.dart';
import '../providers/library_providers.dart';
import '../providers/playback_providers.dart';
import '../theme/app_theme.dart';
import '../utils/clipboard.dart';
import 'album_art.dart';
import 'playability_badge.dart';
import 'playability_help.dart';

/// 曲库列表里的一行，1:1 对齐设计原型 `.song`。
///
/// 桌面端列序：封面 44 → 标题/艺术家 → 来源 pill 120 → **网盘路径** →
/// **格式 · 品质** → **大小** → 时长 → 心形。
///
/// 后三段里只有「时长」来自原型，另外两段是原型之外加的：
///   - 「网盘路径」—— 用户要拿着路径去网盘里定位文件，只给「来自夸克网盘」不够用；
///   - 「格式 · 品质」「大小」—— 网盘列表本身只看得到文件名，
///     用户想知道「这首是不是无损」「有多大」，不该逼他挨个点开。
///
/// 窄屏没有这些列，它们会被压成副标题里的一小段（见 [_narrowSubtitle]）。
class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.capabilities,
    required this.onPlay,
  });

  final Track track;

  /// 用于判定可播性 —— 阈值来自网盘能力声明，不在这里写死
  final Capabilities capabilities;

  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = AppTheme.isWide(context);
    final playability = track.playability(capabilities);

    final favorites =
        ref.watch(favoriteIdsProvider).valueOrNull ?? const <String>{};
    final isFavorite = favorites.contains(track.id);
    final isCurrent = ref.watch(playerProvider).current?.id == track.id;

    return Material(
      // 当前播放行：原型没有这个态，用主色 8% 淡染，和侧边栏选中态同一口径
      color: isCurrent ? AppTheme.accent.withValues(alpha: 0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(
            children: [
              AlbumArt(provider: track.provider, size: 44),
              const SizedBox(width: AppTheme.rowGap),
              Expanded(
                flex: 3,
                child: _TitleBlock(
                  track: track,
                  playability: playability,
                  isCurrent: isCurrent,
                  // 窄屏没有路径列，路径降级成第三行
                  showPathLine: !wide,
                  // 窄屏也没有「格式 · 品质」「大小」两列，压进副标题
                  showSpecInSubtitle: !wide,
                ),
              ),
              if (wide) ...[
                const SizedBox(width: AppTheme.rowGap),
                SizedBox(
                  width: AppTheme.sourceColWidth,
                  child: _SourcePill(track: track),
                ),
                const SizedBox(width: AppTheme.rowGap),
                Expanded(flex: 2, child: _PathCell(track: track)),
                const SizedBox(width: AppTheme.rowGap),
                SizedBox(
                  width: AppTheme.qualityColWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _QualityCell(track: track),
                  ),
                ),
                const SizedBox(width: AppTheme.rowGap),
                SizedBox(
                  width: AppTheme.sizeColWidth,
                  child: _SizeCell(track: track),
                ),
              ],
              const SizedBox(width: AppTheme.rowGap),
              SizedBox(
                width: 56,
                child: Text(
                  formatDuration(track.duration),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.dim,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.rowGap),
              _HeartButton(track: track, isFavorite: isFavorite),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一行的音频规格：格式标签 + 音质家族 + 平均码率。
///
/// 三个值互相依赖（`.m4a` 到底是 AAC 还是 ALAC，得先看码率才分得出），
/// 所以收在一个地方算一次，给格式 chip、品质文字、窄屏副标题共用 ——
/// 分三处各算一遍的话，哪天口径改了必然会漏改一处。
({String format, AudioQuality quality, int? kbps}) _specOf(Track track) {
  final kbps = averageBitrateKbps(
    sizeBytes: track.sizeBytes,
    durationMs: track.durationMs,
  );
  return (
    format: formatLabelOf(track.name),
    quality: audioQualityOf(track.name, bitrateKbps: kbps),
    kbps: kbps,
  );
}

/// 家族词 + 码率：`无损 1411k`。拿不到码率时只有家族词，不留半截空格。
String _qualityText(({String format, AudioQuality quality, int? kbps}) spec) {
  final bitrate = formatBitrate(spec.kbps);
  return bitrate == null ? spec.quality.label : '${spec.quality.label} $bitrate';
}

/// 窄屏副标题：`艺术家 · FLAC 无损 1411k · 729.7 MB`。
///
/// **专辑在这里被挤掉了**，不是随手删的：窄屏一行放不下四段，
/// 而按专辑分组时专辑名本来就在组头上；规格与体积却只有这一处能显示。
/// 体积缺失时不写「未知」—— 副标题里出现「未知」是噪声，不如不写。
String _narrowSubtitle(Track track) {
  final spec = _specOf(track);
  final artist = track.displayArtist;
  final size = track.sizeBytes;
  return [
    if (artist != null && artist.isNotEmpty) artist,
    '${spec.format} ${_qualityText(spec)}',
    if (size != null && size > 0) formatBytes(size),
  ].join(' · ');
}

/// 标题 / 副标题（+ 可播性徽标）。
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.track,
    required this.playability,
    required this.isCurrent,
    required this.showPathLine,
    required this.showSpecInSubtitle,
  });

  final Track track;
  final Playability playability;
  final bool isCurrent;
  final bool showPathLine;
  final bool showSpecInSubtitle;

  @override
  Widget build(BuildContext context) {
    final p = playability;
    final subtitle =
        showSpecInSubtitle ? _narrowSubtitle(track) : track.displaySubtitle;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                track.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: isCurrent ? AppTheme.accent : AppTheme.text,
                ),
              ),
            ),
            if (p.needsBadge) ...[
              const SizedBox(width: 6),
              PlayabilityBadge(
                playability: p,
                dense: true,
                onTap: () => showPlayabilityHelp(
                  context,
                  track: track,
                  playability: p,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle.isEmpty ? track.name : subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
        ),
        if (showPathLine) ...[
          const SizedBox(height: 2),
          _PathCell(track: track),
        ],
      ],
    );
  }
}

/// 来源 pill：原型 `.src-col .pill`，底色即网盘品牌色。
class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: track.provider.brandColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          track.provider.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 格式 chip：`FLAC` / `WAV` / `DSF`，配色跟着音质家族走。
///
/// 与 [_SourcePill] 的区别是**描边而非填色**。一行里并排两个实心色块会互相抢，
/// 而且两者色系完全不同（来源用网盘品牌色、品质用家族色），
/// 填色并排会吵；描边则能在保持可辨识的同时退到后面去。
class _FormatChip extends StatelessWidget {
  const _FormatChip({required this.label, required this.quality});

  final String label;
  final AudioQuality quality;

  @override
  Widget build(BuildContext context) {
    final c = quality.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          height: 1.25,
          letterSpacing: 0.3,
          color: c,
        ),
      ),
    );
  }
}

/// 「格式 · 品质」列：`[FLAC] 无损 1411k`。
///
/// 悬停会把话说全 —— 尤其是**码率是算出来的**这件事必须讲明白，
/// 否则用户会拿它当文件里的官方规格，跟别的软件对不上就会以为本应用读错了。
class _QualityCell extends StatelessWidget {
  const _QualityCell({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final spec = _specOf(track);
    final text = _qualityText(spec);

    return Tooltip(
      message: '${spec.format} · $text\n${spec.quality.hint}',
      waitDuration: const Duration(milliseconds: 350),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FormatChip(label: spec.format, quality: spec.quality),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.3,
                color: AppTheme.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「大小」列。右对齐 + 等宽数字，与「时长」列同一套排版口径 ——
/// 两列紧挨着，字重/字号/对齐只要有一处不同，扫读时就会觉得错位。
class _SizeCell extends StatelessWidget {
  const _SizeCell({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatBytes(track.sizeBytes),
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 11.5,
        color: AppTheme.dim,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// 网盘路径。目录过长时截目录，**文件名始终完整可见** ——
/// 用户拿它去网盘里定位，看得到文件名才有意义。点一下复制整条路径。
class _PathCell extends StatelessWidget {
  const _PathCell({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final dir = track.path?.trim() ?? '';
    final dirText = dir.isEmpty
        ? ''
        : (dir.endsWith('/') ? dir : '$dir/');

    return Tooltip(
      message: '${track.fullPath}\n点击复制完整路径',
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: () => copyText(context, track.fullPath, label: '已复制路径'),
        borderRadius: BorderRadius.circular(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_outlined, size: 12, color: AppTheme.dim),
            const SizedBox(width: 5),
            if (dirText.isNotEmpty)
              Flexible(
                child: Text(
                  dirText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.3,
                    color: AppTheme.dim,
                    fontFamily: 'Menlo',
                  ),
                ),
              ),
            Flexible(
              child: Text(
                track.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.3,
                  color: AppTheme.muted,
                  fontFamily: 'Menlo',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 收藏按钮：原型 `.hbtn`（30×30，未收藏描边、已收藏填色）。
class _HeartButton extends ConsumerWidget {
  const _HeartButton({required this.track, required this.isFavorite});

  final Track track;
  final bool isFavorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 30,
      height: 30,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => ref
            .read(favoriteActionsProvider)
            .toggle(track.id, value: !isFavorite),
        child: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 16,
          color: isFavorite ? AppTheme.heart : AppTheme.dim,
        ),
      ),
    );
  }
}
