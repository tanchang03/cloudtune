import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/diagnostics/diag_log.dart';
import '../../domain/entities/stream_ticket.dart';

/// 回探直链的函数签名，便于在测试里换成假实现。
typedef StreamProbe = Future<void> Function(StreamTicket ticket);

/// 装载 / 播放失败之后，回探一次直链本身能不能取到。
///
/// **为什么值得为一次失败多打一个请求。**
/// 「播不了」的原因分成两大类，而它们的修法完全不同：
///   - **直链或请求头不行** —— CDN 直接回 403 / 412（夸克缺 Cookie 就是 412），
///     或域名根本连不上 → 问题在取链与请求头这一侧；
///   - **播放器不行** —— 字节拿到了，但解码器解不开这个编码/容器 → 问题在格式侧。
///
/// 平台播放器抛出来的异常经常只有一句「操作无法完成」（AVFoundation 的
/// `-11800` 之类），从文案上分不出是哪一类 —— 而这恰恰是
/// 「debug 能播、release 不能播」这类问题最难判的地方。
/// 自己带 Range 打一次请求拿状态码，就能一刀切开。
///
/// 四条约束，缺一条都会让探测本身变成新的麻烦：
///   1. **只在失败之后才打**。正常播放一次额外请求都不发，不占取链配额。
///   2. **不阻塞调用方**（调用处 `unawaited`）。失败路径该跳歌就跳歌，
///      不能被探测的几秒超时拖住。
///   3. **任何异常都吞掉**。探测失败绝不能变成第二个错误冒到上层。
///   4. **只请求 1 个字节**（`Range: bytes=0-0`）。够拿状态码，又几乎不耗流量。
Future<void> probeStreamAfterFailure(StreamTicket ticket) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final request = await client
        .getUrl(ticket.url)
        .timeout(const Duration(seconds: 6));
    // 请求头必须原样带上：不带 Cookie 的话夸克直链会回 412，
    // 那样探出来的结论就是错的（把「我们没带 Cookie」当成「直链废了」）。
    ticket.headers.forEach(request.headers.set);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');

    final response =
        await request.close().timeout(const Duration(seconds: 8));

    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    diag.info(
      '探测',
      '回探直链 ${ticket.redactedUrl} → HTTP ${response.statusCode} '
      '${response.reasonPhrase}'
      '${contentRange == null ? "" : "，content-range=$contentRange"}',
    );

    final body = await response
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(const Duration(seconds: 4));
    if (body.isNotEmpty) {
      // 网盘把失败原因写在响应体里（`code` / `message`），前 200 字就够看
      final head = body.length > 200 ? body.substring(0, 200) : body;
      diag.warn('探测', '响应体前 ${head.length} 字：$head');
    }
  } catch (e) {
    // 连不上 / 超时 / DNS 失败，本身也是有信息量的结论：
    // 说明问题不在播放器，而在网络或直链这一侧。
    diag.warn('探测', '回探直链本身也失败了（网络 / DNS / 被拦）', error: e);
  } finally {
    client.close(force: true);
  }
}
