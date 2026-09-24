import '../../domain/adapters/browser_auth.dart';
import '../../domain/entities/auth_credential.dart';
import '../../domain/entities/capabilities.dart';
import '../../domain/entities/drive_provider.dart';
import '../remote/quark/quark_endpoints.dart';

/// 从浏览器会话读取 Cookie 的回调。
///
/// 由 UI 层提供实现（包一层 `flutter_inappwebview` 的 `CookieManager`）。
/// 领域层/数据层因此**不依赖任何 WebView 实现**，测试可注入假实现。
///
/// 参数是域名列表（如 `https://pan.quark.cn`），返回该域下所有
/// `Cookie 名 → 值`。实现应逐个域名调用 CookieManager 后合并。
typedef CookieReader = Future<Map<String, String>> Function(List<String> domains);

/// 夸克「浏览器登录 → 抓取 Cookie」授权器。
///
/// 这是当前**主链路**：夸克没有开放平台 `client_id`，无法走标准 OAuth；
/// 而本机客户端的加密 Cookie 库已确认是自研加密（700 次穷举未破解），
/// 所以只能由用户正常登录一次，然后从会话里取凭证。
class QuarkBrowserAuthorizer implements BrowserAuthorizer {
  QuarkBrowserAuthorizer({
    required CookieReader readCookies,
    bool supportsEmbedded = true,
    DateTime Function()? clock,
  })  : _readCookies = readCookies,
        _supportsEmbedded = supportsEmbedded,
        _clock = clock ?? DateTime.now;

  final CookieReader _readCookies;
  final bool _supportsEmbedded;
  final DateTime Function() _clock;

  @override
  bool get supportsEmbeddedBrowser => _supportsEmbedded;

  @override
  Set<AuthMode> get supportedModes => const {
        AuthMode.browserCookie,
        AuthMode.manualCookie,
      };

  @override
  bool supports(DriveProvider provider) => provider == DriveProvider.quark;

  @override
  Uri loginUrl(DriveProvider provider) => Uri.parse(QuarkEndpoints.loginUrl);

  /// 判断当前页面是否已登录。
  ///
  /// 刻意**不**用「URL 变了」这种脆弱条件，而是：
  ///   1. 仍在夸克域内（严格域名边界，避免 `evilquark.cn` 这类仿冒域通过）；
  ///   2. 路径不含登录/通行证相关的片段。
  ///
  /// 真正的有效性验证交给 `adapter.authorize()`（它会打一次 `/member`），
  /// 因为「页面看着像登录了」和「Cookie 真能用」是两回事。
  @override
  Future<bool> isLoggedIn({
    required DriveProvider provider,
    String? currentUrl,
  }) async {
    if (!supports(provider)) return false;
    final url = currentUrl == null ? null : Uri.tryParse(currentUrl);
    if (url == null || url.host.isEmpty) return false;
    if (!_isQuarkHost(url.host)) return false;

    final path = url.path.toLowerCase();
    for (final marker in const ['login', 'passport', 'signin', 'auth/']) {
      if (path.contains(marker)) return false;
    }
    return true;
  }

  /// 严格的夸克域名判断。
  ///
  /// 只接受 `quark.cn` 本身或以 `.quark.cn` 结尾，
  /// 这样 `evilquark.cn`、`quark.cn.evil.com` 都会被拒绝。
  static bool _isQuarkHost(String host) {
    final h = host.toLowerCase();
    return h == 'quark.cn' || h.endsWith('.quark.cn');
  }

  @override
  Future<AuthCredential?> capture(DriveProvider provider) async {
    if (!supports(provider)) return null;

    final cookies = await _readCookies(QuarkEndpoints.cookieDomains);
    if (!_hasEssentialCookies(cookies)) return null;

    return AuthCredential(
      provider: provider,
      mode: AuthMode.browserCookie,
      capturedAt: _clock(),
      cookies: _filterKnown(cookies),
    );
  }

  /// 是否已具备会话必需 Cookie。
  static bool _hasEssentialCookies(Map<String, String> cookies) =>
      QuarkEndpoints.essentialCookieNames
          .any((name) => (cookies[name] ?? '').isNotEmpty);

  /// 只保留已知 Cookie + 必需 Cookie。
  ///
  /// 保留全部第三方 Cookie 没有意义，还会把无关凭据带进钥匙串；
  /// 但**必需 Cookie 一定保留**（即使名字不在已知列表里）。
  static Map<String, String> _filterKnown(Map<String, String> cookies) {
    final out = <String, String>{};
    for (final name in QuarkEndpoints.knownCookieNames) {
      final v = cookies[name];
      if (v != null && v.isNotEmpty) out[name] = v;
    }
    for (final name in QuarkEndpoints.essentialCookieNames) {
      final v = cookies[name];
      if (v != null && v.isNotEmpty) out[name] = v;
    }
    return out;
  }
}

/// 夸克「手动粘贴 Cookie」授权器。
///
/// 用于两种情况：
///   1. 平台不支持内嵌浏览器（受限的 Linux 桌面等）；
///   2. 用户已经在本机浏览器登录，懒得再登一次。
///
/// 解析宽容度见 `parseCookieLooseText`：既吃 `k=v; k=v`，
/// 也吃用户从开发者工具复制出来的 `k : v` 多行形式。
class QuarkManualCookieAuthorizer implements BrowserAuthorizer {
  QuarkManualCookieAuthorizer({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  @override
  bool get supportsEmbeddedBrowser => false;

  @override
  Set<AuthMode> get supportedModes => const {AuthMode.manualCookie};

  @override
  bool supports(DriveProvider provider) => provider == DriveProvider.quark;

  @override
  Uri loginUrl(DriveProvider provider) => Uri.parse(QuarkEndpoints.loginUrl);

  @override
  Future<bool> isLoggedIn({
    required DriveProvider provider,
    String? currentUrl,
  }) async =>
      false;

  @override
  Future<AuthCredential?> capture(DriveProvider provider) async => null;

  /// 把用户粘贴的文本转成凭证。
  ///
  /// 不含必需 Cookie 时抛 [FormatException]，由 UI 提示用户「粘贴内容不正确」。
  AuthCredential parse(DriveProvider provider, String rawInput) {
    final credential = AuthCredential.fromCookieString(
      provider: provider,
      mode: AuthMode.manualCookie,
      cookieString: rawInput,
      capturedAt: _clock(),
    );

    final missing = QuarkEndpoints.essentialCookieNames
        .where((name) => !credential.hasCookie(name))
        .toList();
    if (missing.length == QuarkEndpoints.essentialCookieNames.length) {
      throw const FormatException(
        '未识别到夸克会话凭证，请确认复制了 __pus 与 __puus 的完整内容',
      );
    }
    return credential;
  }
}
