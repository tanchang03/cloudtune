import 'package:cloudtune/domain/entities/auth_credential.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/stream_ticket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthCredential.fromCookieString', () {
    test('解析标准 Cookie 头', () {
      final c = AuthCredential.fromCookieString(
        provider: DriveProvider.quark,
        mode: AuthMode.browserCookie,
        cookieString: '__pus=aaa; __puus=bbb',
      );
      expect(c.cookies, {'__pus': 'aaa', '__puus': 'bbb'});
      expect(c.provider, DriveProvider.quark);
      expect(c.mode, AuthMode.browserCookie);
      expect(c.isEmpty, isFalse);
      expect(c.isNotEmpty, isTrue);
    });

    test('解析用户实际粘贴的 `k  :v` 形式', () {
      final c = AuthCredential.fromCookieString(
        provider: DriveProvider.quark,
        mode: AuthMode.manualCookie,
        cookieString: '__pus  :7aa52fb080f2d75a\n__puus: dfbc5322bdd17481',
      );
      expect(c.hasCookie('__pus'), isTrue);
      expect(c.hasCookie('__puus'), isTrue);
      expect(c.cookies['__pus'], '7aa52fb080f2d75a');
    });

    test('空字符串得到空凭证', () {
      final c = AuthCredential.fromCookieString(
        provider: DriveProvider.quark,
        mode: AuthMode.manualCookie,
        cookieString: '',
      );
      expect(c.isEmpty, isTrue);
      expect(c.isNotEmpty, isFalse);
    });

    test('capturedAt 默认取当前时间', () {
      final before = DateTime.now();
      final c = AuthCredential.fromCookieString(
        provider: DriveProvider.quark,
        mode: AuthMode.browserCookie,
        cookieString: 'a=1',
      );
      expect(c.capturedAt.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
    });
  });

  group('cookieHeader', () {
    test('关键会话键排在最前，便于排查', () {
      final c = AuthCredential(
        provider: DriveProvider.quark,
        mode: AuthMode.browserCookie,
        capturedAt: DateTime(2026, 9, 23),
        cookies: {'__kp': '3', '__pus': '1', '__uid': '4', '__puus': '2'},
      );
      expect(c.cookieHeader, '__pus=1; __puus=2; __kp=3; __uid=4');
    });

    test('无 cookie 时为空串', () {
      final c = AuthCredential(
        provider: DriveProvider.quark,
        mode: AuthMode.oauth,
        capturedAt: DateTime(2026, 9, 23),
        tokens: {'access_token': 'x'},
      );
      expect(c.cookieHeader, '');
    });
  });

  group('hasCookie / hasToken', () {
    test('值非空才算命中', () {
      final c = AuthCredential(
        provider: DriveProvider.quark,
        mode: AuthMode.manualCookie,
        capturedAt: DateTime(2026, 9, 23),
        cookies: {'__pus': 'a', '__kp': ''},
        tokens: {'refresh_token': 'r'},
      );
      expect(c.hasCookie('__pus'), isTrue);
      expect(c.hasCookie('__kp'), isFalse);
      expect(c.hasCookie('不存在'), isFalse);
      expect(c.hasToken('refresh_token'), isTrue);
      expect(c.hasToken('不存在'), isFalse);
    });
  });

  group('redacted — 日志安全', () {
    test('不泄漏任何明文凭证', () {
      const pus = '7aa52fb080f2d75a103553d437b23fbb';
      const puus = 'dfbc5322bdd17481bcfc4a17781d97d5';
      final c = AuthCredential(
        provider: DriveProvider.quark,
        mode: AuthMode.manualCookie,
        capturedAt: DateTime(2026, 9, 23),
        cookies: {'__pus': pus, '__puus': puus},
        tokens: {'access_token': 'AT-secret-value-here'},
      );
      final snapshot = c.redacted;
      final text = snapshot.toString();

      expect(text.contains(pus), isFalse);
      expect(text.contains(puus), isFalse);
      expect(text.contains('AT-secret-value-here'), isFalse);
      expect(text, contains('__pus'));
      expect(snapshot['provider'], 'quark');
      expect(snapshot['mode'], 'manual_cookie');
    });

    test('toString 同样不泄漏', () {
      const pus = '7aa52fb080f2d75a103553d437b23fbb';
      final c = AuthCredential(
        provider: DriveProvider.quark,
        mode: AuthMode.manualCookie,
        capturedAt: DateTime(2026, 9, 23),
        cookies: {'__pus': pus},
      );
      expect(c.toString().contains(pus), isFalse);
      expect(c.toString(), contains('quark'));
    });
  });

  group('isSameSessionAs', () {
    AuthCredential make(Map<String, String> cookies) => AuthCredential(
          provider: DriveProvider.quark,
          mode: AuthMode.browserCookie,
          capturedAt: DateTime(2026, 9, 23),
          cookies: cookies,
        );

    test('内容一致视为同一会话（忽略抓取时间差异）', () {
      expect(make({'a': '1'}).isSameSessionAs(make({'a': '1'})), isTrue);
    });

    test('值不同则不同会话', () {
      expect(make({'a': '1'}).isSameSessionAs(make({'a': '2'})), isFalse);
    });

    test('键数量不同则不同会话', () {
      expect(make({'a': '1'}).isSameSessionAs(make({'a': '1', 'b': '2'})), isFalse);
    });

    test('网盘不同则不同会话', () {
      final a = make({'a': '1'});
      final b = AuthCredential(
        provider: DriveProvider.aliyun,
        mode: AuthMode.browserCookie,
        capturedAt: DateTime(2026, 9, 23),
        cookies: {'a': '1'},
      );
      expect(a.isSameSessionAs(b), isFalse);
    });
  });

  group('isOlderThan', () {
    test('超过指定年龄返回 true', () {
      final c = AuthCredential(
        provider: DriveProvider.quark,
        mode: AuthMode.browserCookie,
        capturedAt: DateTime(2026, 9, 1),
        cookies: {'a': '1'},
      );
      expect(c.isOlderThan(const Duration(days: 7), now: DateTime(2026, 9, 23)), isTrue);
      expect(c.isOlderThan(const Duration(days: 30), now: DateTime(2026, 9, 23)), isFalse);
    });
  });

  group('StreamTicket', () {
    test('提前 30 秒判定过期，避免播放中途失效', () {
      final t = StreamTicket(
        url: Uri.parse('https://x.com/a'),
        expiresAt: DateTime.now().add(const Duration(seconds: 20)),
      );
      expect(t.isExpired, isTrue);
    });

    test('过期时间充裕时不判过期', () {
      final t = StreamTicket(
        url: Uri.parse('https://x.com/a'),
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );
      expect(t.isExpired, isFalse);
      expect(t.remaining!.inMinutes, greaterThanOrEqualTo(9));
    });

    test('无过期时间视为永不过期', () {
      final t = StreamTicket(url: Uri.parse('https://x.com/a'));
      expect(t.isExpired, isFalse);
      expect(t.remaining, isNull);
    });

    test('remaining 已过期时为 Duration.zero 而非负数', () {
      final t = StreamTicket(
        url: Uri.parse('https://x.com/a'),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(t.remaining, Duration.zero);
    });

    test('redactedUrl 丢掉签名查询串', () {
      final t = StreamTicket(
        url: Uri.parse('https://drive-pc.quark.cn/f/down?sign=SECRET&t=123'),
      );
      expect(t.redactedUrl, 'https://drive-pc.quark.cn/f/down');
      expect(t.redactedUrl.contains('SECRET'), isFalse);
    });

    test('toString 不泄漏签名', () {
      final t = StreamTicket(
        url: Uri.parse('https://drive-pc.quark.cn/f/down?sign=SECRET'),
        headers: const {'Cookie': 'x'},
      );
      expect(t.toString().contains('SECRET'), isFalse);
      expect(t.toString(), contains('Cookie'));
    });

    test('needsHeaders 反映是否需带自定义头（夸克必须带 Cookie）', () {
      expect(
        StreamTicket(url: Uri.parse('https://x.com/a'), headers: const {'Cookie': 'c'}).needsHeaders,
        isTrue,
      );
      expect(StreamTicket(url: Uri.parse('https://x.com/a')).needsHeaders, isFalse);
    });
  });
}
