import 'dart:async';

import 'package:cloudtune/data/audio/just_audio_output.dart';
import 'package:cloudtune/domain/adapters/audio_output.dart';
import 'package:cloudtune/domain/entities/stream_ticket.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

/// [JustAudioOutput.classify] 的归类正确性。
///
/// 这是平台与领域之间的翻译层：归错了，引擎就会做错事 ——
/// 把「直链过期」当成「文件坏了」会让用户白丢一首歌；
/// 把「文件超限」当成「直链过期」会变成无限重取直链。
///
/// `classify` 是静态纯函数，不需要真的创建 `AudioPlayer`（那要平台通道）。
void main() {
  PlaybackFailureKind kindOf(Object error) =>
      JustAudioOutput.classify(error).kind;

  group('夸克业务码', () {
    test('错误码 23018 归为「音源不可播」', () {
      final f = JustAudioOutput.classify(
        PlayerException(23018, 'download failed'),
        trackId: 'quark:f1',
      );

      expect(f.kind, PlaybackFailureKind.unplayableSource);
      expect(f.providerCode, 23018);
      expect(f.trackId, 'quark:f1');
      expect(f.message, contains('体积'));
    });

    test('文案里带 23018 也能认出来', () {
      expect(
        kindOf(Exception('quark err code=23018 file too large')),
        PlaybackFailureKind.unplayableSource,
      );
    });

    test('23018 不会被当成 HTTP 状态码', () {
      final f = JustAudioOutput.classify(PlayerException(23018, null));
      expect(f.httpStatus, isNull);
    });
  });

  group('HTTP 状态码归类', () {
    test('403 归为「直链失效」（可自愈）', () {
      final f = JustAudioOutput.classify(PlayerException(403, null));

      expect(f.kind, PlaybackFailureKind.linkExpired);
      expect(f.kind.isSelfHealable, isTrue);
      expect(f.httpStatus, 403);
    });

    test('412 归为「直链失效」（夸克缺 Cookie 的典型返回）', () {
      expect(
        kindOf(PlayerException(412, 'Precondition Failed')),
        PlaybackFailureKind.linkExpired,
      );
    });

    test('416 Range 不满足归为「直链失效」', () {
      expect(kindOf(PlayerException(416, null)),
          PlaybackFailureKind.linkExpired);
    });

    test('404 归为「文件不存在」', () {
      expect(kindOf(PlayerException(404, null)), PlaybackFailureKind.notFound);
    });

    test('5xx / 408 / 429 归为「网络」', () {
      for (final code in [408, 429, 500, 502, 503, 504]) {
        expect(kindOf(PlayerException(code, null)), PlaybackFailureKind.network,
            reason: 'HTTP $code 应可重试');
      }
    });

    test('从文案里解析 HTTP 状态码', () {
      expect(
        kindOf(PlayerException(0, 'HTTP 403 Forbidden')),
        PlaybackFailureKind.linkExpired,
      );
      expect(
        kindOf(Exception('Server returned status 503')),
        PlaybackFailureKind.network,
      );
    });

    test('文案里无关的数字不会被当成状态码', () {
      final f = JustAudioOutput.classify(
        Exception('file size 1234567 bytes, duration 245 seconds'),
      );

      expect(f.httpStatus, isNull);
      expect(f.kind, PlaybackFailureKind.unknown);
    });

    test('code 4003 不会被截成 400', () {
      final f = JustAudioOutput.classify(
        Exception('MediaCodec reported code 4003'),
      );

      expect(f.httpStatus, isNull, reason: '后面还跟着数字，不能截断成 400');
    });

    test('非 4xx/5xx 的三位数不被当成 HTTP 状态码', () {
      expect(
        JustAudioOutput.classify(Exception('status 200 ok')).httpStatus,
        isNull,
      );
    });
  });

  group('平台异常', () {
    test('PlatformException 的状态码同样能归类', () {
      expect(
        kindOf(PlatformException(code: '403', message: 'Forbidden')),
        PlaybackFailureKind.linkExpired,
      );
    });

    test('PlatformException 的非数字 code 不会崩', () {
      final f = JustAudioOutput.classify(
        PlatformException(code: 'DECODER_ERROR', message: 'decoder init failed'),
      );

      expect(f.kind, PlaybackFailureKind.unplayableSource);
    });
  });

  group('解码 / 格式问题', () {
    test('常见解码失败文案归为「音源不可播」', () {
      const messages = [
        'UnrecognizedInputFormatException',
        'Decoder init failed',
        'Unable to create a decoder',
        'source error',
      ];
      for (final m in messages) {
        expect(kindOf(Exception(m)), PlaybackFailureKind.unplayableSource,
            reason: '$m 应归为不可播');
      }
    });

    test('大小写不敏感', () {
      expect(kindOf(Exception('UNRECOGNIZEDINPUTFORMAT')),
          PlaybackFailureKind.unplayableSource);
    });
  });

  group('兜底', () {
    test('认不出的错误归为 unknown 并保留原始文案', () {
      final f = JustAudioOutput.classify(Exception('something odd happened'));

      expect(f.kind, PlaybackFailureKind.unknown);
      expect(f.kind.isSelfHealable, isFalse);
      expect(f.kind.isRetryable, isFalse);
      expect(f.message, contains('something odd'));
    });

    test('unknown / notFound / unplayableSource 都不该触发续链', () {
      expect(PlaybackFailureKind.unknown.isSelfHealable, isFalse);
      expect(PlaybackFailureKind.notFound.isSelfHealable, isFalse);
      expect(PlaybackFailureKind.unplayableSource.isSelfHealable, isFalse);
    });

    test('归类后不会把带签名的直链带进日志', () {
      final f = JustAudioOutput.classify(PlayerException(
        403,
        'failed to load https://drive-pc.quark.cn/1/download?sign=SUPERSECRET',
      ));

      expect(f.kind, PlaybackFailureKind.linkExpired);
      expect(f.message, 'HTTP 403',
          reason: 'message 被规范化为状态码，签名不会外泄');
      expect(f.toString(), isNot(contains('SUPERSECRET')));
    });
  });

  // -------------------------------------------------------------------
  // 装载失败回灌去重（防「一次失败连跳两首」）
  //
  // 真实链路里，`just_audio` 在 setAudioSource 抛错时会把**同一个错误**再
  // 回灌进 playbackEventStream.onError。修复前：load() 的 catch 处理一次、
  // _failures 流又推一次 → 引擎 4ms 内连跳两首、且第二首跳错对象。
  // -------------------------------------------------------------------
  group('装载失败回灌去重', () {
    final ticket = StreamTicket(url: Uri.parse('https://example.com/a.flac'));
    final loadError = PlayerException(-11828, 'Cannot Open');

    late _FakeAudioPlayer player;
    late JustAudioOutput output;
    late List<PlaybackFailure> failures;
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 9, 24, 19);
      player = _FakeAudioPlayer();
      failures = [];
      output = JustAudioOutput(
        player: player,
        probe: (_) async {},
        clock: () => now,
      );
      output.failures.listen(failures.add);
      output.setCurrentTrackId('quark:t1');
    });

    tearDown(() => output.dispose());

    test('装载失败后窗口内回灌的同一错误不进失败流', () async {
      player.setAudioSourceError = loadError;

      await expectLater(
        output.load(ticket),
        throwsA(isA<PlaybackLoadException>()),
      );
      await pumpEventQueue();

      // 模拟 just_audio 的回灌
      player.emitError(loadError);
      await pumpEventQueue();

      expect(failures, isEmpty,
          reason: 'load() 抛 PlaybackLoadException 已处理过一次，'
              '回灌的那条必须被吞掉，否则一次失败跳两首');
    });

    test('窗口外的中途错误正常进失败流（不被误吞）', () async {
      player.setAudioSourceError = loadError;
      await expectLater(
        output.load(ticket),
        throwsA(isA<PlaybackLoadException>()),
      );
      await pumpEventQueue();

      now = now.add(const Duration(milliseconds: 600));
      player.emitError(PlayerException(403, 'HTTP 403'));
      await pumpEventQueue();

      expect(failures.length, 1);
      expect(failures.single.httpStatus, 403);
      expect(failures.single.trackId, 'quark:t1');
    });

    test('装载成功后回灌窗口解除', () async {
      await output.load(ticket); // 装载成功
      await pumpEventQueue();

      player.emitError(PlayerException(403, 'HTTP 403'));
      await pumpEventQueue();

      expect(failures.length, 1,
          reason: '成功装载不应留下去重窗口，否则紧随其后的中途错误被吞');
      expect(failures.single.httpStatus, 403);
    });
  });
}

/// 只实现 [JustAudioOutput] 用到的成员，其余走 noSuchMethod。
class _FakeAudioPlayer implements AudioPlayer {
  final _events = StreamController<PlaybackEvent>.broadcast();
  final _states = StreamController<ProcessingState>.broadcast();

  /// 非 null 时 [setAudioSource] 抛出它（模拟装载失败）。
  Object? setAudioSourceError;

  @override
  Stream<PlaybackEvent> get playbackEventStream => _events.stream;

  @override
  Stream<ProcessingState> get processingStateStream => _states.stream;

  @override
  Duration? get duration => null;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    final e = setAudioSourceError;
    if (e != null) throw e;
    return null;
  }

  /// 模拟 just_audio 把错误回灌进 playbackEventStream.onError。
  void emitError(Object e) => _events.addError(e);

  @override
  Future<void> dispose() async {
    await _events.close();
    await _states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未在假播放器中实现');
}
