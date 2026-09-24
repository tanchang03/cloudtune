import 'package:cloudtune/data/remote/quark/quark_endpoints.dart';
import 'package:cloudtune/data/remote/quark/quark_models.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/cloud_account.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseIsDirectory —— 目录判定（PoC 踩过的坑）', () {
    test('dir 为布尔时以此为准', () {
      expect(QuarkMapper.parseIsDirectory({'dir': true}), isTrue);
      expect(QuarkMapper.parseIsDirectory({'dir': false}), isFalse);
    });

    test('dir 优先于 file_type —— 这是最容易搞错的地方', () {
      // 若误用 file_type（0=目录），会把文件当目录，BFS 队列爆炸
      expect(
        QuarkMapper.parseIsDirectory({'dir': false, 'file_type': 0}),
        isFalse,
      );
      expect(
        QuarkMapper.parseIsDirectory({'dir': true, 'file_type': 1}),
        isTrue,
      );
    });

    test('dir 缺失时用 file_type 兜底：0=目录 1=文件', () {
      expect(QuarkMapper.parseIsDirectory({'file_type': 0}), isTrue);
      expect(QuarkMapper.parseIsDirectory({'file_type': 1}), isFalse);
    });

    test('字符串与数字形式的 dir 也能识别', () {
      expect(QuarkMapper.parseIsDirectory({'dir': 'true'}), isTrue);
      expect(QuarkMapper.parseIsDirectory({'dir': 'false'}), isFalse);
      expect(QuarkMapper.parseIsDirectory({'dir': 1}), isTrue);
      expect(QuarkMapper.parseIsDirectory({'dir': 0}), isFalse);
    });

    test('字段全缺时保守判为文件（宁可漏扫目录也不炸队列）', () {
      expect(QuarkMapper.parseIsDirectory(const {}), isFalse);
    });
  });

  group('toEntry', () {
    test('完整字段映射', () {
      final entry = QuarkMapper.toEntry({
        'fid': 'f1',
        'pdir_fid': 'd1',
        'file_name': '周杰伦 - 晴天.flac',
        'dir': false,
        'file_type': 1,
        'size': 31457280,
        'format_type': 'audio/flac',
        'updated_at': 1758600000000,
        'duration': 269,
      })!;

      expect(entry.id, 'f1');
      expect(entry.name, '周杰伦 - 晴天.flac');
      expect(entry.isDirectory, isFalse);
      expect(entry.sizeBytes, 31457280);
      expect(entry.mimeType, 'audio/flac');
      expect(entry.parentId, 'd1');
      expect(entry.modifiedAt, isNotNull);
      expect(entry.durationMs, 269000, reason: '夸克给的是秒，要换算成毫秒');
    });

    test('目录项的 size 归一为 0（避免被当成「体积未知」）', () {
      final entry = QuarkMapper.toEntry({
        'fid': 'd1',
        'file_name': '华语',
        'dir': true,
        'size': 12345,
      })!;
      expect(entry.isDirectory, isTrue);
      expect(entry.sizeBytes, 0);
      expect(entry.fileSizeBytes, 0);
    });

    test('缺 fid 或 file_name 的脏数据被丢弃', () {
      expect(QuarkMapper.toEntry({'file_name': 'a.mp3', 'dir': false}), isNull);
      expect(QuarkMapper.toEntry({'fid': 'f1', 'dir': false}), isNull);
      expect(QuarkMapper.toEntry({'fid': '', 'file_name': 'a.mp3'}), isNull);
      expect(QuarkMapper.toEntry({'fid': 'f1', 'file_name': ''}), isNull);
    });

    test('兼容 id / name 别名', () {
      final entry = QuarkMapper.toEntry({'id': 'x', 'name': 'y.mp3', 'dir': false})!;
      expect(entry.id, 'x');
      expect(entry.name, 'y.mp3');
    });

    test('size 为字符串也能解析', () {
      final entry = QuarkMapper.toEntry({
        'fid': 'f1',
        'file_name': 'a.mp3',
        'dir': false,
        'size': '1024',
      })!;
      expect(entry.sizeBytes, 1024);
    });

    test('批量映射自动跳过脏数据', () {
      final list = QuarkMapper.toEntries([
        {'fid': 'f1', 'file_name': 'a.mp3', 'dir': false},
        {'file_name': 'no-fid.mp3'},
        {'fid': 'f2', 'file_name': 'b.flac', 'dir': false},
      ]);
      expect(list.map((e) => e.id).toList(), ['f1', 'f2']);
    });
  });

  group('parseDurationMs —— 音频时长（夸克给的是秒）', () {
    test('秒换算成毫秒', () {
      // 实测：一条 39.3MB 的 flac 返回 duration=186，即 3 分 06 秒
      expect(QuarkMapper.parseDurationMs(186), 186000);
      expect(QuarkMapper.parseDurationMs(1), 1000);
    });

    test('字符串数字也能解析', () {
      expect(QuarkMapper.parseDurationMs('186'), 186000);
    });

    test('0 归一为 null —— 网盘没刮削到，不是空文件', () {
      // 显示 00:00 会让人以为文件是坏的，--:-- 才是诚实的「不知道」
      expect(QuarkMapper.parseDurationMs(0), isNull);
      expect(QuarkMapper.parseDurationMs('0'), isNull);
    });

    test('缺失 / 负数 / 乱码一律 null', () {
      expect(QuarkMapper.parseDurationMs(null), isNull);
      expect(QuarkMapper.parseDurationMs(-5), isNull);
      expect(QuarkMapper.parseDurationMs('abc'), isNull);
      expect(QuarkMapper.parseDurationMs(const <String, Object>{}), isNull);
    });

    test('toEntry：没有 duration 字段的文件时长是 null（非音频、未刮削）', () {
      final entry = QuarkMapper.toEntry({
        'fid': 'f9',
        'file_name': '说明.txt',
        'dir': false,
        'size': 1024,
      })!;

      expect(entry.durationMs, isNull);
    });

    test('toEntry：目录项不带时长（目录没有「播放时长」这个概念）', () {
      final entry = QuarkMapper.toEntry({
        'fid': 'd9',
        'file_name': '华语',
        'dir': true,
        'duration': 186,
      })!;

      expect(entry.durationMs, isNull);
    });
  });

  group('parseTimestamp', () {
    final ms = DateTime.utc(2026, 9, 23, 12).millisecondsSinceEpoch;

    test('毫秒时间戳', () {
      expect(
        QuarkMapper.parseTimestamp(ms)!.toUtc(),
        DateTime.utc(2026, 9, 23, 12),
      );
    });

    test('秒时间戳（自动识别，不靠猜位数以外的东西）', () {
      final dt = QuarkMapper.parseTimestamp(ms ~/ 1000)!;
      expect(dt.toUtc().year, 2026);
      expect(dt.toUtc().month, 9);
      expect(dt.toUtc().day, 23);
    });

    test('字符串数字', () {
      expect(QuarkMapper.parseTimestamp('$ms')!.toUtc().year, 2026);
    });

    test('ISO8601 字符串', () {
      expect(
        QuarkMapper.parseTimestamp('2026-09-23T12:00:00Z')!.toUtc().year,
        2026,
      );
    });

    test('null / 0 / 负数 / 乱码 / 越界年份 一律返回 null', () {
      expect(QuarkMapper.parseTimestamp(null), isNull);
      expect(QuarkMapper.parseTimestamp(0), isNull);
      expect(QuarkMapper.parseTimestamp(-1), isNull);
      expect(QuarkMapper.parseTimestamp('not a date'), isNull);
      expect(QuarkMapper.parseTimestamp(1), isNull); // 1970 年，视为脏数据
    });
  });

  group('mergeAccountInfo', () {
    final base = CloudAccount(
      provider: DriveProvider.quark,
      authMode: AuthMode.browserCookie,
      authorizedAt: DateTime(2026, 9, 23),
    );

    test('合并昵称、容量、会员档位', () {
      final acc = QuarkMapper.mergeAccountInfo(base, {
        'nickname': '张三',
        'user_id': 'u1',
        'member_type': 'SUPER_VIP',
        'use_capacity': 1073741824,
        'total_capacity': 6442450944000,
      });
      expect(acc.displayName, '张三');
      expect(acc.userId, 'u1');
      expect(acc.memberLabel, 'SUPER_VIP');
      expect(acc.storageUsedBytes, 1073741824);
      expect(acc.storageTotalBytes, 6442450944000);
      expect(acc.hasStorageInfo, isTrue);
    });

    test('member_type 在 member_info 里也能取到', () {
      final acc = QuarkMapper.mergeAccountInfo(base, {
        'member_info': {'member_type': 'VIP'},
      });
      expect(acc.memberLabel, 'VIP');
    });

    test('字段缺失时保留原值，不覆盖成 null', () {
      final withName = base.copyWith(displayName: '原昵称');
      final acc = QuarkMapper.mergeAccountInfo(withName, const {});
      expect(acc.displayName, '原昵称');
    });

    test('容量为字符串也能解析', () {
      final acc = QuarkMapper.mergeAccountInfo(base, {
        'use_capacity': '1024',
        'total_capacity': '2048',
      });
      expect(acc.storageUsedBytes, 1024);
      expect(acc.storageTotalBytes, 2048);
      expect(acc.storageRatio, 0.5);
    });
  });

  group('parseDirectUrl', () {
    test('download 路由：download_url', () {
      final uri = QuarkMapper.parseDirectUrl({
        'download_url': 'https://dl-pc-zb.drive.quark.cn/f/down?sign=abc',
      });
      expect(uri, isNotNull);
      expect(uri!.host, 'dl-pc-zb.drive.quark.cn');
    });

    test('audioplay 路由：audio_url（响应形状与 download 不同）', () {
      final uri = QuarkMapper.parseDirectUrl({
        'audio_url': 'https://video-play-c-sz.drive.quark.cn/f/play?auth_key=x',
        'size': 198018943,
        'format_type': 'audio/x-flac',
      });
      expect(uri, isNotNull);
      expect(uri!.host, 'video-play-c-sz.drive.quark.cn');
    });

    test('兼容 url / dl_url / audioUrl / downloadUrl 别名', () {
      for (final key in const ['url', 'dl_url', 'audioUrl', 'downloadUrl']) {
        expect(
          QuarkMapper.parseDirectUrl({key: 'https://x.com/a'}),
          isNotNull,
          reason: '$key 应该被识别',
        );
      }
    });

    test('缺失、空串、非 Map、无 scheme 一律返回 null', () {
      expect(QuarkMapper.parseDirectUrl(const {}), isNull);
      expect(QuarkMapper.parseDirectUrl({'download_url': ''}), isNull);
      expect(QuarkMapper.parseDirectUrl('https://x.com/a'), isNull);
      expect(QuarkMapper.parseDirectUrl(null), isNull);
      expect(QuarkMapper.parseDirectUrl({'download_url': '/relative/path'}), isNull);
    });
  });

  group('parseUrlExpiry', () {
    test('download 路由 auth_key —— <过期秒>-3-<TTL秒>-<签名>', () {
      // 实测样本（2026-09-23）：auth_key=1790173162-3-21600-e84ee84e...
      // 1790173162 = 2026-09-23 22:19:22 +08:00，21600 秒 = 6 小时
      final uri = Uri.parse(
        'https://dl-pc-sz.drive.quark.cn/a/b?auth_key=1790173162-3-21600-e84ee84e156ef6f5',
      );
      final exp = QuarkMapper.parseUrlExpiry(uri)!;
      // 用 epoch 毫秒比较，避免测试依赖运行机器的时区
      expect(exp.millisecondsSinceEpoch, 1790173162 * 1000);
    });

    test('audioplay 路由 auth_key —— 第 2、3 段与 download 不同，仍只取第 1 段', () {
      // 实测样本（2026-09-24）：
      //   download  15.1MB → 1790235226-15500-21600-<sig>   （TTL 6h）
      //   audioplay 15.1MB → 1790224426-15500-10800-<sig>   （TTL 3h）
      //   audioplay 774MB  → 1790232030-792656-18404-<sig>  （TTL 5.11h）
      // 第 3 段的 TTL 随路由与文件变化，**不能**拿它反推过期时刻。
      final uri = Uri.parse(
        'https://video-play-c-sz.drive.quark.cn/f/play'
        '?auth_key=1790224426-15500-10800-sig',
      );
      expect(
        QuarkMapper.parseUrlExpiry(uri)!.millisecondsSinceEpoch ~/ 1000,
        1790224426,
      );
    });

    test('auth_key 优先级高于通用候选名', () {
      final uri = Uri.parse(
        'https://x.com/a?auth_key=1790173162-3-21600-sig&exp=1',
      );
      // exp=1 是 1970 年的脏数据，不应被选中
      expect(
        QuarkMapper.parseUrlExpiry(uri)!.millisecondsSinceEpoch ~/ 1000,
        1790173162,
      );
    });

    test('auth_key 首段非法时回落到通用候选名', () {
      final exp = DateTime.utc(2026, 9, 23, 13);
      final uri = Uri.parse(
        'https://x.com/a?auth_key=notanumber-3-21600-sig'
        '&Expires=${exp.millisecondsSinceEpoch ~/ 1000}',
      );
      expect(QuarkMapper.parseUrlExpiry(uri)!.toUtc(), exp);
    });

    test('Expires（秒）', () {
      final exp = DateTime.utc(2026, 9, 23, 13);
      final uri = Uri.parse(
        'https://x.com/a?Expires=${exp.millisecondsSinceEpoch ~/ 1000}',
      );
      expect(QuarkMapper.parseUrlExpiry(uri)!.toUtc(), exp);
    });

    test('Expires（毫秒）', () {
      final exp = DateTime.utc(2026, 9, 23, 13);
      final uri = Uri.parse('https://x.com/a?Expires=${exp.millisecondsSinceEpoch}');
      expect(QuarkMapper.parseUrlExpiry(uri)!.toUtc(), exp);
    });

    test('exp / e 等候选名', () {
      final exp = DateTime.utc(2026, 9, 23, 13);
      final s = exp.millisecondsSinceEpoch ~/ 1000;
      expect(QuarkMapper.parseUrlExpiry(Uri.parse('https://x.com/a?exp=$s')), isNotNull);
      expect(QuarkMapper.parseUrlExpiry(Uri.parse('https://x.com/a?e=$s')), isNotNull);
    });

    test('无可解析参数时返回 null（由调用方套兜底 TTL）', () {
      expect(QuarkMapper.parseUrlExpiry(Uri.parse('https://x.com/a')), isNull);
      expect(QuarkMapper.parseUrlExpiry(Uri.parse('https://x.com/a?sign=abc')), isNull);
      expect(QuarkMapper.parseUrlExpiry(Uri.parse('https://x.com/a?t=abc')), isNull);
      // 1970 年，视为脏数据
      expect(QuarkMapper.parseUrlExpiry(Uri.parse('https://x.com/a?t=1')), isNull);
    });
  });

  group('toStreamTicket', () {
    final now = DateTime(2026, 9, 23, 12);

    test('必须带上 Cookie —— 缺了直链会返回 412', () {
      final ticket = QuarkMapper.toStreamTicket(
        url: Uri.parse('https://dl.x/a'),
        cookieHeader: '__pus=aaa; __puus=bbb',
        now: now,
      );
      expect(ticket.headers['Cookie'], '__pus=aaa; __puus=bbb');
      expect(ticket.needsHeaders, isTrue);
    });

    test('同时带上 UA / Referer（PoC 实测的有效组合）', () {
      final ticket = QuarkMapper.toStreamTicket(
        url: Uri.parse('https://dl.x/a'),
        cookieHeader: '__pus=aaa',
        now: now,
      );
      expect(ticket.headers['User-Agent'], QuarkEndpoints.userAgent);
      expect(ticket.headers['Referer'], QuarkEndpoints.referer);
      expect(ticket.headers['Accept'], '*/*');
    });

    test('无 Cookie 时不塞空的 Cookie 头', () {
      final ticket = QuarkMapper.toStreamTicket(
        url: Uri.parse('https://dl.x/a'),
        cookieHeader: '',
        now: now,
      );
      expect(ticket.headers.containsKey('Cookie'), isFalse);
    });

    test('解析不出过期时间时套兜底 TTL（宁可提前刷新）', () {
      final ticket = QuarkMapper.toStreamTicket(
        url: Uri.parse('https://dl.x/a'),
        cookieHeader: 'c=1',
        now: now,
      );
      // 兜底 TTL 精确等于约定的 15 分钟
      expect(
        ticket.expiresAt!.difference(now),
        QuarkEndpoints.ticketFallbackTtl,
      );
    });

    test('能解析出过期时间时以解析值为准', () {
      final exp = DateTime.utc(2026, 9, 23, 13);
      final ticket = QuarkMapper.toStreamTicket(
        url: Uri.parse('https://dl.x/a?Expires=${exp.millisecondsSinceEpoch ~/ 1000}'),
        cookieHeader: 'c=1',
        now: now,
      );
      expect(ticket.expiresAt!.toUtc(), exp);
    });

    test('真实夸克直链：从 auth_key 解析出 6 小时有效期', () {
      // 实测样本：auth_key=1790173162-3-21600-<签名>
      final ticket = QuarkMapper.toStreamTicket(
        url: Uri.parse(
          'https://dl-pc-sz.drive.quark.cn/hENCPjKd/922653933/abc'
          '?auth_key=1790173162-3-21600-sig&sp=100&filename=a.flac',
        ),
        cookieHeader: 'c=1',
        now: now,
      );
      expect(ticket.expiresAt!.millisecondsSinceEpoch, 1790173162 * 1000);
      // 拿到真实过期时间后不应再套兜底 TTL
      expect(
        ticket.expiresAt!.difference(now),
        isNot(QuarkEndpoints.ticketFallbackTtl),
      );
    });

    test('透传体积与 MIME，支持 Range', () {
      final ticket = QuarkMapper.toStreamTicket(
        url: Uri.parse('https://dl.x/a'),
        cookieHeader: 'c=1',
        contentLength: 31457280,
        contentType: 'audio/flac',
        now: now,
      );
      expect(ticket.contentLength, 31457280);
      expect(ticket.contentType, 'audio/flac');
      expect(ticket.supportsRange, isTrue);
    });

    test('toString 不泄漏签名', () {
      final ticket = QuarkMapper.toStreamTicket(
        url: Uri.parse('https://dl.x/a?sign=SECRET'),
        cookieHeader: 'c=1',
        now: now,
      );
      expect(ticket.toString().contains('SECRET'), isFalse);
    });
  });
}
