import 'dart:convert';

import 'package:cloudtune/core/utils/lrc.dart';
import 'package:cloudtune/core/utils/text_encoding.dart';
import 'package:flutter_test/flutter_test.dart';

/// LRC 解析器。
///
/// 这个文件里的每一段输入都来自**真实歌词文件的写法**（千千静听 / foobar2000 /
/// 各种歌词下载器），不是编出来的理想格式 —— 解析器要面对的就是这种杂乱。
void main() {
  group('时间戳', () {
    test('基本形式：mm:ss.xx 按厘秒解释', () {
      final doc = parseLrc('[00:12.34]从出生那年就飘着');
      expect(doc.lines, hasLength(1));
      expect(doc.lines.single.at, const Duration(seconds: 12, milliseconds: 340));
      expect(doc.lines.single.text, '从出生那年就飘着');
    });

    test('三位小数按毫秒解释', () {
      final doc = parseLrc('[01:02.345]A');
      expect(doc.lines.single.at,
          const Duration(minutes: 1, seconds: 2, milliseconds: 345));
    });

    test('一位小数按百毫秒解释', () {
      final doc = parseLrc('[00:05.5]A');
      expect(doc.lines.single.at, const Duration(seconds: 5, milliseconds: 500));
    });

    test('没有小数部分', () {
      final doc = parseLrc('[00:07]A');
      expect(doc.lines.single.at, const Duration(seconds: 7));
    });

    test('用冒号代替小数点（部分工具这么写）', () {
      final doc = parseLrc('[00:12:34]A');
      expect(doc.lines.single.at, const Duration(seconds: 12, milliseconds: 340));
    });

    test('分钟只有一位、秒只有一位', () {
      final doc = parseLrc('[0:5.00]A');
      expect(doc.lines.single.at, const Duration(seconds: 5));
    });

    test('超过 100 分钟的演唱会歌词', () {
      final doc = parseLrc('[123:45.67]A');
      expect(
        doc.lines.single.at,
        const Duration(minutes: 123, seconds: 45, milliseconds: 670),
      );
    });

    test('一行多个时间戳展开成多行（副歌的标准写法）', () {
      final doc = parseLrc('[00:12.00][01:20.00][02:30.00]副歌重复三次');
      expect(doc.lines, hasLength(3));
      expect(
        doc.lines.map((l) => l.at.inMilliseconds).toList(),
        [12000, 80000, 150000],
      );
      expect(doc.lines.every((l) => l.text == '副歌重复三次'), isTrue);
    });

    test('空正文的时间戳保留成空行（间奏的常见写法）', () {
      final doc = parseLrc('[00:12.00]A\n[00:20.00]\n[00:30.00]B');
      expect(doc.lines, hasLength(3));
      expect(doc.lines[1].text, isEmpty);
    });

    test('输出按时间升序，输入乱序也纠正过来', () {
      final doc = parseLrc('[00:30.00]C\n[00:10.00]A\n[00:20.00]B');
      expect(doc.lines.map((l) => l.text).toList(), ['A', 'B', 'C']);
    });

    test('同一时刻的多行保持原有先后（排序必须稳定）', () {
      // 造足够多的行，逼 Dart 的 sort 走非插入排序的分支 ——
      // 小列表的插入排序本来就是稳定的，只测 2 行测不出这个坑。
      // 同一时刻的行必须**成组**出现，否则测的是时间排序而不是稳定性。
      final buf = StringBuffer('[00:01.00]first\n');
      for (var i = 0; i < 40; i++) {
        buf.writeln('[00:02.00]L${i.toString().padLeft(2, '0')}');
      }
      buf.write('[00:02.00]last');
      final doc = parseLrc(buf.toString());
      final texts = doc.lines.map((l) => l.text).toList();

      expect(texts.first, 'first', reason: '时间最早的行排最前');
      expect(
        texts.sublist(1),
        [
          for (var i = 0; i < 40; i++) 'L${i.toString().padLeft(2, '0')}',
          'last',
        ],
        reason: '同一时刻的行必须保持文件里的先后 —— '
            '乱了的话副歌的几行会在每次重建时来回换位',
      );
    });
  });

  group('元数据标签', () {
    test('ti / ar / al', () {
      final doc = parseLrc('[ti:晴天]\n[ar:周杰伦]\n[al:叶惠美]\n[00:01.00]A');
      expect(doc.title, '晴天');
      expect(doc.artist, '周杰伦');
      expect(doc.album, '叶惠美');
      expect(doc.lines, hasLength(1));
    });

    test('只有元数据、没有任何歌词时，正文是空的', () {
      final doc = parseLrc('[ti:晴天]\n[ar:周杰伦]');
      expect(doc.isEmpty, isTrue);
      expect(doc.title, '晴天');
    });

    test('认不出的标签被忽略，不影响后面的行', () {
      final doc = parseLrc('[by:某人]\n[00:01.00]A\n[re:某播放器]');
      expect(doc.lines, hasLength(1));
      expect(doc.lines.single.text, 'A');
    });

    test('标签与时间戳写在同一行', () {
      final doc = parseLrc('[ar:周杰伦][00:01.00]A');
      expect(doc.artist, '周杰伦');
      expect(doc.lines.single.text, 'A');
    });
  });

  group('offset 标签', () {
    test('正值让歌词提前出现', () {
      final doc = parseLrc('[offset:+500]\n[00:10.00]A');
      expect(doc.offsetMs, 500);
      expect(doc.lines.single.at, const Duration(milliseconds: 9500));
    });

    test('负值让歌词推后', () {
      final doc = parseLrc('[offset:-500]\n[00:10.00]A');
      expect(doc.lines.single.at, const Duration(milliseconds: 10500));
    });

    test('不带正负号按正值算', () {
      final doc = parseLrc('[offset:300]\n[00:10.00]A');
      expect(doc.lines.single.at, const Duration(milliseconds: 9700));
    });

    test('偏移把时间压到负数时钳到 0，而不是负数', () {
      final doc = parseLrc('[offset:+9000]\n[00:01.00]A');
      expect(doc.lines.single.at, Duration.zero);
    });

    test('认不出的 offset 值不影响其余解析', () {
      final doc = parseLrc('[offset:abc]\n[00:10.00]A');
      expect(doc.offsetMs, 0);
      expect(doc.lines.single.at, const Duration(seconds: 10));
    });
  });

  group('增强型 LRC 与容错', () {
    test('词级标签被抹掉，不会显示成正文', () {
      final doc = parseLrc('[00:12.00]<00:12.00>故<00:12.50>事<00:13.00>的小黄花');
      expect(doc.lines.single.text, '故事的小黄花');
    });

    test('CRLF / CR / LF 混用', () {
      final doc = parseLrc('[00:01.00]A\r\n[00:02.00]B\r[00:03.00]C\n[00:04.00]D');
      expect(doc.lines.map((l) => l.text).toList(), ['A', 'B', 'C', 'D']);
    });

    test('UTF-8 BOM 不影响第一行', () {
      final doc = parseLrc('\uFEFF[00:01.00]A');
      expect(doc.lines.single.text, 'A');
    });

    test('空输入与纯空白返回 empty', () {
      expect(parseLrc('').isEmpty, isTrue);
      expect(parseLrc('   \n\n  ').isEmpty, isTrue);
      expect(parseLrc('').isSynced, isFalse);
    });

    test('完全没有时间轴时退化成纯文本', () {
      final doc = parseLrc('第一句\n第二句\n第三句');
      expect(doc.isSynced, isFalse);
      expect(doc.plainText, '第一句\n第二句\n第三句');
    });

    test('有时间轴时，零散的无时间轴行被丢掉（多半是文件头说明）', () {
      final doc = parseLrc('晴天 - 周杰伦\n[00:01.00]A\n下载自某网站');
      expect(doc.isSynced, isTrue);
      expect(doc.lines, hasLength(1));
      expect(doc.plainText, isNull);
    });

    test('半截的方括号不炸，只是认不出', () {
      final doc = parseLrc('[00:01.00未闭合\n[00:02.00]B');
      expect(doc.lines, hasLength(1));
      expect(doc.lines.single.text, 'B');
    });
  });

  group('lineIndexAt', () {
    final doc = parseLrc('[00:10.00]A\n[00:20.00]B\n[00:30.00]C');

    test('第一行之前返回 -1（还没有歌词该点亮）', () {
      expect(doc.lineIndexAt(const Duration(seconds: 5)), -1);
      expect(doc.lineIndexAt(Duration.zero), -1);
    });

    test('正好在某一行的时刻上，点亮该行', () {
      expect(doc.lineIndexAt(const Duration(seconds: 10)), 0);
      expect(doc.lineIndexAt(const Duration(seconds: 20)), 1);
    });

    test('两行之间点亮前一行（歌词从某时刻起一直有效）', () {
      expect(doc.lineIndexAt(const Duration(seconds: 19, milliseconds: 999)), 0);
    });

    test('最后一行之后一直是最后一行', () {
      expect(doc.lineIndexAt(const Duration(minutes: 5)), 2);
    });

    test('没有时间轴时恒为 -1', () {
      expect(parseLrc('纯文本').lineIndexAt(const Duration(seconds: 30)), -1);
    });
  });

  group('decodeTextBytes（歌词与 CUE 共用的编码判定）', () {
    test('UTF-8 中文', () {
      expect(decodeTextBytes(utf8.encode('[00:01.00]晴天')), '[00:01.00]晴天');
    });

    test('GBK 中文（中文 Windows 上抓轨工具写出来的那种）', () {
      // '晴天' 的 GBK 编码
      final gbkBytes = [0xC7, 0xE7, 0xCC, 0xEC];
      expect(decodeTextBytes(gbkBytes), '晴天');
    });

    test('带 BOM 的 UTF-8', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('[00:01.00]A')];
      expect(decodeTextBytes(bytes), '[00:01.00]A');
    });

    test('空字节返回空串', () {
      expect(decodeTextBytes(const []), '');
    });

    test('两种编码都解不了时用替换字符兜底，ASCII 部分保住', () {
      // 0xFF 是两种编码里的非法字节
      final out = decodeTextBytes([0x5B, 0xFF, 0x5D]);
      expect(out.startsWith('['), isTrue);
      expect(out.endsWith(']'), isTrue);
    });
  });
}
