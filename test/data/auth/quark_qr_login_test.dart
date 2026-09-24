import 'package:cloudtune/data/auth/quark_qr_login.dart';
import 'package:cloudtune/data/http/http_client.dart';
import 'package:cloudtune/data/remote/quark/quark_endpoints.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http_client.dart';

/// 造一个「取票成功」的响应，形状与实测一致：
/// `{"status":2000000,"message":"ok","data":{"members":{"token":"sta…"}}}`
HttpResult tokenResponse([String token = 'sta_abc123']) => HttpResult(
      statusCode: 200,
      json: {
        'status': QuarkQrLoginClient.statusOk,
        'message': 'ok',
        'data': {
          'members': {'token': token},
        },
      },
    );

/// 造一个「未扫码」的响应：`{"status":50004001,"message":"Query result is empty"}`
HttpResult notScannedResponse() => const HttpResult(
      statusCode: 200,
      json: {
        'status': QuarkQrLoginClient.statusNotScanned,
        'message': 'Query result is empty',
      },
    );

void main() {
  group('QuarkQrLoginClient.start', () {
    test('取到 token 并拼出二维码 URL', () async {
      final http = FakeHttpClient.always(tokenResponse('sta_xyz'));
      final client = QuarkQrLoginClient(http: http);

      final session = await client.start();

      expect(session.token, 'sta_xyz');
      expect(session.qrUrl.host, 'su.quark.cn');
      expect(session.qrUrl.queryParameters['token'], 'sta_xyz');
      expect(
        session.qrUrl.queryParameters['client_id'],
        QuarkEndpoints.webClientId,
      );
      // 二维码内容里绝不能出现未转义的原始 token
      expect(session.qrUrl.toString(), contains('token=sta_xyz'));
    });

    test('取票请求带 client_id —— 与轮询配对的前提', () async {
      final http = FakeHttpClient.always(tokenResponse());
      final client = QuarkQrLoginClient(http: http);

      await client.start();

      expect(http.lastRequest.param('client_id'), QuarkEndpoints.webClientId);
      expect(http.lastRequest.url, endsWith(QuarkEndpoints.casQrToken));
    });

    test('请求打到 uop.quark.cn，不是 user-auth-server', () async {
      final http = FakeHttpClient.always(tokenResponse());
      final client = QuarkQrLoginClient(http: http);

      await client.start();

      expect(http.lastRequest.url, startsWith(QuarkEndpoints.casGateway));
      expect(http.lastRequest.url, isNot(contains('user-auth-server')));
    });

    test('data.members.token 缺失时抛 QrLoginException', () async {
      final http = FakeHttpClient.always(
        const HttpResult(statusCode: 200, json: {'status': 2000000}),
      );
      final client = QuarkQrLoginClient(http: http);

      expect(client.start(), throwsA(isA<QrLoginException>()));
    });

    test('members 不是 Map 时不崩，同样抛异常', () async {
      final http = FakeHttpClient.always(
        const HttpResult(
          statusCode: 200,
          json: {
            'status': 2000000,
            'data': {'members': 'oops'},
          },
        ),
      );
      final client = QuarkQrLoginClient(http: http);

      expect(client.start(), throwsA(isA<QrLoginException>()));
    });

    test('网络层失败时抛 QrLoginException', () async {
      final http = FakeHttpClient.always(
        const HttpResult.networkFailure('DNS 解析失败'),
      );
      final client = QuarkQrLoginClient(http: http);

      expect(client.start(), throwsA(isA<QrLoginException>()));
    });

    test('HTTP 500 时抛 QrLoginException', () async {
      final http = FakeHttpClient.always(
        const HttpResult(statusCode: 500, rawBody: 'boom'),
      );
      final client = QuarkQrLoginClient(http: http);

      expect(client.start(), throwsA(isA<QrLoginException>()));
    });
  });

  group('QuarkQrLoginClient.poll', () {
    late QrLoginSession session;

    setUp(() async {
      final http = FakeHttpClient.always(tokenResponse('sta_poll'));
      session = await QuarkQrLoginClient(http: http).start();
    });

    test('未扫码 → QrPollWaiting（这是正常态，不是错误）', () async {
      final http = FakeHttpClient.always(notScannedResponse());
      final client = QuarkQrLoginClient(http: http);

      final outcome = await client.poll(session);

      expect(outcome, isA<QrPollWaiting>());
    });

    test('轮询带上 token 与 client_id —— 与取票配对', () async {
      final http = FakeHttpClient.always(notScannedResponse());
      final client = QuarkQrLoginClient(http: http);

      await client.poll(session);

      expect(http.lastRequest.param('token'), 'sta_poll');
      expect(http.lastRequest.param('client_id'), QuarkEndpoints.webClientId);
      expect(http.lastRequest.url, endsWith(QuarkEndpoints.casQrServiceTicket));
    });

    test('50004002 → QrPollExpired', () async {
      final http = FakeHttpClient.always(
        const HttpResult(
          statusCode: 200,
          json: {
            'status': QuarkQrLoginClient.statusTokenNotFound,
            'message': 'Token Not Found',
          },
        ),
      );
      final client = QuarkQrLoginClient(http: http);

      final outcome = await client.poll(session);

      expect(outcome, isA<QrPollExpired>());
      expect((outcome as QrPollExpired).message, 'Token Not Found');
    });

    test('2000000 → QrPollConfirmed，payload 原样保留', () async {
      final http = FakeHttpClient.always(
        const HttpResult(
          statusCode: 200,
          json: {
            'status': QuarkQrLoginClient.statusOk,
            'message': 'ok',
            'data': {
              'members': {'service_ticket': 'ST-123', 'uid': '42'},
            },
          },
        ),
      );
      final client = QuarkQrLoginClient(http: http);

      final outcome = await client.poll(session);

      expect(outcome, isA<QrPollConfirmed>());
      final confirmed = outcome as QrPollConfirmed;
      expect(confirmed.payload['members'], isA<Map>());
      // payloadKeys 只展开顶层键，够排查用又不暴露值
      expect(confirmed.payloadKeys, ['members']);
    });

    test('没见过的业务码 → QrPollError', () async {
      final http = FakeHttpClient.always(
        const HttpResult(
          statusCode: 200,
          json: {'status': 9999999, 'message': '什么鬼'},
        ),
      );
      final client = QuarkQrLoginClient(http: http);

      final outcome = await client.poll(session);

      expect(outcome, isA<QrPollError>());
      expect((outcome as QrPollError).status, 9999999);
    });

    test('网络失败 / 非 2xx → QrPollError，不抛异常', () async {
      final http = FakeHttpClient.sequence([
        const HttpResult.networkFailure('timeout'),
        const HttpResult(statusCode: 502, rawBody: 'bad gateway'),
      ]);
      final client = QuarkQrLoginClient(http: http);

      expect(await client.poll(session), isA<QrPollError>());
      expect(await client.poll(session), isA<QrPollError>());
    });
  });

  group('client_id 配对铁律', () {
    // 这条是 2026-09-24 实测踩出来的：取票带了 client_id，轮询就必须带；
    // 混着用服务端返回 50004002 Token Not Found。
    test('取票与轮询用的是同一个 client_id', () async {
      final http = FakeHttpClient.sequence([
        tokenResponse('sta_pair'),
        notScannedResponse(),
      ]);
      final client = QuarkQrLoginClient(http: http, clientId: '532');

      final session = await client.start();
      await client.poll(session);

      final tokenReq = http.requestsTo(QuarkEndpoints.casQrToken).single;
      final ticketReq = http.requestsTo(QuarkEndpoints.casQrServiceTicket).single;
      expect(tokenReq.param('client_id'), ticketReq.param('client_id'));
    });

    test('显式传 clientId 时，二维码 URL 里也带它', () async {
      final http = FakeHttpClient.always(tokenResponse());
      final client = QuarkQrLoginClient(http: http, clientId: '533');

      final session = await client.start();

      expect(session.qrUrl.queryParameters['client_id'], '533');
    });
  });

  test('QrLoginException 的 toString 就是 message', () {
    expect(const QrLoginException('炸了').toString(), '炸了');
  });

  group('QuarkQrLoginClient.exchangeServiceTicket（最后一跳）', () {
    /// `/account/info?st=` 的成功响应：success=true + Set-Cookie 下发账号 Cookie。
    HttpResult accountInfoOk(List<String> setCookie) => HttpResult(
          statusCode: 200,
          json: <String, Object?>{
            'success': true,
            'data': <String, Object?>{'nickname': 'tester'},
          },
          headers: <String, List<String>>{'set-cookie': setCookie},
        );

    /// `success=false`：票据无效/过期。
    HttpResult accountInfoRejected({int status = 200}) => HttpResult(
          statusCode: status,
          json: <String, Object?>{
            'success': false,
            'code': 4,
            'message': 'ticket invalid',
          },
        );

    test('200 + success + __pus/__puus → 返回账号 Cookie', () async {
      final http = FakeHttpClient.always(
        accountInfoOk(<String>[
          '__pus=abc123; Path=/; Domain=.quark.cn; HttpOnly',
          '__puus=def456; Path=/; Domain=.quark.cn; HttpOnly',
          '_UP_xx=zzz; Path=/',
        ]),
      );
      final client = QuarkQrLoginClient(http: http);

      final cookies = await client.exchangeServiceTicket('ST-1');

      expect(cookies.cookies['__pus'], 'abc123');
      expect(cookies.cookies['__puus'], 'def456');
      expect(cookies.hasEssential, isTrue);
      // 端点与参数：GET /account/info?st=<ticket>
      expect(http.lastRequest.url, QuarkEndpoints.accountInfo);
      expect(http.lastRequest.param('st'), 'ST-1');
      // __puus 已有 → 不需要补跳
      expect(http.requests.length, 1);
    });

    test('有 __pus 缺 __puus → 补跳首页拿 __puus 并合并', () async {
      final http = FakeHttpClient.sequence([
        // /account/info：给 __pus 但不给 __puus
        accountInfoOk(<String>[
          '__pus=abc123; Path=/; Domain=.quark.cn',
          '__kp=k1; Path=/',
        ]),
        // 补跳 /list/all：下发 __puus
        HttpResult(
          statusCode: 200,
          rawBody: '<html>home</html>',
          headers: <String, List<String>>{
            'set-cookie': <String>['__puus=def456; Path=/; Domain=.quark.cn'],
          },
        ),
      ]);
      final client = QuarkQrLoginClient(http: http);

      final cookies = await client.exchangeServiceTicket('ST-1');

      expect(cookies.cookies['__pus'], 'abc123');
      expect(cookies.cookies['__puus'], 'def456');
      expect(cookies.hasEssential, isTrue);
      // 补跳请求带上了第一阶段的 Cookie
      expect(http.requests[1].headers?['Cookie'], contains('__pus=abc123'));
      // 补跳请求用页面导航语义，且首跳是 /list/all
      expect(http.requests[1].url, QuarkEndpoints.postLoginHomeUrls.first);
      expect(
        http.requests[1].headers?['Accept'],
        startsWith('text/html'),
      );
    });

    test('补跳后仍无 __puus → 不抛异常，交给 authorize 校验裁决', () async {
      final http = FakeHttpClient.sequence([
        // 兑换：给 __pus，不给 __puus
        accountInfoOk(<String>['__pus=abc123; Path=/; Domain=.quark.cn']),
        // 补跳候选首页全部不返回 cookie
      ]);
      final client = QuarkQrLoginClient(http: http);

      final cookies = await client.exchangeServiceTicket('ST-1');

      expect(cookies.cookies['__pus'], 'abc123');
      expect(cookies.cookies['__puus'], isNull);
      // 兑换 1 次 + 补跳两个候选首页（/list/all 和 /）都没拿到 __puus
      expect(http.requests.length, 1 + QuarkEndpoints.postLoginHomeUrls.length);
    });

    test('没拿到 __pus → 抛 QrLoginException', () async {
      final http = FakeHttpClient.always(
        accountInfoOk(<String>['_UP_xx=zzz; Path=/']),
      );
      final client = QuarkQrLoginClient(http: http);

      expect(
        client.exchangeServiceTicket('ST-1'),
        throwsA(isA<QrLoginException>()),
      );
    });

    test('success=false → 抛 QrLoginException（票据被拒绝）', () async {
      final http = FakeHttpClient.always(accountInfoRejected());
      final client = QuarkQrLoginClient(http: http);

      expect(
        client.exchangeServiceTicket('ST-1'),
        throwsA(isA<QrLoginException>()),
      );
      expect(http.requests.length, 1);
    });

    test('网络失败 → 抛 QrLoginException', () async {
      final http = FakeHttpClient.always(const HttpResult.networkFailure('断网'));
      final client = QuarkQrLoginClient(http: http);

      expect(
        client.exchangeServiceTicket('ST-1'),
        throwsA(isA<QrLoginException>()),
      );
    });

    test('非 2xx（如 500）→ 抛 QrLoginException', () async {
      final http = FakeHttpClient.always(
        const HttpResult(statusCode: 500, rawBody: 'boom'),
      );
      final client = QuarkQrLoginClient(http: http);

      expect(
        client.exchangeServiceTicket('ST-1'),
        throwsA(isA<QrLoginException>()),
      );
    });
  });

  group('parseSetCookieLines / filterQrCookiesForCredential', () {
    test('只取 name=value，丢掉 path/domain/expires 等属性', () {
      final lines = <String>[
        '__pus=a b; Path=/; Domain=.quark.cn; HttpOnly',
        '__puus=cd; Expires=Thu, 24 Sep 2026 00:00:00 GMT',
      ];
      final m = parseSetCookieLines(lines);
      expect(m['__pus'], 'a b');
      expect(m['__puus'], 'cd');
      expect(m.length, 2);
    });

    test('过滤只留 known + essential，无关 Cookie 不进凭证', () {
      final all = <String, String>{
        '__pus': 'a',
        '__puus': 'b',
        '_UP_xx': 'z',
        'ctoken': 'c',
        'junk': 'j',
      };
      final kept = filterQrCookiesForCredential(all);
      expect(kept.containsKey('__pus'), isTrue);
      expect(kept.containsKey('__puus'), isTrue);
      expect(kept.containsKey('junk'), isFalse);
      expect(kept.containsKey('_UP_xx'), isFalse); // 不在 known 名单
      expect(kept.containsKey('ctoken'), isFalse);
    });
  });
}
