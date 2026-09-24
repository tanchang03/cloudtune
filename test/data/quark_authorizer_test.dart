import 'package:cloudtune/data/auth/quark_authorizer.dart';
import 'package:cloudtune/data/remote/quark/quark_endpoints.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuarkBrowserAuthorizer —— 基础属性', () {
    test('登录地址指向 pan.quark.cn', () {
      final a = QuarkBrowserAuthorizer(readCookies: (_) async => {});
      expect(a.loginUrl(DriveProvider.quark).host, 'pan.quark.cn');
    });

    test('只支持夸克', () {
      final a = QuarkBrowserAuthorizer(readCookies: (_) async => {});
      expect(a.supports(DriveProvider.quark), isTrue);
      expect(a.supports(DriveProvider.aliyun), isFalse);
      expect(a.supports(DriveProvider.baidu), isFalse);
    });

    test('声明支持内嵌浏览器与手动粘贴两种方式', () {
      final a = QuarkBrowserAuthorizer(readCookies: (_) async => {});
      expect(a.supportedModes, contains(AuthMode.browserCookie));
      expect(a.supportedModes, contains(AuthMode.manualCookie));
    });

    test('平台不支持内嵌浏览器时如实上报', () {
      final a = QuarkBrowserAuthorizer(
        readCookies: (_) async => {},
        supportsEmbedded: false,
      );
      expect(a.supportsEmbeddedBrowser, isFalse);
    });
  });

  group('isLoggedIn', () {
    final a = QuarkBrowserAuthorizer(readCookies: (_) async => {});

    Future<bool> check(String? url) =>
        a.isLoggedIn(provider: DriveProvider.quark, currentUrl: url);

    test('空 / 相对地址 / 非夸克域名 → 未登录', () async {
      expect(await check(null), isFalse);
      expect(await check(''), isFalse);
      expect(await check('/'), isFalse);
      expect(await check('https://www.google.com/'), isFalse);
      expect(await check('https://fakequark.cn.evil.com/'), isFalse);
    });

    test('仿冒域名被严格拒绝（不能用后缀匹配）', () async {
      expect(await check('https://evilquark.cn/'), isFalse);
      expect(await check('https://notquark.cn/'), isFalse);
      expect(await check('https://pan.quark.cn.evil.com/'), isFalse);
      // 真正的子域才放行
      expect(await check('https://pan.quark.cn/'), isTrue);
      expect(await check('https://quark.cn/'), isTrue);
    });

    test('登录相关路径 → 未登录', () async {
      expect(await check('https://pan.quark.cn/login'), isFalse);
      expect(await check('https://pan.quark.cn/passport/login'), isFalse);
      expect(await check('https://pan.quark.cn/signin'), isFalse);
      expect(await check('https://pan.quark.cn/auth/callback'), isFalse);
    });

    test('夸克首页 / 文件页 → 已登录', () async {
      expect(await check('https://pan.quark.cn/'), isTrue);
      expect(await check('https://pan.quark.cn/list#/list/all'), isTrue);
      expect(await check('https://drive-pc.quark.cn/1/clouddrive/config'), isTrue);
    });

    test('非夸克网盘直接返回 false，不解析地址', () async {
      expect(
        await a.isLoggedIn(
          provider: DriveProvider.aliyun,
          currentUrl: 'https://pan.quark.cn/',
        ),
        isFalse,
      );
    });
  });

  group('capture', () {
    test('读取的是两个夸克域名', () async {
      List<String>? seen;
      final a = QuarkBrowserAuthorizer(readCookies: (domains) async {
        seen = domains;
        return {'__pus': 'p'};
      });

      await a.capture(DriveProvider.quark);
      expect(seen, QuarkEndpoints.cookieDomains);
      expect(seen, contains('https://pan.quark.cn'));
      expect(seen, contains('https://drive-pc.quark.cn'));
    });

    test('没有必需 Cookie 时返回 null（还没登录成功）', () async {
      final a = QuarkBrowserAuthorizer(
        readCookies: (_) async => {'__kp': 'x', 'other': 'y'},
      );
      expect(await a.capture(DriveProvider.quark), isNull);
    });

    test('有 __pus 即可认为登录成功', () async {
      final a = QuarkBrowserAuthorizer(
        readCookies: (_) async => {'__pus': 'PUS', '__puus': 'PUUS'},
      );
      final cred = (await a.capture(DriveProvider.quark))!;
      expect(cred.mode, AuthMode.browserCookie);
      expect(cred.cookies['__pus'], 'PUS');
      expect(cred.cookies['__puus'], 'PUUS');
      expect(cred.cookieHeader, '__pus=PUS; __puus=PUUS');
    });

    test('只保留已知 Cookie，避免把无关凭据带进钥匙串', () async {
      final a = QuarkBrowserAuthorizer(readCookies: (_) async => {
            '__pus': 'PUS',
            '__kuus': 'KUUS',
            'unrelated_analytics': 'track-me',
            'third_party_session': 'nope',
          });
      final cred = (await a.capture(DriveProvider.quark))!;
      expect(cred.cookies.keys, containsAll(['__pus', '__kuus']));
      expect(cred.cookies.containsKey('unrelated_analytics'), isFalse);
      expect(cred.cookies.containsKey('third_party_session'), isFalse);
    });

    test('空值 Cookie 被丢弃', () async {
      final a = QuarkBrowserAuthorizer(
        readCookies: (_) async => {'__pus': 'PUS', '__kp': ''},
      );
      final cred = (await a.capture(DriveProvider.quark))!;
      expect(cred.cookies.containsKey('__kp'), isFalse);
    });

    test('不支持的网盘返回 null', () async {
      final a = QuarkBrowserAuthorizer(readCookies: (_) async => {'__pus': 'p'});
      expect(await a.capture(DriveProvider.baidu), isNull);
    });
  });

  group('QuarkManualCookieAuthorizer', () {
    final a = QuarkManualCookieAuthorizer();

    test('解析标准 Cookie 头', () {
      final cred = a.parse(DriveProvider.quark, '__pus=aaa; __puus=bbb');
      expect(cred.mode, AuthMode.manualCookie);
      expect(cred.cookies, {'__pus': 'aaa', '__puus': 'bbb'});
    });

    test('解析用户实际粘贴的 `k  :v` 多行形式', () {
      final cred = a.parse(
        DriveProvider.quark,
        '__pus  :7aa52fb080f2d75a103553d437b23fbb\n'
        '__puus: dfbc5322bdd17481bcfc4a17781d97d5',
      );
      expect(cred.cookies['__pus'], '7aa52fb080f2d75a103553d437b23fbb');
      expect(cred.cookies['__puus'], 'dfbc5322bdd17481bcfc4a17781d97d5');
    });

    test('只有一个必需 Cookie 也接受（__pus 单独存在即可能有效）', () {
      final cred = a.parse(DriveProvider.quark, '__pus=only-pus');
      expect(cred.cookies['__pus'], 'only-pus');
    });

    test('完全没有必需 Cookie 时抛 FormatException，便于 UI 提示', () {
      expect(
        () => a.parse(DriveProvider.quark, '__kp=1; __uid=2'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => a.parse(DriveProvider.quark, ''),
        throwsA(isA<FormatException>()),
      );
    });

    test('异常消息面向用户、可直接展示', () {
      try {
        a.parse(DriveProvider.quark, 'garbage');
        fail('应当抛异常');
      } on FormatException catch (e) {
        expect(e.message, contains('__pus'));
        expect(e.message, contains('__puus'));
      }
    });

    test('不支持内嵌浏览器，也不接受浏览器轮询', () async {
      expect(a.supportsEmbeddedBrowser, isFalse);
      expect(a.supportedModes, {AuthMode.manualCookie});
      expect(await a.capture(DriveProvider.quark), isNull);
      expect(
        await a.isLoggedIn(provider: DriveProvider.quark, currentUrl: 'https://pan.quark.cn/'),
        isFalse,
      );
    });
  });
}
