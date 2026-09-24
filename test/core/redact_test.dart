import 'package:cloudtune/core/utils/redact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('maskSecret', () {
    test('null 与空串', () {
      expect(maskSecret(null), '<empty>');
      expect(maskSecret(''), '<empty>');
    });

    test('短值只暴露长度', () {
      expect(maskSecret('abc'), '<3B>');
      expect(maskSecret('12345678'), '<8B>');
    });

    test('长值暴露长度与前 4 位', () {
      expect(maskSecret('7aa52fb080f2d75a1035'), '<20B:7aa5…>');
    });

    test('真实夸克 cookie 不会泄漏（前 4 位之外不可见）', () {
      const pus = '7aa52fb080f2d75a103553d437b23fbbAASk16c0bxIPH0eWx0qHlC3RuUDWphb0GiERi';
      final masked = maskSecret(pus);
      expect(masked, startsWith('<'));
      expect(masked.contains(pus.substring(4, 20)), isFalse);
      expect(masked, contains(pus.substring(0, 4)));
    });
  });

  group('maskMapValues', () {
    test('保留键名，脱敏值', () {
      final m = maskMapValues({'__pus': 'abcdefghijkl', '__puus': 'xyz'});
      expect(m.keys, containsAll(['__pus', '__puus']));
      expect(m['__pus'], '<12B:abcd…>');
      expect(m['__puus'], '<3B>');
    });

    test('空 Map 返回空 Map', () {
      expect(maskMapValues({}), isEmpty);
    });
  });

  group('maskCookieHeader', () {
    test('逐段脱敏', () {
      final masked = maskCookieHeader('__pus=aaa; __puus=bbbbbbbbbb');
      expect(masked, '__pus=<3B>; __puus=<10B:bbbb…>');
    });

    test('空串返回占位符', () {
      expect(maskCookieHeader(''), '<empty>');
    });

    test('忽略空片段', () {
      expect(maskCookieHeader('a=1;;  ; b=2'), 'a=<1B>; b=<1B>');
    });

    test('无等号片段原样保留（便于排查格式错误）', () {
      expect(maskCookieHeader('garbage'), 'garbage');
    });
  });

  group('redactUrl', () {
    test('丢弃查询串（签名在其中）', () {
      expect(
        redactUrl('https://drive-pc.quark.cn/1/clouddrive/file/download?a=1&sign=SECRET'),
        'https://drive-pc.quark.cn/1/clouddrive/file/download',
      );
    });

    test('接受 Uri 对象', () {
      expect(redactUrl(Uri.parse('https://x.com/p?k=v')), 'https://x.com/p');
    });

    test('null 与空串', () {
      expect(redactUrl(null), '<empty>');
      expect(redactUrl(''), '<empty>');
    });

    test('畸形输入不抛异常', () {
      expect(() => redactUrl('::::'), returnsNormally);
      expect(redactUrl('::::'), isA<String>());
    });
  });

  group('scrubSecrets', () {
    test('抹掉 Cookie 段里的值', () {
      expect(
        scrubSecrets('Cookie: __pus=aaa; __puus=bbbbbbbbbb'),
        'Cookie: __pus=<redacted>; __puus=<redacted>',
      );
    });

    test('抹掉直链签名参数', () {
      expect(
        scrubSecrets('https://cdn.x.com/a.flac?token=SECRET&sign=ALSO'),
        'https://cdn.x.com/a.flac?token=<redacted>&sign=<redacted>',
      );
    });

    test('不误伤普通文案', () {
      const text = '取播放直链：文件超出夸克单文件下载体积上限，无法在线播放';
      expect(scrubSecrets(text), text);
    });

    test('无敏感字段时原样返回', () {
      expect(scrubSecrets('已开始播放'), '已开始播放');
      expect(scrubSecrets(''), '');
    });

    test('等号两侧的空格也会被抹掉', () {
      expect(scrubSecrets('token = SECRET'), 'token=<redacted>');
    });

    test('保留字段名本身，便于判断「有没有带上」', () {
      final scrubbed = scrubSecrets('Cookie: __puus=abcdefghijklmnop');
      expect(scrubbed, contains('__puus'));
      expect(scrubbed.contains('abcdefghijklmnop'), isFalse);
    });
  });
}
