import 'package:cloudtune/data/http/token_bucket.dart';
import 'package:flutter_test/flutter_test.dart';

/// 虚拟时钟 + 虚拟等待。
///
/// 让限流测试**不需要真的 sleep**：等待时间直接推进虚拟时间，
/// 于是「第 N 次请求应该等多少毫秒」可以被精确断言。
class VirtualClock {
  VirtualClock([DateTime? start])
      : now = start ?? DateTime(2026, 9, 23, 10, 0, 0);

  DateTime now;

  /// 累计等待时长
  Duration totalWaited = Duration.zero;

  /// 每次等待的记录
  final List<Duration> waits = [];

  DateTime call() => now;

  Future<void> delay(Duration d) async {
    waits.add(d);
    totalWaited += d;
    now = now.add(d);
  }
}

void main() {
  group('初始化与令牌补充', () {
    test('初始即有 burst 个令牌，可连续取用而不等待', () async {
      final clock = VirtualClock();
      final bucket = TokenBucket(
        ratePerSecond: 3,
        burst: 3,
        clock: clock.call,
        delay: clock.delay,
      );

      await bucket.acquire();
      await bucket.acquire();
      await bucket.acquire();

      expect(clock.waits, isEmpty, reason: '桶内令牌足够，不应产生等待');
    });

    test('桶容量为 1 时第二次就要等', () async {
      final clock = VirtualClock();
      final bucket = TokenBucket(
        ratePerSecond: 1,
        burst: 1,
        clock: clock.call,
        delay: clock.delay,
      );

      await bucket.acquire();
      await bucket.acquire();

      expect(clock.waits.length, 1);
      expect(clock.waits.first.inMilliseconds, 1000);
    });
  });

  group('等待时长计算', () {
    test('3 QPS 时第 4 次请求等待约 333ms', () async {
      final clock = VirtualClock();
      final bucket = TokenBucket(
        ratePerSecond: 3,
        burst: 3,
        clock: clock.call,
        delay: clock.delay,
      );

      for (var i = 0; i < 4; i++) {
        await bucket.acquire();
      }

      expect(clock.waits.length, 1);
      // 1/3 秒 ≈ 333333us
      expect(clock.waits.first.inMicroseconds, 333333);
    });

    test('按 350ms 间隔构造：速率约 2.857 QPS，等待 350ms', () async {
      final clock = VirtualClock();
      final bucket = bucketFromInterval(
        const Duration(milliseconds: 350),
        clock: clock.call,
        delay: clock.delay,
      );

      expect(bucket.ratePerSecond, closeTo(2.857, 0.001));
      expect(bucket.minInterval.inMilliseconds, 350);

      await bucket.acquire();
      await bucket.acquire();
      expect(clock.waits.single.inMicroseconds, closeTo(350000, 1));
    });

    test('零间隔退化为高速率而非除零崩溃', () {
      final bucket = bucketFromInterval(Duration.zero);
      expect(bucket.ratePerSecond, 1000.0);
    });

    test('连续调用后令牌随时间自然补充', () async {
      final clock = VirtualClock();
      final bucket = TokenBucket(
        ratePerSecond: 10,
        burst: 1,
        clock: clock.call,
        delay: clock.delay,
      );

      await bucket.acquire();
      expect(bucket.availableTokens, closeTo(0, 1e-9));

      // 手动推进 500ms → 应补充 5 个令牌，但受 burst=1 限制
      clock.now = clock.now.add(const Duration(milliseconds: 500));
      expect(bucket.availableTokens, closeTo(1.0, 1e-9));
    });

    test('时间倒流（时钟回拨）不产生负令牌或崩溃', () async {
      final clock = VirtualClock();
      final bucket = TokenBucket(
        ratePerSecond: 2,
        burst: 2,
        clock: clock.call,
        delay: clock.delay,
      );

      await bucket.acquire();
      clock.now = clock.now.subtract(const Duration(minutes: 5));
      expect(bucket.availableTokens, greaterThanOrEqualTo(0));
    });
  });

  group('安全护栏', () {
    test('单次取用超过桶容量直接抛错（避免静默失效）', () {
      final bucket = TokenBucket(ratePerSecond: 1, burst: 2);
      expect(() => bucket.acquire(tokens: 3), throwsArgumentError);
    });

    test('ratePerSecond 非正数在构造期就被拒绝', () {
      expect(() => TokenBucket(ratePerSecond: 0), throwsA(isA<AssertionError>()));
      expect(() => TokenBucket(ratePerSecond: -1), throwsA(isA<AssertionError>()));
    });

    test('burst 小于 1 在构造期就被拒绝', () {
      expect(() => TokenBucket(ratePerSecond: 1, burst: 0), throwsA(isA<AssertionError>()));
    });

    test('等待超过 maxWait 时被截断并计入 forcedThrough', () async {
      final clock = VirtualClock();
      final bucket = TokenBucket(
        ratePerSecond: 0.001, // 极慢：需要 1000 秒
        burst: 1,
        maxWait: const Duration(seconds: 5),
        clock: clock.call,
        delay: clock.delay,
      );

      await bucket.acquire(); // 消耗初始令牌
      await bucket.acquire(); // 需要等 1000 秒，被截断到 5 秒

      expect(clock.waits.single, const Duration(seconds: 5));
      expect(bucket.forcedThrough, 1);
    });
  });

  group('run', () {
    test('包住一次调用并返回其结果', () async {
      final clock = VirtualClock();
      final bucket = TokenBucket(
        ratePerSecond: 1,
        burst: 1,
        clock: clock.call,
        delay: clock.delay,
      );

      final result = await bucket.run(() async => 42);
      expect(result, 42);
      expect(bucket.availableTokens, closeTo(0, 1e-9));
    });

    test('任务抛异常时令牌已被消耗（不重复放行）', () async {
      final clock = VirtualClock();
      final bucket = TokenBucket(
        ratePerSecond: 1,
        burst: 1,
        clock: clock.call,
        delay: clock.delay,
      );

      await expectLater(
        bucket.run(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(bucket.availableTokens, closeTo(0, 1e-9));
    });
  });
}
