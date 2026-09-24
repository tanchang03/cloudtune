import 'dart:async';
import 'dart:io';

import 'package:cloudtune/core/diagnostics/diag_log.dart';
import 'package:cloudtune/data/audio/stream_probe.dart';
import 'package:cloudtune/domain/entities/stream_ticket.dart';
import 'package:flutter_test/flutter_test.dart';

/// 直链回探的测试。
///
/// 这个探测器的价值全在「结论准不准」上 —— 它探错了会把排查带偏，
/// 比没有更糟。所以这里起一个真的本地 HTTP 服务，断言：
///   - 状态码与响应体真的被记进日志；
///   - 票据里的请求头**原样带上**（不带 Cookie 的话夸克直链会回 412，
///     那样探出来的结论就是「直链废了」，而真相是「我们没带 Cookie」）；
///   - 只请求 1 个字节；
///   - 连不上时只记一条 warn，不抛异常、不变成第二个错误。
void main() {
  setUp(diag.clearBuffer);

  /// 起一个只服务一次请求的本地服务，返回它的票据。
  Future<StreamTicket> ticketFrom(
    FutureOr<void> Function(HttpRequest req) handler, {
    Map<String, String>? headers,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async => handler(req));
    return StreamTicket(
      url: Uri.parse('http://127.0.0.1:${server.port}/a.flac'),
      headers: headers ?? const {},
    );
  }

  test('把状态码与响应体记进日志 —— 失败原因通常就写在体里', () async {
    final ticket = await ticketFrom((req) async {
      req.response
        ..statusCode = 412
        ..write('{"code":23018,"message":"file too large"}');
      await req.response.close();
    });

    await probeStreamAfterFailure(ticket);

    final text = diag.dump();
    expect(text, contains('HTTP 412'));
    expect(text, contains('23018'), reason: '网盘把业务码写在响应体里，必须带出来');
  });

  test('票据里的请求头原样带上（缺 Cookie 会得到假的 412）', () async {
    final seen = Completer<String?>();
    final ticket = await ticketFrom(
      (req) async {
        if (!seen.isCompleted) seen.complete(req.headers.value('cookie'));
        req.response.statusCode = 206;
        await req.response.close();
      },
      headers: {'Cookie': '__puus=abcdefgh'},
    );

    await probeStreamAfterFailure(ticket);

    expect(await seen.future, '__puus=abcdefgh');
  });

  test('只请求 1 个字节（够拿状态码，又不耗流量）', () async {
    final seen = Completer<String?>();
    final ticket = await ticketFrom((req) async {
      if (!seen.isCompleted) seen.complete(req.headers.value('range'));
      req.response.statusCode = 206;
      await req.response.close();
    });

    await probeStreamAfterFailure(ticket);

    expect(await seen.future, 'bytes=0-0');
  });

  test('206 与 content-range 也记下来（能确认服务端真的支持 Range）', () async {
    final ticket = await ticketFrom((req) async {
      req.response
        ..statusCode = 206
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-0/765145628');
      await req.response.close();
    });

    await probeStreamAfterFailure(ticket);

    expect(diag.dump(), contains('bytes 0-0/765145628'));
  });

  test('连不上时只记一条 warn，不抛异常', () async {
    // 先绑一个端口再关掉，拿到一个必定拒绝连接的端口号
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close(force: true);

    await expectLater(
      probeStreamAfterFailure(
        StreamTicket(url: Uri.parse('http://127.0.0.1:$port/a.flac')),
      ),
      completes,
      reason: '探测失败绝不能变成第二个错误冒到上层',
    );

    expect(diag.dump(), contains('回探直链本身也失败了'));
  });

  test('日志里不出现直链的签名参数', () async {
    final ticket = await ticketFrom(
      (req) async {
        req.response.statusCode = 200;
        await req.response.close();
      },
    );
    final signed = StreamTicket(
      url: ticket.url.replace(query: 'token=SUPERSECRET&sign=ALSO'),
    );

    await probeStreamAfterFailure(signed);

    final text = diag.dump();
    expect(text, isNot(contains('SUPERSECRET')));
    expect(text, contains('http://127.0.0.1'), reason: '主机路径要留着，便于定位路由');
  });
}
