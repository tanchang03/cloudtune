import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/diagnostics/diag_log.dart';
import '../../domain/adapters/audio_output.dart';
import '../../domain/entities/stream_ticket.dart';
import 'stream_probe.dart';

/// 基于 `just_audio` 的音频输出实现。
///
/// 这一层刻意做得很薄：**只负责把平台播放器的 API 与错误码翻译成领域语言**，
/// 所有编排逻辑（取链、缓存、续链、跳过、统计）都在
/// `PlaybackController` 里，那部分才是容易写错的地方，也因此能被单元测试覆盖。
///
/// 三个必须注意的平台差异：
///   1. **请求头必须原样传下去**。夸克直链缺 `Cookie` 会直接 `412`，
///      只带 `Referer` 或 `User-Agent` 都不行；
///   2. **Web 平台无法给媒体请求设置请求头**（浏览器的限制，不是 just_audio
///      的问题）。因此带 Cookie 的网盘直链在 Web 上播不了 —— 这也是当初把
///      Web 排除出首期范围的原因之一；
///   3. 桌面端需要额外注册后端（`just_audio_windows` / `just_audio_media_kit`），
///      在 `main()` 里完成。
class JustAudioOutput implements AudioOutput {
  JustAudioOutput({AudioPlayer? player, StreamProbe? probe})
      : _player = player ?? AudioPlayer(),
        _probe = probe ?? probeStreamAfterFailure {
    // 播放中途的错误统一从 playbackEventStream 的 onError 出来
    // （当前 just_audio 版本没有独立的 errorStream）。
    _eventErrorSub = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace _) => _report(e),
    );
    _stateSub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !_completed.isClosed) {
        _completed.add(null);
      }
    });
  }

  final AudioPlayer _player;

  /// 失败后回探直链用的钩子。默认是真实探测，测试里换成假实现。
  final StreamProbe _probe;

  /// 最近一次装载的票据。失败是**异步**报出来的（`playbackEventStream`
  /// 的 onError），那时 [load] 的入参早就不在栈上了 —— 没有这个字段，
  /// 探测就无从谈起。
  StreamTicket? _lastTicket;

  late final StreamSubscription<PlaybackEvent> _eventErrorSub;
  late final StreamSubscription<ProcessingState> _stateSub;

  final _failures = StreamController<PlaybackFailure>.broadcast();
  final _completed = StreamController<void>.broadcast();

  /// 当前音源对应的曲目 id，用于让失败事件带上归属。
  /// 由 [load] 从票据里推不出来，因此由调用方通过 [setCurrentTrackId] 告知。
  String? _trackId;

  var _disposed = false;

  /// 告知当前装载的是哪首曲目。引擎在 [load] 之前调用。
  void setCurrentTrackId(String? trackId) => _trackId = trackId;

  @override
  Future<void> load(
    StreamTicket ticket, {
    Duration initialPosition = Duration.zero,
  }) async {
    _lastTicket = ticket;
    diag.info(
      '播放器',
      '装载音源：${ticket.redactedUrl}，'
      '请求头=${ticket.headers.isEmpty ? "无" : ticket.headers.keys.join(",")}，'
      '起始位置=$initialPosition',
    );
    try {
      await _player.setAudioSource(
        AudioSource.uri(ticket.url, headers: ticket.headers),
        initialPosition: initialPosition,
      );
      diag.info('播放器', '装载成功，平台声明时长=${_player.duration ?? "未知"}');
    } catch (e, st) {
      // 归类后一律用 PlaybackLoadException 上抛，让引擎用与「播放中途失败」
      // 完全相同的那套决策处理（见 AudioOutput 的约定）。
      //
      // ⚠️ 不能只把 unplayableSource 翻译掉、其余 rethrow：那样引擎收到的
      // 是一个没有归类的 Object，分不清「解码器解不开这个编码」（要标记跳过，
      // 免得每轮随机播放都撞同一堵墙）和「网络抖了一下」（只需提示用户），
      // 于是只能一律停下 —— 这正是「遇到播不了的文件就卡住」的由来。
      //
      // 原始异常**必须原样进日志**：`classify` 会把它翻译成「HTTP 412」
      // 这类领域语言，翻译过程会丢掉平台原话（AVFoundation 的错误域、
      // 失败原因、底层 OSStatus）。排查时想看的恰恰是那句原话。
      diag.error('播放器', '装载失败（原始异常）', error: e, stackTrace: st);
      final failure = classify(e, trackId: _trackId);
      diag.error(
        '播放器',
        '装载失败（归类后）：kind=${failure.kind.name} '
        'http=${failure.httpStatus ?? "-"} '
        'providerCode=${failure.providerCode ?? "-"} '
        'message=${failure.message}',
      );
      // 平台原话经常只有一句「操作无法完成」，分不出是直链废了还是解码器不认。
      // 回探一次直链拿状态码来切开这个歧义。**不 await** ——
      // 该跳歌就跳歌，不能被探测的超时拖住。
      unawaited(_probe(ticket));
      throw PlaybackLoadException(failure);
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  bool get isPlaying => _player.playing;

  @override
  Stream<PlaybackFailure> get failures => _failures.stream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<void> get completedStream => _completed.stream;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventErrorSub.cancel();
    await _stateSub.cancel();
    await _failures.close();
    await _completed.close();
    await _player.dispose();
  }

  void _report(Object error) {
    if (_disposed || _failures.isClosed) return;
    // 播放中途的错误同样保留原始文案 —— 这是判断「解码器解不开」
    // 还是「网盘把直链掐了」的唯一依据。
    diag.error('播放器', '播放中途失败（原始异常）', error: error);
    final failure = classify(error, trackId: _trackId);
    diag.error(
      '播放器',
      '播放中途失败（归类后）：kind=${failure.kind.name} '
      'http=${failure.httpStatus ?? "-"} message=${failure.message}',
    );
    final ticket = _lastTicket;
    if (ticket != null) unawaited(_probe(ticket));
    _failures.add(failure);
  }

  // -------------------------------------------------------------------
  // 平台错误 → 领域语义
  // -------------------------------------------------------------------

  /// 把平台播放器的错误归类成引擎能决策的 [PlaybackFailureKind]。
  ///
  /// 顺序很重要：先认网盘业务码（`23018` 最明确），再认 HTTP 状态码，
  /// 最后才靠文案猜解码/格式问题 —— 文案匹配是最不可靠的一层，放最后。
  static PlaybackFailure classify(Object error, {String? trackId}) {
    var message = error.toString();
    int? code;

    if (error is PlayerException) {
      code = error.code;
      final m = error.message;
      if (m != null && m.isNotEmpty) message = m;
    } else if (error is PlatformException) {
      code = int.tryParse(error.code);
      final m = error.message;
      if (m != null && m.isNotEmpty) message = m;
    }

    // 夸克超限码：文件超出单文件下载上限
    if (code == _quarkFileTooLarge || message.contains('$_quarkFileTooLarge')) {
      return PlaybackFailure(
        kind: PlaybackFailureKind.unplayableSource,
        message: '文件超出网盘允许的下载体积',
        providerCode: _quarkFileTooLarge,
        trackId: trackId,
      );
    }

    final httpStatus = _httpStatusIn(message) ?? _httpStatusFromCode(code);
    if (httpStatus != null) {
      return PlaybackFailure(
        kind: PlaybackFailure.kindFromHttpStatus(httpStatus),
        message: 'HTTP $httpStatus',
        httpStatus: httpStatus,
        providerCode: code,
        trackId: trackId,
      );
    }

    if (_looksLikeFormatProblem(message)) {
      return PlaybackFailure(
        kind: PlaybackFailureKind.unplayableSource,
        message: '播放器无法解码该音频（可能是不受支持的编码或损坏的文件）',
        providerCode: code,
        trackId: trackId,
      );
    }

    return PlaybackFailure(
      kind: PlaybackFailureKind.unknown,
      message: message,
      providerCode: code,
      trackId: trackId,
    );
  }

  static const int _quarkFileTooLarge = 23018;

  /// 从错误文案里抠出 HTTP 状态码。
  ///
  /// 两个收紧条件，都是被真实误判逼出来的：
  ///   - 状态码前面必须有 `HTTP` / `status` / `code` 之类的提示词，
  ///     否则消息里的体积、时长等数字会被当成状态码；
  ///   - 状态码必须以 4 或 5 开头**且后面不能再跟数字**，
  ///     否则 `code 4003` 会被截成 `400`。
  static int? _httpStatusIn(String message) {
    final m = _httpInMessage.firstMatch(message);
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!);
    if (n == null) return null;
    return (n >= 400 && n <= 599) ? n : null;
  }

  static final RegExp _httpInMessage = RegExp(
    r'(?:http|status|code)[^0-9]{0,4}([45][0-9]{2})(?![0-9])',
    caseSensitive: false,
  );

  /// 有些平台直接把 HTTP 状态码当成错误码，没有文案提示。
  static int? _httpStatusFromCode(int? code) {
    if (code == null) return null;
    const known = {400, 401, 403, 404, 408, 410, 412, 416, 429, 500, 502, 503, 504};
    return known.contains(code) ? code : null;
  }

  static bool _looksLikeFormatProblem(String message) {
    const markers = [
      'unrecognizedinputformat',
      'decoder init failed',
      'unable to create a decoder',
      'decoding failed',
      'source error',
      'unsupported',
      'invalid format',
      'mediacodec',
      'format error',
    ];
    final lower = message.toLowerCase();
    return markers.any(lower.contains);
  }
}
