import 'package:cloudtune/core/utils/cookie_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCookieHeader', () {
    test('解析标准 Cookie 头', () {
      final m = parseCookieHeader('__pus=aaa; __puus=bbb; __kp=ccc');
      expect(m, {
        '__pus': 'aaa',
        '__puus': 'bbb',
        '__kp': 'ccc',
      });
    });

    test('按第一个等号切分，保留值里的 base64 padding', () {
      final m = parseCookieHeader('__puus=dfbc5322bdd17481==');
      expect(m['__puus'], 'dfbc5322bdd17481==');
    });

    test('容忍换行分隔', () {
      final m = parseCookieHeader('__pus=aaa\n__puus=bbb\r\n__kp=ccc');
      expect(m.keys, containsAll(['__pus', '__puus', '__kp']));
      expect(m['__puus'], 'bbb');
    });

    test('剥掉成对双引号', () {
      final m = parseCookieHeader('a="quoted value"; b=plain');
      expect(m['a'], 'quoted value');
      expect(m['b'], 'plain');
    });

    test('跳过空片段与无等号片段', () {
      final m = parseCookieHeader(';; a=1 ; garbage ; =noKey ; b=2');
      expect(m, {'a': '1', 'b': '2'});
    });

    test('空字符串返回空 Map', () {
      expect(parseCookieHeader(''), isEmpty);
      expect(parseCookieHeader('   \n  '), isEmpty);
    });

    test('值本身为空字符串时保留该键', () {
      final m = parseCookieHeader('a=; b=2');
      expect(m.containsKey('a'), isTrue);
      expect(m['a'], '');
      expect(m['b'], '2');
    });

    test('重复键以后出现的为准', () {
      final m = parseCookieHeader('a=1; a=2');
      expect(m['a'], '2');
    });
  });

  group('parseCookieLooseText', () {
    test('支持用户粘贴的 `k: v` 换行形式（含冒号前空格）', () {
      const raw = '__pus  :7aa52fb080f2d75a\n__puus: dfbc5322bdd17481';
      final m = parseCookieLooseText(raw);
      expect(m['__pus'], '7aa52fb080f2d75a');
      expect(m['__puus'], 'dfbc5322bdd17481');
    });

    test('含等号的行不会被冒号规则误伤（JWT 场景）', () {
      // 值里有冒号，但整行含 '='，必须按 '=' 切
      const raw = 'token=eyJhbGciOi:JIUzI1NiJ9.payload.sig';
      final m = parseCookieLooseText(raw);
      expect(m['token'], 'eyJhbGciOi:JIUzI1NiJ9.payload.sig');
    });

    test('混合形式可同时解析', () {
      const raw = '__pus=aaa; __kp=bbb\n__puus: ccc';
      final m = parseCookieLooseText(raw);
      expect(m, {'__pus': 'aaa', '__kp': 'bbb', '__puus': 'ccc'});
    });

    test('行尾多余分号被清理', () {
      final m = parseCookieLooseText('__pus: aaa;');
      expect(m['__pus'], 'aaa');
    });

    test('空输入返回空 Map', () {
      expect(parseCookieLooseText(''), isEmpty);
    });
  });

  group('buildCookieHeader', () {
    test('优先键排在最前，其余保持插入顺序', () {
      final header = buildCookieHeader(
        {'__kp': '3', '__pus': '1', '__uid': '4', '__puus': '2'},
        preferredOrder: const ['__pus', '__puus'],
      );
      expect(header, '__pus=1; __puus=2; __kp=3; __uid=4');
    });

    test('跳过空值键', () {
      final header = buildCookieHeader({'a': '1', 'b': '', 'c': '3'});
      expect(header, 'a=1; c=3');
    });

    test('空 Map 返回空串', () {
      expect(buildCookieHeader({}), '');
    });

    test('preferredOrder 中的键不存在时不产生空片段', () {
      final header = buildCookieHeader(
        {'a': '1'},
        preferredOrder: const ['__pus', '__puus'],
      );
      expect(header, 'a=1');
    });
  });
}
