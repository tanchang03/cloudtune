import '../../core/utils/audio_formats.dart';
import '../../core/utils/format.dart';
import '../entities/capabilities.dart';
import '../entities/playability.dart';

/// 可播性判定器。
///
/// 单一职责：给定「文件名 + 体积 + MIME」和网盘能力，判断这条曲目
/// 能不能播、为什么不能播。纯函数，无 IO，便于穷举边界。
///
/// 判定优先级（顺序不能换）：
///   1. 是不是音频 —— 不是音频直接排除，避免把封面图当歌；
///   2. 网盘是否开放直链 —— 未开放则整体不可播；
///   3. 体积是否未知 —— 未知不判死，交给运行时兜底；
///   4. 体积是否超限 —— 只在网盘**明确声明了播放取链上限**时才可能命中。
///
/// ⚠️ 第 4 条的前提是 [Capabilities.maxSingleFileBytes] 描述的是
/// **播放取链**的上限，而不是网盘「下载」接口的上限。夸克两者不同
/// （下载 50MiB / 播放无限制），所以它的能力声明里不填上限 ——
/// 详见 [Capabilities.maxSingleFileBytes] 的注释。
///
/// 结果上，第 4 条对当前已接入的网盘都不会命中：**没有哪个网盘会在
/// 声明里给出一个我们真的取不到链的体积门槛**。它是一条为未来网盘
/// 预留的、以及为运行时兜底保留的状态。
Playability resolvePlayability({
  required String fileName,
  required Capabilities capabilities,
  int? sizeBytes,
  String? mimeType,
}) {
  if (!isAudioFile(fileName, mimeType: mimeType)) {
    return const Playability(
      PlayabilityState.notAudio,
      reason: '这个文件不是音频（扩展名与类型都不像 MP3 / FLAC / WAV / M4A 等格式）',
    );
  }

  if (!capabilities.canResolveDirectLink) {
    return Playability(
      PlayabilityState.unsupportedByProvider,
      reason: '${capabilities.provider.displayName} 未开放直链播放能力，'
          '无法直接在线播放其中的文件',
    );
  }

  final limit = capabilities.maxSingleFileBytes;

  if (sizeBytes == null || sizeBytes <= 0) {
    return const Playability(
      PlayabilityState.unknownSize,
      reason: '网盘未返回文件体积，将在播放时验证',
    );
  }

  if (limit != null && sizeBytes > limit) {
    return Playability(
      PlayabilityState.overLimit,
      // 说清三件事：什么文件、什么原因、什么条件才能播。
      // 「超限」是内部术语，用户看不懂，这里一律用人话。
      // 注意措辞：是**取链接口**不给，不是文件坏了 —— 不能引导用户
      // 去「换成更小的文件」，那是把接口的限制说成了文件的毛病。
      reason: '这个文件 ${formatBytes(sizeBytes)}，'
          '超过${capabilities.provider.displayName}播放取链接口允许的'
          '单文件 ${formatBytes(limit)}。这是网盘接口的限制，'
          '不是文件本身有问题；换一条取链路由，或改用没有这条限制的网盘即可。',
      limitBytes: limit,
    );
  }

  return const Playability(PlayabilityState.playable);
}

/// 批量判定的统计结果，用于扫描完成后给用户一份「可播体检报告」。
class PlayabilitySummary {
  const PlayabilitySummary({
    required this.playable,
    required this.overLimit,
    required this.unknownSize,
    required this.notAudio,
    required this.unsupported,
    required this.playableBytes,
    required this.totalBytes,
  });

  final int playable;
  final int overLimit;
  final int unknownSize;
  final int notAudio;
  final int unsupported;

  /// 可播曲目的总体积
  final int playableBytes;

  /// 全部曲目的总体积
  final int totalBytes;

  int get total => playable + overLimit + unknownSize + notAudio + unsupported;

  /// 可播比例（含未知体积的乐观估计）。分母为 0 时返回 0。
  double get playableRatio {
    final denom = playable + overLimit + unknownSize + unsupported;
    if (denom <= 0) return 0;
    return (playable + unknownSize) / denom;
  }

  double get playableBytesRatio {
    if (totalBytes <= 0) return 0;
    return playableBytes / totalBytes;
  }

  static const PlayabilitySummary empty = PlayabilitySummary(
    playable: 0,
    overLimit: 0,
    unknownSize: 0,
    notAudio: 0,
    unsupported: 0,
    playableBytes: 0,
    totalBytes: 0,
  );

  @override
  String toString() => 'PlayabilitySummary(可播 $playable / 超限 $overLimit / '
      '未知 $unknownSize / 非音频 $notAudio)';
}

/// 可播性累加器。
///
/// 扫描过程中逐条 `add`，扫描结束后 `summary` 即可拿到体检报告，
/// 不必把所有 [Playability] 都留在内存里。
class PlayabilityAccumulator {
  int _playable = 0;
  int _overLimit = 0;
  int _unknownSize = 0;
  int _notAudio = 0;
  int _unsupported = 0;
  int _playableBytes = 0;
  int _totalBytes = 0;

  /// 累计一条判定结果。[sizeBytes] 用于统计体积维度。
  void add(Playability playability, {int? sizeBytes}) {
    final size = (sizeBytes != null && sizeBytes > 0) ? sizeBytes : 0;
    switch (playability.state) {
      case PlayabilityState.playable:
        _playable++;
        _playableBytes += size;
        _totalBytes += size;
      case PlayabilityState.unknownSize:
        _unknownSize++;
        _playableBytes += size;
        _totalBytes += size;
      case PlayabilityState.overLimit:
        _overLimit++;
        _totalBytes += size;
      case PlayabilityState.notAudio:
        _notAudio++;
      case PlayabilityState.unsupportedByProvider:
        _unsupported++;
        _totalBytes += size;
      case PlayabilityState.decodeFailed:
        // 故意不统计：这个状态只有**真正播过一次**之后才会产生
        // （静态判定看不出解码器认不认某个编码），而本累加器只在扫描时
        // 消费 [resolvePlayability] 的结果，所以这里根本不可能被走到。
        // 真被走到说明有人把运行时状态喂进了扫描报告，那是 bug ——
        // 但也不该因此炸掉扫描，所以留一个空分支并写清楚原因。
        break;
    }
  }

  PlayabilitySummary get summary => PlayabilitySummary(
        playable: _playable,
        overLimit: _overLimit,
        unknownSize: _unknownSize,
        notAudio: _notAudio,
        unsupported: _unsupported,
        playableBytes: _playableBytes,
        totalBytes: _totalBytes,
      );
}
