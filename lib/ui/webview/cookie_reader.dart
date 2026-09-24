import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../data/auth/quark_authorizer.dart';

/// 从内置 WebView 的 Cookie 管理器读取指定域下的 Cookie。
///
/// `QuarkBrowserAuthorizer` 通过 [CookieReader] 回调拿到它，因此数据层
/// 不必依赖 `flutter_inappwebview`，单元测试里可以注入假实现。
///
/// 逐个域名容错：某个域读失败（未访问过、Cookie 存储未就绪）不该让整次
/// 抓取失败 —— 夸克的关键键在 `pan.quark.cn`，`drive-pc.quark.cn` 读不到
/// 也不影响授权。
Future<Map<String, String>> readCookiesFromWebView(List<String> domains) async {
  final out = <String, String>{};
  for (final domain in domains) {
    try {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(domain));
      for (final cookie in cookies) {
        final value = cookie.value;
        if (value == null || value.isEmpty) continue;
        out[cookie.name] = value;
      }
    } catch (_) {
      // 单个域失败不影响其它域
    }
  }
  return out;
}
