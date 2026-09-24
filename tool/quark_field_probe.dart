// 夸克响应字段探针（只读，诊断用）。
//
// 目的：冒烟测试发现搜索结果里 size 为 0、根目录 total 为 null。
// 单元测试用的是我**假设**的字段名，必须用真实响应校准。
//
// 运行：dart run tool/quark_field_probe.dart
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

const _gateway = 'https://drive-pc.quark.cn';
const _ua =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

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

Future<Map<String, Object?>> _get(
  String path,
  Map<String, String> params,
  String cookie,
) async {
  final uri = Uri.parse('$_gateway$path').replace(queryParameters: {
    'pr': 'ucpro',
    'fr': 'pc',
    ...params,
  });
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    req.headers.set('User-Agent', _ua);
    req.headers.set('Accept', 'application/json, text/plain, */*');
    req.headers.set('Referer', 'https://pan.quark.cn/');
    req.headers.set('Origin', 'https://pan.quark.cn');
    req.headers.set('Cookie', cookie);
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is Map) return decoded.cast<String, Object?>();
    return {'_nonMap': body.substring(0, 200)};
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _postJson(
  String path,
  Object body,
  String cookie,
) async {
  final uri = Uri.parse('$_gateway$path')
      .replace(queryParameters: {'pr': 'ucpro', 'fr': 'pc'});
  final client = HttpClient();
  try {
    final req = await client.postUrl(uri);
    req.headers.set('User-Agent', _ua);
    req.headers.set('Accept', 'application/json, text/plain, */*');
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Referer', 'https://pan.quark.cn/');
    req.headers.set('Origin', 'https://pan.quark.cn');
    req.headers.set('Cookie', cookie);
    req.write(jsonEncode(body));
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    final decoded = jsonDecode(text);
    if (decoded is Map) return decoded.cast<String, Object?>();
    return {'_nonMap': text.substring(0, 200)};
  } finally {
    client.close(force: true);
  }
}

void _dumpItem(String label, Map<String, Object?>? item) {
  print('  $label');
  if (item == null) {
    print('    （无）');
    return;
  }
  final keys = item.keys.toList()..sort();
  for (final k in keys) {
    final v = item[k];
    final text = v == null
        ? 'null'
        : (v is String && v.length > 60 ? '${v.substring(0, 60)}…(${v.length})' : '$v');
    print('    ${k.padRight(26)} $text');
  }
}

void _dumpDataShape(String label, Map<String, Object?> resp) {
  print('  $label');
  print('    code=${resp['code']}  message=${resp['message']}');
  final data = resp['data'];
  if (data is Map) {
    print('    data 顶层键: ${(data.keys.toList()..sort()).join(', ')}');
    final list = data['list'];
    if (list is List) {
      print('    data.list 长度: ${list.length}');
      if (list.isNotEmpty && list.first is Map) {
        _dumpItem('data.list[0] 字段:', (list.first as Map).cast<String, Object?>());
      }
    }
  } else if (data is List) {
    print('    data 是数组，长度 ${data.length}');
    if (data.isNotEmpty && data.first is Map) {
      _dumpItem('data[0] 字段:', (data.first as Map).cast<String, Object?>());
    }
  } else {
    print('    data 类型: ${data.runtimeType}  值: $data');
  }
}

Future<void> main() async {
  final cookie = _readCookie();
  if (cookie == null) {
    print('未找到凭证');
    exitCode = 1;
    return;
  }

  final sep = '─' * 70;

  print(sep);
  print('A. 列根目录 /1/clouddrive/file/sort  (pdir_fid=0, _fetch_total=1)');
  print(sep);
  final sort = await _get('/1/clouddrive/file/sort', {
    'pdir_fid': '0',
    '_page': '1',
    '_size': '50',
    '_fetch_total': '1',
    '_sort': 'file_type:asc,updated_at:desc',
    '_is_hl': '1',
  }, cookie);
  _dumpDataShape('响应结构:', sort);

  print('');
  print(sep);
  print('B. 搜索 /1/clouddrive/file/search  (_key=flac)');
  print(sep);
  final search = await _get('/1/clouddrive/file/search', {
    '_key': 'flac',
    '_page': '1',
    '_size': '50',
    '_fetch_total': '1',
    '_sort': 'file_type:asc,updated_at:desc',
  }, cookie);
  _dumpDataShape('响应结构:', search);

  print('');
  print(sep);
  print('C. 换关键词搜索 (_key=.flac 精确后缀)');
  print(sep);
  final search2 = await _get('/1/clouddrive/file/search', {
    '_key': '.flac',
    '_page': '1',
    '_size': '10',
    '_fetch_total': '1',
    '_sort': 'file_type:asc,updated_at:desc',
  }, cookie);
  _dumpDataShape('响应结构:', search2);

  print('');
  print(sep);
  print('D. 取直链 /1/clouddrive/file/download 的响应字段');
  print(sep);

  // 先从搜索里找一个文件 fid
  final data = search['data'];
  String? fid;
  if (data is Map) {
    final list = data['list'];
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is Map) {
        for (final k in ['fid', 'file_id', 'id']) {
          final v = first[k];
          if (v is String && v.isNotEmpty) {
            fid = v;
            break;
          }
        }
      }
    }
  }

  if (fid == null) {
    print('  搜索里没拿到 fid，跳过');
  } else {
    final dl = await _postJson(
      '/1/clouddrive/file/download',
      {
        'fids': [fid],
      },
      cookie,
    );
    print('  code=${dl['code']}  message=${dl['message']}');
    final d = dl['data'];
    if (d is List) {
      print('  data 是数组，长度 ${d.length}');
      if (d.isNotEmpty && d.first is Map) {
        final item = (d.first as Map).cast<String, Object?>();
        _dumpItem('data[0] 字段:', item);
        final url = item['download_url'];
        if (url is String) {
          final parsed = Uri.parse(url);
          print('');
          print('  download_url 结构:');
          print('    host  : ${parsed.host}');
          print('    path  : ${parsed.path}');
          print('    参数名: ${parsed.queryParameters.keys.join(", ")}');
          for (final e in parsed.queryParameters.entries) {
            final v = e.value;
            print('      ${e.key.padRight(22)} '
                '${v.length > 40 ? "${v.substring(0, 40)}…(${v.length})" : v}');
          }
        }
      }
    } else {
      print('  data 类型: ${d.runtimeType}');
      print('  $d');
    }
  }

  print('');
  print(sep);
}
