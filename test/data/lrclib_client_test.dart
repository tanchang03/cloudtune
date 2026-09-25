import 'package:cloudtune/data/http/http_client.dart';
import 'package:cloudtune/data/lyrics/lrclib_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_http_client.dart';

/// LRCLIB 客户端。
///
/// 重点不是「能不能取到歌词」，而是**取不到/取错的时候行为是否正确**：
/// 时长这道硬闸、三级兜底、限流重试，任何一条写错都会表现成
/// 「某些歌的歌词时有时无」—— 一个几乎没法从现象反推原因的 bug。
void main() {
  /// 一份完整的 LRCLIB 返回。
  Map<String, Object?> payload({
    String trackName = '晴天',
    String? artistName = '周杰伦',
    String? albumName = '叶惠美',
    int? duration = 269,
    bool instrumental = false,
    String? plain = '故事的小黄花',
    String? synced = '[00:01.00]故事的小黄花',
  }) =>
      {
        'id': 1,
        'trackName': trackName,
        'artistName': artistName,
        'albumName': albumName,
        'duration': duration,
        'instrumental': instrumental,
        'plainLyrics': plain,
        'syncedLyrics': synced,
      };

  HttpResult ok(Map<String, Object?> body) =>
      HttpResult(statusCode: 200, json: body);
  HttpResult okList(List<Map<String, Object?>> body) =>
      HttpResult(statusCode: 200, jsonList: body);
  const notFound = HttpResult(statusCode: 404, rawBody: 'Not Found');

  /// 造一个只关心「按 URL 路径给不同响应」的客户端。
  LrclibClient build(
    FakeHttpClient http, {
    Duration minInterval = Duration.zero,
    Future<void> Function(Duration)? sleep,
  }) =>
      LrclibClient(
        http: http,
        minInterval: minInterval,
        sleep: sleep,
        retryDelay: Duration.zero,
      );

  String pathOf(RecordedRequest r) => Uri.parse(r.url).path;

  group('时长：是一道硬闸，不是「有更好」', () {
    test('时长已知时带上它（能区分同一首歌的不同版本）', () async {
      final http = FakeHttpClient.always(ok(payload()));
      final result = await build(http).lookup(trackName: '晴天', durationSeconds: 269);

      expect(result, isNotNull);
      expect(http.requestsTo('/get').single.param('duration'), 269);
    });

    test('时长未知时**根本不带**这个参数', () async {
      // 关键用例。LRCLIB 只返回 ±2 秒以内的版本，传一个不准的时长会把本来
      // 查得到的曲子变成 404 —— 比不传还差。本项目的时长来自网盘元数据，
      // 而网盘并不保证有（README 已知限制里就有 `--:--` 的曲目）。
      final http = FakeHttpClient.always(ok(payload()));
      await build(http).lookup(trackName: '晴天');

      expect(
        http.requestsTo('/get').first.param('duration'),
        isNull,
        reason: '时长未知时传 0 或乱猜一个，等于把能查到的曲子变成查不到',
      );
    });

    test('时长超出 1..3600 时也不带（接口不接受）', () async {
      final http = FakeHttpClient.always(ok(payload()));
      await build(http).lookup(trackName: '晴天', durationSeconds: 7200);

      expect(http.requestsTo('/get').first.param('duration'), isNull);
    });

    test('时长为 0 时也不带（网盘没刮削到时长会归一成 0/null）', () async {
      final http = FakeHttpClient.always(ok(payload()));
      await build(http).lookup(trackName: '晴天', durationSeconds: 0);

      expect(http.requestsTo('/get').first.param('duration'), isNull);
    });
  });

  group('三级兜底', () {
    test('第一级命中就不再往下走', () async {
      final http = FakeHttpClient.always(ok(payload()));
      await build(http).lookup(trackName: '晴天', durationSeconds: 269);

      expect(http.callCount, 1);
    });

    test('带时长 404 时退到不带时长', () async {
      final http = FakeHttpClient.sequence([
        notFound,
        ok(payload(synced: '[00:01.00]另一个版本')),
      ]);
      final result = await build(http).lookup(trackName: '晴天', durationSeconds: 248);

      expect(result, isNotNull);
      expect(result!.text, '[00:01.00]另一个版本');
      expect(http.callCount, 2);
      expect(http.requestsTo('/get').last.param('duration'), isNull);
    });

    test('带时长拿到「既没正文也没说纯音乐」时也往下走', () async {
      final http = FakeHttpClient.sequence([
        ok(payload(plain: null, synced: null)),
        ok(payload(synced: '[00:01.00]有正文的')),
      ]);
      final result = await build(http).lookup(trackName: '晴天', durationSeconds: 269);

      expect(result!.text, '[00:01.00]有正文的');
      expect(http.callCount, 2);
    });

    test('两个 /get 都查不到时退到搜索', () async {
      final http = FakeHttpClient.sequence([
        notFound,
        notFound,
        okList([payload(trackName: '晴天', synced: '[00:01.00]搜到的')]),
      ]);
      final result = await build(http)
          .lookup(trackName: '晴天', artistName: '周杰伦', durationSeconds: 269);

      expect(result, isNotNull);
      expect(result!.text, '[00:01.00]搜到的');
      expect(http.requestsTo('/search'), hasLength(1));
    });

    test('搜索返回空数组时给 null', () async {
      final http = FakeHttpClient.sequence([notFound, notFound, okList([])]);
      expect(await build(http).lookup(trackName: '晴天'), isNull);
    });

    test('曲名为空时一次请求都不发', () async {
      final http = FakeHttpClient.always(ok(payload()));
      expect(await build(http).lookup(trackName: '   '), isNull);
      expect(http.callCount, 0);
    });
  });

  group('搜索结果打分', () {
    test('优先选曲名与艺术家都对上的那个', () async {
      final http = FakeHttpClient.sequence([
        notFound,
        notFound,
        okList([
          payload(trackName: '晴天', artistName: '别的歌手', duration: 200,
              synced: '[00:01.00]翻唱'),
          payload(trackName: '晴天', artistName: '周杰伦', duration: 269,
              synced: '[00:01.00]原唱'),
        ]),
      ]);
      final result = await build(http)
          .lookup(trackName: '晴天', artistName: '周杰伦', durationSeconds: 269);

      expect(result!.text, '[00:01.00]原唱');
    });

    test('时长差太远的候选被扣分，不会被选中', () async {
      final http = FakeHttpClient.sequence([
        notFound,
        notFound,
        okList([
          payload(trackName: '晴天', artistName: '周杰伦', duration: 900,
              synced: '[00:01.00]现场版'),
        ]),
      ]);
      // 曲名与艺术家都对上（4+3），但时长差了 10 分钟（-1），仍是 6 分
      final result = await build(http)
          .lookup(trackName: '晴天', artistName: '周杰伦', durationSeconds: 269);
      expect(result, isNotNull, reason: '曲名+艺术家都对上，时长对不上仍可用');

      // 但曲名只有一个「包含」关系时，时长差太多就掉到门槛以下
      final http2 = FakeHttpClient.sequence([
        notFound,
        notFound,
        okList([
          payload(trackName: '晴天 (Live)', artistName: null, duration: 900,
              synced: '[00:01.00]别的'),
        ]),
      ]);
      expect(
        await build(http2).lookup(trackName: '晴天', durationSeconds: 269),
        isNull,
        reason: '只有一个模糊的曲名对得上、时长又差 10 分钟 —— '
            '宁可显示没找到，也不要显示别人的歌词',
      );
    });

    test('候选全都不够可信时给 null 而不是硬挑一个', () async {
      final http = FakeHttpClient.sequence([
        notFound,
        notFound,
        okList([payload(trackName: '完全不同的歌', artistName: null)]),
      ]);
      expect(await build(http).lookup(trackName: '晴天'), isNull);
    });

    test('没有正文的候选不会被选中（纯音乐除外）', () async {
      final http = FakeHttpClient.sequence([
        notFound,
        notFound,
        okList([payload(trackName: '晴天', plain: null, synced: null)]),
      ]);
      expect(await build(http).lookup(trackName: '晴天'), isNull);
    });
  });

  group('响应体形状', () {
    test('搜索的顶层 JSON 数组能被解析', () async {
      // 顶层数组原本会被 HttpResult 整段丢掉（json 为 null，
      // rawBody 又只留 400 字符），见 HttpResult.jsonList 的注释。
      // 没有时长时只有两次调用：/get（不带时长）与 /search。
      final http = FakeHttpClient.sequence([
        notFound,
        okList([payload(synced: '[00:01.00]数组里的')]),
      ]);
      final result = await build(http).lookup(trackName: '晴天');
      expect(result!.text, '[00:01.00]数组里的');
      expect(http.requestsTo('/search'), hasLength(1));
    });

    test('优先用带时间轴的那份，而不是纯文本', () async {
      final http = FakeHttpClient.always(ok(payload(
        plain: '纯文本正文',
        synced: '[00:01.00]带时间轴',
      )));
      final result = await build(http).lookup(trackName: '晴天');
      expect(result!.text, '[00:01.00]带时间轴');
    });

    test('只有纯文本时也能用', () async {
      final http = FakeHttpClient.always(ok(payload(plain: '只有纯文本', synced: null)));
      final result = await build(http).lookup(trackName: '晴天');
      expect(result!.text, '只有纯文本');
      expect(result.hasLyrics, isTrue);
    });

    test('snake_case 字段也认（自建实例可能这么给）', () async {
      final http = FakeHttpClient.always(ok({
        'track_name': '晴天',
        'artist_name': '周杰伦',
        'duration': 269,
        'synced_lyrics': '[00:01.00]下划线',
      }));
      final result = await build(http).lookup(trackName: '晴天');
      expect(result!.text, '[00:01.00]下划线');
      expect(result.artistName, '周杰伦');
    });

    test('纯音乐：没有正文也是一份「值得记下来」的结果', () async {
      final http = FakeHttpClient.always(
        ok(payload(plain: null, synced: null, instrumental: true)),
      );
      final result = await build(http).lookup(trackName: '某首纯音乐');

      expect(result, isNotNull);
      expect(result!.instrumental, isTrue);
      expect(result.hasLyrics, isFalse);
      expect(result.isUseful, isTrue, reason: '「纯音乐」是确定的答案，'
          '不该每次播放都去重问一遍第三方接口');
      expect(http.callCount, 1);
    });

    test('非对象响应体不炸，只是当作没查到', () async {
      final http = FakeHttpClient.always(
        const HttpResult(statusCode: 200, rawBody: '<html>not json</html>'),
      );
      expect(await build(http).lookup(trackName: '晴天'), isNull);
    });
  });

  group('限流与故障', () {
    test('429 时按 Retry-After 等待后重试一次', () async {
      final slept = <Duration>[];
      final http = FakeHttpClient.sequence([
        const HttpResult(statusCode: 429, headers: {'retry-after': ['3']}),
        ok(payload(synced: '[00:01.00]重试成功')),
      ]);

      final result = await build(http, sleep: (d) async => slept.add(d))
          .lookup(trackName: '晴天');

      expect(result!.text, '[00:01.00]重试成功');
      expect(slept, contains(const Duration(seconds: 3)),
          reason: '必须尊重 Retry-After，否则会被当成爬虫直接封掉');
    });

    test('Retry-After 过大时被压到上限，不会真的干等', () async {
      final slept = <Duration>[];
      final http = FakeHttpClient.sequence([
        const HttpResult(statusCode: 429, headers: {'retry-after': ['86400']}),
        ok(payload()),
      ]);

      await build(http, sleep: (d) async => slept.add(d)).lookup(trackName: '晴天');

      expect(slept, contains(const Duration(seconds: 30)));
    });

    test('没有 Retry-After 时用默认等待', () async {
      final slept = <Duration>[];
      final http = FakeHttpClient.sequence([
        const HttpResult(statusCode: 429),
        ok(payload()),
      ]);

      await build(
        http,
        sleep: (d) async => slept.add(d),
      ).lookup(trackName: '晴天');

      // retryDelay 在 build() 里被设成 zero，所以这里只断言「重试发生了」
      expect(http.callCount, 2);
    });

    test('503 也重试一次', () async {
      final http = FakeHttpClient.sequence([
        const HttpResult(statusCode: 503, rawBody: 'ServerOverloaded'),
        ok(payload(synced: '[00:01.00]过载恢复')),
      ]);
      final result = await build(http).lookup(trackName: '晴天');

      expect(result!.text, '[00:01.00]过载恢复');
      expect(http.callCount, 2);
    });

    test('只重试一次 —— 持续 503 时不会无限打接口', () async {
      final http = FakeHttpClient.always(
        const HttpResult(statusCode: 503, rawBody: 'ServerOverloaded'),
      );
      // 三级兜底各重试一次，所以是 3 级 × 2 次 = 6 次。
      // 关键是它**有上限**：一个持续过载的接口不该被我们打成 DDoS。
      expect(
        await build(http).lookup(trackName: '晴天', durationSeconds: 269),
        isNull,
      );
      expect(http.callCount, 6);
    });

    test('网络层失败返回 null，不抛异常', () async {
      final http = FakeHttpClient.throwing(Exception('connection refused'));
      expect(await build(http).lookup(trackName: '晴天'), isNull);
    });

    test('网络层不通时立刻放弃整条链，不再一级一级试', () async {
      // 断网时继续试下一级毫无意义，而每一级都带一个 10 秒超时 ——
      // 用户看到的是「切歌之后界面卡住半分钟」。
      final http = FakeHttpClient.throwing(Exception('offline'));
      await build(http).lookup(trackName: '晴天', durationSeconds: 269);
      expect(http.callCount, 1);
    });

    test('服务器过载（503）时**会**继续试下一级 —— 那只是这一级不行', () async {
      final http = FakeHttpClient.sequence([
        const HttpResult(statusCode: 503),
        const HttpResult(statusCode: 503),
        ok(payload(synced: '[00:01.00]退到第二级就好了')),
      ]);
      final result = await build(http).lookup(trackName: '晴天', durationSeconds: 269);

      expect(result!.text, '[00:01.00]退到第二级就好了');
    });
  });

  group('请求约定', () {
    test('带上能标识应用与项目主页的 User-Agent', () async {
      final http = FakeHttpClient.always(ok(payload()));
      await build(http).lookup(trackName: '晴天');

      final ua = http.lastRequest.headers?['User-Agent'];
      expect(ua, isNotNull);
      expect(ua, contains('CloudTune'));
      expect(ua, contains('github.com'),
          reason: 'LRCLIB 的接口约定明确要求可标识、可追溯 —— '
              '通用 UA 会被封禁');
    });

    test('曲名与艺术家都发出去', () async {
      final http = FakeHttpClient.always(ok(payload()));
      await build(http)
          .lookup(trackName: '晴天', artistName: '周杰伦', albumName: '叶惠美');

      final q = http.lastRequest.query!;
      expect(q['track_name'], '晴天');
      expect(q['artist_name'], '周杰伦');
      expect(q['album_name'], '叶惠美');
    });

    test('艺术家是占位词时干脆不传（传了必然匹配不上）', () async {
      final http = FakeHttpClient.always(ok(payload()));
      await build(http).lookup(trackName: '晴天', artistName: '未知艺术家');

      expect(http.lastRequest.query!.containsKey('artist_name'), isFalse);
    });

    test('相邻两次请求之间保持最小间隔', () async {
      final slept = <Duration>[];
      final http = FakeHttpClient.sequence([notFound, ok(payload())]);

      await build(
        http,
        minInterval: const Duration(milliseconds: 300),
        sleep: (d) async => slept.add(d),
      ).lookup(trackName: '晴天', durationSeconds: 269);

      // 等待时长 = 最小间隔 − 已经过去的时间，所以会比 300ms 略小一点点
      // （第一次请求本身耗时几毫秒）。断言的是「确实等了一次接近整段间隔」，
      // 不是「正好 300ms」。
      expect(slept, hasLength(1));
      expect(
        slept.single,
        greaterThan(const Duration(milliseconds: 200)),
        reason: 'LRCLIB 的接口约定要求串行 + 200~500ms 间隔',
      );
      expect(slept.single, lessThanOrEqualTo(const Duration(milliseconds: 300)));
    });

    test('路径用的是 /get 与 /search', () async {
      final http = FakeHttpClient.sequence([notFound, notFound, okList([])]);
      await build(http).lookup(trackName: '晴天', durationSeconds: 269);

      final paths = http.requests.map(pathOf).toList();
      expect(paths, ['/api/get', '/api/get', '/api/search']);
    });
  });

  group('cleanQueryValue', () {
    test('空值与占位词都归一成 null', () {
      expect(cleanQueryValue(null), isNull);
      expect(cleanQueryValue(''), isNull);
      expect(cleanQueryValue('   '), isNull);
      expect(cleanQueryValue('未知艺术家'), isNull);
      expect(cleanQueryValue('Unknown'), isNull);
      expect(cleanQueryValue('--'), isNull);
    });

    test('正常值原样返回（去掉首尾空白）', () {
      expect(cleanQueryValue('  周杰伦 '), '周杰伦');
      expect(cleanQueryValue('Adele'), 'Adele');
    });
  });
}
