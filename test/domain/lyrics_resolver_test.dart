import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudtune/core/error/drive_error.dart';
import 'package:cloudtune/data/db/app_database.dart';
import 'package:cloudtune/data/db/library_repository_impl.dart';
import 'package:cloudtune/data/http/http_client.dart';
import 'package:cloudtune/data/lyrics/lrclib_client.dart';
import 'package:cloudtune/data/registry/drive_adapter_registry.dart';
import 'package:cloudtune/domain/adapters/cloud_drive_adapter.dart';
import 'package:cloudtune/domain/entities/auth_credential.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/cloud_account.dart';
import 'package:cloudtune/domain/entities/drive_entry.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/lyrics.dart';
import 'package:cloudtune/domain/entities/stream_ticket.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/domain/services/lyrics_resolver.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_http_client.dart';

/// 只实现读文件能力的假网盘。
///
/// Dart 不允许在函数体里声明 class，所以它必须放在顶层。
class FakeAdapter extends CloudDriveAdapter {
  FakeAdapter({this.bytes = const {}});

  Map<String, List<int>> bytes;

  /// 非空时 `readFileBytes` 一律抛这个类型的错误
  DriveErrorType? failWith;

  final List<String> readCalls = [];

  @override
  DriveProvider get provider => DriveProvider.quark;

  @override
  String get rootId => 'root';

  @override
  Capabilities get capabilities => Capabilities(provider: DriveProvider.quark);

  @override
  Future<Uint8List> readFileBytes(
    String fileId, {
    int maxBytes = 512 * 1024,
  }) async {
    readCalls.add(fileId);
    final type = failWith;
    if (type != null) {
      throw DriveException(type: type, message: '读文件失败：$fileId');
    }
    final data = bytes[fileId];
    if (data == null) {
      throw const DriveException(
        type: DriveErrorType.notFound,
        message: '无此文件',
      );
    }
    return Uint8List.fromList(data);
  }

  @override
  Future<DrivePage> listDirectory({
    required String dirId,
    String? pageToken,
    int? pageSize,
  }) async =>
      const DrivePage.empty();

  @override
  Future<List<DriveEntry>> search({
    required String keyword,
    int limit = 100,
    int offset = 0,
  }) async =>
      const [];

  @override
  Future<StreamTicket> resolveStream(String fileId) async =>
      throw UnimplementedError();

  @override
  Future<CloudAccount?> restoreSession() async => null;

  @override
  Future<CloudAccount> authorize(AuthCredential credential) async =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> ping() async => true;

  @override
  Future<void> dispose() async {}
}

/// 播放时的歌词解析。
///
/// 重点全在**失败路径**上：「本地 .lrc 读不到时该不该删引用」「网络不通时
/// 会不会每次都卡半分钟」这类判断写错，表现都是「歌词时有时无」——
/// 从现象根本反推不出原因。
void main() {
  late AppDatabase db;
  late DriftLibraryRepository repo;
  late FakeAdapter adapter;
  late FakeHttpClient http;

  Track track({
    String remoteId = 'f1',
    String name = '周杰伦 - 晴天.flac',
    String? title,
    String? artist,
    int? durationMs,
  }) =>
      Track(
        provider: DriveProvider.quark,
        remoteId: remoteId,
        name: name,
        title: title,
        artist: artist,
        durationMs: durationMs,
      );

  LyricsResolver buildResolver() => LyricsResolver(
        library: repo,
        registry: DefaultDriveAdapterRegistry([adapter]),
        lrclib: LrclibClient(
          http: http,
          minInterval: Duration.zero,
          retryDelay: Duration.zero,
        ),
      );

  Lyrics localRef(String trackId, {String fileId = 'lrc1'}) => Lyrics(
        trackId: trackId,
        provider: DriveProvider.quark,
        source: LyricsSource.local,
        fileId: fileId,
        fileName: '晴天.lrc',
      );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftLibraryRepository(db);
    adapter = FakeAdapter();
    http = FakeHttpClient.throwing(Exception('测试里不该发网络请求'));
  });
  tearDown(() => db.close());

  group('库里有正文', () {
    test('直接返回，既不读网盘也不联网', () async {
      final t = track();
      await repo.upsertLyrics([
        localRef(t.id).copyWith(content: '[00:01.00]晴天'),
      ]);

      final result = await buildResolver().resolve(t, allowNetwork: true);

      expect(result!.content, '[00:01.00]晴天');
      expect(result.isSynced, isTrue);
      expect(adapter.readCalls, isEmpty, reason: '正文已经在库里了');
      expect(http.callCount, 0);
    });
  });

  group('本地 .lrc 懒读', () {
    test('首次播放时读下来并回写库', () async {
      final t = track();
      await repo.upsertLyrics([localRef(t.id)]);
      adapter.bytes = {'lrc1': utf8.encode('[00:01.00]故事的小黄花')};

      final result = await buildResolver().resolve(t, allowNetwork: false);

      expect(result!.content, '[00:01.00]故事的小黄花');
      expect(result.source, LyricsSource.local);
      expect(adapter.readCalls, ['lrc1']);
      expect((await repo.lyricsFor(t.id))!.content, '[00:01.00]故事的小黄花');
    });

    test('第二次播放不再读网盘（正文已落库）', () async {
      final t = track();
      await repo.upsertLyrics([localRef(t.id)]);
      adapter.bytes = {'lrc1': utf8.encode('[00:01.00]A')};

      final resolver = buildResolver();
      await resolver.resolve(t, allowNetwork: false);
      await resolver.resolve(t, allowNetwork: false);

      expect(adapter.readCalls, hasLength(1));
    });

    test('GBK 编码的歌词能正确解出来', () async {
      final t = track();
      await repo.upsertLyrics([localRef(t.id)]);
      // `[00:01.00]晴天` 里「晴天」的 GBK 字节
      adapter.bytes = {
        'lrc1': [0x5B, 0x30, 0x30, 0x3A, 0x30, 0x31, 0x2E, 0x30, 0x30, 0x5D,
          0xC7, 0xE7, 0xCC, 0xEC],
      };

      final result = await buildResolver().resolve(t, allowNetwork: false);
      expect(result!.content, '[00:01.00]晴天');
    });

    test('本地歌词读得出来时就不去联网（本地优先）', () async {
      final t = track();
      await repo.upsertLyrics([localRef(t.id)]);
      adapter.bytes = {'lrc1': utf8.encode('[00:01.00]本地的')};

      await buildResolver().resolve(t, allowNetwork: true);

      expect(http.callCount, 0);
    });

    test('文件已经没了：清掉引用，避免每次播放都白试一次', () async {
      final t = track();
      await repo.upsertLyrics([localRef(t.id)]);
      adapter.bytes = {}; // 读的时候网盘上说没这个文件

      final result = await buildResolver().resolve(t, allowNetwork: false);

      expect(result, isNull);
      expect(await repo.lyricsFor(t.id), isNull, reason: '引用要清掉');
    });

    test('空文件也当成「没了」', () async {
      final t = track();
      await repo.upsertLyrics([localRef(t.id)]);
      adapter.bytes = {'lrc1': const []};

      await buildResolver().resolve(t, allowNetwork: false);

      expect(await repo.lyricsFor(t.id), isNull);
    });

    test('**暂时性**失败（权限/超时）保留引用，下次再试', () async {
      // 把所有失败都当成「文件没了」的话，一次网络抖动就会把用户全部本地
      // 歌词的引用删掉 —— 而下一次扫描才会重新发现它们。
      final t = track();
      await repo.upsertLyrics([localRef(t.id)]);
      adapter.failWith = DriveErrorType.permissionDenied;

      final result = await buildResolver().resolve(t, allowNetwork: false);

      expect(result, isNull);
      expect(await repo.lyricsFor(t.id), isNotNull, reason: '引用要留着');
    });

    test('网盘不支持读文件时也保留引用', () async {
      final t = track();
      await repo.upsertLyrics([localRef(t.id)]);
      adapter.failWith = DriveErrorType.unsupported;

      await buildResolver().resolve(t, allowNetwork: false);

      expect(await repo.lyricsFor(t.id), isNotNull);
    });

    test('文件读到了但给不出歌词（只有空白）：清掉引用，而不是记一条空正文', () async {
      // 记空正文的话，等网盘上那个文件后来补上了内容，upsert 会因为
      // 「fileId 没变」把空正文留住 —— 用户就永远卡在「没有歌词」上，
      // 而且重扫也救不回来。清掉引用则下次扫描会重新发现它。
      final t = track();
      await repo.upsertLyrics([localRef(t.id)]);
      adapter.bytes = {'lrc1': utf8.encode('   \n\n  ')};

      final result = await buildResolver().resolve(t, allowNetwork: false);

      expect(result, isNull);
      expect(await repo.lyricsFor(t.id), isNull);
    });

    test('只有标签、没有正文的文件同样清掉引用', () async {
      final t = track();
      await repo.upsertLyrics([localRef(t.id)]);
      adapter.bytes = {'lrc1': utf8.encode('[ti:晴天]\n[ar:周杰伦]')};

      expect(await buildResolver().resolve(t, allowNetwork: false), isNull);
      expect(await repo.lyricsFor(t.id), isNull);
    });

    test('纯文本（没有时间轴）的歌词是能用的', () async {
      final t = track();
      await repo.upsertLyrics([localRef(t.id)]);
      adapter.bytes = {'lrc1': utf8.encode('第一句\n第二句')};

      final result = await buildResolver().resolve(t, allowNetwork: false);

      expect(result!.hasContent, isTrue);
      expect(result.isSynced, isFalse, reason: '没有时间轴，只能静态展示');
      expect(result.document.plainText, '第一句\n第二句');
    });

    test('网盘未注册时保留引用，不误删', () async {
      final t = track();
      await repo.upsertLyrics([localRef(t.id)]);

      final resolver = LyricsResolver(
        library: repo,
        registry: DefaultDriveAdapterRegistry(const []),
        lrclib: LrclibClient(http: http, minInterval: Duration.zero),
      );
      final result = await resolver.resolve(t, allowNetwork: false);

      expect(result, isNull);
      expect(await repo.lyricsFor(t.id), isNotNull);
    });
  });

  group('联网歌词', () {
    Map<String, Object?> payload({
      String trackName = '晴天',
      String? artistName = '周杰伦',
      int? duration = 269,
      bool instrumental = false,
      String? synced = '[00:01.00]故事的小黄花',
    }) =>
        {
          'trackName': trackName,
          'artistName': artistName,
          'duration': duration,
          'instrumental': instrumental,
          'plainLyrics': null,
          'syncedLyrics': synced,
        };

    test('开关关闭时一次请求都不发', () async {
      final t = track();
      http = FakeHttpClient.always(HttpResult(statusCode: 200, json: payload()));

      final result = await buildResolver().resolve(t, allowNetwork: false);

      expect(result, isNull);
      expect(http.callCount, 0, reason: '默认关闭就是不联网，不是「联网但不用」');
    });

    test('开关打开时查到并落库', () async {
      final t = track(durationMs: 269000);
      http = FakeHttpClient.always(HttpResult(statusCode: 200, json: payload()));

      final result = await buildResolver().resolve(t, allowNetwork: true);

      expect(result, isNotNull);
      expect(result!.source, LyricsSource.lrclib);
      expect(result.content, '[00:01.00]故事的小黄花');
      expect(result.isSynced, isTrue);

      final saved = await repo.lyricsFor(t.id);
      expect(saved!.source, LyricsSource.lrclib);
      expect(saved.content, '[00:01.00]故事的小黄花');
    });

    test('时长取自曲目元数据', () async {
      final t = track(durationMs: 269000);
      http = FakeHttpClient.always(HttpResult(statusCode: 200, json: payload()));

      await buildResolver().resolve(t, allowNetwork: true);

      expect(http.lastRequest.query!['duration'], 269);
    });

    test('时长未知时**不带** duration（带了会把能查到的变成 404）', () async {
      final t = track(); // durationMs 为 null
      http = FakeHttpClient.always(HttpResult(statusCode: 200, json: payload()));

      await buildResolver().resolve(t, allowNetwork: true);

      expect(http.lastRequest.query!.containsKey('duration'), isFalse);
    });

    test('查不到时不落库（下次播放还会再试）', () async {
      final t = track();
      http = FakeHttpClient.always(
        const HttpResult(statusCode: 404, rawBody: 'Not Found'),
      );

      final result = await buildResolver().resolve(t, allowNetwork: true);

      expect(result, isNull);
      expect(await repo.lyricsFor(t.id), isNull);
    });

    test('纯音乐：落库并带上标志', () async {
      final t = track();
      http = FakeHttpClient.always(HttpResult(
        statusCode: 200,
        json: payload(instrumental: true, synced: null),
      ));

      final result = await buildResolver().resolve(t, allowNetwork: true);

      expect(result!.instrumental, isTrue);
      expect(result.hasContent, isFalse);
      expect(result.isDisplayable, isTrue, reason: '要能显示「纯音乐，无歌词」');
      expect((await repo.lyricsFor(t.id))!.instrumental, isTrue);
    });

    test('联网取到的歌词第二次播放直接用库里的，不再打接口', () async {
      final t = track();
      http = FakeHttpClient.always(HttpResult(statusCode: 200, json: payload()));

      final resolver = buildResolver();
      await resolver.resolve(t, allowNetwork: true);
      await resolver.resolve(t, allowNetwork: true);

      expect(http.callCount, 1);
    });

    test('断网时返回 null，不抛异常', () async {
      final t = track();
      http = FakeHttpClient.throwing(Exception('offline'));

      expect(await buildResolver().resolve(t, allowNetwork: true), isNull);
    });
  });

  group('边角', () {
    test('库里没有这一首、也没联网：返回 null', () async {
      expect(await buildResolver().resolve(track(), allowNetwork: false), isNull);
    });

    test('库里那一行是联网来源但正文为 null（不该出现的状态）也不炸', () async {
      final t = track();
      await repo.upsertLyrics([
        Lyrics(
          trackId: t.id,
          provider: DriveProvider.quark,
          source: LyricsSource.lrclib,
        ),
      ]);
      http = FakeHttpClient.always(
        const HttpResult(statusCode: 404, rawBody: 'Not Found'),
      );

      expect(await buildResolver().resolve(t, allowNetwork: true), isNull);
    });

    test('CUE 分段各查各的（同一 remoteId 不会串）', () async {
      final seg1 = Track(
        provider: DriveProvider.quark,
        remoteId: 'wav1',
        name: '专辑.wav',
        cueTrackNo: 1,
        cueStartMs: 0,
        title: '红日',
      );
      final seg2 = Track(
        provider: DriveProvider.quark,
        remoteId: 'wav1',
        name: '专辑.wav',
        cueTrackNo: 2,
        cueStartMs: 200000,
        title: '月半小夜曲',
      );

      await repo.upsertLyrics([
        Lyrics(
          trackId: seg1.id,
          provider: DriveProvider.quark,
          source: LyricsSource.local,
          fileId: 'l1',
        ),
      ]);
      adapter.bytes = {'l1': utf8.encode('[00:01.00]红日')};

      final resolver = buildResolver();
      expect((await resolver.resolve(seg1, allowNetwork: false))!.content,
          '[00:01.00]红日');
      expect(await resolver.resolve(seg2, allowNetwork: false), isNull);
    });
  });
}
