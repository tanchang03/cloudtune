import 'package:cloudtune/data/remote/quark/quark_adapter.dart';
import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/playability.dart';
import 'package:cloudtune/domain/services/playability_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一个**假想的**、声明了 50MiB 播放取链上限的网盘。
///
/// 只用来验证边界逻辑本身（闭区间、+1 字节、体积未知等）。
///
/// ⚠️ 这**不是**夸克的真实声明。夸克的实际声明见
/// [QuarkAdapter.quarkCapabilities]，它**没有**体积上限。
/// 历史上这里曾充当夸克的声明，2026-09-24 验证后已纠正：
/// 50MiB 是 `/1/clouddrive/file/download` 的限制，
/// 播放走的 `/1/clouddrive/file/audioplay` 不受此限。
const limitedCaps = Capabilities(
  provider: DriveProvider.quark,
  canListDirectory: true,
  canSearch: true,
  canResolveDirectLink: true,
  directLinkNeedsHeaders: true,
  supportsRangeRequests: true,
  maxSingleFileBytes: Capabilities.fiftyMiB,
  listQps: 3.0,
  linkQps: 1.0,
);

/// 一个无体积限制、无自定义头需求的假想网盘
const openCaps = Capabilities(
  provider: DriveProvider.aliyun,
  canListDirectory: true,
  canSearch: true,
  canResolveDirectLink: true,
);

void main() {
  const mib = 1024 * 1024;

  group('resolvePlayability — 格式判定', () {
    test('非音频文件直接排除，不进入后续判定', () {
      final p = resolvePlayability(
        fileName: 'cover.jpg',
        capabilities: limitedCaps,
        sizeBytes: 1024,
      );
      expect(p.state, PlayabilityState.notAudio);
      expect(p.isConfirmedPlayable, isFalse);
      expect(p.shouldAttempt, isFalse);
    });

    test('MIME 表明是音频时即使扩展名陌生也放行', () {
      final p = resolvePlayability(
        fileName: 'track.bin',
        capabilities: limitedCaps,
        mimeType: 'audio/flac',
        sizeBytes: 5 * mib,
      );
      expect(p.state, PlayabilityState.playable);
    });
  });

  group('resolvePlayability — 能力判定', () {
    test('网盘不支持直链时整体不可播', () {
      const caps = Capabilities(
        provider: DriveProvider.baidu,
        canResolveDirectLink: false,
      );
      final p = resolvePlayability(
        fileName: 'a.mp3',
        capabilities: caps,
        sizeBytes: 3 * mib,
      );
      expect(p.state, PlayabilityState.unsupportedByProvider);
      expect(p.shouldAttempt, isFalse);
      expect(p.reason, contains('百度网盘'));
    });
  });

  group('resolvePlayability — 体积边界（PoC 实测校准）', () {
    test('体积未知时不判死，交给运行时兜底', () {
      final p = resolvePlayability(
        fileName: 'a.flac',
        capabilities: limitedCaps,
        sizeBytes: null,
      );
      expect(p.state, PlayabilityState.unknownSize);
      expect(p.shouldAttempt, isTrue);
      expect(p.isConfirmedPlayable, isFalse);
    });

    test('体积为 0 视为未知', () {
      final p = resolvePlayability(
        fileName: 'a.flac',
        capabilities: limitedCaps,
        sizeBytes: 0,
      );
      expect(p.state, PlayabilityState.unknownSize);
    });

    test('恰好等于上限判定为可播（边界取闭区间）', () {
      final p = resolvePlayability(
        fileName: 'a.flac',
        capabilities: limitedCaps,
        sizeBytes: Capabilities.fiftyMiB,
      );
      expect(p.state, PlayabilityState.playable);
    });

    test('上限 +1 字节即超限', () {
      final p = resolvePlayability(
        fileName: 'a.flac',
        capabilities: limitedCaps,
        sizeBytes: Capabilities.fiftyMiB + 1,
      );
      expect(p.state, PlayabilityState.overLimit);
      expect(p.limitBytes, Capabilities.fiftyMiB);
    });

    test('48.6MB 实测成功样本 → 可播', () {
      final p = resolvePlayability(
        fileName: 'a.flac',
        capabilities: limitedCaps,
        sizeBytes: (48.6 * mib).round(),
      );
      expect(p.state, PlayabilityState.playable);
    });

    test('53.2MB 实测失败样本 → 超限', () {
      final p = resolvePlayability(
        fileName: 'a.wav',
        capabilities: limitedCaps,
        sizeBytes: (53.2 * mib).round(),
      );
      expect(p.state, PlayabilityState.overLimit);
      expect(p.reason, contains('50.0 MB'));
    });

    test('声明了上限的网盘：18MB 的 dsf 可播，200MB 的 dsf 超限', () {
      expect(
        resolvePlayability(
          fileName: 'a.dsf',
          capabilities: limitedCaps,
          sizeBytes: 18 * mib,
        ).state,
        PlayabilityState.playable,
      );
      expect(
        resolvePlayability(
          fileName: 'a.dsf',
          capabilities: limitedCaps,
          sizeBytes: 200 * mib,
        ).state,
        PlayabilityState.overLimit,
      );
    });

    test('无体积上限的网盘：再大也可播', () {
      final p = resolvePlayability(
        fileName: 'huge.flac',
        capabilities: openCaps,
        sizeBytes: 4096 * mib,
      );
      expect(p.state, PlayabilityState.playable);
    });
  });

  group('Playability 语义', () {
    test('needsBadge 只在非纯可播时为真', () {
      const ok = Playability(PlayabilityState.playable);
      expect(ok.needsBadge, isFalse);
      expect(ok.isConfirmedPlayable, isTrue);
      expect(ok.shouldAttempt, isTrue);

      const unknown = Playability(PlayabilityState.unknownSize, reason: 'x');
      expect(unknown.needsBadge, isTrue);
      expect(unknown.shouldAttempt, isTrue);

      const over = Playability(PlayabilityState.overLimit, reason: 'x');
      expect(over.needsBadge, isTrue);
      expect(over.shouldAttempt, isFalse);
    });

    test('值相等性', () {
      expect(
        const Playability(PlayabilityState.overLimit, reason: 'a', limitBytes: 1),
        const Playability(PlayabilityState.overLimit, reason: 'a', limitBytes: 1),
      );
      expect(
        const Playability(PlayabilityState.playable),
        isNot(const Playability(PlayabilityState.notAudio)),
      );
    });
  });

  group('PlayabilityAccumulator', () {
    test('空累加器给出全零摘要', () {
      final s = PlayabilityAccumulator().summary;
      expect(s.total, 0);
      expect(s.playableRatio, 0);
      expect(s.playableBytesRatio, 0);
    });

    test('按状态分类计数，并统计体积', () {
      final acc = PlayabilityAccumulator();
      acc.add(const Playability(PlayabilityState.playable), sizeBytes: 10 * mib);
      acc.add(const Playability(PlayabilityState.playable), sizeBytes: 20 * mib);
      acc.add(const Playability(PlayabilityState.unknownSize), sizeBytes: 5 * mib);
      acc.add(const Playability(PlayabilityState.overLimit), sizeBytes: 100 * mib);
      acc.add(const Playability(PlayabilityState.notAudio));

      final s = acc.summary;
      expect(s.playable, 2);
      expect(s.unknownSize, 1);
      expect(s.overLimit, 1);
      expect(s.notAudio, 1);
      expect(s.total, 5);
      // 可播体积 = 10 + 20 + 5（未知体积算乐观可播）
      expect(s.playableBytes, 35 * mib);
      // 总体积 = 35 + 100（非音频不计体积）
      expect(s.totalBytes, 135 * mib);
    });

    test('可播比例 = (可播 + 未知) / (可播 + 未知 + 超限 + 不支持)', () {
      final acc = PlayabilityAccumulator();
      for (var i = 0; i < 239; i++) {
        acc.add(const Playability(PlayabilityState.playable), sizeBytes: 1);
      }
      for (var i = 0; i < 205; i++) {
        acc.add(const Playability(PlayabilityState.overLimit), sizeBytes: 1);
      }
      final s = acc.summary;
      expect(s.playableRatio, closeTo(239 / 444, 1e-9));
    });

    test('可播体积占比（对齐 PoC 的 20.2% 口径）', () {
      final acc = PlayabilityAccumulator();
      acc.add(const Playability(PlayabilityState.playable), sizeBytes: 7_500_000_000);
      acc.add(const Playability(PlayabilityState.overLimit), sizeBytes: 29_700_000_000);
      expect(acc.summary.playableBytesRatio, closeTo(0.2016, 0.001));
    });

    test('体积为负或 0 不污染统计', () {
      final acc = PlayabilityAccumulator();
      acc.add(const Playability(PlayabilityState.playable), sizeBytes: 0);
      acc.add(const Playability(PlayabilityState.playable), sizeBytes: -5);
      expect(acc.summary.totalBytes, 0);
      expect(acc.summary.playable, 2);
    });
  });

  group('Capabilities', () {
    test('hasFileSizeLimit 反映是否声明了上限', () {
      expect(limitedCaps.hasFileSizeLimit, isTrue);
      expect(openCaps.hasFileSizeLimit, isFalse);
    });

    test('copyWith 可清除体积上限', () {
      final cleared = limitedCaps.copyWith(clearMaxSingleFileBytes: true);
      expect(cleared.maxSingleFileBytes, isNull);
      expect(cleared.provider, DriveProvider.quark);
      expect(cleared.listQps, 3.0);
    });

    test('copyWith 不改动未传字段', () {
      final c = limitedCaps.copyWith(listQps: 5.0);
      expect(c.listQps, 5.0);
      expect(c.maxSingleFileBytes, Capabilities.fiftyMiB);
      expect(c.directLinkNeedsHeaders, isTrue);
    });
  });

  // -------------------------------------------------------------------
  // 2026-09-24 取流路由改造的**回归锁**
  //
  // 背景：夸克曾经声明了 50MiB 上限，导致库内 195 首（43.9%）被判
  // 「超限不可播」。而 50MiB 只是 /1/clouddrive/file/download 这条
  // **下载**路由的限制；播放改走 /1/clouddrive/file/audioplay 之后，
  // 实测 774.1MB 的文件也能拿到原文件直链。
  //
  // 这组测试锁住「不得再把 download 的上限写进播放能力声明」，
  // 因为那个错误会静默地让近一半曲库不可播。
  // -------------------------------------------------------------------
  group('夸克的真实能力声明（不得再声明体积上限）', () {
    const caps = QuarkAdapter.quarkCapabilities;

    test('不声明体积上限', () {
      expect(caps.maxSingleFileBytes, isNull);
      expect(caps.hasFileSizeLimit, isFalse);
    });

    test('774.1MB 的整轨 WAV 判定为可播', () {
      final p = resolvePlayability(
        fileName: '张宇.-.[好男人的情歌 NEW XRCD](2016)[WAV].wav',
        capabilities: caps,
        sizeBytes: 811679948,
      );
      expect(p.state, PlayabilityState.playable);
      expect(p.shouldAttempt, isTrue);
    });

    test('库内「超限」那一批的代表样本全部判定为可播', () {
      // 体积取自真实曲库扫描结果（444 首中 >50MiB 的 195 首）
      const samples = <String, int>{
        '凤凰传奇 - 奇迹世界.flac': 198018943, // 188.8MB
        '07. 温柔的你.dsf': 219652256, // 209.5MB
        '张宇.-.[好男人的情歌 NEW XRCD](2016)[WAV].wav': 811679948, // 774.1MB
      };
      samples.forEach((name, size) {
        final p = resolvePlayability(
          fileName: name,
          capabilities: caps,
          sizeBytes: size,
        );
        expect(
          p.state,
          PlayabilityState.playable,
          reason: '$name（${size ~/ mib}MB）应判定为可播',
        );
      });
    });

    test('195 首「超限」曲目不再被提前判死', () {
      final acc = PlayabilityAccumulator();
      for (var i = 0; i < 195; i++) {
        final size = (60 + i) * mib; // 全部大于旧口径的 50MiB
        acc.add(
          resolvePlayability(
            fileName: 'track$i.flac',
            capabilities: caps,
            sizeBytes: size,
          ),
          sizeBytes: size,
        );
      }
      final s = acc.summary;
      expect(s.overLimit, 0);
      expect(s.playable, 195);
      expect(s.playableRatio, 1.0);
    });
  });

  group('AuthMode', () {
    test('fromId 可反查，未知返回 null', () {
      expect(AuthMode.fromId('browser_cookie'), AuthMode.browserCookie);
      expect(AuthMode.fromId('oauth'), AuthMode.oauth);
      expect(AuthMode.fromId('nope'), isNull);
    });

    test('id 全局唯一', () {
      final ids = AuthMode.values.map((m) => m.id).toSet();
      expect(ids.length, AuthMode.values.length);
    });
  });

  group('DriveProvider', () {
    test('parse 严格解析', () {
      expect(DriveProvider.parse('quark'), DriveProvider.quark);
      expect(() => DriveProvider.parse('nope'), throwsArgumentError);
    });

    test('fromId 宽容解析', () {
      expect(DriveProvider.fromId('aliyun'), DriveProvider.aliyun);
      expect(DriveProvider.fromId('nope'), isNull);
    });

    test('id 全局唯一且非空', () {
      final ids = DriveProvider.values.map((p) => p.id).toSet();
      expect(ids.length, DriveProvider.values.length);
      expect(ids.every((i) => i.isNotEmpty), isTrue);
    });
  });
}
