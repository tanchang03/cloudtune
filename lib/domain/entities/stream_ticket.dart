/// 一次播放所需的直链票据。
///
/// 网盘的直链都是**带签名的临时 URL**，通常几十分钟就过期。因此票据不是
/// 长期数据，只在「准备播放」这一刻有效。播放中失效时由播放引擎捕获
/// `403` / `urlExpired` 后重新取链并 seek 回原位置。
class StreamTicket {
  const StreamTicket({
    required this.url,
    this.headers = const {},
    this.expiresAt,
    this.contentLength,
    this.supportsRange = true,
    this.contentType,
  });

  /// 直链地址（含签名查询串，**不要打进日志**）
  final Uri url;

  /// 播放器必须携带的请求头。
  ///
  /// 夸克实测：缺少 `Cookie` 时直链返回 `412 Precondition Failed`；
  /// 任何带 Cookie 的组合都返回 `206 Partial Content`。
  final Map<String, String> headers;

  final DateTime? expiresAt;

  /// 服务端声明的体积，可用于与索引库比对、校正本地记录
  final int? contentLength;

  /// 是否支持 HTTP Range（决定能否 seek）
  final bool supportsRange;

  final String? contentType;

  /// 是否已过期。
  ///
  /// 提前 [earlyMargin] 判定，避免「刚取到就过期」导致播放中途断流。
  bool get isExpired => isExpiredAt(DateTime.now());

  /// 距离过期的剩余时间。未知返回 `null`。
  Duration? get remaining => remainingAt(DateTime.now());

  /// 在指定时刻是否已过期。
  ///
  /// 与 [isExpired] 的区别是**时钟可注入** —— 票据缓存与播放引擎的
  /// 续链判定都必须能在单元测试里精确控制时间，否则只能靠 `sleep` 测。
  bool isExpiredAt(DateTime now) {
    final e = expiresAt;
    if (e == null) return false;
    return now.isAfter(e.subtract(earlyMargin));
  }

  /// 在指定时刻距离过期还有多久。未知返回 `null`。
  Duration? remainingAt(DateTime now) {
    final e = expiresAt;
    if (e == null) return null;
    final d = e.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  /// 提前判定过期的安全余量
  static const Duration earlyMargin = Duration(seconds: 30);

  bool get needsHeaders => headers.isNotEmpty;

  /// 脱敏后的地址，仅保留协议与主机路径，可安全打日志。
  String get redactedUrl => '${url.scheme}://${url.host}${url.path}';

  @override
  String toString() => 'StreamTicket($redactedUrl, '
      'headers=${headers.keys.join(",")}, expires=$expiresAt, '
      'len=$contentLength, range=$supportsRange)';
}
