import 'package:cloudtune/core/error/drive_error.dart';
import 'package:cloudtune/data/http/http_client.dart';
import 'package:cloudtune/data/remote/quark/quark_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DriveException map(
    HttpResult r, {
    String? context,
  }) =>
      quarkExceptionFrom(r, context: context);

  group('网络层', () {
    test('连接失败 → network，可重试', () {
      final e = map(const HttpResult.networkFailure('connection refused'));
      expect(e.type, DriveErrorType.network);
      expect(e.isRetryable, isTrue);
      expect(e.needsReauth, isFalse);
      expect(e.message, contains('网络'));
    });

    test('HTTP 5xx → network，可重试', () {
      final e = map(const HttpResult(statusCode: 502, rawBody: 'bad gateway'));
      expect(e.type, DriveErrorType.network);
      expect(e.isRetryable, isTrue);
      expect(e.httpStatus, 502);
    });

    test('HTTP 429 → rateLimited，可重试', () {
      final e = map(const HttpResult(statusCode: 429));
      expect(e.type, DriveErrorType.rateLimited);
      expect(e.isRetryable, isTrue);
    });
  });

  group('业务码映射（HTTP 200 + code 非 0 —— 夸克的常态）', () {
    test('31001 require login → unauthorized，需重新授权', () {
      final e = map(HttpResult(
        statusCode: 200,
        json: {'code': 31001, 'message': 'require login [guest]'},
      ));
      expect(e.type, DriveErrorType.unauthorized);
      expect(e.needsReauth, isTrue);
      expect(e.isRetryable, isFalse);
      expect(e.providerCode, 31001);
      expect(e.message, contains('重新授权'));
      expect(e.rawMessage, 'require login [guest]');
    });

    test('31004 token invalid → unauthorized', () {
      final e = map(HttpResult(
        statusCode: 200,
        json: {'code': 31004, 'message': 'token invalid'},
      ));
      expect(e.type, DriveErrorType.unauthorized);
      expect(e.needsReauth, isTrue);
      expect(e.message, contains('已过期'));
    });

    test('23018 体积超限 → fileTooLarge，不可重试', () {
      final e = map(HttpResult(
        statusCode: 200,
        json: {'code': 23018, 'message': 'download file size limit'},
      ));
      expect(e.type, DriveErrorType.fileTooLarge);
      expect(e.isRetryable, isFalse);
      expect(e.providerCode, 23018);
      expect(e.message, contains('体积上限'));
    });

    test('10001 签名失败 → permissionDenied', () {
      final e = map(HttpResult(
        statusCode: 200,
        json: {'code': 10001, 'message': 'sign check failed'},
      ));
      expect(e.type, DriveErrorType.permissionDenied);
    });

    test('未知业务码 → unknown，保留原始码与消息便于排查', () {
      final e = map(HttpResult(
        statusCode: 200,
        json: {'code': 99999, 'message': 'something new'},
      ));
      expect(e.type, DriveErrorType.unknown);
      expect(e.providerCode, 99999);
      expect(e.message, contains('something new'));
    });

    test('业务码为字符串也能解析（网盘返回类型不稳定）', () {
      final e = map(HttpResult(
        statusCode: 200,
        json: {'code': '31001', 'message': 'require login'},
      ));
      expect(e.type, DriveErrorType.unauthorized);
    });
  });

  group('HTTP 状态码映射', () {
    test('401 → unauthorized', () {
      expect(map(const HttpResult(statusCode: 401)).type,
          DriveErrorType.unauthorized);
    });

    test('403 → permissionDenied', () {
      expect(map(const HttpResult(statusCode: 403)).type,
          DriveErrorType.permissionDenied);
    });

    test('412 → permissionDenied，并明确提示缺 Cookie（直链实测结论）', () {
      final e = map(const HttpResult(statusCode: 412));
      expect(e.type, DriveErrorType.permissionDenied);
      expect(e.message, contains('Cookie'));
      expect(e.httpStatus, 412);
    });

    test('404 → notFound', () {
      final e = map(const HttpResult(statusCode: 404));
      expect(e.type, DriveErrorType.notFound);
      expect(e.message, contains('不存在'));
    });

    test('业务码优先于状态码（200 带 31001 仍判 unauthorized）', () {
      final e = map(HttpResult(
        statusCode: 401,
        json: {'code': 31001, 'message': 'require login'},
      ));
      expect(e.type, DriveErrorType.unauthorized);
      expect(e.providerCode, 31001);
    });
  });

  group('畸形响应', () {
    test('非 JSON → malformedResponse', () {
      final e = map(const HttpResult(statusCode: 200, rawBody: '<html>502</html>'));
      expect(e.type, DriveErrorType.malformedResponse);
      expect(e.rawMessage, contains('502'));
    });

    test('空响应体 → malformedResponse', () {
      final e = map(const HttpResult(statusCode: 200));
      expect(e.type, DriveErrorType.malformedResponse);
    });
  });

  group('上下文前缀', () {
    test('有 context 时消息带前缀', () {
      final e = map(
        HttpResult(statusCode: 200, json: {'code': 23018, 'message': 'limit'}),
        context: '取播放直链',
      );
      expect(e.message, startsWith('取播放直链：'));
    });

    test('空 context 不加前缀', () {
      final e = map(
        HttpResult(statusCode: 200, json: {'code': 23018, 'message': 'limit'}),
        context: '',
      );
      expect(e.message, isNot(startsWith('：')));
    });
  });

  group('isQuarkSuccess', () {
    test('HTTP 2xx 且 code=0 才算成功', () {
      expect(isQuarkSuccess(const HttpResult(statusCode: 200, json: {'code': 0})), isTrue);
      expect(isQuarkSuccess(const HttpResult(statusCode: 200, json: {'code': 31001})), isFalse);
      expect(isQuarkSuccess(const HttpResult(statusCode: 500, json: {'code': 0})), isFalse);
      expect(isQuarkSuccess(const HttpResult(statusCode: 200)), isFalse);
      expect(isQuarkSuccess(const HttpResult.networkFailure('x')), isFalse);
    });
  });
}
