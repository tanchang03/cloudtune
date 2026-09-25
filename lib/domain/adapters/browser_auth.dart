import '../entities/auth_credential.dart';
import '../entities/capabilities.dart';
import '../entities/drive_provider.dart';

/// 浏览器授权契约。
///
/// 背景：夸克没有开放平台 `client_id`，无法走标准 OAuth。主链路是 App 扫码
/// （不接触账号密码），本接口是**备选链路**：
/// **打开网盘登录页 → 用户正常登录 → 抓取该会话的 Cookie**。
///
/// 职责划分（重要）：
///   - **UI 层**持有 WebView 组件本身（`flutter_inappwebview`），负责渲染、
///     导航、展示「请登录」「已登录，正在验证…」等交互状态；
///   - **本接口的实现**只负责三件事：给出登录地址、判断「是否已登录」、
///     从当前 WebView 会话中提取并规范化凭证。
///
/// 这样领域层不依赖任何 WebView 实现，测试时可注入假的 authorizer。
abstract class BrowserAuthorizer {
  /// 该网盘的登录入口地址。
  ///
  /// 夸克用 PC 网页版登录页，登录成功后会话 Cookie 落在
  /// `pan.quark.cn` 域下。
  Uri loginUrl(DriveProvider provider);

  /// 判断当前页面是否已经登录成功。
  ///
  /// 典型实现：URL 已跳转回网盘首页 / 页面里出现了用户信息元素 /
  /// 关键 Cookie 已就位。**不要**用「URL 变化」这种脆弱条件。
  Future<bool> isLoggedIn({required DriveProvider provider, String? currentUrl});

  /// 从当前浏览器会话提取凭证。
  ///
  /// 返回 `null` 表示还没抓到（继续等）；抛异常表示抓取过程本身出错。
  /// 由 UI 在 [isLoggedIn] 为真时调用，或由用户手动点「我已登录」触发。
  Future<AuthCredential?> capture(DriveProvider provider);

  /// 当前平台是否支持内嵌浏览器。
  ///
  /// 不支持时（例如受限的 Linux 桌面），UI 降级为
  /// 「打开系统浏览器 + 手动粘贴 Cookie」。
  bool get supportsEmbeddedBrowser;

  /// 该网盘是否支持用本方式授权。
  bool supports(DriveProvider provider);

  /// 支持的授权方式（用于 UI 展示可选项）
  Set<AuthMode> get supportedModes;
}
