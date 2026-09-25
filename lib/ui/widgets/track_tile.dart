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
///
/// **CUE 分段的两个特殊处理**（其余一切都与普通曲目一致，这是 方案 A 的前提：
/// 分段曲目就是普通的曲目行，能点、能收藏、能随机）：
///   - 标题前多一列**轨号**（`03`），由 CUE 定序 —— 整轨文件名推不出第几首；
///   - **体积与码率必须走整轨口径**，见 [imageDurationMs]。
class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.capabilities,
    required this.onPlay,
    this.imageDurationMs,
  });

  final Track track;

  /// 用于判定可播性 —— 阈值来自网盘能力声明，不在这里写死
  final Capabilities capabilities;

  final VoidCallback onPlay;

  /// 本曲目所属**整轨的总时长**（毫秒）。非整轨分段、或整轨时长拿不到时为 `null`。
  ///
  /// 为什么非要单独传进来：分段的 [Track.sizeBytes] 是**整轨体积**
  /// （一张 CD 的 WAV 动辄 700MB+），而 [Track.durationMs] 是**本轨时长**
  /// （4 分钟）。两者直接相除会算出 24000kbps 这种离谱的码率 ——
  /// 那是拿整张专辑的体积除以一首歌的时长。有了整轨总时长才能：
  ///   - 码率按「整轨体积 ÷ 整轨总时长」算（WAV 这类恒定位率文件下即准确值）；
  ///   - 本轨体积按「整轨体积 × 本轨时长 ÷ 整轨总时长」摊出来。
  ///
  /// 值由列表侧从 `TrackGroup.cueImageDurations` 取 —— 整轨那一行已被扫描器
  /// 删掉，只能靠分段还原（见 `Track.imageOf`）。
  final int? imageDurationMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = AppTheme.isWide(context);
    final playability = track.playability(capabilities);
    // 规格只算一次，给格式 chip、品质文字、体积列、窄屏副标题共用
    final spec = _specOf(track, imageDurationMs);

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
                  spec: spec,
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
                    child: _QualityCell(track: track, spec: spec),
                  ),
                ),
                const SizedBox(width: AppTheme.rowGap),
                SizedBox(
                  width: AppTheme.sizeColWidth,
                  child: _SizeCell(track: track, spec: spec),
                ),
              ],
              const SizedBox(width: AppTheme.rowGap),
              _TimeCell(track: track),
              const SizedBox(width: AppTheme.rowGap),
              _HeartButton(track: track, isFavorite: isFavorite),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一行的音频规格：格式标签 + 音质家族 + 平均码率 + 本行体积。
///
/// 四个值互相依赖（`.m4a` 到底是 AAC 还是 ALAC，得先看码率才分得出），
/// 所以收在一个地方算一次，给格式 chip、品质文字、体积列、窄屏副标题共用 ——
/// 分几处各算一遍的话，哪天口径改了必然会漏改一处。
class _Spec {
  const _Spec({
    required this.format,
    required this.quality,
    required this.kbps,
    required this.sizeBytes,
  });

  final String format;
  final AudioQuality quality;
  final int? kbps;

  /// 本行要显示的体积：独立文件就是文件体积；整轨分段是按比例**摊**出来的
  /// 估计值（口径见 [_estimatedSegmentBytes]），摊不出来时为 `null`。
  final int? sizeBytes;
}

/// 算一行的规格。[imageDurationMs] 的含义见 [TrackTile.imageDurationMs]。
///
/// ⚠️ **分段必须走整轨口径**：分段的 `sizeBytes` 是整轨体积、`durationMs` 是
/// 本轨时长，直接相除会得出 24000kbps 这种离谱的码率。整轨总时长拿不到时，
/// 宁可**不显示**码率与体积，也不显示一个错得离谱的数 ——
/// 一个假的规格比没有规格更糟，用户会拿它去和别的软件对账。
_Spec _specOf(Track track, int? imageDurationMs) {
  final segment = track.isCueSegment;
  final imageMs = segment ? imageDurationMs : null;

  final kbps = averageBitrateKbps(
    sizeBytes: track.sizeBytes,
    // 独立文件用自身时长；分段的时长必须换成整轨总时长
    durationMs: segment ? imageMs : track.durationMs,
  );

  return _Spec(
    format: formatLabelOf(track.name),
    quality: audioQualityOf(track.name, bitrateKbps: kbps),
    kbps: kbps,
    sizeBytes:
        segment ? _estimatedSegmentBytes(track, imageMs) : track.sizeBytes,
  );
}

/// 分段的体积估计 = 整轨体积 × 本轨时长 ÷ 整轨总时长。
///
/// 对 WAV / FLAC 这类「每秒数据量基本恒定」的文件，这个摊法与真实值很接近；
/// 有损 VBR 会有偏差，但整轨 CUE 几乎只出现在无损 / 未压缩抓轨里。
/// 任何一项缺失都返回 `null` —— 界面显示「未知」比显示一个编造的数字诚实。
int? _estimatedSegmentBytes(Track track, int? imageDurationMs) {
  final size = track.sizeBytes;
  final segMs = track.durationMs;
  if (size == null || size <= 0) return null;
  if (imageDurationMs == null || imageDurationMs <= 0) return null;
  if (segMs == null || segMs <= 0) return null;
  final estimate = size * segMs / imageDurationMs;
  return estimate <= 0 ? null : estimate.round();
}

/// 家族词 + 码率：`无损 1411k`。拿不到码率时只有家族词，不留半截空格。
String _qualityText(_Spec spec) {
  final bitrate = formatBitrate(spec.kbps);
  return bitrate == null ? spec.quality.label : '${spec.quality.label} $bitrate';
}

/// 窄屏副标题：`艺术家 · FLAC 无损 1411k · 729.7 MB`。
///
/// **专辑在这里被挤掉了**，不是随手删的：窄屏一行放不下四段，
/// 而按专辑分组时专辑名本来就在组头上；规格与体积却只有这一处能显示。
/// 体积缺失时不写「未知」—— 副标题里出现「未知」是噪声，不如不写。
String _narrowSubtitle(Track track, _Spec spec) {
  final artist = track.displayArtist;
  final size = spec.sizeBytes;
  return [
    if (artist != null && artist.isNotEmpty) artist,
    '${spec.format} ${_qualityText(spec)}',
    if (size != null && size > 0) formatBytes(size),
  ].join(' · ');
}

/// 轨号列的宽度。
///
/// 取 20 是为了装下两位轨号（PingFang 11.5px 的等宽数字约 6.5px/位）还留余量；
/// 三位轨号（100 轨以上的合辑）会被裁掉一点，属于可接受的极端情况 ——
/// 与其把这一列按最长轨号撑到 26px，不如让它对绝大多数专辑更紧凑。
///
/// ⚠️ 这一列在**标题格内部**，所以有轨号的行标题会比没有轨号的行右移 26px。
/// 这是**有意为之，不是漏改**：
///   - 组内所有行要么都有轨号、要么都没有，所以**组内一定对齐**；
///   - 跨组错开反而读成「这张专辑带编号」，正好是 CUE 整轨专辑想要的效果；
///   - 给所有行（包括绝大多数没有轨号的普通曲目）都留出这条空档，
///     等于在应用最主力的那个列表上永久损失 26px 标题宽度，
///     而 1000px 断点本来就是为标题宽度才抬上去的（见 [AppTheme.isWide]）。
const double _trackNoWidth = 20;

/// 标题 / 副标题（+ 可播性徽标）。
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.track,
    required this.spec,
    required this.playability,
    required this.isCurrent,
    required this.showPathLine,
    required this.showSpecInSubtitle,
  });

  final Track track;
  final _Spec spec;
  final Playability playability;
  final bool isCurrent;
  final bool showPathLine;
  final bool showSpecInSubtitle;

  @override
  Widget build(BuildContext context) {
    final p = playability;
    final subtitle =
        showSpecInSubtitle ? _narrowSubtitle(track, spec) : track.displaySubtitle;

    final no = track.cueTrackNo;
    // 标题本身就是「第 N 轨」时不再重复一个轨号前缀 —— 同一句话说两遍
    final showNo = no != null && track.displayTitle != track.cueTrackLabel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (showNo) ...[
              SizedBox(
                width: _trackNoWidth,
                child: Text(
                  // 补零到两位：整轨专辑动辄十几二十轨，`1` 与 `10` 左对齐时
                  // 视觉长度差一倍，扫读会跳行
                  no.toString().padLeft(2, '0'),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.dim,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
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
  const _QualityCell({required this.track, required this.spec});

  final Track track;
  final _Spec spec;

  @override
  Widget build(BuildContext context) {
    final text = _qualityText(spec);

    return Tooltip(
      message: [
        '${spec.format} · $text',
        // 分段的码率分母是整轨总时长而不是本轨时长，这个口径差异要说出来，
        // 否则用户拿本轨体积自己算一遍会发现对不上
        if (track.isCueSegment) '本轨由整轨切出：码率按「整轨体积 ÷ 整轨总时长」算',
        spec.quality.hint,
      ].join('\n'),
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
  const _SizeCell({required this.track, required this.spec});

  final Track track;
  final _Spec spec;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _hint(),
      waitDuration: const Duration(milliseconds: 350),
      child: Text(
        formatBytes(spec.sizeBytes),
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11.5,
          color: AppTheme.dim,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  /// 体积的口径说明。**分段的体积是摊出来的估算值**，不讲清楚的话用户会
  /// 拿它去网盘里对账（那里只有一个整轨文件、没有这些单轨），对不上就会
  /// 以为是本应用读错了。
  String _hint() {
    if (!track.isCueSegment) return '文件体积';
    if (spec.sizeBytes == null) {
      return '本轨不是独立文件，而整轨时长未知，摊不出体积';
    }
    return '本轨不是独立文件：体积按「本轨时长 ÷ 整轨时长」'
        '从整轨 ${formatBytes(track.sizeBytes)} 摊出来的估算值';
  }
}

/// 时长格。
///
/// 分段曲目额外用悬停提示交代**这一轨在整轨里的位置**：用户在别的软件
/// （foobar2000、Audacity）里对时间轴时，要的就是这个起点。
class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.track});

  final Track track;

  static const TextStyle _style = TextStyle(
    fontSize: 11.5,
    color: AppTheme.dim,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final text = Text(
      formatDuration(track.duration),
      textAlign: TextAlign.right,
      maxLines: 1,
      style: _style,
    );

    final start = track.cueStartMs;
    if (start == null) return SizedBox(width: 56, child: text);

    final end = track.cueEndMs;
    return SizedBox(
      width: 56,
      child: Tooltip(
        message: '${track.name}\n'
            '第 ${track.cueTrackNo} 轨 · 整轨内 '
            '${formatDuration(Duration(milliseconds: start))}'
            '${end == null ? '' : ' → ${formatDuration(Duration(milliseconds: end))}'}',
        waitDuration: const Duration(milliseconds: 350),
        child: text,
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
      // 分段的路径指向**整轨文件**（那才是网盘里真实存在的东西），
      // 不点明的话用户会去网盘里找一个根本不存在、名字还一模一样的单轨文件
      message: track.isCueSegment
          ? '${track.fullPath}\n本轨是这份整轨的第 ${track.cueTrackNo} 轨\n点击复制完整路径'
          : '${track.fullPath}\n点击复制完整路径',
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
