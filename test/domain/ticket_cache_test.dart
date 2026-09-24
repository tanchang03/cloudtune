import 'package:cloudtune/domain/entities/stream_ticket.dart';
import 'package:cloudtune/domain/services/ticket_cache.dart';
import 'package:flutter_test/flutter_test.dart';

StreamTicket _ticket({
  String url = 'https://drive-pc.quark.cn/1/clouddrive/file/download?sign=abc',
  DateTime? expiresAt,
}) =>
    StreamTicket(
      url: Uri.parse(url),
      headers: const {'Cookie': '__pus=xxx'},
      expiresAt: expiresAt,
    );

void main() {
  final t0 = DateTime(2026, 9, 23, 12);

  TicketCache build({Duration ttl = const Duration(minutes: 20)}) =>
      TicketCache(defaultTtl: ttl, clock: () => t0);

  group('命中与过期', () {
    test('未过期的票据可以命中', () {
      final cache = build();
      final ticket = _ticket(expiresAt: t0.add(const Duration(hours: 1)));

      cache.put('quark:f1', ticket);

      expect(cache.get('quark:f1'), same(ticket));
      expect(cache.containsFresh('quark:f1'), isTrue);
    });

    test('已过期的票据返回 null 并被顺手清掉', () {
      final cache = build();
      cache.put('quark:f1', _ticket(expiresAt: t0.subtract(const Duration(minutes: 1))));

      expect(cache.get('quark:f1'), isNull);
      expect(cache.length, 0, reason: '过期条目应被清理，不堆积死数据');
    });

    test('剩余时间不足安全余量时视为已过期（避免刚取到就断流）', () {
      final cache = build();
      // 还剩 10 秒，小于 StreamTicket 的 30 秒安全余量
      cache.put('quark:f1', _ticket(expiresAt: t0.add(const Duration(seconds: 10))));

      expect(cache.get('quark:f1'), isNull);
    });

    test('恰好卡在安全余量边界上仍可用', () {
      final cache = build();
      cache.put('quark:f1', _ticket(expiresAt: t0.add(const Duration(seconds: 31))));

      expect(cache.get('quark:f1'), isNotNull);
    });

    test('未命中的 id 返回 null', () {
      expect(build().get('quark:nope'), isNull);
    });
  });

  group('无 expiresAt 时套用默认 TTL', () {
    test('默认 TTL 内可命中', () {
      final cache = build(ttl: const Duration(minutes: 20));
      cache.put('quark:f1', _ticket()); // 网盘没给过期时间

      expect(cache.get('quark:f1'), isNotNull);
    });

    test('超过默认 TTL 后失效（不会永久缓存）', () {
      var now = t0;
      final cache = TicketCache(
        defaultTtl: const Duration(minutes: 20),
        clock: () => now,
      );
      cache.put('quark:f1', _ticket());
      expect(cache.get('quark:f1'), isNotNull);

      now = t0.add(const Duration(minutes: 21));

      expect(cache.get('quark:f1'), isNull,
          reason: '没有过期时间的票据必须靠默认 TTL 兜底');
    });

    test('网盘给了过期时间时以它为准，不用默认 TTL', () {
      var now = t0;
      final cache = TicketCache(
        defaultTtl: const Duration(minutes: 20),
        clock: () => now,
      );
      cache.put('quark:f1', _ticket(expiresAt: t0.add(const Duration(hours: 6))));

      now = t0.add(const Duration(hours: 1));

      expect(cache.get('quark:f1'), isNotNull, reason: 'auth_key 有 6 小时 TTL');
    });
  });

  group('作废与清理', () {
    test('invalidate 后不再命中（播放中 403 时用）', () {
      final cache = build();
      cache.put('quark:f1', _ticket(expiresAt: t0.add(const Duration(hours: 1))));

      cache.invalidate('quark:f1');

      expect(cache.get('quark:f1'), isNull);
    });

    test('invalidate 不存在的 id 不报错', () {
      expect(() => build().invalidate('quark:nope'), returnsNormally);
    });

    test('覆盖写入以最后一次为准', () {
      final cache = build();
      final first = _ticket(url: 'https://a.example.com/1', expiresAt: t0.add(const Duration(hours: 1)));
      final second = _ticket(url: 'https://a.example.com/2', expiresAt: t0.add(const Duration(hours: 1)));

      cache.put('quark:f1', first);
      cache.put('quark:f1', second);

      expect(cache.length, 1);
      expect(cache.get('quark:f1')!.url.path, '/2');
    });

    test('evictExpired 只剔除过期条目并返回数量', () {
      final cache = build();
      cache.put('a', _ticket(expiresAt: t0.add(const Duration(hours: 1))));
      cache.put('b', _ticket(expiresAt: t0.subtract(const Duration(hours: 1))));
      cache.put('c', _ticket(expiresAt: t0.subtract(const Duration(minutes: 1))));

      expect(cache.evictExpired(), 2);
      expect(cache.length, 1);
      expect(cache.get('a'), isNotNull);
    });

    test('clear 清空全部', () {
      final cache = build();
      cache.put('a', _ticket(expiresAt: t0.add(const Duration(hours: 1))));
      cache.put('b', _ticket(expiresAt: t0.add(const Duration(hours: 1))));

      cache.clear();

      expect(cache.length, 0);
      expect(cache.get('a'), isNull);
    });
  });

  group('脏数据防御', () {
    test('空 trackId 被忽略', () {
      final cache = build();
      cache.put('', _ticket(expiresAt: t0.add(const Duration(hours: 1))));

      expect(cache.length, 0);
    });

    test('空 URL 被忽略', () {
      final cache = build();
      cache.put('quark:f1', StreamTicket(url: Uri()));

      expect(cache.length, 0);
    });
  });
}
