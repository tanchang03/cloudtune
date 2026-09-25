import 'dart:async';

import 'package:cloudtune/core/error/drive_error.dart';
import 'package:cloudtune/data/db/app_database.dart';
import 'package:cloudtune/data/db/library_repository_impl.dart';
import 'package:cloudtune/data/registry/drive_adapter_registry.dart';
import 'package:cloudtune/domain/adapters/audio_output.dart';
import 'package:cloudtune/domain/adapters/cloud_drive_adapter.dart';
import 'package:cloudtune/domain/entities/auth_credential.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/cloud_account.dart';
import 'package:cloudtune/domain/entities/drive_entry.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/stream_ticket.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/domain/services/playback_controller.dart';
import 'package:cloudtune/domain/services/playback_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _mib = 1024 * 1024;

/// 假想的能力声明：50MiB 播放取链上限 + 直链必须带请求头。
/// 夸克的真实声明**没有**体积上限，这里保留上限是为了覆盖「被判不可播」的分支。
const _quarkCap = Capabilities(
  provider: DriveProvider.quark,
  maxSingleFileBytes: Capabilities.fiftyMiB,
  directLinkNeedsHeaders: true,
);

// =====================================================================
// 假音频输出
// =====================================================================

class _LoadRecord {
  const _LoadRecord({
    required this.url,
    required this.headers,
    required this.from,
  });

  final Uri url;
  final Map<String, String> headers;
  final Duration from;
}

class _FakeAudioOutput implements AudioOutput {
  final loads = <_LoadRecord>[];

  // 用同步流：真实播放器的事件是异步投递的，但测试里需要「emit 之后
  // 立刻能读到 controller.pendingTask」才能确定地等待自愈结束。
  // 同步投递对引擎是更严格的要求，能过说明两种投递方式都处理正确。
  final _failures = StreamController<PlaybackFailure>.broadcast(sync: true);
  final _completed = StreamController<void>.broadcast(sync: true);
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _duration = StreamController<Duration?>.broadcast(sync: true);

  /// 装载阶段直接抛出的异常（模拟「一开始就播不了」）。**每次装载都抛**，
  /// 用于「整个队列都坏了」的场景。
  Object? loadError;

  /// 只让**下一次**装载失败，之后自动恢复正常。
  ///
  /// 「这一首坏了、下一首是好的」是最常见的真实场景（DSD 文件混在
  /// 一堆 FLAC 里），用 [loadError] 会让下一首也失败，测不出「自动跳过
  /// 之后真的接着播了」。
  Object? loadErrorOnce;

  @override
  Duration position = Duration.zero;

  @override
  Duration? duration = const Duration(minutes: 4);

  /// 收到的全部 seek 请求（**播放器坐标**，即整轨文件内的绝对位置）。
  ///
  /// 断言用这个而不是 [position]：`await controller.seek(...)` 会让微任务
  /// 跑完，一次「拖到终点」触发的切歌可能已经把 [position] 重置成下一首的
  /// 起点了。
  final List<Duration> seeks = [];

  @override
  bool isPlaying = false;

  @override
  Future<void> load(
    StreamTicket ticket, {
    Duration initialPosition = Duration.zero,
  }) async {
    final err = loadErrorOnce ?? loadError;
    if (err != null) {
      if (loadErrorOnce != null) loadErrorOnce = null;
      throw err;
    }
    loads.add(_LoadRecord(
      url: ticket.url,
      headers: ticket.headers,
      from: initialPosition,
    ));
    position = initialPosition;
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    this.position = position;
    _position.add(position);
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
    position = Duration.zero;
  }

  @override
  Stream<PlaybackFailure> get failures => _failures.stream;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<Duration?> get durationStream => _duration.stream;

  @override
  Stream<void> get completedStream => _completed.stream;

  void emitFailure(PlaybackFailure f) {
    if (!_failures.isClosed) _failures.add(f);
  }

  void emitCompleted() {
    if (!_completed.isClosed) _completed.add(null);
  }

  @override
  Future<void> dispose() async {
    await _failures.close();
    await _completed.close();
    await _position.close();
    await _playing.close();
    await _duration.close();
  }
}

// =====================================================================
// 假网盘适配器
// =====================================================================

class _FakeAdapter extends CloudDriveAdapter {
  _FakeAdapter({Capabilities? capabilities})
      : _capabilities = capabilities ??
            const Capabilities(
              provider: DriveProvider.quark,
              maxSingleFileBytes: Capabilities.fiftyMiB,
            );

  @override
  DriveProvider get provider => DriveProvider.quark;

  final Capabilities _capabilities;

  /// 已取链次数（用来验证票据缓存省下了配额）
  int resolveCalls = 0;

  /// 按文件 id 指定取链时要抛的错误
  final Map<String, Object> resolveErrors = {};

  @override
  Capabilities get capabilities => _capabilities;

  @override
  String get rootId => 'root';

  @override
  Future<StreamTicket> resolveStream(String fileId) async {
    resolveCalls++;
    final err = resolveErrors[fileId];
    if (err != null) throw err;

    return StreamTicket(
      // 每次取链给一个不同的签名，便于断言「用的是新直链」
      url: Uri.parse(
        'https://drive-pc.quark.cn/1/clouddrive/file/download'
        '?file=$fileId&sign=$resolveCalls',
      ),
      headers: const {'Cookie': '__pus=secret-session'},
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      contentLength: 1024,
    );
  }

  @override
  Future<DrivePage> listDirectory({
    required String dirId,
    String? pageToken,
    int? pageSize,
  }) async =>
      const DrivePage.empty();

  @override
  Future<List<DriveEntry>> search({
    required String keyword,
    int limit = 100,
    int offset = 0,
  }) async =>
      const [];

  @override
  Future<CloudAccount?> restoreSession() async => null;

  @override
  Future<CloudAccount> authorize(AuthCredential credential) async =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> ping() async => true;

  @override
  Future<void> dispose() async {}
}

// =====================================================================
// 工具
// =====================================================================

Track _t(String remoteId, {DriveProvider provider = DriveProvider.quark}) =>
    Track(
      provider: provider,
      remoteId: remoteId,
      name: '$remoteId.flac',
      sizeBytes: _mib,
    );

/// 让事件流里的回调跑完（广播流的投递是异步的）
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late AppDatabase db;
  late DriftLibraryRepository repo;
  late _FakeAdapter adapter;
  late _FakeAudioOutput output;
  late PlaybackController controller;

  final t1 = _t('f1');
  final t2 = _t('f2');
  final t3 = _t('f3');

  PlaybackController build({
    List<CloudDriveAdapter>? adapters,
    int maxLinkRetries = 2,
    int maxConsecutiveSkips = 5,
    PlaybackQueue? queue,
  }) {
    adapter = _FakeAdapter();
    output = _FakeAudioOutput();
    return PlaybackController(
      registry: DefaultDriveAdapterRegistry(adapters ?? [adapter]),
      library: repo,
      output: output,
      queue: queue,
      maxLinkRetries: maxLinkRetries,
      maxConsecutiveSkips: maxConsecutiveSkips,
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftLibraryRepository(db);
    controller = build();

    // 索引库里必须有这几行，markUnplayable 才有行可更新
    await repo.upsertTracks([t1, t2, t3], capabilities: _quarkCap);
  });

  tearDown(() async {
    await controller.dispose();
    await db.close();
  });

  /// 等 controller 正在跑的异步任务（自愈 / 自动续播）结束。
  ///
  /// 假播放器用的是同步流，所以 `emitXxx()` 返回时任务已经挂上了。
  Future<void> pumpTask() async {
    final task = controller.pendingTask;
    if (task == null) fail('异步任务未启动');
    await task;
  }

  Future<TrackRow> row(String remoteId) async =>
      (await db.select(db.tracks).get()).firstWhere((r) => r.remoteId == remoteId);

  // ===================================================================
  // 基本播放
  // ===================================================================

  group('基本播放', () {
    test('把直链必需的 Cookie 原样交给播放器，并记一次播放', () async {
      final event = await controller.playTrack(t1);

      expect(event.type, PlaybackEventType.started);
      expect(event.track, t1);
      expect(output.loads.length, 1);
      expect(output.loads.single.headers['Cookie'], '__pus=secret-session',
          reason: '夸克缺 Cookie 会直接返回 412');
      expect(output.loads.single.url.queryParameters['file'], 'f1');
      expect(output.loads.single.from, Duration.zero);
      expect(output.isPlaying, isTrue);

      final cands = await repo.shuffleCandidates(provider: DriveProvider.quark);
      expect(cands['quark:f1']!.playCount, 1);
    });

    test('同一首连播两次只取一次直链（票据缓存省配额）', () async {
      await controller.playTrack(t1);
      await controller.playTrack(t1);

      expect(adapter.resolveCalls, 1);
      expect(output.loads.length, 2);
      expect(output.loads[0].url, output.loads[1].url);
    });

    test('播放不在队列里的歌时把它单独作为队列', () async {
      controller.setQueue([t1, t2]);

      await controller.playTrack(t3);

      expect(controller.queue.length, 1);
      expect(controller.current, t3);
    });

    test('next 在顺序模式下依次推进并落库播放统计', () async {
      controller.setQueue([t1, t2, t3]);

      expect((await controller.next()).track, t1);
      expect((await controller.next()).track, t2);
      expect((await controller.next()).track, t3);

      final cands = await repo.shuffleCandidates();
      expect(cands.values.map((c) => c.playCount).toList(), [1, 1, 1]);
    });

    test('previous 回到实际播过的上一首', () async {
      controller.setQueue([t1, t2, t3]);
      await controller.next(); // f1
      await controller.next(); // f2

      final event = await controller.previous();

      expect(event.track, t1, reason: 'f1 才是实际播过的上一首');
      expect(controller.current, t1);
    });

    test('空队列 next 返回 queueEmpty 而不是崩', () async {
      final event = await controller.next();

      expect(event.type, PlaybackEventType.queueEmpty);
      expect(controller.current, isNull);
    });

    test('pause / resume / seek 透传到播放器', () async {
      await controller.playTrack(t1);

      expect((await controller.pause()).type, PlaybackEventType.paused);
      expect(output.isPlaying, isFalse);

      expect((await controller.resume()).type, PlaybackEventType.resumed);
      expect(output.isPlaying, isTrue);

      await controller.seek(const Duration(seconds: 42));
      expect(output.position, const Duration(seconds: 42));
    });

    test('没有当前曲时 resume 等价于 next', () async {
      controller.setQueue([t1, t2]);

      final event = await controller.resume();

      expect(event.type, PlaybackEventType.started);
      expect(event.track, t1);
    });
  });

  // ===================================================================
  // 直链失效自愈（核心）
  // ===================================================================

  group('直链失效自愈', () {
    test('403 后重取直链，并 seek 回中断位置继续播', () async {
      controller.setQueue([t1, t2]);
      await controller.playTrack(t1);
      expect(adapter.resolveCalls, 1);

      // 播到 1 分 23 秒时直链失效
      output.position = const Duration(minutes: 1, seconds: 23);
      output.emitFailure(const PlaybackFailure(
        kind: PlaybackFailureKind.linkExpired,
        message: 'HTTP 403',
        httpStatus: 403,
      ));
      await pumpTask();

      expect(adapter.resolveCalls, 2, reason: '应重取直链');
      expect(output.loads.length, 2);
      expect(output.loads.last.from, const Duration(minutes: 1, seconds: 23),
          reason: '必须从断点续播，否则长曲子跨过一次过期就永远听不完');
      expect(output.loads.last.url.queryParameters['sign'], '2',
          reason: '用的必须是新直链');
      expect(controller.current, t1, reason: '续链不该换歌');
    });

    test('续链自愈不额外计入播放次数', () async {
      await controller.playTrack(t1);

      output.position = const Duration(seconds: 30);
      output.emitFailure(const PlaybackFailure(
        kind: PlaybackFailureKind.linkExpired,
        message: 'HTTP 412',
        httpStatus: 412,
      ));
      await pumpTask();

      final cands = await repo.shuffleCandidates();
      expect(cands['quark:f1']!.playCount, 1,
          reason: '一首歌听一半不该被算成两次播放');
    });

    test('重试上限用尽后跳过并接下一首（不会无限重试）', () async {
      controller.setQueue([t1, t2]);
      await controller.playTrack(t1);

      // 三次失效：前两次重取，第三次超过 maxLinkRetries=2 直接跳过
      for (var i = 0; i < 3; i++) {
        output.emitFailure(const PlaybackFailure(
          kind: PlaybackFailureKind.linkExpired,
          message: 'HTTP 403',
          httpStatus: 403,
        ));
        await pumpTask();
      }

      expect(adapter.resolveCalls, 4, reason: '初始 1 次 + 重试 2 次 + 下一首 1 次');
      expect(controller.current, t2);
    });

    test('续链后再次失效，重试计数不会因为续链成功而清零', () async {
      controller.setQueue([t1, t2]);
      await controller.playTrack(t1);

      for (var i = 0; i < 2; i++) {
        output.emitFailure(const PlaybackFailure(
          kind: PlaybackFailureKind.linkExpired,
          message: 'HTTP 403',
          httpStatus: 403,
        ));
        await pumpTask();
      }
      // 两次重试已用完，但当前还在 f1
      expect(controller.current, t1);

      output.emitFailure(const PlaybackFailure(
        kind: PlaybackFailureKind.linkExpired,
        message: 'HTTP 403',
        httpStatus: 403,
      ));
      await pumpTask();

      expect(controller.current, t2, reason: '第三次应当放弃并跳歌');
    });

    test('HTTP 状态码归类：403/412/416 算过期，404 算文件不存在', () {
      expect(PlaybackFailure.kindFromHttpStatus(403),
          PlaybackFailureKind.linkExpired);
      expect(PlaybackFailure.kindFromHttpStatus(412),
          PlaybackFailureKind.linkExpired);
      expect(PlaybackFailure.kindFromHttpStatus(416),
          PlaybackFailureKind.linkExpired);
      expect(PlaybackFailure.kindFromHttpStatus(404),
          PlaybackFailureKind.notFound);
      expect(PlaybackFailure.kindFromHttpStatus(503),
          PlaybackFailureKind.network);
      expect(PlaybackFailure.kindFromHttpStatus(418),
          PlaybackFailureKind.unknown);
    });
  });

  // ===================================================================
  // 运行时不可播
  // ===================================================================

  group('不可播处理', () {
    test('取链返回超限码时标记落库、移出队列并接下一首', () async {
      controller.setQueue([t1, t2]);
      adapter.resolveErrors['f1'] = const DriveException(
        type: DriveErrorType.fileTooLarge,
        message: '文件超出网盘允许的下载体积',
        providerCode: 23018,
      );

      final event = await controller.playTrack(t1);

      expect(event.type, PlaybackEventType.started);
      expect(event.track, t2, reason: '自动接上了下一首');

      final r = await row('f1');
      expect(r.playabilityState, 'overLimit');
      expect(r.isPlayable, isFalse);
      expect(r.playabilityNote, contains('超出'));
      expect(controller.queue.contains('quark:f1'), isFalse,
          reason: '不可播的曲目要移出队列，否则随机播放每轮都撞同一堵墙');
    });

    test('播放中途报「音源不可播」时落库为解码失败并跳过', () async {
      controller.setQueue([t1, t2]);
      await controller.playTrack(t1);

      output.emitFailure(const PlaybackFailure(
        kind: PlaybackFailureKind.unplayableSource,
        message: '播放器无法解码该音频（可能是不受支持的编码或损坏的文件）',
      ));
      await pumpTask();

      expect((await row('f1')).playabilityState, 'decodeFailed',
          reason: '这是本机解码器的问题，不是网盘不给链 —— 记成 overLimit '
              '会让列表显示「取不到链」，用户照着这个原因永远修不好');
      expect((await row('f1')).playabilityNote, contains('解码'));
      expect(controller.current, t2);
    });

    test('网盘未开放直链能力时标记 unsupportedByProvider 并移出队列', () async {
      final noLink = _FakeAdapter(
        capabilities: const Capabilities(
          provider: DriveProvider.quark,
          canResolveDirectLink: false,
        ),
      );
      await controller.dispose();
      controller = build(adapters: [noLink]);
      controller.setQueue([t1]);

      final event = await controller.playTrack(t1);

      expect(event.type, PlaybackEventType.queueEmpty,
          reason: '唯一的曲目不可播，队列随即空了');
      expect(noLink.resolveCalls, 0, reason: '不该白试一次取链');
      expect(controller.queue.contains('quark:f1'), isFalse);
      expect((await row('f1')).playabilityState, 'unsupportedByProvider');
    });

    test('未注册的网盘直接跳过，不抛异常', () async {
      controller.setQueue([_t('ali1', provider: DriveProvider.aliyun), t2]);

      final event = await controller.playTrack(
        _t('ali1', provider: DriveProvider.aliyun),
      );

      expect(event.type, PlaybackEventType.started);
      expect(event.track, t2);
    });

    test('整个队列都不可播时不会无限刷接口', () async {
      final many = [for (var i = 0; i < 10; i++) _t('x$i')];
      await repo.upsertTracks(many, capabilities: _quarkCap);
      for (final t in many) {
        adapter.resolveErrors[t.remoteId] = const DriveException(
          type: DriveErrorType.fileTooLarge,
          message: '超出上限',
          providerCode: 23018,
        );
      }
      controller.setQueue(many);

      final event = await controller.playTrack(many.first);

      expect(event.type, PlaybackEventType.failed);
      expect(event.message, contains('连续跳过'));
      expect(adapter.resolveCalls, 6, reason: '跳过 5 首后停止，第 6 首不再取链');
    });

    test('不可播落库后，随机候选集里不再包含它', () async {
      controller.setQueue([t1, t2]);
      adapter.resolveErrors['f1'] = const DriveException(
        type: DriveErrorType.fileTooLarge,
        message: '超出上限',
        providerCode: 23018,
      );

      await controller.playTrack(t1);

      final cands = await repo.shuffleCandidates(provider: DriveProvider.quark);
      expect(cands.containsKey('quark:f1'), isFalse);
      expect(cands.containsKey('quark:f2'), isTrue);
    });
  });

  // ===================================================================
  // 播不出来时自动跳过（不要把播放停住）
  // ===================================================================

  group('播不出来时自动跳过', () {
    test('装载阶段解码失败：落库为解码失败、移出队列、接着播下一首', () async {
      controller.setQueue([t1, t2]);
      // DSD（.dsf）就属于这一类：网盘给了链，但 macOS 的 AVFoundation
      // 根本不认这个编码 —— 典型「播不了的音乐」
      output.loadErrorOnce = const PlaybackLoadException(PlaybackFailure(
        kind: PlaybackFailureKind.unplayableSource,
        message: '播放器无法解码该音频（可能是不受支持的编码或损坏的文件）',
      ));

      final event = await controller.playTrack(t1);

      expect(event.type, PlaybackEventType.started);
      expect(event.track, t2, reason: '一首解不开的文件不该把整个播放停住');
      expect((await row('f1')).playabilityState, 'decodeFailed');
      expect(controller.queue.contains('quark:f1'), isFalse,
          reason: '不移出队列的话，随机播放每一轮都会再撞一次同一堵墙');
    });

    test('装载阶段抛未归类异常：跳过而不是停住，且不落库', () async {
      controller.setQueue([t1, t2]);
      output.loadErrorOnce = StateError('平台播放器内部炸了');

      final event = await controller.playTrack(t1);

      expect(event.type, PlaybackEventType.started);
      expect(event.track, t2);
      expect((await row('f1')).playabilityState, isNot('decodeFailed'),
          reason: '原因不明的偶发失败不该给这首歌判死刑');
    });

    test('播放中途未归类失败：跳过而不是停住，且不落库', () async {
      controller.setQueue([t1, t2]);
      await controller.playTrack(t1);

      output.emitFailure(const PlaybackFailure(
        kind: PlaybackFailureKind.unknown,
        message: '某个没见过的错误',
      ));
      await pumpTask();

      expect(controller.current, t2, reason: '播到一半出的怪毛病也要跳过去');
      expect((await row('f1')).playabilityState, isNot('decodeFailed'));
    });

    test('取链遇到未归类错误：跳过而不是停住', () async {
      controller.setQueue([t1, t2]);
      adapter.resolveErrors['f1'] = const DriveException(
        type: DriveErrorType.malformedResponse,
        message: '响应解析失败',
      );

      final event = await controller.playTrack(t1);

      expect(event.type, PlaybackEventType.started);
      expect(event.track, t2);
    });

    test('限流仍然停下来 —— 跳歌只会让限流更糟', () async {
      controller.setQueue([t1, t2]);
      adapter.resolveErrors['f1'] = const DriveException(
        type: DriveErrorType.rateLimited,
        message: '请求过于频繁',
      );

      final event = await controller.playTrack(t1);

      expect(event.type, PlaybackEventType.failed);
      expect(controller.current, t1, reason: '限流是环境问题，跳歌解决不了');
      expect(adapter.resolveCalls, 1, reason: '不该继续去撞取链接口');
    });

    test('整个队列都解不开时，连续跳过上限仍然生效', () async {
      final many = [for (var i = 0; i < 10; i++) _t('y$i')];
      await repo.upsertTracks(many, capabilities: _quarkCap);
      output.loadError = const PlaybackLoadException(PlaybackFailure(
        kind: PlaybackFailureKind.unplayableSource,
        message: '播放器无法解码该音频',
      ));
      controller.setQueue(many);

      final event = await controller.playTrack(many.first);

      expect(event.type, PlaybackEventType.failed);
      expect(event.message, contains('连续跳过'),
          reason: '自动跳过必须有上限，否则整个库都坏掉时会无限刷接口');
    });
  });

  // ===================================================================
  // 授权与网络
  // ===================================================================

  group('授权与网络错误', () {
    test('授权失效时报错并停在原地，不盲目跳歌', () async {
      controller.setQueue([t1, t2]);
      adapter.resolveErrors['f1'] = const DriveException(
        type: DriveErrorType.unauthorized,
        message: '登录态失效',
        providerCode: 31001,
      );

      final event = await controller.playTrack(t1);

      expect(event.type, PlaybackEventType.failed);
      expect(event.message, contains('重新登录'));
      expect(controller.current, t1, reason: '授权问题要用户处理，跳歌只会掩盖问题');
      expect(output.loads, isEmpty);
      expect(controller.isPlaying, isFalse);
    });

    test('文件已不存在时移出队列并跳过', () async {
      controller.setQueue([t1, t2]);
      adapter.resolveErrors['f1'] = const DriveException(
        type: DriveErrorType.notFound,
        message: '文件不存在',
      );

      final event = await controller.playTrack(t1);

      expect(event.type, PlaybackEventType.started);
      expect(event.track, t2);
      expect(controller.queue.contains('quark:f1'), isFalse);
    });

    test('播放中途 404 也走「移出队列 + 跳过」', () async {
      controller.setQueue([t1, t2]);
      await controller.playTrack(t1);

      output.emitFailure(const PlaybackFailure(
        kind: PlaybackFailureKind.notFound,
        message: 'HTTP 404',
        httpStatus: 404,
      ));
      await pumpTask();

      expect(controller.current, t2);
      expect(controller.queue.contains('quark:f1'), isFalse);
    });

    test('网络类失败只报错，不自动跳歌', () async {
      controller.setQueue([t1, t2]);
      await controller.playTrack(t1);

      output.emitFailure(const PlaybackFailure(
        kind: PlaybackFailureKind.network,
        message: '连接超时',
      ));
      await pumpTask();

      expect(controller.current, t1, reason: '网络抖动不该把歌跳掉');
      expect(controller.isPlaying, isFalse);
      expect(adapter.resolveCalls, 1, reason: '网络问题不该重取直链');
    });

    test('装载阶段抛错时报错而不是当成播放成功', () async {
      output.loadError = const DriveException(
        type: DriveErrorType.network,
        message: '连接被重置',
      );

      final event = await controller.playTrack(t1);

      expect(event.type, PlaybackEventType.failed);
      expect(controller.isPlaying, isFalse);
      final cands = await repo.shuffleCandidates();
      expect(cands['quark:f1']!.playCount, 0,
          reason: '没播出声就不该记播放次数');
    });
  });

  // ===================================================================
  // 播完自动续
  // ===================================================================

  group('播完自动续', () {
    test('一首播完自动接下一首', () async {
      controller.setQueue([t1, t2, t3]);
      await controller.playTrack(t1);

      output.emitCompleted();
      await pumpTask();

      expect(controller.current, t2);
      expect(output.loads.length, 2);
    });

    test('单曲循环模式播完重播同一首', () async {
      controller.setQueue([t1, t2]);
      controller.setMode(PlaybackMode.repeatOne);
      await controller.playTrack(t1);

      output.emitCompleted();
      await pumpTask();

      expect(controller.current, t1);
      expect(adapter.resolveCalls, 1, reason: '重播同一首应命中票据缓存');
    });

    test('队列末尾播完后回到第一首', () async {
      controller.setQueue([t1, t2]);
      await controller.playTrack(t2);

      output.emitCompleted();
      await pumpTask();

      expect(controller.current, t1);
    });

    test('播完事件会上报给 UI', () async {
      final events = <PlaybackEvent>[];
      final sub = controller.events.listen(events.add);
      controller.setQueue([t1, t2]);
      await controller.playTrack(t1);

      output.emitCompleted();
      await pumpTask();
      await _flush();

      expect(events.map((e) => e.type), contains(PlaybackEventType.completed));
      await sub.cancel();
    });
  });

  // ===================================================================
  // 队列与权重
  // ===================================================================

  group('队列与权重', () {
    test('setQueue 把播放统计接进随机权重', () async {
      controller.setQueue([t1, t2, t3], weights: await repo.shuffleCandidates());

      await controller.playTrack(t1);

      final cands = await repo.shuffleCandidates();
      expect(cands['quark:f1']!.playCount, 1);
    });

    test('setQueue 保留当前曲目（重新扫描不打断播放）', () async {
      controller.setQueue([t1, t2, t3]);
      await controller.playTrack(t2);

      controller.setQueue([t1, t2, t3]);

      expect(controller.current, t2);
    });

    test('setMode 切到随机后队列开始随机取曲', () async {
      controller.setQueue([t1, t2, t3]);
      controller.setMode(PlaybackMode.shuffle);

      final seen = <String>{};
      for (var i = 0; i < 3; i++) {
        seen.add((await controller.next()).track!.id);
      }

      expect(seen.length, 3, reason: '一轮内不重复');
    });

    test('播放事件流会把跳过原因报给 UI', () async {
      final events = <PlaybackEvent>[];
      final sub = controller.events.listen(events.add);
      controller.setQueue([t1, t2]);
      adapter.resolveErrors['f1'] = const DriveException(
        type: DriveErrorType.fileTooLarge,
        message: '文件超出网盘允许的下载体积',
        providerCode: 23018,
      );

      await controller.playTrack(t1);
      await _flush();

      final skipped =
          events.firstWhere((e) => e.type == PlaybackEventType.skipped);
      expect(skipped.track, t1);
      expect(skipped.message, contains('超出'));
      expect(skipped.isProblem, isTrue);
      await sub.cancel();
    });
  });

  // ===================================================================
  // 播放顺序
  // ===================================================================

  group('播放顺序', () {
    test('顺序播放严格按曲池次序推进（曲池就是用户看到的那份列表）', () async {
      // 故意乱序传入：曲池的次序才是「当前列表顺序」，不是 id、也不是文件名
      controller.setQueue([t3, t1, t2]);

      expect((await controller.next()).track, t3);
      expect((await controller.next()).track, t1);
      expect((await controller.next()).track, t2);
      expect((await controller.next()).track, t3, reason: '播到末尾回到第一首');
    });

    test('从随机切回顺序后，下一首回到曲池里的下一首', () async {
      controller.setQueue([t1, t2, t3]);
      await controller.playTrack(t1);

      controller.setMode(PlaybackMode.shuffle);
      await controller.next(); // 随机抽一首

      controller.setMode(PlaybackMode.sequential);
      final tracks = controller.queue.tracks;
      final idx = tracks.indexWhere((t) => t.id == controller.current!.id);
      final expected = tracks[(idx + 1) % tracks.length];

      expect((await controller.next()).track, expected,
          reason: '切回顺序播放必须沿用列表次序，而不是沿用随机的抽签结果');
    });

    test('模式互切一次到位（顺序 ↔ 随机），不经过单曲循环', () {
      controller.setQueue([t1, t2]);
      expect(controller.queue.mode, PlaybackMode.sequential);

      controller.setMode(controller.queue.mode.toggled);
      expect(controller.queue.mode, PlaybackMode.shuffle);

      controller.setMode(controller.queue.mode.toggled);
      expect(controller.queue.mode, PlaybackMode.sequential);
    });

    test('重设队列按新列表次序生效，且不会顺带改掉播放模式', () {
      controller.setQueue([t1, t2, t3]);
      controller.setMode(PlaybackMode.shuffle);

      controller.setQueue([t2, t3, t1]); // 例如用户改了排序

      expect(
        controller.queue.tracks.map((t) => t.id).toList(),
        ['quark:f2', 'quark:f3', 'quark:f1'],
        reason: '队列必须换成新列表的次序，否则顺序播放会沿用旧列表',
      );
      expect(controller.queue.mode, PlaybackMode.shuffle,
          reason: '换列表不该悄悄把用户选好的随机播放关掉');
    });
  });

  // ===================================================================
  // 生命周期
  // ===================================================================

  group('生命周期', () {
    test('dispose 关闭事件流（否则 UI 订阅会泄漏），且可重复调用', () async {
      await controller.playTrack(t1);

      var done = false;
      controller.events.listen(null, onDone: () => done = true);

      await controller.dispose();
      await _flush();

      expect(done, isTrue);
      expect(() => controller.dispose(), returnsNormally);
    });

    test('dispose 后再收到失败事件也不会崩', () async {
      await controller.playTrack(t1);
      await controller.dispose();

      // 假播放器的流已关闭，这里只验证 emit 侧与引擎侧都不抛
      expect(
        () => output.emitFailure(const PlaybackFailure(
          kind: PlaybackFailureKind.linkExpired,
          message: 'HTTP 403',
          httpStatus: 403,
        )),
        returnsNormally,
      );
      await _flush();

      expect(controller.pendingTask, isNull);
    });
  });

  // ===================================================================
  // 整轨分段播放（CUE）
  // ===================================================================

  /// 从整轨文件 `wav1` 切出的一段。
  ///
  /// 坐标是**整轨文件内**的毫秒数：这一段从 200493ms 开始、长 219507ms，
  /// 也就是到 420000ms 结束 —— 与 `CueIndexer` 真实产出的一致。
  Track seg({
    int trackNo = 2,
    int startMs = 200493,
    int? durationMs = 219507,
    String name = '月半小夜曲',
  }) =>
      Track(
        provider: DriveProvider.quark,
        remoteId: 'wav1',
        name: 'CD1.wav',
        sizeBytes: 765145628,
        durationMs: durationMs,
        cueTrackNo: trackNo,
        cueStartMs: startMs,
        title: name,
      );

  group('整轨分段播放', () {
    test('分段从本轨起点起播，而不是文件开头', () async {
      final s = seg();
      await repo.upsertTracks([s], capabilities: _quarkCap);

      await controller.playTrack(s);

      expect(output.loads.single.from, const Duration(milliseconds: 200493),
          reason: '起点错成 0 就会从上一首的尾巴开始放');
    });

    test('普通曲目仍从 0 起播', () async {
      await controller.playTrack(t1);
      expect(output.loads.single.from, Duration.zero);
    });

    test('位置到本轨终点就切下一首（不然一首会放完整张专辑）', () async {
      final s = seg();
      await repo.upsertTracks([s, t2], capabilities: _quarkCap);
      controller.setQueue([s, t2]);
      await controller.playTrack(s);

      // 播到本轨区间内：还没到终点
      output.seek(const Duration(milliseconds: 300000));
      await _flush();
      expect(controller.current, s, reason: '没到终点不该切');

      // 到达终点
      output.seek(const Duration(milliseconds: 420000));
      await pumpTask();

      expect(controller.current, t2);
      expect(output.loads, hasLength(2));
    });

    test('本轨终点未知时不切（只能放到整轨结束）', () async {
      // CUE 末轨要靠整轨时长补齐终点，而网盘可能没给出整轨时长
      final s = seg(trackNo: 9, startMs: 420000, durationMs: null);
      await repo.upsertTracks([s, t2], capabilities: _quarkCap);
      controller.setQueue([s, t2]);
      await controller.playTrack(s);

      output.seek(const Duration(milliseconds: 999999));
      await _flush();

      expect(controller.current, s);
      expect(controller.pendingTask, isNull);
    });

    test('上一首残留的位置事件不会误切（关键回归）', () async {
      // 长段在前、短段在后：从长段切到短段时，长段的残留位置（4338000ms）
      // 远大于短段的终点（200493ms）。不做防护就会立刻再切一首。
      final long = seg(trackNo: 3, startMs: 420000, durationMs: 3918000);
      final short = seg(trackNo: 1, startMs: 0, durationMs: 200493);
      await repo.upsertTracks([long, short], capabilities: _quarkCap);
      controller.setQueue([long, short]);
      await controller.playTrack(long);

      // 先在本轨区间内播一会儿（真实播放中位置事件是连续来的），
      // 再到达终点
      output.seek(const Duration(milliseconds: 500000));
      output.seek(const Duration(milliseconds: 4338000));
      await pumpTask();
      expect(controller.current, short);
      final loadsAfterCut = output.loads.length;

      // 旧音源迟到的位置事件
      output.seek(const Duration(milliseconds: 4338000));
      await _flush();
      expect(controller.current, short, reason: '残留位置不该被当成短段播完');
      expect(output.loads, hasLength(loadsAfterCut), reason: '不该再切一首');

      // 而短段自己播到终点时，仍然要正常切
      output.seek(const Duration(milliseconds: 100000));
      output.seek(const Duration(milliseconds: 200493));
      await pumpTask();
      expect(controller.current, long, reason: '短段真的播完了就该切');
    });

    test('自然播完与分段到点同时发生也只切一首', () async {
      // 整轨最后一轨的 cueEndMs 恰好等于文件结尾，两条路径会几乎同时触发
      final last = seg(trackNo: 3, startMs: 420000, durationMs: 300000);
      await repo.upsertTracks([last, t2], capabilities: _quarkCap);
      controller.setQueue([last, t2]);
      await controller.playTrack(last);

      output.seek(const Duration(milliseconds: 720000));
      output.emitCompleted();
      await pumpTask();
      await _flush();

      expect(controller.current, t2, reason: '连切两首会跳过 t2');
      expect(output.loads, hasLength(2));
    });

    test('单曲循环下分段到点重播本轨，回到本轨起点', () async {
      final s = seg();
      await repo.upsertTracks([s], capabilities: _quarkCap);
      controller.setMode(PlaybackMode.repeatOne);
      controller.setQueue([s]);
      await controller.playTrack(s);

      output.seek(const Duration(milliseconds: 300000));
      output.seek(const Duration(milliseconds: 420000));
      await pumpTask();

      expect(controller.current, s);
      expect(output.loads, hasLength(2));
      expect(output.loads.last.from, const Duration(milliseconds: 200493),
          reason: '重播要从本轨起点开始，不能回到文件开头');
    });

    test('position / duration 用相对本曲目的坐标', () async {
      final s = seg();
      await repo.upsertTracks([s], capabilities: _quarkCap);
      await controller.playTrack(s);

      // 播放器报的是文件内的绝对位置 260493ms
      output.seek(const Duration(milliseconds: 260493));

      expect(controller.position, const Duration(milliseconds: 60000),
          reason: '用户看到的是「本轨播到第 60 秒」');
      expect(controller.duration, const Duration(milliseconds: 219507),
          reason: '用户看到的是本轨时长，不是整轨 72:18');
    });

    test('位置/时长流对外广播的也是本曲目相对坐标（修复：UI 曾拿到整轨绝对坐标）',
        () async {
      // 回归：歌词高亮依赖 `playbackPositionProvider`（来自控制器的
      // `positionStream`）。若这里广播的是整轨文件内的绝对位置，第 3 轨会
      // 看到进度从第 7 分钟起、歌词时间戳全错位，整首歌的歌词都对不上。
      final s = seg();
      await repo.upsertTracks([s], capabilities: _quarkCap);
      await controller.playTrack(s);

      final positions = <Duration>[];
      final durations = <Duration?>[];
      final posSub = controller.positionStream.listen(positions.add);
      final durSub = controller.durationStream.listen(durations.add);

      // 整轨文件实际有 72 分钟：播放器报整轨时长，控制器应转成单轨时长
      output.duration = const Duration(milliseconds: 4320000);
      output._duration.add(output.duration!);
      // 播放器报的是文件内的绝对位置 260493ms（本轨第 60 秒）
      output.seek(const Duration(milliseconds: 260493));
      await _flush();

      await posSub.cancel();
      await durSub.cancel();

      expect(positions, [const Duration(milliseconds: 60000)],
          reason: 'UI 拿到的应是本轨第 60 秒，否则歌词时间戳全错位');
      expect(durations, [const Duration(milliseconds: 219507)],
          reason: 'UI 拿到的应是本轨时长，不是整轨 72 分钟');
    });

    test('单轨时长缺失时，用整轨时长倒推本轨时长', () async {
      // 起点要小于播放器报的整轨时长（假播放器是 4 分钟），否则倒推出来是负数
      final s = seg(trackNo: 9, startMs: 100000, durationMs: null);
      await repo.upsertTracks([s], capabilities: _quarkCap);
      await controller.playTrack(s);

      expect(controller.duration, const Duration(milliseconds: 240000 - 100000),
          reason: '倒推总比让进度条瞎掉强');
    });

    test('倒推不出正数时长时返回 null（不编造负数）', () async {
      // 整轨时长比本轨起点还短 —— 数据明显不对，宁可显示 --:--
      final s = seg(trackNo: 9, startMs: 420000, durationMs: null);
      await repo.upsertTracks([s], capabilities: _quarkCap);
      await controller.playTrack(s);

      expect(controller.duration, isNull);
    });

    test('seek 把相对位置换算成文件内绝对位置', () async {
      final s = seg();
      await repo.upsertTracks([s], capabilities: _quarkCap);
      await controller.playTrack(s);

      await controller.seek(const Duration(seconds: 30));

      expect(output.seeks.last, const Duration(milliseconds: 200493 + 30000),
          reason: '少加起点就会 seek 到上一首的地盘');
    });

    test('seek 夹在本轨范围内，拖到最右不会伸进下一轨', () async {
      final s = seg();
      await repo.upsertTracks([s, t2], capabilities: _quarkCap);
      controller.setQueue([s, t2]);
      await controller.playTrack(s);

      await controller.seek(const Duration(minutes: 10));

      expect(output.seeks.last, const Duration(milliseconds: 420000),
          reason: '本轨只有 219507ms，拖到底应该停在本轨终点');
      // 夹到终点恰好等于「播完了」，切歌是预期行为，把任务收干净
      await pumpTask();
      expect(controller.current, t2);
    });

    test('续链自愈回到文件内的绝对断点（不是相对位置）', () async {
      final s = seg();
      await repo.upsertTracks([s], capabilities: _quarkCap);
      await controller.playTrack(s);
      expect(output.loads.single.from, const Duration(milliseconds: 200493));

      // 播到文件内的 260493ms（相对本轨 60 秒）时直链失效
      output.position = const Duration(milliseconds: 260493);
      output.emitFailure(const PlaybackFailure(
        kind: PlaybackFailureKind.linkExpired,
        message: 'HTTP 412',
        httpStatus: 412,
      ));
      await pumpTask();

      expect(output.loads, hasLength(2));
      expect(output.loads.last.from, const Duration(milliseconds: 260493),
          reason: '用相对位置（60000ms）续播会退回文件开头附近');
      expect(controller.current, s);
    });
  });
}
