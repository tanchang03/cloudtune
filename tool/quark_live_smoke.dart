// 夸克适配器真机冒烟测试（只读）。
//
// 目的：验证 Dart 版适配器**真的能**和夸克接口对话 —— 单元测试用的是假 HTTP
// 客户端，只能证明逻辑自洽，不能证明端点、请求头、字段名猜对了。
//
// 运行：
//   dart run tool/quark_live_smoke.dart
//
// 凭证来源（按优先级）：
//   1. 环境变量 QUARK_COOKIE
//   2. .quark_cookie
//
// 全程只读：只调用 config / member / file/sort / file/search /
// file/audioplay / file/download，并且直链只读前 1KB 做 Range 校验，
// 不下载完整文件。
//
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:cloudtune/core/error/drive_error.dart';
import 'package:cloudtune/core/utils/audio_formats.dart';
import 'package:cloudtune/core/utils/format.dart';
import 'package:cloudtune/core/utils/redact.dart';
import 'package:cloudtune/data/auth/memory_credential_store.dart';
import 'package:cloudtune/data/http/dio_http_client.dart';
import 'package:cloudtune/data/remote/quark/quark_adapter.dart';
import 'package:cloudtune/domain/entities/auth_credential.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/drive_entry.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/playability.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/domain/services/playability_resolver.dart';

const _sep = '────────────────────────────────────────────────────────';

String _line(String label, Object? value) => '  ${label.padRight(14)} $value';

/// 读取凭证。
String? _readCookie() {
  final fromEnv = Platform.environment['QUARK_COOKIE'];
  if (fromEnv != null && fromEnv.trim().isNotEmpty) return fromEnv.trim();

  for (final candidate in [
    '.quark_cookie',
  ]) {
    final f = File(candidate);
    if (f.existsSync()) {
      final text = f.readAsStringSync().trim();
      if (text.isNotEmpty) return text;
    }
  }
  return null;
}

Future<void> main(List<String> args) async {
  print(_sep);
  print('夸克适配器真机冒烟测试（只读）');
  print(_sep);

  final rawCookie = _readCookie();
  if (rawCookie == null) {
    print('未找到凭证。请设置 QUARK_COOKIE 环境变量，或写入 .quark_cookie。');
    print('格式示例：__pus=<值>; __puus=<值>');
    exitCode = 1;
    return;
  }

  final credential = AuthCredential.fromCookieString(
    provider: DriveProvider.quark,
    mode: AuthMode.manualCookie,
    cookieString: rawCookie,
  );
  print(_line('凭证', maskCookieHeader(credential.cookieHeader)));
  print('');

  final http = DioHttpClient();
  final store = InMemoryCredentialStore();
  final adapter = QuarkAdapter(http: http, credentialStore: store);

  var failures = 0;

  // ------------------------------------------------------------------
  // 1. 授权（打 /member 校验会话）
  // ------------------------------------------------------------------
  print('1) 授权与账号信息');
  try {
    final account = await adapter.authorize(credential);
    print(_line('结果', '成功'));
    print(_line('昵称', account.label));
    print(_line('会员档位', account.memberLabel ?? '未知'));
    if (account.hasStorageInfo) {
      print(_line(
        '容量',
        '${formatBytes(account.storageUsedBytes)} / '
            '${formatBytes(account.storageTotalBytes)}',
      ));
    }
  } on DriveException catch (e) {
    failures++;
    print(_line('结果', '失败：${e.message}'));
    if (e.needsReauth) {
      print('  → 会话已失效，请重新登录夸克网页版并更新 .quark_cookie');
    }
    print(_sep);
    exitCode = 1;
    await adapter.dispose();
    return;
  }
  print('');

  // ------------------------------------------------------------------
  // 2. 列目录
  // ------------------------------------------------------------------
  print('2) 列根目录（第一页）');
  List<DriveEntry> rootEntries = const [];
  try {
    final page = await adapter.listDirectory(dirId: adapter.rootId);
    rootEntries = page.entries;
    print(_line('结果', '成功'));
    print(_line('条目数', '${page.entries.length}（total=${page.total}）'));
    print(_line('下一页', page.nextPageToken ?? '（已到底）'));
    for (final e in page.entries.take(5)) {
      print('    ${e.isDirectory ? "[目录]" : "[文件]"} ${e.name}');
    }
  } on DriveException catch (e) {
    failures++;
    print(_line('结果', '失败：${e.message}'));
  }
  print('');

  // ------------------------------------------------------------------
  // 3. 搜索
  // ------------------------------------------------------------------
  print('3) 搜索 "flac"（注意：夸克搜索会返回目录）');
  List<DriveEntry> found = const [];
  try {
    found = await adapter.search(keyword: 'flac', limit: 50);
    final files = found.where((e) => e.isFile).toList();
    final dirs = found.where((e) => e.isDirectory).toList();
    print(_line('结果', '成功'));
    print(_line('命中', '${found.length} 项（文件 ${files.length} / 目录 ${dirs.length}）'));
    for (final e in found.take(5)) {
      print('    ${e.isDirectory ? "[目录]" : "[文件]"} ${e.name}'
          '  ${e.isDirectory ? "" : formatBytes(e.sizeBytes)}');
    }
  } on DriveException catch (e) {
    failures++;
    print(_line('结果', '失败：${e.message}'));
  }
  print('');

  // ------------------------------------------------------------------
  // 2.5 遍历音乐目录（验证 BFS 分页 + 音频识别）
  // ------------------------------------------------------------------
  print('2.5) 遍历音乐目录（BFS，深度 2，每页 50）');
  final audioFiles = <DriveEntry>[];
  final musicRoot = rootEntries
      .where((e) => e.isDirectory && e.name.contains('音乐'))
      .firstOrNull;
  if (musicRoot == null) {
    print(_line('结果', '跳过：根目录下没找到「音乐」目录'));
  } else {
    final queue = <(String, String, int)>[(musicRoot.id, musicRoot.name, 0)];
    var visited = 0;
    var pages = 0;
    while (queue.isNotEmpty && visited < 12) {
      final (fid, label, depth) = queue.removeAt(0);
      visited++;
      String? token;
      do {
        final page = await adapter.listDirectory(
          dirId: fid,
          pageToken: token,
          pageSize: 50,
        );
        pages++;
        for (final e in page.entries) {
          if (e.isDirectory) {
            if (depth < 2) queue.add((e.id, e.name, depth + 1));
          } else if (isAudioFile(e.name, mimeType: e.mimeType)) {
            audioFiles.add(e);
          }
        }
        token = page.nextPageToken;
      } while (token != null);
    }
    print(_line('结果', '成功'));
    print(_line('访问目录', '$visited 个，共 $pages 次请求'));
    print(_line('音频文件', '${audioFiles.length} 个'));
    final totalBytes = audioFiles.fold<int>(0, (s, e) => s + (e.sizeBytes ?? 0));
    print(_line('总体积', formatBytes(totalBytes)));
    for (final e in audioFiles.take(5)) {
      print('    ${e.name}  ${formatBytes(e.sizeBytes)}');
    }
  }
  print('');

  // ------------------------------------------------------------------
  // 4. 取直链 + Range 校验（验证「必须带 Cookie」这条结论）
  // ------------------------------------------------------------------
  print('4) 取播放直链并做 Range 校验');
  // 只用**真实遍历到的音频文件**，且体积 > 1KB ——
  // 否则 Range: bytes=0-1023 对不足 1KB 的文件会（正确地）返回 200 全量，
  // 看起来像失败，其实是 HTTP 规范行为。
  //
  // 样本刻意取**体积最大**的那个：这是本条改造最该被验证的点 ——
  // 改走 /file/audioplay 之前，>50MiB 的文件取链必失败（code=23018），
  // 所以「最大的那个现在能取到链」就是改造生效的直接证据。
  final probe = audioFiles
      .where((e) => (e.sizeBytes ?? 0) > 1024)
      .fold<DriveEntry?>(
        null,
        (best, e) =>
            (best == null || (e.sizeBytes ?? 0) > (best.sizeBytes ?? 0)) ? e : best,
      );

  if (probe == null) {
    print(_line('结果', '跳过：没找到大于 1KB 的音频文件样本'));
  } else {
    print(_line('样本', '${probe.name} (${formatBytes(probe.sizeBytes)})'));
    try {
      final ticket = await adapter.resolveStream(probe.id);
      print(_line('直链', ticket.redactedUrl));
      print(_line('请求头', ticket.headers.keys.join(', ')));
      print(_line('过期', ticket.expiresAt?.toIso8601String() ?? '未知'));

      final (status, magic, acceptRanges) = await _rangeProbe(ticket.url, ticket.headers);
      print(_line('Range 探测', 'HTTP $status  Accept-Ranges=${acceptRanges ? "yes" : "no"}'));
      print(_line('首字节特征', magic));

      if (status == 206) {
        print(_line('判定', '✅ 可在线播放（206 + Range 支持，可拖动进度条）'));
      } else if (status == 412) {
        failures++;
        print(_line('判定', '❌ 412 —— 缺少 Cookie 前置条件'));
      } else if (status == 200) {
        print(_line('判定', '⚠️ 200（服务端忽略了 Range，仍可播但无法拖动进度）'));
      } else {
        failures++;
        print(_line('判定', '⚠️ HTTP $status，与预期不符'));
      }
    } on DriveException catch (e) {
      // 改造后不该再出现 fileTooLarge：播放路由没有体积上限。
      failures++;
      print(_line('结果', '❌ 失败：${e.message}'));
    }
  }
  print('');

  // ------------------------------------------------------------------
  // 5. 可播性体检（跑在**真实遍历到的音乐库**上，而非搜索结果）
  // ------------------------------------------------------------------
  print('5) 可播性体检（对 BFS 遍历到的 ${audioFiles.length} 个音频文件）');
  if (audioFiles.isEmpty) {
    print(_line('结果', '跳过：没有遍历到音频文件'));
  } else {
    final acc = PlayabilityAccumulator();
    final rows = <(Track, Playability)>[];
    final byExt = <String, List<(Track, Playability)>>{};

    for (final e in audioFiles) {
      final t = Track.fromEntry(entry: e, provider: DriveProvider.quark);
      final p = t.playability(adapter.capabilities);
      acc.add(p, sizeBytes: t.sizeBytes);
      rows.add((t, p));
      byExt.putIfAbsent(extensionOf(t.name), () => []).add((t, p));
    }

    final attemptable = rows.where((r) => r.$2.shouldAttempt).toList();
    final blocked = rows.where((r) => !r.$2.shouldAttempt).toList();
    final s = acc.summary;

    print(_line('可播', '${attemptable.length} / ${rows.length}'
        '（${(attemptable.length / rows.length * 100).toStringAsFixed(1)}%）'));
    print(_line('取不到链', '${blocked.length}'));
    print(_line('可播体积', '${formatBytes(s.playableBytes)} / ${formatBytes(s.totalBytes)}'
        '（${(s.playableBytesRatio * 100).toStringAsFixed(1)}%）'));

    // 按格式分解 —— 直接决定「哪些格式值得留、哪些该提示用户转码」
    // 可播数按**判定结果**算，不再按体积猜（体积猜是旧口径，已被推翻）
    print('');
    print('  按格式分解：');
    print('    ${"格式".padRight(8)}${"总数".padLeft(6)}${"可播".padLeft(6)}'
        '${"占比".padLeft(8)}${"平均体积".padLeft(12)}${"最大体积".padLeft(12)}');
    final sortedExts = byExt.keys.toList()
      ..sort((a, b) => byExt[b]!.length.compareTo(byExt[a]!.length));
    for (final ext in sortedExts) {
      final group = byExt[ext]!;
      final ok = group.where((r) => r.$2.shouldAttempt).length;
      final total = group.fold<int>(0, (sum, r) => sum + (r.$1.sizeBytes ?? 0));
      final maxBytes = group.fold<int>(
          0, (m, r) => (r.$1.sizeBytes ?? 0) > m ? (r.$1.sizeBytes ?? 0) : m);
      print('    ${ext.padRight(8)}${"${group.length}".padLeft(6)}'
          '${"$ok".padLeft(6)}'
          '${"${(ok / group.length * 100).toStringAsFixed(0)}%".padLeft(8)}'
          '${formatBytes(total ~/ group.length).padLeft(12)}'
          '${formatBytes(maxBytes).padLeft(12)}');
    }

    if (attemptable.isNotEmpty) {
      final top = [...attemptable]
        ..sort((a, b) => (b.$1.sizeBytes ?? 0).compareTo(a.$1.sizeBytes ?? 0));
      print('');
      print('  可播样本（体积最大的 5 个）：');
      for (final (t, _) in top.take(5)) {
        print('    ${t.name}  ${formatBytes(t.sizeBytes)}');
      }
    }
    if (blocked.isNotEmpty) {
      print('');
      print('  取不到链样本（前 3 个）：');
      for (final (t, p) in blocked.take(3)) {
        print('    ${t.name}  ${formatBytes(t.sizeBytes)}  ${p.reason ?? ""}');
      }
    }
  }

  print('');
  print(_sep);
  print(failures == 0 ? '冒烟测试通过：适配器与夸克接口链路正常' : '冒烟测试有 $failures 项异常');
  print(_sep);

  await adapter.dispose();
  exitCode = failures == 0 ? 0 : 1;
}

/// 只读前 1KB 验证 Range 与音频特征。
Future<(int, String, bool)> _rangeProbe(
  Uri url,
  Map<String, String> headers,
) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
    headers.forEach((k, v) => req.headers.set(k, v));

    final resp = await req.close();
    final acceptRanges = resp.headers.value(HttpHeaders.acceptRangesHeader) != null;
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
      if (bytes.length >= 1024) break;
    }
    return (resp.statusCode, _magicOf(bytes), acceptRanges);
  } finally {
    client.close(force: true);
  }
}

const _magicTable = <(List<int>, String)>[
  ([0x49, 0x44, 0x33], 'ID3v2 (MP3)'),
  ([0x66, 0x4C, 0x61, 0x43], 'fLaC (FLAC)'),
  ([0x4F, 0x67, 0x67, 0x53], 'OggS (OGG)'),
  ([0x52, 0x49, 0x46, 0x46], 'RIFF (WAV)'),
  ([0x44, 0x53, 0x44, 0x20], 'DSD (DSF)'),
  ([0xFF, 0xFB], 'MP3 frame'),
  ([0xFF, 0xF3], 'MP3 frame'),
  ([0xFF, 0xF1], 'AAC/ADTS'),
];

String _magicOf(List<int> head) {
  for (final (sig, name) in _magicTable) {
    if (head.length >= sig.length) {
      var match = true;
      for (var i = 0; i < sig.length; i++) {
        if (head[i] != sig[i]) {
          match = false;
          break;
        }
      }
      if (match) return name;
    }
  }
  if (head.length >= 8 &&
      head[4] == 0x66 &&
      head[5] == 0x74 &&
      head[6] == 0x79 &&
      head[7] == 0x70) {
    return 'MP4/M4A (ftyp)';
  }
  final hex = head.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '未知 (hex=$hex)';
}

/// `Iterable.firstOrNull` 的本地实现，避免为了一个方法引入 collection 依赖。
extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
