import 'package:cloudtune/core/error/drive_error.dart';
import 'package:cloudtune/data/auth/memory_credential_store.dart';
import 'package:cloudtune/data/http/http_client.dart';
import 'package:cloudtune/data/http/token_bucket.dart';
import 'package:cloudtune/data/remote/quark/quark_adapter.dart';
import 'package:cloudtune/data/remote/quark/quark_endpoints.dart';
import 'package:cloudtune/domain/entities/auth_credential.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_http_client.dart';

/// 测试用限流器：速率极高、桶极大，不产生任何等待。
TokenBucket fastBucket() => TokenBucket(ratePerSecond: 100000, burst: 1000);

AuthCredential quarkCredential({String pus = 'aaa', String puus = 'bbb'}) =>
    AuthCredential(
      provider: DriveProvider.quark,
      mode: AuthMode.browserCookie,
      capturedAt: DateTime(2026, 9, 23),
      cookies: {'__pus': pus, '__puus': puus},
    );

void main() {
  late InMemoryCredentialStore store;

  setUp(() => store = InMemoryCredentialStore());

  QuarkAdapter build(
    HttpClientLike http, {
    TokenBucket? listBucket,
    TokenBucket? linkBucket,
  }) =>
      QuarkAdapter(
        http: http,
        credentialStore: store,
        listBucket: listBucket ?? fastBucket(),
        linkBucket: linkBucket ?? fastBucket(),
      );

  group('能力与身份', () {
    test('provider / rootId / capabilities 正确', () {
      final adapter = build(FakeHttpClient.always(quarkOk(null)));
      expect(adapter.provider, DriveProvider.quark);
      expect(adapter.rootId, '0');
      expect(adapter.capabilities.provider, DriveProvider.quark);
      expect(adapter.capabilities.canListDirectory, isTrue);
      expect(adapter.capabilities.canSearch, isTrue);
      expect(adapter.capabilities.directLinkNeedsHeaders, isTrue);
      expect(adapter.capabilities.supportsRangeRequests, isTrue);
      // ⚠️ 刻意**不**声明体积上限：50MiB 是 /file/download 的限制，
      // 播放走 /file/audioplay 不受此限。填上会让 43.9% 的曲目被误判。
      // 详见 Capabilities.maxSingleFileBytes 的注释与 resolveStream 的用例。
      expect(adapter.capabilities.maxSingleFileBytes, isNull);
      expect(adapter.capabilities.hasFileSizeLimit, isFalse);
      // 扫码是主链路，必须声明；否则「支持哪些授权方式」会与授权页自相矛盾。
      expect(adapter.capabilities.authModes, contains(AuthMode.qrCode));
      expect(adapter.capabilities.authModes, contains(AuthMode.browserCookie));
      expect(adapter.capabilities.authModes, contains(AuthMode.manualCookie));
    });

    test('未授权时 hasSession 为 false', () {
      final adapter = build(FakeHttpClient.always(quarkOk(null)));
      expect(adapter.hasSession, isFalse);
      expect(adapter.currentAccount, isNull);
    });
  });

  group('restoreSession', () {
    test('无持久化凭证时返回 null，且不发任何请求', () async {
      final http = FakeHttpClient.always(quarkOk(null));
      final adapter = build(http);

      expect(await adapter.restoreSession(), isNull);
      expect(http.callCount, 0);
    });

    test('凭证有效时返回账号信息（昵称 / 容量 / 会员档位）', () async {
      await store.save(quarkCredential());
      final http = FakeHttpClient.always(quarkOk({
        'nickname': '张三',
        'member_type': 'SUPER_VIP',
        'use_capacity': 100,
        'total_capacity': 400,
      }));
      final adapter = build(http);

      final account = (await adapter.restoreSession())!;
      expect(account.provider, DriveProvider.quark);
      expect(account.displayName, '张三');
      expect(account.memberLabel, 'SUPER_VIP');
      expect(account.storageUsedBytes, 100);
      expect(account.storageTotalBytes, 400);
      expect(adapter.hasSession, isTrue);
    });

    test('请求带上了 Cookie 与公共参数 pr/fr', () async {
      await store.save(quarkCredential(pus: 'PUS', puus: 'PUUS'));
      final http = FakeHttpClient.always(quarkOk(const {}));
      await build(http).restoreSession();

      final req = http.lastRequest;
      expect(req.headers!['Cookie'], '__pus=PUS; __puus=PUUS');
      expect(req.param('pr'), 'ucpro');
      expect(req.param('fr'), 'pc');
      expect(req.url, contains(QuarkEndpoints.member));
    });

    test('凭证已失效时抛 unauthorized（而非静默返回 null）', () async {
      await store.save(quarkCredential());
      final http = FakeHttpClient.always(quarkError(31001, message: 'require login [guest]'));
      final adapter = build(http);

      await expectLater(
        adapter.restoreSession(),
        throwsA(
          isA<DriveException>()
              .having((e) => e.type, 'type', DriveErrorType.unauthorized)
              .having((e) => e.needsReauth, 'needsReauth', isTrue),
        ),
      );
    });
  });

  group('authorize', () {
    test('空凭证直接拒绝，不发请求', () async {
      final http = FakeHttpClient.always(quarkOk(null));
      final adapter = build(http);

      await expectLater(
        adapter.authorize(AuthCredential(
          provider: DriveProvider.quark,
          mode: AuthMode.manualCookie,
          capturedAt: DateTime(2026, 9, 23),
        )),
        throwsA(isA<DriveException>()
            .having((e) => e.type, 'type', DriveErrorType.unauthorized)),
      );
      expect(http.callCount, 0);
    });

    test('校验通过后落库，并返回账号', () async {
      final http = FakeHttpClient.always(quarkOk({'nickname': '李四'}));
      final adapter = build(http);

      final account = await adapter.authorize(quarkCredential());
      expect(account.displayName, '李四');
      expect(await store.load(DriveProvider.quark), isNotNull);
      expect((await store.load(DriveProvider.quark))!.cookies['__pus'], 'aaa');
    });

    test('校验失败时不落库（避免把废凭证写进钥匙串）', () async {
      final http = FakeHttpClient.always(quarkError(31004, message: 'token invalid'));
      final adapter = build(http);

      await expectLater(
        adapter.authorize(quarkCredential()),
        throwsA(isA<DriveException>()),
      );
      expect(await store.load(DriveProvider.quark), isNull);
      expect(adapter.hasSession, isFalse);
      expect(adapter.currentAccount, isNull);
    });

    test('网络故障时不落库', () async {
      final http = FakeHttpClient.always(const HttpResult.networkFailure('boom'));
      final adapter = build(http);

      await expectLater(
        adapter.authorize(quarkCredential()),
        throwsA(isA<DriveException>()
            .having((e) => e.type, 'type', DriveErrorType.network)),
      );
      expect(await store.load(DriveProvider.quark), isNull);
    });
  });

  group('signOut / dispose', () {
    test('signOut 清空内存会话与持久化凭证', () async {
      await store.save(quarkCredential());
      final adapter = build(FakeHttpClient.always(quarkOk(const {})));
      await adapter.restoreSession();
      expect(adapter.hasSession, isTrue);

      await adapter.signOut();
      expect(adapter.hasSession, isFalse);
      expect(adapter.currentAccount, isNull);
      expect(await store.load(DriveProvider.quark), isNull);
    });

    test('dispose 关闭 HTTP 客户端', () async {
      final http = FakeHttpClient.always(quarkOk(null));
      await build(http).dispose();
      expect(http.closed, isTrue);
    });
  });

  group('listDirectory', () {
    Future<QuarkAdapter> authorized(FakeHttpClient http) async {
      await store.save(quarkCredential());
      final adapter = build(http);
      await adapter.restoreSession();
      return adapter;
    }

    test('请求参数与 PoC 实测一致', () async {
      final http = FakeHttpClient.always(
        quarkOk(quarkListPage([quarkDirItem(fid: 'd1', name: '华语')], total: 1)),
      );
      final adapter = await authorized(http);
      await adapter.listDirectory(dirId: '0');

      final req = http.requestsTo(QuarkEndpoints.fileSort).single;
      expect(req.param('pdir_fid'), '0');
      expect(req.param('_page'), 1);
      expect(req.param('_size'), 50);
      // 没有 _fetch_total 就拿不到 data.total，分页会退化
      expect(req.param('_fetch_total'), 1);
      expect(req.param('_sort'), QuarkEndpoints.defaultSort);
      expect(req.param('_is_hl'), 1);
      expect(req.param('pr'), 'ucpro');
      expect(req.param('fr'), 'pc');
    });

    test('映射条目为 DriveEntry', () async {
      final http = FakeHttpClient.always(quarkOk(quarkListPage([
        quarkDirItem(fid: 'd1', name: '华语'),
        quarkFileItem(fid: 'f1', name: '晴天.flac', size: 31457280, formatType: 'audio/flac'),
      ], total: 2)));
      final adapter = await authorized(http);

      final page = await adapter.listDirectory(dirId: '0');
      expect(page.entries.length, 2);
      expect(page.directories.map((e) => e.name), ['华语']);
      expect(page.files.map((e) => e.name), ['晴天.flac']);
      expect(page.total, 2);
    });

    test('total 大于本页时给出下一页游标', () async {
      final http = FakeHttpClient.always(
        quarkOk(quarkListPage(
          List.generate(50, (i) => quarkFileItem(fid: 'f$i', name: 'a$i.mp3')),
          total: 120,
        )),
      );
      final adapter = await authorized(http);

      final page = await adapter.listDirectory(dirId: '0');
      expect(page.nextPageToken, '2');
      expect(page.hasMore, isTrue);
    });

    test('最后一页不再给出游标', () async {
      final http = FakeHttpClient.always(
        quarkOk(quarkListPage(
          List.generate(20, (i) => quarkFileItem(fid: 'f$i', name: 'a$i.mp3')),
          total: 120,
        )),
      );
      final adapter = await authorized(http);

      final page = await adapter.listDirectory(dirId: '0', pageToken: '3');
      expect(page.nextPageToken, isNull);
      expect(page.hasMore, isFalse);
    });

    test('无 total 时按「本页是否满页」兜底判断', () async {
      final http = FakeHttpClient.always(HttpResult(
        statusCode: 200,
        json: {
          'code': 0,
          'data': {
            'list': List.generate(50, (i) => quarkFileItem(fid: 'f$i', name: 'a$i.mp3')),
          },
        },
      ));
      final adapter = await authorized(http);

      final page = await adapter.listDirectory(dirId: '0');
      expect(page.total, isNull);
      expect(page.nextPageToken, '2');
    });

    test('空目录返回空页且无游标', () async {
      final http = FakeHttpClient.always(quarkOk(quarkListPage([], total: 0)));
      final adapter = await authorized(http);

      final page = await adapter.listDirectory(dirId: 'd9');
      expect(page.isEmpty, isTrue);
      expect(page.nextPageToken, isNull);
    });

    test('dirId 为空串时回落到根目录 0', () async {
      final http = FakeHttpClient.always(quarkOk(quarkListPage([], total: 0)));
      final adapter = await authorized(http);
      await adapter.listDirectory(dirId: '');

      expect(http.lastRequest.param('pdir_fid'), '0');
    });

    test('自定义 pageSize 生效', () async {
      final http = FakeHttpClient.always(quarkOk(quarkListPage([], total: 0)));
      final adapter = await authorized(http);
      await adapter.listDirectory(dirId: '0', pageSize: 100);

      expect(http.lastRequest.param('_size'), 100);
    });

    test('非法 pageToken 回落到第 1 页（不崩）', () async {
      final http = FakeHttpClient.always(quarkOk(quarkListPage([], total: 0)));
      final adapter = await authorized(http);

      await adapter.listDirectory(dirId: '0', pageToken: 'abc');
      expect(http.lastRequest.param('_page'), 1);

      await adapter.listDirectory(dirId: '0', pageToken: '-3');
      expect(http.lastRequest.param('_page'), 1);
    });

    test('未授权时抛 unauthorized，且不发请求', () async {
      final http = FakeHttpClient.always(quarkOk(quarkListPage([])));
      final adapter = build(http);

      await expectLater(
        adapter.listDirectory(dirId: '0'),
        throwsA(isA<DriveException>()
            .having((e) => e.type, 'type', DriveErrorType.unauthorized)),
      );
      expect(http.callCount, 0);
    });

    test('列目录返回 31004 时向上抛 unauthorized', () async {
      final http = FakeHttpClient.sequence([
        quarkOk(const {}), // restoreSession 的 /member
        quarkError(31004, message: 'token invalid'),
      ]);
      final adapter = await authorized(http);

      await expectLater(
        adapter.listDirectory(dirId: '0'),
        throwsA(isA<DriveException>()
            .having((e) => e.type, 'type', DriveErrorType.unauthorized)),
      );
    });
  });

  group('search', () {
    Future<QuarkAdapter> authorized(FakeHttpClient http) async {
      await store.save(quarkCredential());
      final adapter = build(http);
      await adapter.restoreSession();
      return adapter;
    }

    test('空关键词直接返回空，不发请求', () async {
      final http = FakeHttpClient.always(quarkOk(quarkListPage([])));
      final adapter = await authorized(http);
      final before = http.callCount;

      expect(await adapter.search(keyword: '   '), isEmpty);
      expect(http.callCount, before);
    });

    test('关键词与分页参数正确，且关键词被 trim', () async {
      final http = FakeHttpClient.always(quarkOk(quarkListPage([
        quarkFileItem(fid: 'f1', name: '晴天.flac', size: 1000),
      ])));
      final adapter = await authorized(http);

      final results = await adapter.search(keyword: '  周杰伦  ', limit: 50);
      expect(results.single.name, '晴天.flac');

      final req = http.requestsTo(QuarkEndpoints.fileSearch).single;
      expect(req.param('_key'), '周杰伦');
      expect(req.param('_page'), 1);
      expect(req.param('_size'), 50);
      expect(req.param('_fetch_total'), 1);
      // 文件优先排序 —— 实测 file_type:asc 时前 20 条全是目录
      expect(req.param('_sort'), QuarkEndpoints.searchSort);
      expect(req.param('_sort'), contains('file_type:desc'));
    });

    test('搜索会返回目录（夸克实测），调用方需自行过滤', () async {
      final http = FakeHttpClient.always(quarkOk(quarkListPage([
        quarkDirItem(fid: 'd1', name: '某个目录'),
        quarkFileItem(fid: 'f1', name: '晴天.flac', size: 1000),
      ])));
      final adapter = await authorized(http);

      final results = await adapter.search(keyword: 'flac');
      // 适配器如实返回，不擅自过滤
      expect(results.length, 2);
      expect(results.where((e) => e.isDirectory).length, 1);
      expect(results.where((e) => e.isFile).map((e) => e.name), ['晴天.flac']);
    });

    test('offset 换算成页码', () async {
      final http = FakeHttpClient.always(quarkOk(quarkListPage([])));
      final adapter = await authorized(http);

      await adapter.search(keyword: 'flac', limit: 50, offset: 100);
      expect(http.lastRequest.param('_page'), 3);
    });
  });

  group('resolveStream', () {
    Future<QuarkAdapter> authorized(FakeHttpClient http) async {
      await store.save(quarkCredential(pus: 'PUS', puus: 'PUUS'));
      final adapter = build(http);
      await adapter.restoreSession();
      return adapter;
    }

    // -----------------------------------------------------------------
    // 主路径：/1/clouddrive/file/audioplay
    // -----------------------------------------------------------------

    test('主路径走 GET /file/audioplay?fid=，并解析 audio_url', () async {
      final http = FakeHttpClient.sequence([
        quarkOk(const {}),
        quarkOk({
          'audio_url':
              'https://video-play-c-sz.drive.quark.cn/f/play?auth_key=1-2-3-sig',
          'size': 198018943,
          'format_type': 'audio/x-flac',
        }),
      ]);
      final adapter = await authorized(http);

      final ticket = await adapter.resolveStream('f1');
      expect(ticket.url.host, 'video-play-c-sz.drive.quark.cn');
      // 关键：必须带 Cookie，否则实测会返回 412
      expect(ticket.headers['Cookie'], '__pus=PUS; __puus=PUUS');
      expect(ticket.contentLength, 198018943);
      expect(ticket.contentType, 'audio/x-flac');
      expect(ticket.supportsRange, isTrue);

      final req = http.requestsTo(QuarkEndpoints.fileAudioplay).single;
      expect(req.method, 'GET');
      expect(req.param('fid'), 'f1');
      expect(req.param('pr'), 'ucpro');
      // 主路径成功就不该再打 download
      expect(http.requestsTo(QuarkEndpoints.fileDownload), isEmpty);
    });

    test('188.8MB 的 FLAC 走播放路由照样能取到链（回归：50MB 不再是门槛）', () async {
      // 改造前：这个体积走 /file/download 必然返回 23018，
      // 库内 195 首（43.9%）因此被判「超限不可播」。
      final http = FakeHttpClient.sequence([
        quarkOk(const {}),
        quarkOk({
          'audio_url':
              'https://video-play-c-zb.drive.quark.cn/f/play?auth_key=1-2-3-sig',
          'size': 198018943, // 凤凰传奇 - 奇迹世界.flac 的真实体积
        }),
      ]);
      final adapter = await authorized(http);

      final ticket = await adapter.resolveStream('flac188');
      expect(ticket.contentLength, 198018943);
      expect(http.requestsTo(QuarkEndpoints.fileDownload), isEmpty);
    });

    test('774.1MB 的整轨 WAV 也能取到链', () async {
      final http = FakeHttpClient.sequence([
        quarkOk(const {}),
        quarkOk({
          'audio_url':
              'https://video-play-c-zb.drive.quark.cn/f/play?auth_key=1-2-3-sig',
          'size': 811679948,
        }),
      ]);
      final adapter = await authorized(http);

      final ticket = await adapter.resolveStream('wav774');
      expect(ticket.contentLength, 811679948);
    });

    test('DSF 被服务端标成 text/plain / doc 也照样取链（只信 size 与地址）',
        () async {
      // 实测怪癖：audioplay 对 DSF 返回 format_type=text/plain、
      // obj_category=doc、duration=0，但仍给出原文件字节。
      final http = FakeHttpClient.sequence([
        quarkOk(const {}),
        quarkOk({
          'audio_url':
              'https://video-play-c-sz.drive.quark.cn/f/play?auth_key=1-2-3-sig',
          'size': 219652256,
          'format_type': 'text/plain',
          'obj_category': 'doc',
          'duration': 0,
        }),
      ]);
      final adapter = await authorized(http);

      final ticket = await adapter.resolveStream('dsf1');
      expect(ticket.contentLength, 219652256);
      expect(ticket.url.host, 'video-play-c-sz.drive.quark.cn');
    });

    // -----------------------------------------------------------------
    // 兜底路径：/1/clouddrive/file/download
    // -----------------------------------------------------------------

    test('播放路由拿不到地址时，兜底 POST fids 并解析出带 Cookie 的票据', () async {
      final http = FakeHttpClient.sequence([
        quarkOk(const {}),
        // audioplay 返回了对象但没有 audio_url → 视为失败，降级
        quarkOk(const {}),
        quarkOk([
          {
            'download_url': 'https://dl-pc-zb.drive.quark.cn/f/down?sign=SECRET',
            'size': 31457280,
            'format_type': 'audio/flac',
          }
        ]),
      ]);
      final adapter = await authorized(http);

      final ticket = await adapter.resolveStream('f1');
      expect(ticket.url.host, 'dl-pc-zb.drive.quark.cn');
      expect(ticket.headers['Cookie'], '__pus=PUS; __puus=PUUS');
      expect(ticket.contentLength, 31457280);
      expect(ticket.contentType, 'audio/flac');

      final req = http.requestsTo(QuarkEndpoints.fileDownload).single;
      expect(req.method, 'POST');
      expect((req.body as Map)['fids'], ['f1']);
      expect(req.param('pr'), 'ucpro');
    });

    test('播放路由返回业务错误码 → 降级 download', () async {
      final http = FakeHttpClient.sequence([
        quarkOk(const {}),
        quarkError(14001, message: 'param error'),
        quarkOk([
          {
            'download_url': 'https://dl-pc-zb.drive.quark.cn/f/down?sign=SECRET',
            'size': 31457280,
          }
        ]),
      ]);
      final adapter = await authorized(http);

      final ticket = await adapter.resolveStream('f1');
      expect(ticket.url.host, 'dl-pc-zb.drive.quark.cn');
      expect(http.requestsTo(QuarkEndpoints.fileAudioplay), hasLength(1));
      expect(http.requestsTo(QuarkEndpoints.fileDownload), hasLength(1));
    });

    test('两条路由都失败 → 抛出 download 侧的错误（体积超限）', () async {
      final http = FakeHttpClient.sequence([
        quarkOk(const {}),
        quarkError(14001, message: 'param error'),
        quarkError(23018, message: 'download file size limit'),
      ]);
      final adapter = await authorized(http);

      await expectLater(
        adapter.resolveStream('big'),
        throwsA(isA<DriveException>()
            .having((e) => e.type, 'type', DriveErrorType.fileTooLarge)
            .having((e) => e.providerCode, 'providerCode', 23018)),
      );
    });

    // -----------------------------------------------------------------
    // 不该降级的失败：换条路由结果一样，只白费一次配额
    // -----------------------------------------------------------------

    test('播放路由报未授权 → 直接抛出，不浪费一次 download', () async {
      final http = FakeHttpClient.sequence([
        quarkOk(const {}),
        quarkError(31001, message: 'require login [guest]'),
      ]);
      final adapter = await authorized(http);

      await expectLater(
        adapter.resolveStream('f1'),
        throwsA(isA<DriveException>()
            .having((e) => e.type, 'type', DriveErrorType.unauthorized)
            .having((e) => e.needsReauth, 'needsReauth', isTrue)),
      );
      expect(http.requestsTo(QuarkEndpoints.fileDownload), isEmpty);
    });

    test('播放路由报 404 → 直接抛出，不浪费一次 download', () async {
      final http = FakeHttpClient.sequence([
        quarkOk(const {}),
        const HttpResult(statusCode: 404, rawBody: 'not found'),
      ]);
      final adapter = await authorized(http);

      await expectLater(
        adapter.resolveStream('gone'),
        throwsA(isA<DriveException>()
            .having((e) => e.type, 'type', DriveErrorType.notFound)),
      );
      expect(http.requestsTo(QuarkEndpoints.fileDownload), isEmpty);
    });

    // -----------------------------------------------------------------
    // 兜底路径自身的错误处理（与改造前一致）
    // -----------------------------------------------------------------

    test('两条路由都取不到有效地址 → malformedResponse', () async {
      final http = FakeHttpClient.sequence([
        quarkOk(const {}),
        quarkOk(const []), // audioplay：不是对象
        quarkOk(const []), // download：空数组
      ]);
      final adapter = await authorized(http);

      await expectLater(
        adapter.resolveStream('f1'),
        throwsA(isA<DriveException>()
            .having((e) => e.type, 'type', DriveErrorType.malformedResponse)),
      );
    });

    test('download 兜底响应里没有 download_url → malformedResponse', () async {
      final http = FakeHttpClient.sequence([
        quarkOk(const {}),
        quarkOk(const {}), // audioplay 无 audio_url
        quarkOk([
          {'size': 100}
        ]),
      ]);
      final adapter = await authorized(http);

      await expectLater(
        adapter.resolveStream('f1'),
        throwsA(isA<DriveException>()
            .having((e) => e.type, 'type', DriveErrorType.malformedResponse)),
      );
    });

    test('未授权时抛 unauthorized，且一次请求都不发', () async {
      final http = FakeHttpClient.always(quarkOk(null));
      final adapter = build(http);

      await expectLater(
        adapter.resolveStream('f1'),
        throwsA(isA<DriveException>()),
      );
      expect(http.callCount, 0);
    });
  });

  group('ping', () {
    test('无会话时返回 false，不发请求', () async {
      final http = FakeHttpClient.always(quarkOk(null));
      final adapter = build(http);

      expect(await adapter.ping(), isFalse);
      expect(http.callCount, 0);
    });

    test('会话有效时返回 true', () async {
      await store.save(quarkCredential());
      final http = FakeHttpClient.always(quarkOk(const {}));
      final adapter = build(http);
      // ping 依赖内存中的会话，而会话由 restoreSession 装载
      await adapter.restoreSession();

      expect(await adapter.ping(), isTrue);
      expect(http.lastRequest.url, contains(QuarkEndpoints.config));
    });

    test('会话失效时返回 false（而不是抛异常）', () async {
      await store.save(quarkCredential());
      final http = FakeHttpClient.sequence([
        quarkOk(const {}), // restoreSession
        quarkError(31001, message: 'require login'), // ping
      ]);
      final adapter = build(http);
      await adapter.restoreSession();

      expect(await adapter.ping(), isFalse);
    });

    test('网络故障时向上抛（需要与「凭证失效」区分开）', () async {
      await store.save(quarkCredential());
      final http = FakeHttpClient.sequence([
        quarkOk(const {}), // restoreSession
        const HttpResult.networkFailure('offline'), // ping
      ]);
      final adapter = build(http);
      await adapter.restoreSession();

      await expectLater(
        adapter.ping(),
        throwsA(isA<DriveException>()
            .having((e) => e.type, 'type', DriveErrorType.network)),
      );
    });
  });

  group('响应 Cookie 轮换回填（CDN 直链 412 的修复）', () {
    /// 夸克服务端在每个 API 响应的 Set-Cookie 里轮换下发 `__puus`；
    /// 直链防重放校验依赖最新值，缺它一律 412。
    HttpResult quarkOkWithCookies(
      Object? data,
      List<String> setCookie,
    ) =>
        HttpResult(
          statusCode: 200,
          json: {'code': 0, 'message': 'ok', 'data': data},
          headers: <String, List<String>>{'set-cookie': setCookie},
        );

    test('响应下发新 __puus → 回填凭证，下一个请求带上它', () async {
      await store.save(quarkCredential(pus: 'PUS', puus: 'OLD'));
      final http = FakeHttpClient.sequence([
        // restoreSession：响应轮换下发新 __puus
        quarkOkWithCookies(const {}, [
          '__puus=NEW123; Path=/; Domain=.quark.cn; HttpOnly',
        ]),
        quarkOk(const {}), // 第二个请求（验证 Cookie 头已更新）
      ]);
      final adapter = build(http);
      await adapter.restoreSession();

      await adapter.ping();

      final second = http.requests[1];
      expect(second.headers!['Cookie'], contains('__puus=NEW123'));
      expect(second.headers!['Cookie'], contains('__pus=PUS'));
    });

    test('值没变化的响应不触发回填', () async {
      await store.save(quarkCredential(pus: 'PUS', puus: 'SAME'));
      final http = FakeHttpClient.always(quarkOkWithCookies(const {}, [
        '__puus=SAME; Path=/',
      ]));
      final adapter = build(http);
      await adapter.restoreSession();

      await adapter.ping();
      // Cookie 头保持不变（值一样）
      expect(http.lastRequest.headers!['Cookie'], contains('__puus=SAME'));
    });

    test('响应没有 Set-Cookie 时不影响凭证', () async {
      await store.save(quarkCredential(pus: 'PUS', puus: 'KEEP'));
      final http = FakeHttpClient.always(quarkOk(const {}));
      final adapter = build(http);
      await adapter.restoreSession();

      await adapter.ping();
      expect(http.lastRequest.headers!['Cookie'], contains('__puus=KEEP'));
    });

    test('不在 known 名单的 Cookie 不进凭证', () async {
      await store.save(quarkCredential());
      final http = FakeHttpClient.always(quarkOkWithCookies(const {}, [
        'ctoken=xyz; Path=/',
        'sm_uuid=abc; Path=/',
      ]));
      final adapter = build(http);
      await adapter.restoreSession();

      await adapter.ping();
      expect(http.lastRequest.headers!['Cookie'], isNot(contains('ctoken')));
      expect(http.lastRequest.headers!['Cookie'], isNot(contains('sm_uuid')));
    });
  });
}
