// 夸克分页与直链结构探针（只读，诊断用）。
//
// 待回答的问题：
//   1. /file/sort 没有 data.total，那分页信号是什么？「满页即还有下一页」成立吗？
//   2. 搜索默认把目录排在前面（_sort=file_type:asc），能否只搜文件？
//   3. download_url 的查询参数名是什么？有没有可解析的过期时间？
//
// 运行：dart run tool/quark_paging_probe.dart
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

const _gateway = 'https://drive-pc.quark.cn';
const _ua =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
final _sep = '─' * 70;

String? _readCookie() {
  final fromEnv = Platform.environment['QUARK_COOKIE'];
  if (fromEnv != null && fromEnv.trim().isNotEmpty) return fromEnv.trim();
  final f = File('.quark_cookie');
  if (f.existsSync()) {
    final t = f.readAsStringSync().trim();
    if (t.isNotEmpty) return t;
  }
  return null;
}

Future<Map<String, Object?>> _request(
  String method,
  String path,
  Map<String, String> params,
  String cookie, {
  Object? body,
}) async {
  final uri = Uri.parse('$_gateway$path')
      .replace(queryParameters: {'pr': 'ucpro', 'fr': 'pc', ...params});
  final client = HttpClient();
  try {
    final req = method == 'POST' ? await client.postUrl(uri) : await client.getUrl(uri);
    req.headers.set('User-Agent', _ua);
    req.headers.set('Accept', 'application/json, text/plain, */*');
    req.headers.set('Referer', 'https://pan.quark.cn/');
    req.headers.set('Origin', 'https://pan.quark.cn');
    req.headers.set('Cookie', cookie);
    if (body != null) {
      req.headers.set('Content-Type', 'application/json');
      req.write(jsonEncode(body));
    }
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    final decoded = jsonDecode(text);
    return decoded is Map ? decoded.cast<String, Object?>() : {'_raw': text};
  } finally {
    client.close(force: true);
  }
}

List<Map<String, Object?>> _items(Map<String, Object?> resp) {
  final data = resp['data'];
  if (data is Map) {
    final list = data['list'];
    if (list is List) {
      return list.whereType<Map>().map((m) => m.cast<String, Object?>()).toList();
    }
  }
  return const [];
}

Future<Map<String, Object?>> _listDir(
  String pdirFid,
  String cookie, {
  int page = 1,
  int size = 50,
}) =>
    _request('GET', '/1/clouddrive/file/sort', {
      'pdir_fid': pdirFid,
      '_page': '$page',
      '_size': '$size',
      '_fetch_total': '1',
      '_sort': 'file_type:asc,updated_at:desc',
      '_is_hl': '1',
    }, cookie);

Future<void> main() async {
  final cookie = _readCookie();
  if (cookie == null) {
    print('未找到凭证');
    exitCode = 1;
    return;
  }

  // ------------------------------------------------------------------
  print(_sep);
  print('1) 分页信号验证：找一个「条目数 > 5」的目录，用 _size=5 取两页');
  print(_sep);

  final root = await _listDir('0', cookie, size: 100);
  print('  顶层响应键: ${(root.keys.toList()..sort()).join(", ")}');
  final rootData = root['data'];
  if (rootData is Map) {
    print('  data 键    : ${(rootData.keys.toList()..sort()).join(", ")}');
    print('  data.total : ${rootData['total']}');
    print('  data.count : ${rootData['count']}');
    print('  data._total: ${rootData['_total']}');
  }
  print('  根目录条目 : ${_items(root).length}');

  // 找到条目最多的目录
  String? targetFid;
  String? targetName;
  var bestCount = 0;
  for (final e in _items(root).where((e) => e['dir'] == true)) {
    final fid = e['fid'] as String?;
    if (fid == null) continue;
    final probe = await _listDir(fid, cookie, size: 100);
    final n = _items(probe).length;
    print('    ${(e['file_name'] as String? ?? "").padRight(28)} $n 条');
    if (n > bestCount) {
      bestCount = n;
      targetFid = fid;
      targetName = e['file_name'] as String?;
    }
  }

  if (targetFid == null || bestCount <= 5) {
    print('  没有足够大的目录用于分页验证，跳过');
  } else {
    print('');
    print('  目标目录: $targetName ($bestCount 条)');
    final p1 = await _listDir(targetFid, cookie, page: 1, size: 5);
    final p2 = await _listDir(targetFid, cookie, page: 2, size: 5);
    final p3 = await _listDir(targetFid, cookie, page: 3, size: 5);
    final i1 = _items(p1);
    final i2 = _items(p2);
    final i3 = _items(p3);

    print('  _size=5 page=1 → ${i1.length} 条');
    print('  _size=5 page=2 → ${i2.length} 条');
    print('  _size=5 page=3 → ${i3.length} 条');

    final n1 = i1.map((e) => e['fid']).toSet();
    final n2 = i2.map((e) => e['fid']).toSet();
    final n3 = i3.map((e) => e['fid']).toSet();
    print('  page1 与 page2 是否不同: ${n1.intersection(n2).isEmpty}');
    print('  page2 与 page3 是否不同: ${n2.intersection(n3).isEmpty}');
    print('  page1 首条: ${i1.isEmpty ? "-" : i1.first['file_name']}');
    print('  page2 首条: ${i2.isEmpty ? "-" : i2.first['file_name']}');
    print('  page3 首条: ${i3.isEmpty ? "-" : i3.first['file_name']}');
    print('');
    print('  → 若各页条数都等于 5 且互不重叠，则「满页即还有下一页」成立');
  }

  // ------------------------------------------------------------------
  print('');
  print(_sep);
  print('2) 搜索排序：目录是否总是排在前面');
  print(_sep);

  for (final sort in [
    'file_type:asc,updated_at:desc',
    'file_type:desc,updated_at:desc',
    '',
  ]) {
    final params = <String, String>{
      '_key': '.flac',
      '_page': '1',
      '_size': '20',
      '_fetch_total': '1',
    };
    if (sort.isNotEmpty) params['_sort'] = sort;
    final resp = await _request('GET', '/1/clouddrive/file/search', params, cookie);
    final items = _items(resp);
    final dirs = items.where((e) => e['dir'] == true).length;
    final files = items.where((e) => e['dir'] != true).length;
    print('  _sort="${sort.isEmpty ? "(不传)" : sort}"');
    print('    返回 ${items.length} 条：目录 $dirs / 文件 $files');
    for (final e in items.where((e) => e['dir'] != true).take(3)) {
      final size = e['size'];
      print('      文件: ${e['file_name']}  size=$size  mime=${e['format_type']}');
    }
  }

  // ------------------------------------------------------------------
  print('');
  print(_sep);
  print('3) 直链结构：对真实文件取直链，检查查询参数');
  print(_sep);

  // 在搜索结果的「文件」里找一个体积合适的
  final searchResp = await _request('GET', '/1/clouddrive/file/search', {
    '_key': '.flac',
    '_page': '1',
    '_size': '50',
    '_fetch_total': '1',
    '_sort': 'file_type:desc,updated_at:desc',
  }, cookie);
  final files = _items(searchResp).where((e) => e['dir'] != true).toList();
  print('  搜到文件 ${files.length} 个');

  Map<String, Object?>? sample;
  for (final f in files) {
    final s = f['size'];
    if (s is int && s > 0 && s <= 50 * 1024 * 1024) {
      sample = f;
      break;
    }
  }
  sample ??= files.isNotEmpty ? files.first : null;

  if (sample == null) {
    print('  没有可用的文件样本，跳过');
    return;
  }

  print('  样本: ${sample['file_name']}  '
      '${((sample['size'] as int? ?? 0) / 1048576).toStringAsFixed(2)} MB');
  final fid = sample['fid'] as String;

  final dl = await _request(
    'POST',
    '/1/clouddrive/file/download',
    const {},
    cookie,
    body: {
      'fids': [fid],
    },
  );
  print('  code=${dl['code']}  message="${dl['message']}"');
  final data = dl['data'];
  if (data is! List || data.isEmpty) {
    print('  data 非预期: ${data.runtimeType} $data');
    return;
  }

  final item = (data.first as Map).cast<String, Object?>();
  print('  data[0] 全部字段:');
  for (final k in item.keys.toList()..sort()) {
    final v = item[k];
    final text = v is String && v.length > 70 ? '${v.substring(0, 70)}…(${v.length})' : '$v';
    print('    ${k.padRight(24)} $text');
  }

  final url = item['download_url'];
  if (url is String) {
    final parsed = Uri.parse(url);
    print('');
    print('  download_url 结构:');
    print('    host : ${parsed.host}');
    print('    path : ${parsed.path}');
    print('    参数 :');
    for (final e in parsed.queryParameters.entries) {
      final v = e.value;
      print('      ${e.key.padRight(20)} '
          '${v.length > 50 ? "${v.substring(0, 50)}…(${v.length})" : v}');
    }
  }
  print(_sep);
}
