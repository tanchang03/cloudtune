import 'package:cloudtune/core/utils/audio_formats.dart';
import 'package:cloudtune/ui/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// 锁死「格式 · 品质」这一列对外的口径。
///
/// 这一列的信息有一半是**推算**出来的：网盘只给文件名 / 体积 / 时长，
/// 码率得自己拿「体积 ÷ 时长」算。所以这里最容易出的错不是渲染，
/// 而是**让用户以为那是文件里写着的官方规格** ——
/// 他拿去和别的软件对账、对不上，就会以为是本应用读错了。
///
/// 把「说明里必须交代这是平均值」变成断言，免得哪天有人顺手把说明改短。
void main() {
  group('label —— 列表里的家族词', () {
    test('每个家族都有词，且互不重复', () {
      final labels = AudioQuality.values.map((q) => q.label).toList();
      for (final l in labels) {
        expect(l, isNotEmpty);
      }
      expect(labels.toSet().length, AudioQuality.values.length);
    });

    test('用用户能直接读懂的说法，不出现「编码」「容器」这类内部词', () {
      expect(AudioQuality.lossless.label, '无损');
      expect(AudioQuality.lossy.label, '有损');
      expect(AudioQuality.dsd.label, 'DSD');
      for (final q in AudioQuality.values) {
        expect(q.label, isNot(contains('编码')));
        expect(q.label, isNot(contains('容器')));
      }
    });
  });

  group('hint —— 悬停说明', () {
    test('每个家族都有说明', () {
      for (final q in AudioQuality.values) {
        expect(q.hint, isNotEmpty, reason: '${q.name} 没有说明');
      }
    });

    test('会显示码率的家族，必须讲清那是「平均值」', () {
      for (final q in const [
        AudioQuality.dsd,
        AudioQuality.lossless,
        AudioQuality.uncompressed,
        AudioQuality.lossy,
      ]) {
        expect(
          q.hint,
          contains('平均值'),
          reason: '${q.name} 的说明没交代码率是推算的，'
              '用户会拿它当官方参数去对账',
        );
      }
    });

    test('有损给出可判断的档位参照', () {
      expect(AudioQuality.lossy.hint, contains('320'));
      expect(AudioQuality.lossy.hint, contains('128'));
    });

    test('未压缩给出 CD 规格参照', () {
      expect(AudioQuality.uncompressed.hint, contains('1411'));
    });
  });

  group('color —— 分档配色', () {
    test('无损与有损不能同色（这是用户最需要一眼分出的两档）', () {
      expect(AudioQuality.lossless.color, isNot(AudioQuality.lossy.color));
    });

    test('有损刻意用最弱的灰，让无损与 DSD 自己跳出来', () {
      expect(AudioQuality.lossy.color, AppTheme.dim);
      expect(AudioQuality.unknown.color, AppTheme.dim);
      expect(AudioQuality.lossless.color, isNot(AppTheme.dim));
      expect(AudioQuality.dsd.color, isNot(AppTheme.dim));
    });
  });

  group('formatBitrate —— 列里那一小串数字', () {
    test('万位以下用 k', () {
      expect(formatBitrate(1411), '1411k');
      expect(formatBitrate(320), '320k');
      expect(formatBitrate(9999), '9999k');
    });

    test('万位及以上换 M（DSD256 是 11290k，不换会把列撑开）', () {
      expect(formatBitrate(10000), '10.0M');
      expect(formatBitrate(11290), '11.3M');
    });

    test('拿不到码率返回 null，调用方据此只显示家族词', () {
      expect(formatBitrate(null), isNull);
      expect(formatBitrate(0), isNull);
      expect(formatBitrate(-1), isNull);
    });
  });
}
