/// 曲目可播性判定结果。
///
/// 这是 PoC 阶段踩出来的核心业务规则：网盘**允许列出**的文件，
/// 未必**允许下载**。夸克对单文件有约 50MB 的硬上限，超限时取链直接
/// 返回 `code=23018`。如果不提前预判，用户点播放才失败，体验极差。
enum PlayabilityState {
  /// 体积与格式都在能力范围内，可正常播放
  playable,

  /// 体积超出网盘允许的单文件下载上限
  overLimit,

  /// 网盘未返回体积，无法预判；先尝试播放，失败再降级
  unknownSize,

  /// 网盘声明不支持直链播放
  unsupportedByProvider,

  /// 扩展名与 MIME 都不像音频
  notAudio,

  /// 本机播放器解不开这个文件。
  ///
  /// 两种成因，对用户是同一件事（「这首歌放不出来」）：
  ///   - **编码不受支持**：典型是 DSD（`.dsf` / `.dff`）—— macOS 的
  ///     AVFoundation 根本不认这种编码，重试一百次也没用；
  ///   - **文件损坏**：容器头坏了，解码器初始化失败。
  ///
  /// ⚠️ 它是**运行时**才会发现的状态，静态判定（[resolvePlayability]）
  /// 永远产不出它 —— 光看文件名和体积猜不出「解码器认不认这个编码」。
  /// 所以它不进扫描体检报告，只在真正播过之后落库。
  ///
  /// 以前这种情况被错记成 [overLimit]，于是列表上显示「取不到链」——
  /// 而网盘明明给了链接，是本机解不开。原因写错了，用户就永远修不好。
  decodeFailed;

  /// 该状态是否仍值得尝试播放。
  ///
  /// `unknownSize` 也算 —— 网盘没返回体积时宁可试一次，也不要把文件判死。
  /// 这是「乐观可播」口径的唯一来源：索引库的 `is_playable` 列、各种可播
  /// 比例都依赖它，所以不要在各处重复写这个判断。
  bool get isAttemptable =>
      this == PlayabilityState.playable || this == PlayabilityState.unknownSize;
}

/// 可播性判定。
class Playability {
  const Playability(this.state, {this.reason, this.limitBytes});

  final PlayabilityState state;

  /// 面向用户的中文原因，可直接展示
  final String? reason;

  /// 触发判定的体积上限（仅 [PlayabilityState.overLimit] 有值）
  final int? limitBytes;

  /// 确认可播（无需任何运行时兜底）
  bool get isConfirmedPlayable => state == PlayabilityState.playable;

  /// 值得尝试播放。`unknownSize` 也算——宁可试一次，也不要把
  /// 网盘没返回体积的文件直接判死。
  bool get shouldAttempt => state.isAttemptable;

  /// 需要在 UI 上给出视觉标记
  bool get needsBadge => state != PlayabilityState.playable;

  @override
  String toString() => 'Playability(${state.name}${reason == null ? "" : ", $reason"})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Playability &&
          other.state == state &&
          other.reason == reason &&
          other.limitBytes == limitBytes;

  @override
  int get hashCode => Object.hash(state, reason, limitBytes);
}
