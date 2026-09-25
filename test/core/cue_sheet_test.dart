import 'dart:convert';

import 'package:cloudtune/core/utils/cue_sheet.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一份最典型的整轨 CUE：一个 72:18 的 WAV，切出 3 轨。
///
/// 用的是仓库里真实存在的那张专辑的形状
/// （`李克勤.-.[精选到无朋友 CD1](2014)[WAV].wav` = 765145628 字节 / 4338 秒）。
const _singleImageCue = '''
REM GENRE Pop
REM DATE 2014
REM COMMENT "ExactAudioCopy v1.0beta3"
PERFORMER "李克勤"
TITLE "精选到无朋友"
FILE "李克勤.-.[精选到无朋友 CD1](2014)[WAV].wav" WAVE
  TRACK 01 AUDIO
    TITLE "红日"
    PERFORMER "李克勤"
    ISRC HKD000000001
    INDEX 00 00:00:00
    INDEX 01 00:00:32
  TRACK 02 AUDIO
    TITLE "月半小夜曲"
    PERFORMER "李克勤"
    INDEX 00 03:20:37
    INDEX 01 03:20:62
  TRACK 03 AUDIO
    TITLE "护花使者"
    PERFORMER "李克勤"
    INDEX 01 07:00:00
''';

void main() {
  group('decodeCueBytes 编码判定', () {
    test('空字节返回空串', () {
      expect(decodeCueBytes(const []), '');
    });

    test('合法 UTF-8 直接解出', () {
      final bytes = const Utf8Encoder().convert('TITLE "红日"');
      expect(decodeCueBytes(bytes), 'TITLE "红日"');
    });

    test('UTF-8 BOM 被剥掉，且带不带 BOM 都能解析', () {
      const body = 'REM GENRE Pop\n'
          'FILE "a.wav" WAVE\n'
          '  TRACK 01 AUDIO\n'
          '    INDEX 01 00:00:00\n';
      final bytes = [0xEF, 0xBB, 0xBF, ...const Utf8Encoder().convert(body)];

      final text = decodeCueBytes(bytes);
      expect(text, body, reason: 'BOM 应被剥掉，解出的文本要干净');
      expect(parseCue(text)!.genre, 'Pop');

      // 即便 BOM 漏进来，解析也不该崩 —— `parseCue` 每行都 trim()，
      // 而 Dart 的 trim() 按 ECMAScript 空白定义会吃掉 U+FEFF。
      // 记在这里是为了说明「去 BOM 是卫生措施，不是解析前提」。
      final sheet = parseCue('\uFEFF$body');
      expect(sheet, isNotNull);
      expect(sheet!.genre, 'Pop');
      expect(sheet.tracks.single.startMs, 0);
    });

    test('纯 ASCII 两种编码等价', () {
      final bytes = const Utf8Encoder().convert('TRACK 01 AUDIO');
      expect(decodeCueBytes(bytes), 'TRACK 01 AUDIO');
    });

    test('GBK 硬编码字节解出中文（证明真的在按 GBK 解，不是回显）', () {
      // "红日" 的 GBK 编码：红=0xBAEC 日=0xC8D5
      const hongRiGbk = [0xBA, 0xEC, 0xC8, 0xD5];
      expect(decodeCueBytes(hongRiGbk), '红日');
    });

    test('整份 GBK CUE 能解出并解析', () {
      final text = 'PERFORMER "李克勤"\n'
          'TITLE "精选到无朋友"\n'
          'FILE "CDImage.wav" WAVE\n'
          '  TRACK 01 AUDIO\n'
          '    TITLE "红日"\n'
          '    INDEX 01 00:00:00\n';
      final bytes = gbk.encode(text);
      // 前提检查：这些字节确实不是合法 UTF-8，否则测不到 GBK 分支
      expect(() => const Utf8Decoder().convert(bytes), throwsFormatException);

      final sheet = parseCue(decodeCueBytes(bytes));
      expect(sheet, isNotNull);
      expect(sheet!.performer, '李克勤');
      expect(sheet.title, '精选到无朋友');
      expect(sheet.tracks.single.title, '红日');
    });

    test('彻底解不了的字节不抛异常（截断/损坏兜底）', () {
      final bytes = [0xFF, 0xFE, 0x41, 0x00];
      expect(() => decodeCueBytes(bytes), returnsNormally);
    });
  });

  group('MSF 时间码', () {
    test('00:00:00 是 0 毫秒', () {
      final sheet = parseCue(
        'FILE "a.wav" WAVE\n'
        '  TRACK 01 AUDIO\n'
        '    INDEX 01 00:00:00\n'
        '  TRACK 02 AUDIO\n'
        '    INDEX 01 00:00:01\n',
      )!;
      expect(sheet.tracks[0].startMs, 0);
      // 1 帧 = 1000/75 ≈ 13.33ms
      expect(sheet.tracks[1].startMs, 13);
    });

    test('帧是 75 进制，不是百分秒', () {
      final sheet = parseCue(
        'FILE "a.wav" WAVE\n'
        '  TRACK 01 AUDIO\n'
        '    INDEX 01 00:00:00\n'
        '  TRACK 02 AUDIO\n'
        '    INDEX 01 00:01:75\n',
      )!;
      // 00:01:75 = 1 秒 + 75 帧 = 2000ms；当成百分秒会算成 1750ms
      expect(sheet.tracks[1].startMs, 2000);
    });

    test('分钟不补零也认（0:00:00）', () {
      final sheet = parseCue(
        'FILE "a.wav" WAVE\n'
        '  TRACK 01 AUDIO\n'
        '    INDEX 01 0:00:00\n'
        '  TRACK 02 AUDIO\n'
        '    INDEX 01 3:20:37\n',
      )!;
      expect(sheet.tracks[1].startMs, 3 * 60000 + 20 * 1000 + 493);
    });

    test('只有 mm:ss 时按 0 帧处理', () {
      final sheet = parseCue(
        'FILE "a.wav" WAVE\n'
        '  TRACK 01 AUDIO\n'
        '    INDEX 01 00:00:00\n'
        '  TRACK 02 AUDIO\n'
        '    INDEX 01 01:30\n',
      )!;
      expect(sheet.tracks[1].startMs, 90000);
    });
  });

  group('parseCue 容错', () {
    test('空文本 / 纯空白返回 null', () {
      expect(parseCue(''), isNull);
      expect(parseCue('   \n\t\n'), isNull);
    });

    test('垃圾文本返回 null', () {
      expect(parseCue('这不是 cue 文件\n随便写点什么'), isNull);
    });

    test('关键字大小写不敏感', () {
      final sheet = parseCue(
        'performer "某人"\n'
        'file "a.wav" wave\n'
        '  track 01 audio\n'
        '    title "某歌"\n'
        '    index 01 00:00:00\n',
      );
      expect(sheet, isNotNull);
      expect(sheet!.performer, '某人');
      expect(sheet.tracks.single.title, '某歌');
    });

    test('CRLF 行尾', () {
      final sheet = parseCue(
        'FILE "a.wav" WAVE\r\n'
        '  TRACK 01 AUDIO\r\n'
        '    TITLE "歌"\r\n'
        '    INDEX 01 00:00:00\r\n',
      );
      expect(sheet!.tracks.single.title, '歌');
    });

    test('值带引号与不带引号都认', () {
      final quoted = parseCue(
        'FILE "a.wav" WAVE\n  TRACK 01 AUDIO\n    TITLE "红日"\n'
        '    INDEX 01 00:00:00\n',
      )!;
      final bare = parseCue(
        'FILE "a.wav" WAVE\n  TRACK 01 AUDIO\n    TITLE 红日\n'
        '    INDEX 01 00:00:00\n',
      )!;
      expect(quoted.tracks.single.title, '红日');
      expect(bare.tracks.single.title, '红日');
    });

    test('不带引号的值含空格时整段保留', () {
      final sheet = parseCue(
        'FILE "a.wav" WAVE\n  TRACK 01 AUDIO\n    TITLE 我 爱 你\n'
        '    INDEX 01 00:00:00\n',
      )!;
      expect(sheet.tracks.single.title, '我 爱 你');
    });

    test('空引号视为没有值', () {
      final sheet = parseCue(
        'TITLE ""\n'
        'FILE "a.wav" WAVE\n  TRACK 01 AUDIO\n    TITLE ""\n'
        '    INDEX 01 00:00:00\n',
      )!;
      expect(sheet.title, isNull);
      expect(sheet.tracks.single.title, isNull);
    });

    test('FILE 指令三种写法都能取到文件名与类型', () {
      final withQuotedType = parseCue(
        'FILE "CDImage.wav" WAVE\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n',
      )!;
      expect(withQuotedType.files.single.name, 'CDImage.wav');
      expect(withQuotedType.files.single.type, 'WAVE');

      final bare = parseCue(
        'FILE CDImage.wav WAVE\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n',
      )!;
      expect(bare.files.single.name, 'CDImage.wav');
      expect(bare.files.single.type, 'WAVE');

      final noType = parseCue(
        'FILE CDImage.wav\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n',
      )!;
      expect(noType.files.single.name, 'CDImage.wav');
      expect(noType.files.single.type, '');
    });

    test('不带引号且文件名含空格时，类型不会被误吞', () {
      final sheet = parseCue(
        'FILE My Album.wav WAVE\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n',
      )!;
      expect(sheet.files.single.name, 'My Album.wav');
      expect(sheet.files.single.type, 'WAVE');
    });

    test('REM GENRE / DATE / COMMENT 有结构才收', () {
      final sheet = parseCue(
        'REM GENRE Pop\n'
        'REM DATE 2014\n'
        'REM COMMENT "抓轨备注"\n'
        'REM 这行是自由文本\n'
        'FILE "a.wav" WAVE\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n',
      )!;
      expect(sheet.genre, 'Pop');
      expect(sheet.date, '2014');
      expect(sheet.comment, '抓轨备注');
    });

    test('CATALOG / ISRC / SONGWRITER', () {
      final sheet = parseCue(
        'CATALOG 0000000000001\n'
        'FILE "a.wav" WAVE\n'
        '  TRACK 01 AUDIO\n'
        '    SONGWRITER "黄霑"\n'
        '    ISRC HKD000000001\n'
        '    INDEX 01 00:00:00\n',
      )!;
      expect(sheet.catalog, '0000000000001');
      expect(sheet.tracks.single.songwriter, '黄霑');
      expect(sheet.tracks.single.isrc, 'HKD000000001');
    });

    test('未知指令（FLAGS / PREGAP / CDTEXTFILE）被忽略且不影响解析', () {
      final sheet = parseCue(
        'FILE "a.wav" WAVE\n'
        '  TRACK 01 AUDIO\n'
        '    FLAGS DCP\n'
        '    PREGAP 00:02:00\n'
        '    INDEX 01 00:00:00\n',
      );
      expect(sheet, isNotNull);
      expect(sheet!.tracks.single.startMs, 0);
    });
  });

  group('parseCue 分轨语义', () {
    test('INDEX 00 是 pregap，必须被忽略', () {
      final sheet = parseCue(_singleImageCue)!;
      // 第 1 轨 INDEX 00 = 00:00:00、INDEX 01 = 00:00:32
      expect(sheet.tracks[0].startMs, (32 * 1000 / 75).round());
      // 若误用 INDEX 00，第 2 轨会从 03:20:37 起，拖上一轨的尾巴
      expect(sheet.tracks[1].startMs, 3 * 60000 + 20 * 1000 + (62 * 1000 / 75).round());
    });

    test('只有 INDEX 00 没有 INDEX 01 的轨被跳过', () {
      final sheet = parseCue(
        'FILE "a.wav" WAVE\n'
        '  TRACK 01 AUDIO\n'
        '    TITLE "没有起点"\n'
        '    INDEX 00 00:00:00\n'
        '  TRACK 02 AUDIO\n'
        '    TITLE "有起点"\n'
        '    INDEX 01 01:00:00\n',
      )!;
      expect(sheet.tracks.length, 1);
      expect(sheet.tracks.single.title, '有起点');
    });

    test('轨号保留原始编号，不重排', () {
      final sheet = parseCue(
        'FILE "a.wav" WAVE\n'
        '  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n'
        '  TRACK 05 AUDIO\n    INDEX 01 01:00:00\n',
      )!;
      expect(sheet.tracks.map((t) => t.number), [1, 5]);
      expect(sheet.trackByNumber(5)!.startMs, 60000);
      expect(sheet.trackByNumber(2), isNull);
    });

    test('同 FILE 内 endMs 取下一轨起点', () {
      final sheet = parseCue(_singleImageCue)!;
      expect(sheet.tracks[0].endMs, sheet.tracks[1].startMs);
      expect(sheet.tracks[1].endMs, sheet.tracks[2].startMs);
    });

    test('同 FILE 最后一轨 endMs 为 null，duration 也为 null', () {
      final sheet = parseCue(_singleImageCue)!;
      expect(sheet.tracks.last.endMs, isNull);
      expect(sheet.tracks.last.duration, isNull);
    });

    test('跨 FILE 不把下一轨当终点（否则算出巨大负数轨长）', () {
      final sheet = parseCue(
        'FILE "01.wav" WAVE\n'
        '  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n'
        'FILE "02.wav" WAVE\n'
        '  TRACK 02 AUDIO\n    INDEX 01 00:00:00\n',
      )!;
      for (final t in sheet.tracks) {
        expect(t.endMs, isNull, reason: '第 ${t.number} 轨不该有跨文件终点');
        expect(t.duration, isNull);
      }
    });

    test('endMs ≤ startMs 时 duration 为 null（不显示负数）', () {
      const track = CueTrack(number: 1, fileName: 'a.wav', startMs: 1000, endMs: 500);
      expect(track.duration, isNull);
      const same = CueTrack(number: 1, fileName: 'a.wav', startMs: 1000, endMs: 1000);
      expect(same.duration, isNull);
      const ok = CueTrack(number: 1, fileName: 'a.wav', startMs: 1000, endMs: 3500);
      expect(ok.duration, const Duration(milliseconds: 2500));
    });

    test('同一 FILE 内轨号乱序时不崩（终点可能为负，但被 duration 挡住）', () {
      final sheet = parseCue(
        'FILE "a.wav" WAVE\n'
        '  TRACK 02 AUDIO\n    INDEX 01 05:00:00\n'
        '  TRACK 01 AUDIO\n    INDEX 01 01:00:00\n',
      )!;
      expect(sheet.tracks.length, 2);
      // 第 1 个出现的是轨 02，终点 = 轨 01 的起点 60000，比自己的 300000 小
      expect(sheet.tracks[0].duration, isNull);
    });
  });

  group('整轨 / 分轨判定', () {
    test('1 个 FILE + 多轨 → isSingleImage', () {
      final sheet = parseCue(_singleImageCue)!;
      expect(sheet.isSingleImage, isTrue);
      expect(sheet.isMultiFile, isFalse);
      expect(sheet.trackCount, 3);
      expect(sheet.files.single.trackNumbers, [1, 2, 3]);
    });

    test('1 个 FILE + 1 轨 → 两者都不是（不该物化虚拟曲目）', () {
      final sheet = parseCue(
        'FILE "a.wav" WAVE\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n',
      )!;
      expect(sheet.isSingleImage, isFalse);
      expect(sheet.isMultiFile, isFalse);
    });

    test('多个 FILE → isMultiFile，只做元数据增强', () {
      final sheet = parseCue(
        'PERFORMER "某人"\n'
        'FILE "01.wav" WAVE\n'
        '  TRACK 01 AUDIO\n    TITLE "第一首"\n    INDEX 01 00:00:00\n'
        'FILE "02.wav" WAVE\n'
        '  TRACK 02 AUDIO\n    TITLE "第二首"\n    INDEX 01 00:00:00\n',
      )!;
      expect(sheet.isMultiFile, isTrue);
      expect(sheet.isSingleImage, isFalse);
      expect(sheet.files.map((f) => f.name), ['01.wav', '02.wav']);
      expect(sheet.files[0].trackNumbers, [1]);
      expect(sheet.files[1].trackNumbers, [2]);
    });
  });

  group('withFileEnd 补齐末轨终点', () {
    test('用真实文件时长补上同 FILE 末轨', () {
      final sheet = parseCue(_singleImageCue)!;
      // 真实时长 4338 秒 = 72:18
      final filled = sheet.withFileEnd((_) => 4338000);
      expect(filled.tracks.last.endMs, 4338000);
      expect(filled.tracks.last.duration!.inSeconds, 4338 - 420);
      // 非末轨不受影响
      expect(filled.tracks[0].endMs, sheet.tracks[0].endMs);
      // 原对象不可变
      expect(sheet.tracks.last.endMs, isNull);
    });

    test('拿不到时长时保持 null', () {
      final sheet = parseCue(_singleImageCue)!;
      final filled = sheet.withFileEnd((_) => null);
      expect(filled.tracks.last.endMs, isNull);
    });

    test('时长 ≤ 起点（数据错乱）时不写入', () {
      final sheet = parseCue(_singleImageCue)!;
      final filled = sheet.withFileEnd((_) => 1000);
      expect(filled.tracks.last.endMs, isNull);
    });

    test('什么都没变时返回同一个实例', () {
      final sheet = parseCue(_singleImageCue)!;
      expect(identical(sheet.withFileEnd((_) => null), sheet), isTrue);
    });

    test('分轨场景按各自文件名分别补齐', () {
      final sheet = parseCue(
        'FILE "01.wav" WAVE\n'
        '  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n'
        '  TRACK 02 AUDIO\n    INDEX 01 00:30:00\n'
        'FILE "02.wav" WAVE\n'
        '  TRACK 03 AUDIO\n    INDEX 01 00:00:00\n',
      )!;
      final filled = sheet.withFileEnd((name) => name == '01.wav' ? 60000 : 120000);
      expect(filled.tracks[1].endMs, 60000, reason: '01.wav 的末轨（第 2 轨）');
      expect(filled.tracks[2].endMs, 120000, reason: '02.wav 的末轨（第 3 轨）');
      expect(filled.tracks[0].endMs, filled.tracks[1].startMs);
    });
  });

  group('辅助', () {
    test('copyWith 只改终点，其余字段保持', () {
      const t = CueTrack(
        number: 3,
        fileName: 'a.wav',
        startMs: 100,
        endMs: 200,
        title: '歌',
        performer: '人',
        songwriter: '词',
        isrc: 'X',
      );
      final c = t.copyWith(endMs: 900);
      expect(c.number, 3);
      expect(c.fileName, 'a.wav');
      expect(c.startMs, 100);
      expect(c.endMs, 900);
      expect(c.title, '歌');
      expect(c.performer, '人');
      expect(c.songwriter, '词');
      expect(c.isrc, 'X');
    });

    test('toString 可用于排查（不抛异常且含关键信息）', () {
      final sheet = parseCue(_singleImageCue)!;
      expect(sheet.toString(), contains('精选到无朋友'));
      expect(sheet.toString(), contains('3 轨'));
      expect(sheet.tracks.first.toString(), contains('红日'));
      expect(sheet.files.single.toString(), contains('WAVE'));
    });
  });
}
