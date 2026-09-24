import 'package:cloudtune/data/http/http_client.dart';

/// 一次被记录下来的请求。
class RecordedRequest {
  RecordedRequest({
    required this.method,
    required this.url,
    this.query,
    this.headers,
    this.body,
  });

  final String method;
  final String url;
  final Map<String, Object?>? query;
  final Map<String, String>? headers;
  final Object? body;

  /// 取查询参数（测试里用得多，单独给个便捷方法）
  Object? param(String key) => query?[key];

  @override
  String toString() => '$method $url query=$query';
}

/// 可编程的假 HTTP 客户端。
///
/// 让适配器的所有逻辑（分页、错误映射、直链组装、请求头注入）
/// 都能在**不发一次网络请求**的前提下被完整验证。
class FakeHttpClient implements HttpClientLike {
  FakeHttpClient(this.handler);

  /// 按顺序返回多个响应的便捷构造：第 N 次调用返回第 N 个响应。
  factory FakeHttpClient.sequence(List<HttpResult> responses) {
    var index = 0;
    return FakeHttpClient((_) async {
      if (index >= responses.length) {
        return const HttpResult(statusCode: 500, rawBody: 'sequence exhausted');
      }
      return responses[index++];
    });
  }

  /// 始终返回同一个响应。
  factory FakeHttpClient.always(HttpResult result) =>
      FakeHttpClient((_) async => result);

  /// 始终抛异常（模拟网络层崩溃）
  factory FakeHttpClient.throwing(Object error) =>
      FakeHttpClient((_) async => throw error);

  final Future<HttpResult> Function(RecordedRequest request) handler;

  final List<RecordedRequest> requests = [];
  bool closed = false;

  RecordedRequest get lastRequest => requests.last;

  int get callCount => requests.length;

  /// 按 URL 路径过滤请求
  List<RecordedRequest> requestsTo(String pathFragment) =>
      requests.where((r) => r.url.contains(pathFragment)).toList();

  @override
  Future<HttpResult> get(
    String url, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) {
    final req = RecordedRequest(
      method: 'GET',
      url: url,
      query: query,
      headers: headers,
    );
    requests.add(req);
    return handler(req);
  }

  @override
  Future<HttpResult> post(
    String url, {
    Object? body,
    Map<String, Object?>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) {
    final req = RecordedRequest(
      method: 'POST',
      url: url,
      query: query,
      headers: headers,
      body: body,
    );
    requests.add(req);
    return handler(req);
  }

  @override
  void close() => closed = true;
}

/// 构造一个夸克成功响应。
HttpResult quarkOk(Object? data, {int status = 200}) => HttpResult(
      statusCode: status,
      json: {'code': 0, 'message': 'ok', 'data': data},
    );

/// 构造一个夸克业务错误响应（HTTP 仍为 200 —— 夸克的常态）。
HttpResult quarkError(int code, {String message = 'error', int status = 200}) =>
    HttpResult(
      statusCode: status,
      json: {'code': code, 'message': message},
    );

/// 构造一页列表数据。
Map<String, Object?> quarkListPage(
  List<Map<String, Object?>> items, {
  int? total,
}) =>
    {'list': items, 'total': total ?? items.length};

/// 构造一个夸克文件项。
Map<String, Object?> quarkFileItem({
  required String fid,
  required String name,
  int? size,
  String? formatType,
  String? pdirFid = '0',
  int? updatedAt,
}) =>
    {
      'fid': fid,
      'file_name': name,
      'dir': false,
      'file_type': 1,
      'size': size,
      'format_type': formatType,
      'pdir_fid': pdirFid,
      'updated_at': updatedAt,
    };

/// 构造一个夸克目录项。
Map<String, Object?> quarkDirItem({
  required String fid,
  required String name,
  String? pdirFid = '0',
}) =>
    {
      'fid': fid,
      'file_name': name,
      'dir': true,
      'file_type': 0,
      'size': 0,
      'pdir_fid': pdirFid,
    };
