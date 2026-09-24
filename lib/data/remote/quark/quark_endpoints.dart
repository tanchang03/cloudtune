/// 夸克 PC 自用接口的端点与请求常量。
///
/// **重要区分**（PoC 结论）：
///   - 官方开放平台：`open-api-drive.quark.cn`，需 OAuth `access_token`；
///   - 本文件用的是**PC 客户端自用接口**：`drive-pc.quark.cn`，
///     靠网页登录态 Cookie（`__pus` / `__puus`）鉴权。
///
/// 两者不可混用：本机 Cookie 换不到开放平台的 token，反之亦然。
library;

class QuarkEndpoints {
  const QuarkEndpoints._();

  /// PC 网关。PoC 实测全部端点在此域名下可用。
  static const String pcGateway = 'https://drive-pc.quark.cn';

  /// 备用网关。列目录/取直链实测同样可用，作为降级备选。
  static const String altGateway = 'https://drive.quark.cn';

  /// 网页版来源，用于构造 `Referer` / `Origin`。
  static const String webOrigin = 'https://pan.quark.cn';

  /// 授权登录入口（浏览器授权时打开的地址）
  static const String loginUrl = 'https://pan.quark.cn/';

  // -------------------------------------------------------------------
  // 端点（相对路径）
  // -------------------------------------------------------------------

  /// 配置 / 会话校验。最轻量的连通性探测。
  static const String config = '/1/clouddrive/config';

  /// 用户信息：昵称、容量、会员档位
  static const String member = '/1/clouddrive/member';

  /// 列目录
  static const String fileSort = '/1/clouddrive/file/sort';

  /// 搜索（全盘，不限目录）
  static const String fileSearch = '/1/clouddrive/file/search';

  /// 取下载直链。
  ///
  /// ⚠️ **单文件约 50MiB 硬上限**（超限返回 `code=23018`）。这是 PC 网页版
  /// 「下载」这条产品路径的限制，**不是**文件能不能播的限制。
  /// 播放走 [fileAudioplay]。
  static const String fileDownload = '/1/clouddrive/file/download';

  /// 取音频播放直链（**播放主路径**）。
  ///
  /// 2026-09-24 实测结论（三个独立探针交叉验证）：
  ///   - **不受 50MiB 限制**：774.1MB 的整轨 WAV 照样返回 `code=0` + `audio_url`；
  ///   - 给的是**原文件**，不是转码流：`Content-Range` 总长逐字节等于原体积
  ///     （比值 1.0000），首字节 magic 与原格式一致；
  ///   - 支持 Range（`206` + `Accept-Ranges: bytes`），可拖动进度；
  ///   - **必须带 Cookie**，裸链返回 `412 Precondition Failed`；
  ///   - **不需要额外签名**，沿用 `pr=ucpro&fr=pc` + Cookie 即可。
  ///
  /// 这是夸克客户端自己用的接口（逆向 `/Applications/Quark.app` 得到），
  /// 因此属于**未公开路由**，存在被改动的风险 —— 所以调用方要保留
  /// [fileDownload] 作为兜底。
  static const String fileAudioplay = '/1/clouddrive/file/audioplay';

  // -------------------------------------------------------------------
  // 请求常量
  // -------------------------------------------------------------------

  /// 根目录 ID。夸克用 `'0'` 表示根。
  static const String rootId = '0';

  /// 所有请求都必须带的公共参数。
  ///
  /// 注意：`fr` 必须与账号类型匹配。实测用 `fr=mac` 会返回
  /// `code=31001 require login [guest]`，因此固定为 `pc`。
  static const Map<String, String> commonParams = {
    'pr': 'ucpro',
    'fr': 'pc',
  };

  /// PoC 实测可用的 UA（Chrome on macOS）
  static const String userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  static const String referer = 'https://pan.quark.cn/';
  static const String origin = 'https://pan.quark.cn';
  static const String accept = 'application/json, text/plain, */*';
  static const String acceptLanguage = 'zh-CN,zh;q=0.9';

  /// 列目录默认排序：目录优先、更新时间倒序
  static const String defaultSort = 'file_type:asc,updated_at:desc';

  /// 搜索排序：**文件优先**。
  ///
  /// 实测（2026-09-23）：
  ///   - `file_type:asc`（默认）→ 返回的前 20 条**全是目录**；
  ///   - `file_type:desc` → 前 20 条**全是文件**。
  /// 音乐检索只关心文件，所以搜索用后者，避免用户翻半天全是目录。
  static const String searchSort = 'file_type:desc,updated_at:desc';

  /// 网页登录态 Cookie 的域名集合。
  ///
  /// 浏览器授权时需要从这两个域取 Cookie：登录动作发生在 `pan.quark.cn`，
  /// 而接口调用走 `drive-pc.quark.cn`。
  static const List<String> cookieDomains = [
    'https://pan.quark.cn',
    'https://drive-pc.quark.cn',
  ];

  /// 会话必需 Cookie —— 缺任一即视为未登录。
  static const List<String> essentialCookieNames = ['__pus', '__puus'];

  /// 会一并抓取的已知 Cookie（便于服务端识别设备/账号）。
  static const List<String> knownCookieNames = [
    '__pus',
    '__puus',
    '__kuus',
    '__uid',
    '__kp',
    '__kps',
    '__ktd',
    '__kui',
  ];

  /// 组装 `Cookie:` 头时的优先顺序（关键键在前，便于日志排查）
  static const List<String> cookieHeaderOrder = [
    '__pus',
    '__puus',
    '__kuus',
    '__uid',
    '__kp',
  ];

  /// 直链过期时间的兜底 TTL。
  ///
  /// 正常情况下用不到：夸克直链的 `auth_key` 参数第 1 段就是真实过期时刻
  /// （unix 秒），由 `QuarkMapper.parseUrlExpiry` 解析。
  ///
  /// ⚠️ **只有第 1 段可信**。2026-09-24 实测 `auth_key` 形如
  /// `<过期unix秒>-<第二段>-<TTL秒>-<签名>`，其中 TTL 段**随路由与文件变化**：
  ///
  /// | 路由 | 文件 | 第1段−now | 第3段 TTL |
  /// |---|---|---|---|
  /// | download | 15.1MB | 21601s | 21600（6h） |
  /// | audioplay | 15.1MB | 10801s | 10800（3h） |
  /// | audioplay | 774.1MB | 18405s | 18404（5.11h） |
  ///
  /// 即**播放路由的地址过期更快且不固定**，所以更不该长期缓存票据。
  ///
  /// 这里只在**解析不出来**时兜底。取 30 分钟是折中：远小于实测最短的 3 小时
  /// （不会导致播放中途断流），又不必每次起播都重新取链。
  static const Duration ticketFallbackTtl = Duration(minutes: 30);
}
