import 'dart:async';

import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/scan_cursor.dart';
import 'package:cloudtune/domain/services/auto_scan_service.dart';
import 'package:cloudtune/domain/services/playability_resolver.dart';
import 'package:cloudtune/domain/services/scan_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 不真正计时、只记录「该在什么时候触发、触发时干什么」的计时器。
///
/// 配合注入的 `timerFactory`，把 `AutoScanService` 的调度逻辑从真实时间中
/// 解耦：测试手动调用捕获到的回调来模拟「到点触发」。
class _StubTimer implements Timer {
  _StubTimer(this._fire);
  final void Function() _fire;

  bool cancelled = false;
  bool fired = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => 0;

  void fire() {
    fired = true;
    _fire();
  }
}

class _FakeRunner implements ScanRunner {
  _FakeRunner(this._scanned, {this.failFor = const {}});

  final List<DriveProvider> _scanned;
  final Set<DriveProvider> failFor;

  bool running = false;

  @override
  bool get isRunning => running;

  @override
  Future<ScanOutcome> scan(DriveProvider provider) async {
    if (failFor.contains(provider)) {
      throw StateError('scan failed for $provider');
    }
    _scanned.add(provider);
    return ScanOutcome(
      cursor: ScanCursor.fresh(provider: provider, rootId: '0'),
      tracksIndexed: 0,
      removedTracks: 0,
      playability: PlayabilitySummary.empty,
      wasCancelled: false,
    );
  }
}

void main() {
  group('AutoScanService：调度与不定时', () {
    test('start 后 runOnce 扫所有已授权网盘一次', () async {
      final scanned = <DriveProvider>[];
      final runner = _FakeRunner(scanned);
      final svc = AutoScanService(
        runner: runner,
        getProviders: () => [DriveProvider.quark, DriveProvider.aliyun],
        interval: const Duration(hours: 1),
        timerFactory: (d, cb) => _StubTimer(cb),
      );
      svc.start();

      final n = await svc.runOnce();
      expect(n, 2);
      expect(scanned, [
        DriveProvider.quark,
        DriveProvider.aliyun,
      ]);
    });

    test('未 start 时 runOnce 直接返回 0（不扫描）', () async {
      final scanned = <DriveProvider>[];
      final svc = AutoScanService(
        runner: _FakeRunner(scanned),
        getProviders: () => [DriveProvider.quark],
        interval: const Duration(hours: 1),
        timerFactory: (d, cb) => _StubTimer(cb),
      );

      expect(await svc.runOnce(), 0);
      expect(scanned, isEmpty);
    });

    test('扫描进行中时 runOnce 跳过本轮（避免两路并发）', () async {
      final scanned = <DriveProvider>[];
      final runner = _FakeRunner(scanned)..running = true;
      final svc = AutoScanService(
        runner: runner,
        getProviders: () => [DriveProvider.quark],
        interval: const Duration(hours: 1),
        timerFactory: (d, cb) => _StubTimer(cb),
      );
      svc.start();

      expect(await svc.runOnce(), 0);
      expect(scanned, isEmpty);
    });

    test('单个网盘失败不中断整轮（其余照常扫，失败上报）', () async {
      final scanned = <DriveProvider>[];
      final errors = <DriveProvider>[];
      final runner = _FakeRunner(scanned, failFor: {DriveProvider.baidu});
      final svc = AutoScanService(
        runner: runner,
        getProviders: () => [
          DriveProvider.quark,
          DriveProvider.baidu,
          DriveProvider.aliyun,
        ],
        interval: const Duration(hours: 1),
        timerFactory: (d, cb) => _StubTimer(cb),
        onError: (e, p) => errors.add(p),
      );
      svc.start();

      final n = await svc.runOnce();
      expect(n, 2, reason: '两个成功、一个失败');
      expect(scanned.map((p) => p.id), ['quark', 'aliyun']);
      expect(errors.map((p) => p.id), ['baidu']);
    });

    test('start 后 nextDelay 落在 [interval - jitter, interval + jitter]', () {
      final svc = AutoScanService(
        runner: _FakeRunner([]),
        getProviders: () => [DriveProvider.quark],
        interval: const Duration(minutes: 30),
        jitter: const Duration(minutes: 5),
        timerFactory: (d, cb) => _StubTimer(cb),
      );
      svc.start();

      final ms = svc.nextDelay!.inMilliseconds;
      expect(ms, greaterThanOrEqualTo(Duration(minutes: 25).inMilliseconds));
      expect(ms, lessThanOrEqualTo(Duration(minutes: 35).inMilliseconds));
    });

    test('stop 取消计时器且 isActive 复位', () {
      final svc = AutoScanService(
        runner: _FakeRunner([]),
        getProviders: () => [DriveProvider.quark],
        interval: const Duration(hours: 1),
        timerFactory: (d, cb) => _StubTimer(cb),
      );
      svc.start();
      expect(svc.isActive, isTrue);

      svc.stop();
      expect(svc.isActive, isFalse);
      expect(svc.nextDelay, isNull);
    });

    test('tick 触发一轮扫描，结束回调 onCycleDone 被调用', () async {
      final scanned = <DriveProvider>[];
      _StubTimer? timer;
      var cycleDone = false;
      final svc = AutoScanService(
        runner: _FakeRunner(scanned),
        getProviders: () => [DriveProvider.quark],
        interval: const Duration(hours: 1),
        timerFactory: (d, cb) {
          timer = _StubTimer(cb);
          return timer!;
        },
        onCycleDone: () => cycleDone = true,
      );
      svc.start();

      // 模拟「计时器到点」
      timer!.fire();
      // runOnce 内的扫描已经 await 完，但 onCycleDone 在 whenComplete 里，
      // 给一拍事件循环让它跑完
      await Future<void>.delayed(Duration.zero);

      expect(scanned, [DriveProvider.quark]);
      expect(cycleDone, isTrue);
    });
  });
}
