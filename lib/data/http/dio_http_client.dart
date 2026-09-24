import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/diagnostics/diag_log.dart';
import '../../core/utils/redact.dart';
import 'http_client.dart';

/// 基于 `dio` 的 [HttpClientLike] 实现。
///
/// 每次请求往诊断日志里写两行（发起 / 结果）。这是**故意啰嗦**的：
/// 「取不到直链」这类问题的分界线就在 HTTP 层 —— 是没发出去（DNS/沙箱/代理）、
/// 发出去被拒（401/403/412）、还是发出去拿到了业务错误码。
/// 少了这一层，上面所有判断都只能靠猜。
class DioHttpClient implements HttpClientLike {
  DioHttpClient({
    Dio? dio,
    Duration? timeout,
    Map<String, String>? defaultHeaders,
  })  : _timeout = timeout ?? const Duration(seconds: 20),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: timeout ?? const Duration(seconds: 20),
              receiveTimeout: timeout ?? const Duration(seconds: 20),
              // 关键：非 2xx 也要把响应体交给我们，业务错误码在里面
              validateStatus: (_) => true,
              // 我们自己解析 JSON，避免 dio 在非 JSON 响应上抛异常
              responseType: ResponseType.plain,
              followRedirects: true,
            )) {
    if (defaultHeaders != null) {
      _dio.options.headers.addAll(defaultHeaders);
    }
  }

  final Dio _dio;
  final Duration _timeout;

  @override
  Future<HttpResult> get(
    String url, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) =>
      _send(
        'GET',
        url,
        headers,
        () => _dio.get<String>(
          url,
          queryParameters: query,
          options: Options(
            headers: headers,
            receiveTimeout: timeout ?? _timeout,
            sendTimeout: timeout ?? _timeout,
          ),
        ),
      );

  @override
  Future<HttpResult> post(
    String url, {
    Object? body,
    Map<String, Object?>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) =>
      _send(
        'POST',
        url,
        headers,
        () => _dio.post<String>(
          url,
          data: body,
          queryParameters: query,
          options: Options(
            headers: headers,
            receiveTimeout: timeout ?? _timeout,
            sendTimeout: timeout ?? _timeout,
          ),
        ),
      );

  Future<HttpResult> _send(
    String method,
    String url,
    Map<String, String>? headers,
    Future<Response<String>> Function() call,
  ) async {
    // 只打「协议 + 主机 + 路径」：查询串里是签名参数，请求头里有 Cookie。
    final label = '$method ${redactUrl(url)}';
    diag.debug('HTTP', '$label 发起${_headerSummary(headers)}');

    final started = DateTime.now();
    try {
      final resp = await call();
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final status = resp.statusCode ?? 0;
      diag.info('HTTP', '$label → $status (${elapsed}ms)');
      return _toResult(status, resp.data);
    } on DioException catch (e) {
      // 有响应但被 dio 归类为异常（例如连接中断），尽量把体带回去
      final body = e.response?.data;
      final status = e.response?.statusCode ?? 0;
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      if (body != null && status != 0) {
        diag.warn('HTTP', '$label → $status (${elapsed}ms，dio 归类为 ${e.type.name})');
        return _toResult(status, body);
      }
      diag.error(
        'HTTP',
        '$label → 请求未完成 (${elapsed}ms)',
        error: '${e.type.name}: ${e.message}',
      );
      return HttpResult.networkFailure('${e.type.name}: ${e.message}');
    } catch (e, st) {
      diag.error('HTTP', '$label → 抛出非 dio 异常', error: e, stackTrace: st);
      return HttpResult.networkFailure(e.toString());
    }
  }

  /// 只列请求头的**键名**，外加脱敏后的 Cookie 摘要。
  ///
  /// 键名能回答「Cookie 到底带没带上」；值一律不打 —— 日志文件会留在
  /// 用户磁盘上，还可能被复制出来求助。
  static String _headerSummary(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return '';
    final keys = headers.keys.join(',');
    String? cookie;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'cookie') {
        cookie = entry.value;
        break;
      }
    }
    if (cookie == null) return '，头[$keys]';
    return '，头[$keys]，Cookie: ${maskCookieHeader(cookie)}';
  }

  HttpResult _toResult(int status, String? body) {
    final text = body ?? '';
    if (text.isEmpty) return HttpResult(statusCode: status);

    Map<String, Object?>? parsed;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) {
        parsed = decoded;
      } else if (decoded is Map) {
        parsed = decoded.cast<String, Object?>();
      }
    } on FormatException {
      parsed = null;
    }

    return HttpResult(
      statusCode: status,
      json: parsed,
      // 只留前 400 字符，避免把巨大响应体带进内存与日志
      rawBody: text.length > 400 ? text.substring(0, 400) : text,
    );
  }

  @override
  void close() => _dio.close(force: true);
}
