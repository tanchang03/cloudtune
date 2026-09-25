import 'package:cloudtune/domain/entities/drive_entry.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/lyrics.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/domain/services/lyrics_indexer.dart';
import 'package:flutter_test/flutter_test.dart';

/// `.lrc` → 曲目 的匹配器。
///
/// 用例里的文件名全部来自真实音乐包的命名习惯 —— 这个匹配器的价值就在于
/// 处理「音频和歌词名字对不上」的各种写法。
void main() {
  const indexer = LyricsIndexer();

  Track track(String name, {int? cueTrackNo, int? cueStartMs, String? title}) =>
      Track(
        provider: DriveProvider.quark,
        remoteId: 'f_$name',
        name: name,
        title: title,
        cueTrackNo: cueTrackNo,
        cueStartMs: cueStartMs,
      );

  DriveEntry lrc(String name, {String id = ''}) =>
      DriveEntry(id: id.isEmpty ? 'lrc_$name' : id, name: name, isDirectory: false);

  DriveEntry dir(String name) =>
      DriveEntry(id: 'd_$name', name: name, isDirectory: true);

  LyricsIndexResult run(List<Track> tracks, List<DriveEntry> files) =>
      indexer.indexDirectory(
        provider: DriveProvider.quark,
        tracks: tracks,
        lrcFiles: files,
      );

  String? fileFor(LyricsIndexResult r, String trackId) {
    for (final m in r.matches) {
      if (m.trackId == trackId) return m.fileName;
    }
    return null;
  }

  group('主干同名', () {
    test('音频与歌词完全同名（最常见）', () {
      final t = track('晴天.flac');
      final r = run([t], [lrc('晴天.lrc')]);
      expect(r.matches, hasLength(1));
      expect(r.matches.single.trackId, t.id);
      expect(r.matches.single.source, LyricsSource.local);
      expect(r.matches.single.fileName, '晴天.lrc');
      expect(r.matches.single.fileId, 'lrc_晴天.lrc');
    });

    test('扫描出来的歌词只有引用，没有正文', () {
      final r = run([track('晴天.flac')], [lrc('晴天.lrc')]);
      expect(r.matches.single.content, isNull, reason: '正文要等播放时才读');
      expect(r.matches.single.isPending, isTrue);
      expect(r.matches.single.isDisplayable, isFalse);
    });

    test('大小写不同也算同名', () {
      final t = track('Hello.flac');
      final r = run([t], [lrc('hello.lrc')]);
      expect(r.matches, hasLength(1));
    });

    test('一边带音轨号、一边不带', () {
      final t = track('01. 晴天.flac');
      final r = run([t], [lrc('晴天.lrc')]);
      expect(r.matches, hasLength(1));
      expect(r.matches.single.trackId, t.id);
    });

    test('一边带 [无损] 尾巴、一边不带', () {
      final t = track('晴天[无损音质].flac');
      final r = run([t], [lrc('晴天.lrc')]);
      expect(r.matches, hasLength(1));
    });

    test('一边带 (Live) 尾巴、一边不带', () {
      final t = track('海阔天空 (Live).flac');
      final r = run([t], [lrc('海阔天空.lrc')]);
      expect(r.matches, hasLength(1));
    });

    test('艺术家前缀一致时命中', () {
      final t = track('周杰伦 - 晴天.flac');
      final r = run([t], [lrc('周杰伦 - 晴天.lrc')]);
      expect(r.matches, hasLength(1));
    });

    test('歌词只有曲名、音频带艺术家前缀', () {
      final t = track('周杰伦 - 晴天.flac');
      final r = run([t], [lrc('晴天.lrc')]);
      expect(r.matches, hasLength(1));
      expect(r.matches.single.trackId, t.id);
    });
  });

  group('一个目录多首歌', () {
    test('各自对上各自的歌词，不会串', () {
      final a = track('01. 晴天.flac');
      final b = track('02. 以父之名.flac');
      final c = track('03. 东风破.flac');
      final r = run([a, b, c], [lrc('晴天.lrc'), lrc('东风破.lrc')]);

      expect(r.matches, hasLength(2));
      expect(fileFor(r, a.id), '晴天.lrc');
      expect(fileFor(r, b.id), isNull);
      expect(fileFor(r, c.id), '东风破.lrc');
    });

    test('多首歌时不会触发「只有一首」的兜底', () {
      final a = track('A.flac');
      final b = track('B.flac');
      final r = run([a, b], [lrc('歌词.lrc')]);
      expect(r.matches, isEmpty, reason: '两份音频配一个通用名的歌词，无从判断给谁');
    });

    test('两个 lrc 抢同一首歌时留下更可信的那个', () {
      final t = track('周杰伦 - 晴天.flac');
      // `晴天.lrc` 只能靠「包含」命中（3 分），`周杰伦 - 晴天.lrc` 是精确命中（0 分）
      final r = run([t], [lrc('晴天.lrc'), lrc('周杰伦 - 晴天.lrc')]);
      expect(r.matches, hasLength(1));
      expect(r.matches.single.fileName, '周杰伦 - 晴天.lrc');
    });

    test('同分时按文件名序取先来的，结果确定', () {
      final t = track('晴天.flac');
      final r = run([t], [lrc('b_晴天.lrc'), lrc('a_晴天.lrc')]);
      expect(r.matches, hasLength(1));
      expect(r.matches.single.fileName, 'a_晴天.lrc');
    });
  });

  group('兜底：目录里唯一的 lrc 归唯一的歌', () {
    test('通用名的歌词文件只有这一条路能被认出来', () {
      final t = track('Adele - Hello.flac');
      final r = run([t], [lrc('lyrics.lrc')]);
      expect(r.matches, hasLength(1));
      expect(r.matches.single.trackId, t.id);
    });

    test('代价：名字毫不相干的 lrc 也会被认下', () {
      // 这是那条兜底刻意接受的代价。理由：一个目录里只有一首歌、又只有一个
      // .lrc，此时**不存在歧义可言** —— 那个 .lrc 不可能是别人的歌词。
      // 换来的是 `lyrics.lrc` / `歌词.lrc` 这类通用名能被用上。
      // 反过来（多首歌 + 通用名）会被拒，见上一组。
      final t = track('Adele - Hello.flac');
      final r = run([t], [lrc('A.lrc')]);
      expect(r.matches, hasLength(1));
    });

    test('目录里有两个 lrc 时兜底不生效', () {
      final t = track('Adele - Hello.flac');
      final r = run([t], [lrc('lyrics.lrc'), lrc('歌词.lrc')]);
      expect(r.matches, isEmpty);
    });
  });

  group('整轨 CUE 分段', () {
    test('按轨号认领（分段的 name 是整轨文件名，不能按名字匹配）', () {
      final seg1 = track('专辑.wav', cueTrackNo: 1, cueStartMs: 0, title: '第一首');
      final seg2 = track('专辑.wav', cueTrackNo: 2, cueStartMs: 200000, title: '第二首');
      final r = run([seg1, seg2], [lrc('02 - 第二首.lrc')]);

      expect(r.matches, hasLength(1));
      expect(r.matches.single.trackId, seg2.id);
    });

    test('按 CUE 标题认领', () {
      final seg1 = track('专辑.wav', cueTrackNo: 1, cueStartMs: 0, title: '晴天');
      final seg2 = track('专辑.wav', cueTrackNo: 2, cueStartMs: 200000, title: '以父之名');
      final r = run([seg1, seg2], [lrc('以父之名.lrc')]);

      expect(r.matches, hasLength(1));
      expect(r.matches.single.trackId, seg2.id);
    });

    test('整张专辑的歌词文件不会被塞给第 1 段', () {
      // `专辑.lrc` 与整轨同名 —— 但它装的是整张专辑的歌词（时间轴从 0 到
      // 整轨结束）。认给第 1 段的话，用户切到第 3 段会看到第 1 段的歌词，
      // 那比没有歌词更像故障。所以分段完全不参与按名字匹配。
      final seg1 = track('专辑.wav', cueTrackNo: 1, cueStartMs: 0, title: '第一首');
      final seg2 = track('专辑.wav', cueTrackNo: 2, cueStartMs: 200000, title: '第二首');
      final r = run([seg1, seg2], [lrc('专辑.lrc')]);

      expect(r.matches, isEmpty);
    });

    test('分段共用同一个 remoteId，但 id 各不相同，认领不会互相覆盖', () {
      final seg1 = track('专辑.wav', cueTrackNo: 1, cueStartMs: 0, title: 'A');
      final seg2 = track('专辑.wav', cueTrackNo: 2, cueStartMs: 1000, title: 'B');
      expect(seg1.id, isNot(seg2.id));

      final r = run([seg1, seg2], [lrc('01 - A.lrc'), lrc('02 - B.lrc')]);
      expect(r.matches, hasLength(2));
      expect(fileFor(r, seg1.id), '01 - A.lrc');
      expect(fileFor(r, seg2.id), '02 - B.lrc');
    });
  });

  group('忽略项', () {
    test('非 .lrc 文件一律不看', () {
      final t = track('晴天.flac');
      final r = run([t], [lrc('晴天.txt'), lrc('晴天.cue'), lrc('cover.jpg')]);
      expect(r.matches, isEmpty);
    });

    test('目录叫 .lrc 也不算', () {
      final t = track('晴天.flac');
      final r = run([t], [dir('晴天.lrc')]);
      expect(r.matches, isEmpty);
    });

    test('目录里没有曲目时什么都不返回', () {
      final r = run([], [lrc('晴天.lrc')]);
      expect(r.matches, isEmpty);
    });

    test('目录里没有歌词时什么都不返回', () {
      final r = run([track('晴天.flac')], []);
      expect(r.matches, isEmpty);
    });

    test('多首歌时，太短的「包含」不算命中（避免 A.lrc 命中 Adele）', () {
      // 必须是**两首以上**的目录：只有一首时走的是「目录里唯一的 lrc 归唯一的
      // 歌」那条兜底，短包含这条闸根本轮不到生效。
      final a = track('Adele - Hello.flac');
      final b = track('Someone Else - Song.flac');
      final r = run([a, b], [lrc('A.lrc')]);
      expect(r.matches, isEmpty, reason: '太短的包含是巧合');
    });
  });

  group('leadingTrackNo', () {
    test('常见写法', () {
      expect(LyricsIndexer.leadingTrackNo('01 - 歌.lrc'), 1);
      expect(LyricsIndexer.leadingTrackNo('05.歌.lrc'), 5);
      expect(LyricsIndexer.leadingTrackNo('12_歌.lrc'), 12);
      expect(LyricsIndexer.leadingTrackNo('1 歌.lrc'), isNull, reason: '没有分隔符不算');
      expect(LyricsIndexer.leadingTrackNo('歌.lrc'), isNull);
      expect(LyricsIndexer.leadingTrackNo('2024.lrc'), isNull,
          reason: '四位数是年份，不是轨号');
    });
  });

  group('打分档位', () {
    test('精确同名比「包含」更可信', () {
      expect(LyricsIndexer.scoreExact, lessThan(LyricsIndexer.scoreContains));
    });

    test('轨号比「包含」更可信', () {
      expect(LyricsIndexer.scoreTrackNo, lessThan(LyricsIndexer.scoreContains));
    });

    test('兜底档最不可信', () {
      expect(LyricsIndexer.scoreSolePair, greaterThan(LyricsIndexer.scoreContains));
    });
  });
}
