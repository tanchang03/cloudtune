import 'package:cloudtune/core/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBytes', () {
    test('null 与负数返回「未知」', () {
      expect(formatBytes(null), '未知');
      expect(formatBytes(-1), '未知');
    });

    test('0 返回 0 B', () {
      expect(formatBytes(0), '0 B');
    });

    test('字节级不带小数', () {
      expect(formatBytes(1), '1 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('KB / MB / GB 保留一位小数', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(50 * 1024 * 1024), '50.0 MB');
      expect(formatBytes(37 * 1024 * 1024 * 1024), '37.0 GB');
    });

    test('超过 PB 时停在 PB 不越界', () {
      expect(formatBytes(1024 * 1024 * 1024 * 1024 * 1024 * 8), '8.0 PB');
    });

    test('可自定义小数位', () {
      expect(formatBytes(1536, fractionDigits: 2), '1.50 KB');
    });
  });

  group('formatDuration', () {
    test('null 返回占位符', () {
      expect(formatDuration(null), '--:--');
    });

    test('一小时以内是 mm:ss', () {
      expect(formatDuration(Duration.zero), '00:00');
      expect(formatDuration(const Duration(seconds: 5)), '00:05');
      expect(formatDuration(const Duration(seconds: 65)), '01:05');
      expect(formatDuration(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('超过一小时是 h:mm:ss', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('负数带前置减号', () {
      expect(formatDuration(const Duration(seconds: -5)), '-00:05');
    });
  });

  group('formatCount', () {
    test('千以内原样输出', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
    });

    test('千位缩写', () {
      expect(formatCount(1234), '1.2k');
      expect(formatCount(15000), '15k');
    });

    test('百万位缩写', () {
      expect(formatCount(2500000), '2.5M');
    });
  });

  group('ratio', () {
    test('正常比例', () {
      expect(ratio(5, 10), 0.5);
    });

    test('分母为 0 返回 null（不产生 NaN）', () {
      expect(ratio(0, 0), isNull);
      expect(ratio(5, -1), isNull);
    });

    test('超过分母时被夹到 1.0', () {
      expect(ratio(15, 10), 1.0);
    });
  });

  group('formatRelativeTime', () {
    final now = DateTime(2026, 9, 23, 15, 0, 0);

    test('一分钟内是「刚刚」', () {
      expect(formatRelativeTime(now.subtract(const Duration(seconds: 30)), now: now), '刚刚');
    });

    test('未来时间也归为「刚刚」', () {
      expect(formatRelativeTime(now.add(const Duration(minutes: 5)), now: now), '刚刚');
    });

    test('分钟 / 小时 / 天', () {
      expect(formatRelativeTime(now.subtract(const Duration(minutes: 3)), now: now), '3 分钟前');
      expect(formatRelativeTime(now.subtract(const Duration(hours: 5)), now: now), '5 小时前');
      expect(formatRelativeTime(now.subtract(const Duration(days: 2)), now: now), '2 天前');
    });

    test('超过 30 天回退到日期', () {
      // now 为 2026-09-23，取 53 天前的日期
      expect(formatRelativeTime(DateTime(2026, 8, 1), now: now), '2026-08-01');
    });

    test('29 天仍走相对时间', () {
      expect(
        formatRelativeTime(DateTime(2026, 8, 25), now: now),
        '29 天前',
      );
    });
  });
}
