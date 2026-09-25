import '../../core/diagnostics/diag_log.dart';
import '../http/http_client.dart';

/// LRCLIB 的接口根地址。
///
/// [LRCLIB](https://lrclib.net) 是一个**开放、免注册、免密钥**的歌词库
/// （服务端 MIT 开源、可自建）。选它而不是网易云/QQ音乐那类接口的理由：
/// 后两者只有逆向出来的非官方接口，授权链更弱，而且随时可能失效。
///
/// ⚠️ 即便它开放，**联网取歌词仍然是默认关闭的可选项**：
/// 打开之后本应用会把曲名/艺术家/专辑/时长发给第三方，并把拿回来的歌词
/// 正文存进本地库。这两件事都超出了「只播放你自己网盘里的文件」这个
/// 既定边界，必须由用户明确同意。见 README 的合规说明。
const String kLrclibBaseUrl = 'https://lrclib.net/api';

/// 请求头里的 `User-Agent`。
///
/// LRCLIB 的接口约定里**明确要求**标识出应用与项目主页，并说明「通用 UA
/// 会被封禁」。这不是可选的礼貌 —— 用默认的 dio UA 等于把自己的流量混进
/// 爬虫里，被限流了都不知道为什么。
const String kLrclibUserAgent =
    'CloudTune/0.1.0 (https://github.com/tanchang03/cloudtune)';

/// LRCLIB 返回的一份歌词。
class LrclibLyrics {
  const LrclibLyrics({
    required this.trackName,
    this.artistName,
    this.albumName,
    this.durationSeconds,
    this.instrumental = false,
    this.plainLyrics,
    this.syncedLyrics,
  });

  /// 从接口返回的 JSON 造。字段名两种写法都认 ——
  /// 文档里是 camelCase，但自建实例或将来改版可能给 snake_case，
  /// 认不出的字段只会让匹配变差，不该让整条结果作废。
  factory LrclibLyrics.fromJson(Map<String, Object?> json) => LrclibLyrics(
        trackName: _str(json['trackName']) ?? _str(json['track_name']) ?? '',
        artistName: _str(json['artistName']) ?? _str(json['artist_name']),
        albumName: _str(json['albumName']) ?? _str(json['album_name']),
        durationSeconds: _int(json['duration']),
        instrumental: json['instrumental'] == true,
        plainLyrics: _str(json['plainLyrics']) ?? _str(json['plain_lyrics']),
        syncedLyrics: _str(json['syncedLyrics']) ?? _str(json['synced_lyrics']),
      );

  final String trackName;
  final String? artistName;
  final String? albumName;
  final int? durationSeconds;

  /// 明确标注的纯音乐（无人声）。**这是一个确定的答案**，
  /// 不该被当成「没查到」而在每次播放时重问一遍。
  final bool instrumental;

  /// 无时间轴的纯文本歌词
  final String? plainLyrics;

  /// 带 `[mm:ss.xx]` 时间轴的 LRC 原文
  final String? syncedLyrics;

  /// 拿这份歌词的正文：**优先带时间轴的那份**。
  ///
  /// 纯文本也能显示，但它不能跟着播放位置走 —— 有带轴的就绝不用它。
  String? get text {
    final synced = syncedLyrics?.trim();
    if (synced != null && synced.isNotEmpty) return syncedLyrics;
    final plain = plainLyrics?.trim();
    if (plain != null && plain.isNotEmpty) return plainLyrics;
    return null;
  }

  bool get hasLyrics => text != null;

  /// 这份结果值不值得记下来。
  ///
  /// 「没正文但明确说是纯音乐」也算值得：那是一个确定的答案，
  /// 落库之后就不必每次播放都去问一遍第三方接口。
  bool get isUseful => hasLyrics || instrumental;

  @override
  String toString() => 'LrclibLyrics("$trackName" / ${artistName ?? "-"}, '
      '${durationSeconds ?? "-"}s, '
      '${instrumental ? "纯音乐" : (hasLyrics ? "${text!.length} 字" : "无正文")})';

  static String? _str(Object? v) {
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}

/// 从 LRCLIB 取歌词。
///
/// **三级兜底，顺序不能改**：
///   1. `/api/get` **带时长** —— 最精确，能区分同一首歌的不同版本
///      （录音室版 / 演唱会版 / remaster）；
///   2. `/api/get` **不带时长** —— 宁可拿到「另一个版本」也不要拿不到。
///      歌词文本在不同版本之间通常只差几行，而 404 就是什么都没有；
///   3. `/api/search` + 本地打分 —— 曲名/艺术家跟库里对不上时的唯一出路。
///
/// ⚠️ **时长是一道硬闸，不是「有更好」**：LRCLIB 只返回时长在 ±2 秒以内的
/// 版本，传一个不准的时长会把本来查得到的曲子变成 404。本项目的曲目时长
/// 来自网盘元数据，而网盘并不保证有（README 已知限制里有 `--:--` 的曲目）。
/// 所以「时长未知就干脆别传」是必须的，不是优化。
class LrclibClient {
  LrclibClient({
    required HttpClientLike http,
    this.baseUrl = kLrclibBaseUrl,
    this.userAgent = kLrclibUserAgent,
    this.minInterval = const Duration(milliseconds: 300),
    this.requestTimeout = const Duration(seconds: 10),
    this.retryDelay = const Duration(seconds: 2),
    this.maxRetryAfter = const Duration(seconds: 30),
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
  })  : _http = http,
        _clock = clock ?? DateTime.now,
        _sleep = sleep ?? Future<void>.delayed;

  final HttpClientLike _http;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleep;

  final String baseUrl;
  final String userAgent;

  /// 相邻两次请求之间的最小间隔。
  ///
  /// LRCLIB 的接口约定要求「串行请求 + 200~500ms 间隔」。取 300ms 落在
  /// 中间：更快没必要（用户切歌的间隔远大于它），更慢则一次切歌要等太久。
  final Duration minInterval;

  final Duration requestTimeout;

  /// 遇到 5xx / 429 时的重试等待
  final Duration retryDelay;

  /// `Retry-After` 的上限。服务端给一个很大的值时不该真的干等。
  final Duration maxRetryAfter;

  /// 时长容差（秒）。LRCLIB 的硬性规则，写在接口文档里。
  static const int durationToleranceSeconds = 2;

  /// `/api/get` 的时长取值范围。超出这个范围**不要传**（会被拒）。
  static const int minDurationSeconds = 1;
  static const int maxDurationSeconds = 3600;

  /// 搜索结果的采纳门槛。低于它的候选一律不要。
  ///
  /// 宁可显示「没找到歌词」，也不要显示**别人的**歌词 —— 后者看起来像
  /// 应用坏了，而且用户很可能不会怀疑到歌词来源上。
  static const int minSearchScore = 3;

  DateTime? _lastRequestAt;

  /// 查一首歌的歌词。查不到返回 `null`。**永不抛异常。**
  Future<LrclibLyrics?> lookup({
    required String trackName,
    String? artistName,
    String? albumName,
    int? durationSeconds,
  }) async {
    final name = trackName.trim();
    if (name.isEmpty) return null;
    final artist = cleanQueryValue(artistName);
    final album = cleanQueryValue(albumName);

    final d = durationSeconds;
    final usableDuration =
        (d != null && d >= minDurationSeconds && d <= maxDurationSeconds)
            ? d
            : null;

    try {
      // 1) 带时长
      if (usableDuration != null) {
        final hit = await _get(name, artist, album, duration: usableDuration);
        if (hit != null && hit.isUseful) return hit;
      }

      // 2) 不带时长
      final loose = await _get(name, artist, album, duration: null);
      if (loose != null && loose.isUseful) return loose;

      // 3) 模糊搜索 + 本地打分
      return await _search(name, artist, durationSeconds: usableDuration);
    } on _NetworkDown {
      // 网络层根本不通（断网 / DNS / 超时）时**立刻放弃整条链**。
      //
      // 不这么做的话，一次断网会让每个曲目都连打两三次必然失败的请求，
      // 每次还各带一个 10 秒超时 —— 用户看到的是「切歌之后界面卡住半分钟」。
      // 而「服务器过载（503）」不走这条路：那种情况下一级不行、下一级
      // 很可能行，值得接着试。
      diag.info('歌词', 'LRCLIB 网络不通，放弃这次查找');
      return null;
    }
  }

  // -------------------------------------------------------------------
  // /api/get
  // -------------------------------------------------------------------

  Future<LrclibLyrics?> _get(
    String trackName,
    String? artist,
    String? album, {
    required int? duration,
  }) async {
    final res = await _send('$baseUrl/get', {
      'track_name': trackName,
      if (artist != null) 'artist_name': artist,
      if (album != null) 'album_name': album,
      if (duration != null) 'duration': duration,
    });
    // 404 = 这个库里没有这一首。**这是正常的答案，不是错误**，
    // 不该打 warn 级日志（否则一个没有歌词的曲库会刷满警告）。
    if (res.statusCode == 404) return null;
    if (!res.isSuccessStatus) return null;

    final json = res.json;
    if (json == null) {
      diag.warn('歌词', 'LRCLIB /get 返回了非对象响应体（${res.statusCode}）');
      return null;
    }
    return LrclibLyrics.fromJson(json);
  }

  // -------------------------------------------------------------------
  // /api/search
  // -------------------------------------------------------------------

  Future<LrclibLyrics?> _search(
    String trackName,
    String? artist, {
    int? durationSeconds,
  }) async {
    final res = await _send('$baseUrl/search', {
      'track_name': trackName,
      if (artist != null) 'artist_name': artist,
    });
    if (!res.isSuccessStatus) return null;

    final items = res.jsonListItems;
    if (items.isEmpty) return null;

    LrclibLyrics? best;
    var bestScore = 0;
    for (final item in items) {
      final candidate = LrclibLyrics.fromJson(item);
      if (!candidate.isUseful) continue;
      final score = _score(
        candidate,
        trackName: trackName,
        artist: artist,
        durationSeconds: durationSeconds,
      );
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }

    if (best == null || bestScore < minSearchScore) {
      diag.info(
        '歌词',
        'LRCLIB 搜索到 ${items.length} 个候选，但没有一个够可信（最高 $bestScore 分）',
      );
      return null;
    }
    diag.info('歌词', 'LRCLIB 搜索命中："${best.trackName}"（$bestScore 分）');
    return best;
  }

  /// 给一个搜索候选打分。**分数决定「敢不敢用」**，见 [minSearchScore]。
  static int _score(
    LrclibLyrics c, {
    required String trackName,
    String? artist,
    int? durationSeconds,
  }) {
    var score = 0;

    final wanted = _norm(trackName);
    final got = _norm(c.trackName);
    if (got == wanted) {
      score += 4;
    } else if (got.isNotEmpty &&
        wanted.isNotEmpty &&
        (got.contains(wanted) || wanted.contains(got))) {
      score += 2;
    }

    if (artist != null &&
        c.artistName != null &&
        _norm(c.artistName!) == _norm(artist)) {
      score += 3;
    }

    final d = durationSeconds;
    final cd = c.durationSeconds;
    if (d != null && cd != null) {
      final diff = (d - cd).abs();
      if (diff <= durationToleranceSeconds) {
        score += 3;
      } else if (diff <= 10) {
        score += 1;
      } else {
        // 差得太多说明是另一个版本 —— 搜到了也不能用
        score -= 1;
      }
    }

    if (c.hasLyrics) score += 1;
    return score;
  }

  static final RegExp _noise = RegExp(r'[\s\-_·・（）()\[\]【】]+');

  static String _norm(String s) => s.toLowerCase().replaceAll(_noise, '');

  // -------------------------------------------------------------------
  // 请求（节流 + 重试）
  // -------------------------------------------------------------------

  /// 发一次请求，带节流与一次重试。
  ///
  /// 网络层不通时抛 [_NetworkDown]，由 [lookup] 接住并放弃整条链 ——
  /// 见那边的注释。
  Future<HttpResult> _send(
    String url,
    Map<String, Object?> query, {
    int attempt = 0,
  }) async {
    await _throttle();

    HttpResult res;
    try {
      res = await _http.get(
        url,
        query: query,
        headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
        timeout: requestTimeout,
      );
    } catch (e) {
      // 网络层抛异常（假客户端、或 dio 之外的意外）。不该让播放流程挂掉。
      diag.warn('歌词', '请求 LRCLIB 抛出异常', error: e);
      throw const _NetworkDown();
    }

    if (res.isNetworkFailure) {
      diag.info('歌词', 'LRCLIB 请求未完成：${res.rawBody}');
      throw const _NetworkDown();
    }

    // 限流：必须尊重 Retry-After，否则会被当成爬虫直接封掉
    if (res.statusCode == 429 && attempt < 1) {
      final wait = _retryAfter(res) ?? retryDelay;
      diag.warn('歌词', 'LRCLIB 限流（429），${wait.inMilliseconds}ms 后重试一次');
      await _sleep(wait);
      return _send(url, query, attempt: attempt + 1);
    }

    // 服务端过载（实测出现过 503 ServerOverloaded）。一次重试通常就好了。
    if (res.statusCode >= 500 && attempt < 1) {
      diag.info('歌词', 'LRCLIB 返回 ${res.statusCode}，${retryDelay.inMilliseconds}ms 后重试一次');
      await _sleep(retryDelay);
      return _send(url, query, attempt: attempt + 1);
    }

    return res;
  }

  /// 解析 `Retry-After`（秒），并压到 [maxRetryAfter] 以内。
  Duration? _retryAfter(HttpResult res) {
    final raw = res.header('retry-after');
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds == null || seconds <= 0) return null;
    final d = Duration(seconds: seconds);
    return d > maxRetryAfter ? maxRetryAfter : d;
  }

  /// 节流：保证相邻两次请求**发起时刻**之间至少间隔 [minInterval]。
  ///
  /// 和扫描器那条限速同一个道理（见 `ScanService.throttleList`）：按请求
  /// **起点**计时，而不是在请求结束后固定 sleep —— 请求本身耗时 800ms 时
  /// 再额外等 300ms，实际速率会被压到远低于配置值。
  Future<void> _throttle() async {
    final interval = minInterval;
    if (interval <= Duration.zero) return;
    final last = _lastRequestAt;
    if (last != null) {
      final wait = interval - _clock().difference(last);
      if (wait > Duration.zero) await _sleep(wait);
    }
    _lastRequestAt = _clock();
  }
}

/// 网络层不通（断网 / DNS 失败 / 超时 / 连接被拒）。
///
/// 做成一个私有异常而不是「返回 null」，是为了让 [LrclibClient.lookup]
/// 能区分两件事：
///   - **服务器给了答复但说没有**（404 / 5xx）→ 值得试下一级；
///   - **压根没连上** → 整条链都没意义，立刻放弃。
/// 用返回值表达这个区别要么多一层包装类型，要么得让调用方去比对
/// 「null 到底是哪种 null」—— 异常在这里恰好是更直白的表达。
class _NetworkDown implements Exception {
  const _NetworkDown();
}

/// 清理要发给第三方的查询值。
///
/// 只做一件事：把「等于没填」的值变成 `null`。
///   - 空串 / 纯空白；
///   - 界面上的占位词（`未知艺术家` / `Unknown`）—— 曲目元数据缺失时
///     调用方可能把展示文案直接传下来，而把 `未知艺术家` 当艺术家名发给
///     LRCLIB 会让 `/api/get` **必然**匹配不上（比不传还差）。
String? cleanQueryValue(String? raw) {
  final v = raw?.trim();
  if (v == null || v.isEmpty) return null;
  const placeholders = {
    '未知', '未知艺术家', '未知歌手', '未知专辑', '未知曲目',
    'unknown', 'unknown artist', 'n/a', '-', '--',
  };
  if (placeholders.contains(v.toLowerCase())) return null;
  return v;
}
