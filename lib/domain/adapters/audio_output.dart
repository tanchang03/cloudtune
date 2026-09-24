import '../entities/stream_ticket.dart';

/// 播放失败归类。
///
/// 把平台播放器五花八门的错误码收敛成「引擎该怎么办」这一件事上：
///   - [linkExpired] → 重取直链后 seek 回原位置，**可以自愈**；
///   - [unplayableSource] → 重取一百次也没用，标记不可播并跳过；
///   - [network] → 稍后重试；
///   - 其余 → 报给用户。
///
/// 这层归类必须由 [AudioOutput] 实现负责做，因为只有它看得到平台原始错误。
enum PlaybackFailureKind {
  /// 直链失效：签名过期、被拒（`401` / `403` / `412`）。可自愈。
  linkExpired,

  /// 音源本身不可播：网盘拒绝取链（夸克 `23018`）、或本机解码器不支持该格式。
  /// 重取直链无意义。
  unplayableSource,

  /// 网络层问题（超时、断连、服务端 5xx）。可重试。
  network,

  /// 文件在网盘侧已不存在。
  notFound,

  /// 其他未归类
  unknown;

  /// 是否值得「重取直链 + 续播」自愈
  bool get isSelfHealable => this == PlaybackFailureKind.linkExpired;

  /// 是否值得原样重试
  bool get isRetryable => this == PlaybackFailureKind.network;
}

/// 一次播放失败。
class PlaybackFailure {
  const PlaybackFailure({
    required this.kind,
    required this.message,
    this.httpStatus,
    this.providerCode,
    this.trackId,
  });

  final PlaybackFailureKind kind;

  /// 面向用户的中文描述
  final String message;

  final int? httpStatus;

  /// 网盘原始业务码（如夸克 `23018`）
  final int? providerCode;

  /// 出问题的曲目 id（平台播放器不一定知道，能填就填）
  final String? trackId;

  /// 从 HTTP 状态码归类。
  ///
  /// 集中在这里是为了让各家 [AudioOutput] 实现口径一致 ——
  /// 否则「403 算过期还是算无权限」会被各处实现各答一遍。
  static PlaybackFailureKind kindFromHttpStatus(int status) {
    switch (status) {
      case 401:
      case 403:
      case 412:
      case 416:
        return PlaybackFailureKind.linkExpired;
      case 404:
      case 410:
        return PlaybackFailureKind.notFound;
      case 408:
      case 429:
      case 500:
      case 502:
      case 503:
      case 504:
        return PlaybackFailureKind.network;
      default:
        return PlaybackFailureKind.unknown;
    }
  }

  @override
  String toString() => 'PlaybackFailure(${kind.name}, http=$httpStatus, '
      'code=$providerCode, $message)';
}

/// 装载阶段（[AudioOutput.load]）失败时抛出的异常。
///
/// 存在的理由：装载失败和播放中途失败**是同一件事**（这首歌播不出来），
/// 只是发现时机不同。包一层 [PlaybackFailure] 之后，引擎就能用同一个
/// 决策函数处理两条路径 —— 否则「解码器解不开」在装载阶段被当成
/// 未知异常、在中途被当成 `unplayableSource`，两处判断迟早会走偏。
///
/// 刻意**不复用 `DriveException`**：那个类型描述的是网盘接口的错误
/// （取链失败、授权失效、文件不存在），而「本机解码器解不开这个编码」
/// 跟网盘没关系，混进去会让错误分类越描越糊。
class PlaybackLoadException implements Exception {
  const PlaybackLoadException(this.failure);

  final PlaybackFailure failure;

  @override
  String toString() => 'PlaybackLoadException($failure)';
}

/// 音频输出抽象。
///
/// **存在的唯一理由是可测试性。** 播放引擎真正容易写错的地方是编排逻辑：
/// 取链、缓存、直链失效后续链并 seek 回原位置、运行时不可播的落库与跳过、
/// 播放统计的落库时机。把这些逻辑放在一个依赖 [AudioOutput] 的纯 Dart
/// 类里，就能用假实现穷举，而不必依赖平台通道（`just_audio` 在单元测试
/// 环境里根本起不来）。
///
/// 实现约定：
///   - [load] 必须把 [StreamTicket.headers] **原样**交给播放器。
///     夸克实测：缺 `Cookie` 时直链直接返回 `412 Precondition Failed`；
///   - **装载阶段就能发现的失败必须直接抛异常**（不要只发到
///     [failures] 流里），否则引擎会以为装载成功、把播放统计先记上；
///     并且要抛 [PlaybackLoadException]（带上归类好的 [PlaybackFailure]），
///     让引擎能分辨「解码器解不开」和「网络抖了一下」—— 前者要标记跳过，
///     后者只需要告诉用户，混成一种会让好歌被误拉黑。
///   - 播放中途断开只能通过 [failures] 流上报。
abstract class AudioOutput {
  /// 装载音源。[initialPosition] 用于「直链失效后续播」场景 ——
  /// 必须真正从该位置起播，而不是回到 0。
  Future<void> load(
    StreamTicket ticket, {
    Duration initialPosition = Duration.zero,
  });

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> stop();

  /// 当前播放位置
  Duration get position;

  /// 当前音源总时长，未知为 `null`
  Duration? get duration;

  bool get isPlaying;

  /// 播放中途的失败
  Stream<PlaybackFailure> get failures;

  Stream<Duration> get positionStream;

  Stream<bool> get playingStream;

  Stream<Duration?> get durationStream;

  /// 当前音源自然播放结束
  Stream<void> get completedStream;

  Future<void> dispose();
}
