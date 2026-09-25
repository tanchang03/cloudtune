import 'dart:typed_data';

import '../../../core/diagnostics/diag_log.dart';
import '../../../core/error/drive_error.dart';
import '../../../core/utils/redact.dart';
import '../../../domain/adapters/cloud_drive_adapter.dart';
import '../../../domain/adapters/credential_store.dart';
import '../../../domain/entities/auth_credential.dart';
import '../../../domain/entities/capabilities.dart';
import '../../../domain/entities/cloud_account.dart';
import '../../../domain/entities/drive_entry.dart';
import '../../../domain/entities/drive_provider.dart';
import '../../../domain/entities/stream_ticket.dart';
import '../../http/http_client.dart';
import '../../http/token_bucket.dart';
import '../../auth/quark_qr_login.dart' show parseSetCookieLines;
import 'quark_endpoints.dart';
import 'quark_error_mapper.dart';
import 'quark_models.dart';

/// 夸克网盘适配器。
///
/// 走 **PC 自用接口**（`drive-pc.quark.cn`），靠网页登录态 Cookie 鉴权。
/// 全部字段语义与端点均按 PoC 实测校准，见 [QuarkMapper] 的表格。
///
/// 该类**只依赖 [HttpClientLike]**，不依赖 `dio`，因此可以在单元测试里
/// 用假客户端把分页、错误映射、限流、直链组装全部覆盖到，不发一次网络请求。
class QuarkAdapter implements CloudDriveAdapter {
  QuarkAdapter({
    required HttpClientLike http,
    required CredentialStore credentialStore,
    Capabilities? capabilities,
    TokenBucket? listBucket,
    TokenBucket? linkBucket,
    String gateway = QuarkEndpoints.pcGateway,
    DateTime Function()? clock,
  })  : _http = http,
        _store = credentialStore,
        _gateway = gateway,
        _clock = clock ?? DateTime.now,
        _capabilities = capabilities ?? quarkCapabilities,
        _listBucket = listBucket ??
            TokenBucket(ratePerSecond: quarkCapabilities.listQps),
        _linkBucket = linkBucket ??
            TokenBucket(ratePerSecond: quarkCapabilities.linkQps);

  /// 夸克的默认能力声明。
  ///
  /// ⚠️ **这里刻意不声明 [Capabilities.maxSingleFileBytes]**。
  ///
  /// 那条 50MiB 限制是 `/1/clouddrive/file/download`（PC 网页版取**下载**直链）
  /// 的限制，而本适配器的播放取链走 [QuarkEndpoints.fileAudioplay]。
  /// 2026-09-24 实测该播放路由**不受体积限制**：774.1MB 的整轨 WAV 同样返回
  /// `code=0` + 原文件直链，库内 195 首「超限」曲目按体积降序抽样 40 首
  /// 全部可播（开发期探针实测）。
  ///
  /// 把 download 的上限写进能力声明，会让 **43.9% 的曲目被误判为不可播**，
  /// 所以它只作为兜底路由存在（见 [resolveStream]）。
  /// 万一两条路由都取不到链，由 `PlaybackController` 在运行时标记不可播 ——
  /// 那才是「真的播不了」。
  static const Capabilities quarkCapabilities = Capabilities(
    provider: DriveProvider.quark,
    canListDirectory: true,
    canSearch: true,
    canResolveDirectLink: true,
    directLinkNeedsHeaders: true,
    supportsRangeRequests: true,
    listQps: 3.0,
    linkQps: 1.0,
    defaultPageSize: 50,
    authModes: {
      // 主链路：夸克 App 扫码 → service_ticket 换账号 Cookie。
      AuthMode.qrCode,
      // 备选与兜底。
      AuthMode.browserCookie,
      AuthMode.manualCookie,
      AuthMode.localClient,
    },
  );

  final HttpClientLike _http;
  final CredentialStore _store;
  final String _gateway;
  final DateTime Function() _clock;
  final Capabilities _capabilities;
  final TokenBucket _listBucket;
  final TokenBucket _linkBucket;

  AuthCredential? _credential;
  CloudAccount? _account;

  @override
  DriveProvider get provider => DriveProvider.quark;

  @override
  Capabilities get capabilities => _capabilities;

  @override
  String get rootId => QuarkEndpoints.rootId;

  /// 当前会话的 `Cookie:` 头。未授权时为空串。
  String get _cookieHeader => _credential?.cookieHeader ?? '';

  /// 是否持有会话（不代表仍然有效）
  bool get hasSession => _cookieHeader.isNotEmpty;

  /// 当前账号（若已恢复/授权）
  CloudAccount? get currentAccount => _account;

  // -------------------------------------------------------------------
  // 授权
  // -------------------------------------------------------------------

  @override
  Future<CloudAccount?> restoreSession() async {
    final stored = await _store.load(DriveProvider.quark);
    if (stored == null || stored.isEmpty) {
      diag.warn('会话', '恢复失败：凭证存储里没有可用凭证');
      return null;
    }

    _credential = stored;
    diag.info(
      '会话',
      '拿到凭证：模式=${stored.mode.name}，'
      'Cookie ${maskCookieHeader(stored.cookieHeader)}，'
      '捕获于 ${stored.capturedAt}',
    );

    // 用 /member 校验并顺带取回昵称与容量
    final member = await _fetchMember();
    _account = member;
    diag.info('会话', '校验通过：${member.label}');
    return member;
  }

  @override
  Future<CloudAccount> authorize(AuthCredential credential) async {
    if (credential.isEmpty) {
      throw const DriveException(
        type: DriveErrorType.unauthorized,
        message: '授权凭证为空，请重新登录夸克账号',
      );
    }

    _credential = credential;
    diag.info(
      '会话',
      '提交凭证校验：模式=${credential.mode.name}，'
      'Cookie ${maskCookieHeader(credential.cookieHeader)}',
    );

    CloudAccount account;
    try {
      // 先校验再落库：避免把废凭证写进钥匙串
      account = await _fetchMember();
    } catch (_) {
      _credential = null;
      _account = null;
      diag.error('会话', '凭证校验失败，已丢弃');
      rethrow;
    }

    _account = account;
    await _store.save(credential);
    diag.info('会话', '授权完成：${account.label}');
    return account;
  }

  @override
  Future<void> signOut() async {
    _credential = null;
    _account = null;
    await _store.clear(DriveProvider.quark);
    diag.info('会话', '已退出登录');
  }

  @override
  Future<bool> ping() async {
    if (!hasSession) return false;
    try {
      await _request(
        () => _get(QuarkEndpoints.config),
        context: '连接诊断',
      );
      return true;
    } on DriveException catch (e) {
      if (e.needsReauth) return false;
      rethrow;
    }
  }

  // -------------------------------------------------------------------
  // 遍历与搜索
  // -------------------------------------------------------------------

  @override
  Future<DrivePage> listDirectory({
    required String dirId,
    String? pageToken,
    int? pageSize,
  }) async {
    final size = pageSize ?? _capabilities.defaultPageSize;
    final page = _parsePageToken(pageToken);

    final result = await _listBucket.run(
      () => _request(
        () => _get(QuarkEndpoints.fileSort, {
          'pdir_fid': dirId.isEmpty ? rootId : dirId,
          '_page': page,
          '_size': size,
          // 实测：即便带 _fetch_total=1，PC 端也**不返回** data.total
          // （data 里只有 list / last_view_list / recent_file_list）。
          // 仍然带上，一是无害，二是官方接口若返回就能拿到更精确的总数。
          '_fetch_total': 1,
          '_sort': QuarkEndpoints.defaultSort,
          '_is_hl': 1,
        }),
        context: '列目录',
      ),
    );

    final entries = QuarkMapper.toEntries(result.dataListItems);
    final total = result.dataTotal;

    // 下一页判定。
    // 主路径实际走的是「满页启发式」：实测 data.total 恒为 null，
    // 但 _size=5 连续取 3 页各返回 5 条且互不重叠，说明
    // 「返回条数 == 请求条数」即代表还有下一页。
    // 若某天能拿到 total，则用 total 判断更精确。
    String? nextToken;
    if (total != null) {
      if (page * size < total) nextToken = '${page + 1}';
    } else if (entries.length >= size) {
      nextToken = '${page + 1}';
    }

    return DrivePage(entries: entries, nextPageToken: nextToken, total: total);
  }

  @override
  Future<List<DriveEntry>> search({
    required String keyword,
    int limit = 100,
    int offset = 0,
  }) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return const [];

    final page = offset <= 0 ? 1 : (offset ~/ limit) + 1;

    final result = await _listBucket.run(
      () => _request(
        () => _get(QuarkEndpoints.fileSearch, {
          '_key': trimmed,
          '_page': page,
          '_size': limit,
          '_fetch_total': 1,
          // 文件优先：实测 file_type:asc 时前 20 条全是目录
          '_sort': QuarkEndpoints.searchSort,
        }),
        context: '搜索',
      ),
    );

    return QuarkMapper.toEntries(result.dataListItems);
  }

  /// 取播放直链。
  ///
  /// **主路径是 `/1/clouddrive/file/audioplay`**（音频专用播放接口）。
  /// 选它的理由（2026-09-24 实测）：
  ///   1. **不受 50MiB 限制** —— 774.1MB 的整轨 WAV 也返回原文件直链，
  ///      而 `/file/download` 对同样文件返回 `code=23018`；
  ///   2. 给的是**原文件**而非转码流（`Content-Range` 总长 == 原体积，
  ///      首字节 magic 与原格式一致），`just_audio` 拿到就能解；
  ///   3. 支持 Range（`206` + `Accept-Ranges: bytes`），可拖动进度。
  ///
  /// [QuarkEndpoints.fileDownload] 保留为**兜底**：只在主路径
  /// 「非致命失败」时启用（判定见 [_shouldFallbackToDownload]）。
  /// 授权失效、文件不存在这类问题换条路由也一样失败，
  /// 再打一次只是白费一次取链配额，所以直接抛出。
  @override
  Future<StreamTicket> resolveStream(String fileId) async {
    diag.info(
      '取链',
      '开始取直链 fid=$fileId，'
      '会话=${hasSession ? "有" : "无（会直接抛未授权）"}',
    );
    try {
      final ticket = await _resolveViaAudioplay(fileId);
      diag.info('取链', '主路由 audioplay 成功');
      return ticket;
    } on DriveException catch (e) {
      if (!_shouldFallbackToDownload(e)) {
        diag.error(
          '取链',
          '主路由 audioplay 失败且不值得兜底，直接放弃',
          error: _describe(e),
        );
        rethrow;
      }
      diag.warn(
        '取链',
        '主路由 audioplay 失败，改试兜底路由 download',
        error: _describe(e),
      );
    }
    final ticket = await _resolveViaDownload(fileId);
    diag.info('取链', '兜底路由 download 成功');
    return ticket;
  }

  /// 读取小文件原始字节（CUE 分轨表）。
  ///
  /// **刻意只用 download 路由，不走 [resolveStream] 那条 audioplay 主路径。**
  /// 理由：
  ///   1. download 的 50MiB 上限对 CUE（几 KB）完全不是问题，而 audioplay 是
  ///      **音频专用**接口 —— 拿它去取一个 `.cue` 没有语义，服务端行为不可预期；
  ///   2. 这里要的是**字节**，不是播放直链，`resolveStream` 返回的票据语义
  ///      是「给播放器用的」。
  ///
  /// 两道体积闸门（声明体积 / 实际字节数）都保留：声明值可能缺失或不准，
  /// 只信其中一道都可能把一个大文件拉进内存。
  @override
  Future<Uint8List> readFileBytes(
    String fileId, {
    int maxBytes = 512 * 1024,
  }) async {
    final ticket = await _resolveViaDownload(fileId);

    final declared = ticket.contentLength;
    if (declared != null && declared > maxBytes) {
      throw DriveException(
        type: DriveErrorType.fileTooLarge,
        message: '文件声明体积 ${declared}B 超出读取上限 ${maxBytes}B，不按小文本文件读取',
      );
    }

    diag.info('读文件', '开始读取 fid=$fileId，声明体积=${declared ?? "未知"}');
    final bytes = await _http.getBytes(ticket.url.toString(), headers: ticket.headers);
    if (bytes == null) {
      throw const DriveException(
        type: DriveErrorType.network,
        message: '读取文件内容失败：网络层未返回响应',
      );
    }
    // 声明体积缺失时这是唯一一道闸门
    if (bytes.length > maxBytes) {
      throw DriveException(
        type: DriveErrorType.fileTooLarge,
        message: '文件实际体积 ${bytes.length}B 超出读取上限 ${maxBytes}B',
      );
    }

    diag.info('读文件', '读取完成 fid=$fileId，实际 ${bytes.length}B');
    return bytes;
  }

  @override
  Future<void> dispose() async {
    _credential = null;
    _account = null;
    _http.close();
  }

  // -------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------

  // -------------------------------------------------------------------
  // 内部：取链
  // -------------------------------------------------------------------

  /// 主路径：音频播放接口。
  ///
  /// 注意响应形状与 download **不同**：`data` 是一个**扁平对象**
  /// （`{audio_url, size, format_type, duration, ...}`），
  /// 不是 download 的 `data: [{download_url, ...}]`。所以这里读 [HttpResult.dataMap]。
  ///
  /// 另有一个实测怪癖：DSF 文件返回 `format_type=text/plain`、
  /// `obj_category=doc`、`duration=0`（服务端不把它当音频），
  /// **但仍会返回原文件字节**。因此这里只信 `size` 与地址，
  /// 不拿 `format_type` / `duration` 做判定。
  Future<StreamTicket> _resolveViaAudioplay(String fileId) async {
    final result = await _linkBucket.run(
      () => _request(
        () => _get(QuarkEndpoints.fileAudioplay, {'fid': fileId}),
        context: '取播放直链',
      ),
    );

    final data = result.dataMap;
    if (data == null) {
      throw const DriveException(
        type: DriveErrorType.malformedResponse,
        message: '取播放直链：响应中没有文件信息',
      );
    }

    final url = QuarkMapper.parseDirectUrl(data);
    if (url == null) {
      throw const DriveException(
        type: DriveErrorType.malformedResponse,
        message: '取播放直链：响应中没有 audio_url',
      );
    }

    final ticket = QuarkMapper.toStreamTicket(
      url: url,
      cookieHeader: _cookieHeader,
      contentLength: _intOf(data['size']),
      contentType: data['format_type'] as String?,
      now: _clock(),
    );
    _logTicket('audioplay', ticket);
    return ticket;
  }

  /// 兜底路径：下载直链接口。单文件 >50MiB 会返回 `code=23018`。
  Future<StreamTicket> _resolveViaDownload(String fileId) async {
    final result = await _linkBucket.run(
      () => _request(
        () => _post(
          QuarkEndpoints.fileDownload,
          body: {
            'fids': [fileId],
          },
        ),
        context: '取播放直链',
      ),
    );

    final items = result.dataListItems;
    if (items.isEmpty) {
      throw const DriveException(
        type: DriveErrorType.malformedResponse,
        message: '取播放直链：响应中没有文件信息',
      );
    }

    final first = items.first;
    final url = QuarkMapper.parseDirectUrl(first);
    if (url == null) {
      throw const DriveException(
        type: DriveErrorType.malformedResponse,
        message: '取播放直链：响应中没有 download_url',
      );
    }

    final ticket = QuarkMapper.toStreamTicket(
      url: url,
      cookieHeader: _cookieHeader,
      contentLength: _intOf(first['size']),
      contentType: first['format_type'] as String?,
      now: _clock(),
    );
    _logTicket('download', ticket);
    return ticket;
  }

  /// 把票据的关键事实写进诊断日志。
  ///
  /// **直链地址本身绝不能进日志** —— 查询串里带着可用的签名令牌。
  /// 这里只留「协议+主机+路径」，足够看出是不是同一条 CDN 路由，
  /// 又不至于把播放权限泄露到磁盘上。
  static void _logTicket(String route, StreamTicket ticket) {
    diag.info(
      '取链',
      '路由 $route 签发票据：${ticket.redactedUrl}，'
      '声明体积=${ticket.contentLength ?? "未知"}，'
      '随票据请求头=${ticket.headers.isEmpty ? "无" : ticket.headers.keys.join(",")}，'
      '过期=${ticket.expiresAt ?? "未声明"}',
    );
  }

  /// 把 [DriveException] 拆成一行可读的诊断描述。
  static String _describe(DriveException e) =>
      'type=${e.type.name} needsReauth=${e.needsReauth} '
      'http=${e.httpStatus ?? "-"} providerCode=${e.providerCode ?? "-"} '
      'message=${e.message}'
      '${e.rawMessage == null ? "" : " raw=${e.rawMessage}"}';

  /// 主路径失败后，是否值得再用 download 试一次。
  ///
  /// 只有「换条路由结果可能不同」的失败才降级：
  ///   - 授权失效 → 换路由一样 401，且会多打一次无谓请求；
  ///   - 文件不存在 → 换路由一样 404。
  ///
  /// 其余（体积超限、限流、网络抖动、响应形状变了、未知业务码）
  /// 都值得兜底一次 —— 尤其是体积超限：**这正是 download 会失败、
  /// 而 audioplay 可能成功的场景**，虽然此时我们已经先走了 audioplay。
  static bool _shouldFallbackToDownload(DriveException e) {
    if (e.needsReauth) return false;
    if (e.type == DriveErrorType.notFound) return false;
    return true;
  }

  /// 拉取账号信息，顺带完成会话校验。
  Future<CloudAccount> _fetchMember() async {
    final result = await _request(
      () => _get(QuarkEndpoints.member, {'uc_param_str': ''}),
      context: '获取账号信息',
    );

    final base = CloudAccount(
      provider: DriveProvider.quark,
      authMode: _credential?.mode ?? AuthMode.browserCookie,
      authorizedAt: _credential?.capturedAt ?? _clock(),
    );

    final data = result.dataMap;
    if (data == null) return base;
    return QuarkMapper.mergeAccountInfo(base, data);
  }

  /// 统一请求包装：注入公共参数与请求头，校验业务码，归一化异常。
  Future<HttpResult> _request(
    Future<HttpResult> Function() call, {
    String? context,
  }) async {
    if (!hasSession) {
      diag.error('接口', '${context ?? "请求"}：尚未授权（没有 Cookie）');
      throw DriveException(
        type: DriveErrorType.unauthorized,
        message: '${context ?? "请求"}：尚未授权夸克账号',
      );
    }

    final result = await call();
    if (!isQuarkSuccess(result)) {
      final e = quarkExceptionFrom(result, context: context);
      diag.error('接口', '${context ?? "请求"} 业务失败', error: _describe(e));
      throw e;
    }
    _absorbRotatedCookies(result);
    return result;
  }

  /// 响应 Cookie 轮换回填（浏览器 cookie jar 的等价物）。
  ///
  /// 夸克服务端会在**每个** API 响应的 `Set-Cookie` 里轮换下发 `__puus`
  ///（2026-09-24 实测：`/member`、`/file/sort`、`/file/audioplay` 每响应必带）。
  /// CDN 直链的防重放校验依赖**最新**的 `__puus` —— 缺它直链一律 412。
  /// 浏览器里 cookie jar 自动完成这件事；我们手动管理 Cookie，必须在
  /// 每个响应后把新值回填进内存凭证，下一个请求（尤其是直链）才能带上。
  ///
  /// ⚠️ 故意**不落库**：扫描时每页都轮换，逐次写钥匙串开销大且无意义 ——
  /// 重启后首次 API 响应就会下发新 `__puus`，本方法会立刻补上。
  void _absorbRotatedCookies(HttpResult result) {
    final credential = _credential;
    if (credential == null) return;

    final lines = result.setCookieLines;
    if (lines.isEmpty) return;

    final fresh = parseSetCookieLines(lines);
    if (fresh.isEmpty) return;

    final current = credential.cookies;
    final updates = <String, String>{};
    for (final name in QuarkEndpoints.knownCookieNames) {
      final v = fresh[name];
      if (v == null || v.isEmpty) continue;
      if (current[name] == v) continue;
      updates[name] = v;
    }
    if (updates.isEmpty) return;

    _credential = credential.copyWith(
      cookies: {...current, ...updates},
      capturedAt: DateTime.now(),
    );
    diag.debug('会话', '响应 Cookie 轮换回填：${updates.keys.toList()}');
  }

  Map<String, String> _headers() => {
        'User-Agent': QuarkEndpoints.userAgent,
        'Accept': QuarkEndpoints.accept,
        'Accept-Language': QuarkEndpoints.acceptLanguage,
        'Referer': QuarkEndpoints.referer,
        'Origin': QuarkEndpoints.origin,
        'Cookie': _cookieHeader,
      };

  Future<HttpResult> _get(String path, [Map<String, Object?>? params]) =>
      _http.get(
        '$_gateway$path',
        query: {...QuarkEndpoints.commonParams, ...?params},
        headers: _headers(),
      );

  Future<HttpResult> _post(String path, {Object? body, Map<String, Object?>? params}) =>
      _http.post(
        '$_gateway$path',
        body: body,
        query: {...QuarkEndpoints.commonParams, ...?params},
        headers: {..._headers(), 'Content-Type': 'application/json'},
      );

  /// 分页游标解析。非法值回落到第 1 页。
  static int _parsePageToken(String? token) {
    if (token == null || token.isEmpty) return 1;
    final n = int.tryParse(token);
    if (n == null || n < 1) return 1;
    return n;
  }

  static int? _intOf(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
