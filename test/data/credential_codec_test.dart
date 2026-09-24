import 'package:cloudtune/data/auth/credential_codec.dart';
import 'package:cloudtune/data/auth/memory_credential_store.dart';
import 'package:cloudtune/domain/entities/auth_credential.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:flutter_test/flutter_test.dart';

AuthCredential sample() => AuthCredential(
      provider: DriveProvider.quark,
      mode: AuthMode.browserCookie,
      capturedAt: DateTime(2026, 9, 23, 10, 30),
      cookies: {'__pus': 'PUS', '__puus': 'PUUS'},
      tokens: {'access_token': 'AT'},
      extra: {'device': 'mac'},
    );

void main() {
  group('CredentialCodec —— 往返一致性', () {
    test('所有字段原样还原（丢字段的表现就是「一重启就掉线」）', () {
      final original = sample();
      final restored = CredentialCodec.decode(CredentialCodec.encode(original))!;

      expect(restored.provider, original.provider);
      expect(restored.mode, original.mode);
      expect(restored.capturedAt, original.capturedAt);
      expect(restored.cookies, original.cookies);
      expect(restored.tokens, original.tokens);
      expect(restored.extra, original.extra);
      expect(restored.isSameSessionAs(original), isTrue);
    });

    test('cookieHeader 在往返后保持不变', () {
      final original = sample();
      final restored = CredentialCodec.decode(CredentialCodec.encode(original))!;
      expect(restored.cookieHeader, original.cookieHeader);
    });

    test('空 Map 字段也能还原', () {
      final minimal = AuthCredential(
        provider: DriveProvider.aliyun,
        mode: AuthMode.oauth,
        capturedAt: DateTime(2026, 1, 1),
      );
      final restored = CredentialCodec.decode(CredentialCodec.encode(minimal))!;
      expect(restored.cookies, isEmpty);
      expect(restored.tokens, isEmpty);
      expect(restored.extra, isEmpty);
      expect(restored.mode, AuthMode.oauth);
    });

    test('含特殊字符的值不被破坏', () {
      final tricky = AuthCredential(
        provider: DriveProvider.quark,
        mode: AuthMode.manualCookie,
        capturedAt: DateTime(2026, 9, 23),
        cookies: {
          '__pus': 'a+b/c==d',
          '__puus': '带中文的值',
          '__kp': r'quote"and\backslash',
        },
      );
      final restored = CredentialCodec.decode(CredentialCodec.encode(tricky))!;
      expect(restored.cookies, tricky.cookies);
    });
  });

  group('CredentialCodec —— 容错', () {
    test('空串 / 非 JSON / 非对象 → null（视为没有凭证，不崩在启动路径）', () {
      expect(CredentialCodec.decode(''), isNull);
      expect(CredentialCodec.decode('not json'), isNull);
      expect(CredentialCodec.decode('[1,2,3]'), isNull);
      expect(CredentialCodec.decode('null'), isNull);
    });

    test('缺 provider → null', () {
      expect(CredentialCodec.decode('{"v":1,"mode":"oauth"}'), isNull);
    });

    test('未知 provider → null', () {
      expect(
        CredentialCodec.decode('{"v":1,"provider":"dropbox","mode":"oauth"}'),
        isNull,
      );
    });

    test('版本号高于当前支持 → null（拒绝读取未来格式）', () {
      expect(
        CredentialCodec.decode(
          '{"v":99,"provider":"quark","mode":"oauth"}',
        ),
        isNull,
      );
    });

    test('缺 mode 时回落到 manualCookie', () {
      final c = CredentialCodec.decode(
        '{"v":1,"provider":"quark","cookies":{"__pus":"p"}}',
      )!;
      expect(c.mode, AuthMode.manualCookie);
    });

    test('未知 mode 也回落到 manualCookie', () {
      final c = CredentialCodec.decode(
        '{"v":1,"provider":"quark","mode":"telepathy"}',
      )!;
      expect(c.mode, AuthMode.manualCookie);
    });

    test('非法 capturedAt 回落到 epoch，不抛异常', () {
      final c = CredentialCodec.decode(
        '{"v":1,"provider":"quark","mode":"oauth","capturedAt":"garbage"}',
      )!;
      expect(c.capturedAt.millisecondsSinceEpoch, 0);
    });

    test('非字符串的 Map 值被过滤（防止脏数据污染 Cookie 头）', () {
      final c = CredentialCodec.decode(
        '{"v":1,"provider":"quark","mode":"oauth",'
        '"cookies":{"ok":"1","bad":123,"alsoBad":null,"arr":[1]}}',
      )!;
      expect(c.cookies, {'ok': '1'});
    });

    test('cookies 不是 Map 时按空处理', () {
      final c = CredentialCodec.decode(
        '{"v":1,"provider":"quark","mode":"oauth","cookies":"oops"}',
      )!;
      expect(c.cookies, isEmpty);
    });
  });

  group('InMemoryCredentialStore', () {
    test('保存 / 读取 / 清除', () async {
      final store = InMemoryCredentialStore();
      expect(await store.load(DriveProvider.quark), isNull);

      await store.save(sample());
      expect((await store.load(DriveProvider.quark))!.cookies['__pus'], 'PUS');

      await store.clear(DriveProvider.quark);
      expect(await store.load(DriveProvider.quark), isNull);
    });

    test('按网盘隔离', () async {
      final store = InMemoryCredentialStore();
      await store.save(sample());
      expect(await store.load(DriveProvider.aliyun), isNull);
      expect(await store.authorizedProviders(), [DriveProvider.quark]);
    });

    test('不支持持久化（Web 与「不记住登录」模式的行为）', () {
      expect(InMemoryCredentialStore().supportsPersistence, isFalse);
    });

    test('重复保存同一网盘会覆盖', () async {
      final store = InMemoryCredentialStore();
      await store.save(sample());
      await store.save(sample().copyWith(cookies: {'__pus': 'NEW'}));
      expect((await store.load(DriveProvider.quark))!.cookies['__pus'], 'NEW');
      expect((await store.authorizedProviders()).length, 1);
    });
  });
}
