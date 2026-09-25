import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/drive_entry.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/playability.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:flutter_test/flutter_test.dart';

Track makeTrack({
  String remoteId = 'f1',
  String name = '周杰伦 - 晴天.flac',
  int? sizeBytes = 30 * 1024 * 1024,
  String? path,
  DriveProvider provider = DriveProvider.quark,
}) =>
    Track(
      provider: provider,
      remoteId: remoteId,
      name: name,
      sizeBytes: sizeBytes,
      path: path,
    );

void main() {
  group('身份与等价性', () {
    test('id 由「网盘 + 远端 ID」拼成，可读且稳定', () {
      expect(makeTrack(remoteId: 'abc').id, 'quark:abc');
      expect(
        makeTrack(remoteId: 'abc', provider: DriveProvider.aliyun).id,
        'aliyun:abc',
      );
    });

    test('不同网盘的同一 remoteId 不相等（避免跨盘碰撞）', () {
      final a = makeTrack(remoteId: 'same', provider: DriveProvider.quark);
      final b = makeTrack(remoteId: 'same', provider: DriveProvider.aliyun);
      expect(a == b, isFalse);
      expect({a, b}.length, 2);
    });

    test('相同身份即相等，即使元数据不同', () {
      final a = makeTrack(name: 'x.mp3', sizeBytes: 1);
      final b = makeTrack(name: 'y.flac', sizeBytes: 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('可作为 Set / Map 键做去重', () {
      final set = {makeTrack(remoteId: '1'), makeTrack(remoteId: '1'), makeTrack(remoteId: '2')};
      expect(set.length, 2);
    });

    test('hasSameMetadataAs 识别元数据变化', () {
      final a = makeTrack(sizeBytes: 1);
      final b = makeTrack(sizeBytes: 2);
      expect(a.hasSameMetadataAs(b), isFalse);
      expect(a.hasSameMetadataAs(makeTrack(sizeBytes: 1)), isTrue);
    });

    test('hasSameMetadataAs 对路径变化敏感（文件被移动）', () {
      expect(
        makeTrack(path: '/a/').hasSameMetadataAs(makeTrack(path: '/b/')),
        isFalse,
      );
    });
  });

  group('格式识别', () {
    test('extension 取小写扩展名', () {
      expect(makeTrack(name: 'A.FLAC').extension, 'flac');
      expect(makeTrack(name: 'noext').extension, '');
    });

    test('isHighResFormat 标记 DSD / WAV', () {
      expect(makeTrack(name: 'a.dsf').isHighResFormat, isTrue);
      expect(makeTrack(name: 'a.wav').isHighResFormat, isTrue);
      expect(makeTrack(name: 'a.flac').isHighResFormat, isFalse);
    });
  });

  group('展示字段', () {
    test('优先用元数据里的标题与艺术家', () {
      final t = Track(
        provider: DriveProvider.quark,
        remoteId: '1',
        name: '01. track.mp3',
        title: '真正的标题',
        artist: '真正的艺术家',
      );
      expect(t.displayTitle, '真正的标题');
      expect(t.displayArtist, '真正的艺术家');
    });

    test('元数据缺失时退化到文件名解析', () {
      final t = makeTrack(name: '周杰伦 - 晴天.flac');
      expect(t.displayTitle, '晴天');
      expect(t.displayArtist, '周杰伦');
    });

    test('空白元数据不算有效值', () {
      final t = Track(
        provider: DriveProvider.quark,
        remoteId: '1',
        name: '周杰伦 - 晴天.flac',
        title: '   ',
        artist: '',
      );
      expect(t.displayTitle, '晴天');
      expect(t.displayArtist, '周杰伦');
    });

    test('displaySubtitle 拼「艺术家 · 专辑」', () {
      final t = Track(
        provider: DriveProvider.quark,
        remoteId: '1',
        name: 'a.flac',
        artist: '周杰伦',
        album: '叶惠美',
      );
      expect(t.displaySubtitle, '周杰伦 · 叶惠美');
    });

    test('无艺术家与专辑时退回所在目录名', () {
      final t = makeTrack(name: 'a.flac', path: '/音乐/华语/');
      expect(t.displaySubtitle, '华语');
    });

    test('全都没有时返回空串', () {
      expect(makeTrack(name: 'a.flac').displaySubtitle, '');
    });
  });

  group('fullPath（用户定位用）', () {
    test('目录 + 文件名拼成完整路径', () {
      expect(
        makeTrack(name: '晴天.flac', path: '/音乐/华语/').fullPath,
        '/音乐/华语/晴天.flac',
      );
    });

    test('目录末尾无 / 时自动补', () {
      expect(
        makeTrack(name: '晴天.flac', path: '/音乐/华语').fullPath,
        '/音乐/华语/晴天.flac',
      );
    });

    test('目录为空时只返回文件名（兜底）', () {
      expect(makeTrack(name: 'a.flac').fullPath, 'a.flac');
      expect(makeTrack(name: 'a.flac', path: '').fullPath, 'a.flac');
      expect(makeTrack(name: 'a.flac', path: null).fullPath, 'a.flac');
    });
  });

  group('可播性', () {
    const caps = Capabilities(
      provider: DriveProvider.quark,
      maxSingleFileBytes: Capabilities.fiftyMiB,
    );

    test('30MB 可播', () {
      expect(makeTrack(sizeBytes: 30 * 1024 * 1024).playability(caps).state,
          PlayabilityState.playable);
    });

    test('120MB 超限', () {
      expect(makeTrack(sizeBytes: 120 * 1024 * 1024).playability(caps).state,
          PlayabilityState.overLimit);
    });

    test('体积未知', () {
      expect(makeTrack(sizeBytes: null).playability(caps).state,
          PlayabilityState.unknownSize);
    });
  });

  group('fromEntry', () {
    test('映射基础字段并解析标题', () {
      final entry = DriveEntry(
        id: 'x1',
        name: '01. 周杰伦 - 晴天.flac',
        isDirectory: false,
        sizeBytes: 12345,
        mimeType: 'audio/flac',
        parentId: 'dir1',
      );
      final t = Track.fromEntry(
        entry: entry,
        provider: DriveProvider.quark,
        path: '/音乐/华语/',
      );
      expect(t.remoteId, 'x1');
      expect(t.provider, DriveProvider.quark);
      expect(t.parentId, 'dir1');
      expect(t.path, '/音乐/华语/');
      expect(t.sizeBytes, 12345);
      expect(t.mimeType, 'audio/flac');
      expect(t.displayTitle, '晴天');
      expect(t.displayArtist, '周杰伦');
    });

    test('未传 path 时回落到 entry 自带的 path', () {
      final entry = DriveEntry(
        id: 'x1',
        name: 'a.mp3',
        isDirectory: false,
        path: '/from-entry/',
      );
      final t = Track.fromEntry(entry: entry, provider: DriveProvider.quark);
      expect(t.path, '/from-entry/');
    });

    test('把目录当文件传入会触发断言（搜索接口会返回目录，实测坑）', () {
      final dirEntry = DriveEntry(id: 'd1', name: '音乐', isDirectory: true);
      expect(
        () => Track.fromEntry(entry: dirEntry, provider: DriveProvider.quark),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('copyWith', () {
    test('只改指定字段', () {
      final t = makeTrack(sizeBytes: 1, path: '/a/');
      final t2 = t.copyWith(sizeBytes: 2);
      expect(t2.sizeBytes, 2);
      expect(t2.path, '/a/');
      expect(t2.remoteId, t.remoteId);
      expect(t2.provider, t.provider);
    });

    test('duration 由 durationMs 派生', () {
      final t = makeTrack().copyWith(durationMs: 215000);
      expect(t.duration, const Duration(seconds: 215));
      expect(makeTrack().duration, isNull);
    });
  });

  group('CUE 分轨', () {
    /// 一张 72:18 的整轨 WAV（对应仓库里真实存在的
    /// `李克勤.-.[精选到无朋友 CD1](2014)[WAV].wav` = 765145628 字节）。
    Track imageFile() => Track(
          provider: DriveProvider.quark,
          remoteId: 'wav765',
          name: '李克勤.-.[精选到无朋友 CD1](2014)[WAV].wav',
          path: '/音乐/华语/精选到无朋友/',
          sizeBytes: 765145628,
          mimeType: 'audio/wav',
          durationMs: 4338000,
          title: '精选到无朋友',
        );

    test('整轨分段：id 带 #cN 后缀，同一整轨切出的各段互不相同', () {
      final image = imageFile();
      final seg1 = Track.cueSegment(
        source: image,
        trackNo: 1,
        startMs: 0,
        durationMs: 200493,
        title: '红日',
      );
      final seg3 = Track.cueSegment(
        source: image,
        trackNo: 3,
        startMs: 420000,
        durationMs: 300000,
        title: '护花使者',
      );

      expect(seg1.id, 'quark:wav765#c1');
      expect(seg3.id, 'quark:wav765#c3');
      expect(seg1.id, isNot(seg3.id));
      // 身份不同 → 收藏/播放次数才能各算各的
      expect(seg1 == seg3, isFalse);
      expect({seg1, seg3, image}.length, 3);
    });

    test('整轨分段继承整轨文件的 remoteId / name / 体积 / 路径', () {
      final seg = Track.cueSegment(
        source: imageFile(),
        trackNo: 2,
        startMs: 200493,
        durationMs: 219507,
        title: '月半小夜曲',
      );

      // remoteId 是取流的键：必须仍指向真实 WAV，否则播不了
      expect(seg.remoteId, 'wav765');
      // name 决定格式识别与可播性：必须保留真实扩展名
      expect(seg.extension, 'wav');
      expect(seg.isHighResFormat, isTrue);
      // 体积保留整轨体积 —— 「这一轨占多少字节」在整轨里没有答案
      expect(seg.sizeBytes, 765145628);
      expect(seg.fullPath, '/音乐/华语/精选到无朋友/'
          '李克勤.-.[精选到无朋友 CD1](2014)[WAV].wav');
      // 时长是**本轨**时长，不是整轨时长
      expect(seg.duration, const Duration(milliseconds: 219507));
    });

    test('cueEndMs = 起点 + 本轨时长；时长未知时为 null', () {
      final seg = Track.cueSegment(
        source: imageFile(),
        trackNo: 2,
        startMs: 200493,
        durationMs: 219507,
      );
      expect(seg.cueEndMs, 420000);

      final noDuration =
          Track.cueSegment(source: imageFile(), trackNo: 9, startMs: 1000);
      expect(noDuration.cueEndMs, isNull);
      // 时长 0 也不该算出「终点 == 起点」这种无意义的区间
      expect(
        Track.cueSegment(
          source: imageFile(),
          trackNo: 9,
          startMs: 1000,
          durationMs: 0,
        ).cueEndMs,
        isNull,
      );
    });

    test('起点为 0 也仍是分段（判据是非空，不是大于 0）', () {
      final seg =
          Track.cueSegment(source: imageFile(), trackNo: 1, startMs: 0, durationMs: 1);
      expect(seg.cueStartMs, 0);
      expect(seg.isCueSegment, isTrue);
      expect(seg.id, 'quark:wav765#c1');
    });

    test('分轨元数据增强：有轨号但没起点，id 必须保持原样', () {
      // 这是最容易写错的一处：如果按「有轨号」加后缀，就会凭空改掉
      // 一个真实独立文件的主键，用户之前收藏的那条会变成孤儿。
      final own = makeTrack(remoteId: 'flac1', name: '01 红日.flac')
          .copyWith(cueTrackNo: 1, title: '红日');

      expect(own.isFromCue, isTrue);
      expect(own.isCueSegment, isFalse);
      expect(own.id, 'quark:flac1', reason: '独立文件的主键不能因为 CUE 而改变');
    });

    test('普通曲目两个标记都为 false，id 不带后缀', () {
      final plain = makeTrack(remoteId: 'x');
      expect(plain.isCueSegment, isFalse);
      expect(plain.isFromCue, isFalse);
      expect(plain.cueTrackLabel, isNull);
      expect(plain.id, 'quark:x');
    });

    test('cueTrackLabel 给出「第 N 轨」', () {
      final seg =
          Track.cueSegment(source: imageFile(), trackNo: 12, startMs: 0);
      expect(seg.cueTrackLabel, '第 12 轨');
    });

    test('分段没拿到 CUE 曲名时，退到「第 N 轨」而不是整轨文件名', () {
      final noTitle =
          Track.cueSegment(source: imageFile(), trackNo: 7, startMs: 0);
      expect(noTitle.title, isNull);
      expect(noTitle.displayTitle, '第 7 轨');

      // 有曲名时当然用曲名
      expect(
        Track.cueSegment(
          source: imageFile(),
          trackNo: 7,
          startMs: 0,
          title: '红日',
        ).displayTitle,
        '红日',
      );
    });

    test('分段没给艺术家时继承整轨的艺术家', () {
      final image = imageFile().copyWith(artist: '李克勤');
      expect(
        Track.cueSegment(source: image, trackNo: 1, startMs: 0).artist,
        '李克勤',
      );
      expect(
        Track.cueSegment(
          source: image,
          trackNo: 1,
          startMs: 0,
          artist: '群星',
        ).artist,
        '群星',
      );
    });

    test('hasSameMetadataAs 能察觉分轨点变化（否则换 CUE 后不会写库）', () {
      final a = Track.cueSegment(
        source: imageFile(),
        trackNo: 1,
        startMs: 0,
        durationMs: 200493,
      );
      final same = Track.cueSegment(
        source: imageFile(),
        trackNo: 1,
        startMs: 0,
        durationMs: 200493,
      );
      final moved = Track.cueSegment(
        source: imageFile(),
        trackNo: 1,
        startMs: 32,
        durationMs: 200461,
      );

      expect(a.hasSameMetadataAs(same), isTrue);
      expect(a.hasSameMetadataAs(moved), isFalse);
      expect(a.hasSameMetadataAs(imageFile()), isFalse);
    });

    test('copyWith 能带上 CUE 字段', () {
      final seg = makeTrack()
          .copyWith(cueTrackNo: 3, cueStartMs: 1000, durationMs: 5000);
      expect(seg.cueTrackNo, 3);
      expect(seg.cueStartMs, 1000);
      expect(seg.cueEndMs, 6000);
      expect(seg.id, 'quark:f1#c3');
    });
  });

  // 「整轨连播」要靠它：分段是扫描时切出来的，整轨那一行已经被扫描器删掉
  // （见 `CueIndexResult.replacedImageIds`），所以播整轨只能就地还原。
  group('CUE 整轨还原（Track.imageOf）', () {
    Track imageFile({
      String remoteId = 'wav765',
      String name = '李克勤.-.[精选到无朋友 CD1](2014)[WAV].wav',
    }) =>
        Track(
          provider: DriveProvider.quark,
          remoteId: remoteId,
          name: name,
          path: '/音乐/华语/精选到无朋友/',
          sizeBytes: 765145628,
          mimeType: 'audio/wav',
          durationMs: 4338000,
          artist: '李克勤',
        );

    /// 首尾相接的三轨，末轨终点正好是整轨真实时长 4338000ms。
    List<Track> segments() => [
          Track.cueSegment(
            source: imageFile(),
            trackNo: 1,
            startMs: 0,
            durationMs: 200493,
          ),
          Track.cueSegment(
            source: imageFile(),
            trackNo: 2,
            startMs: 200493,
            durationMs: 219507,
          ),
          Track.cueSegment(
            source: imageFile(),
            trackNo: 3,
            startMs: 420000,
            durationMs: 3918000,
          ),
        ];

    test('还原出的整轨身份与真实文件一致：id 不带 #cN 后缀', () {
      final image = Track.imageOf(segments())!;

      expect(image.id, 'quark:wav765', reason: '整轨的主键就是它自己的主键');
      expect(image.isCueSegment, isFalse);
      expect(image.name, '李克勤.-.[精选到无朋友 CD1](2014)[WAV].wav');
      expect(image.sizeBytes, 765145628);
      expect(image.artist, '李克勤');
      // 还原出来的整轨必须能当独立曲目播 —— 队列里放的就是它
      expect(image.isFromCue, isFalse);
      expect(image.cueEndMs, isNull);
    });

    test('整轨时长取「所有分段终点的最大值」，而不是某一段的时长', () {
      final image = Track.imageOf(segments())!;
      expect(image.duration, const Duration(milliseconds: 4338000));
      expect(
        image.duration,
        isNot(const Duration(milliseconds: 200493)),
        reason: '拿第一段的时长当整轨时长是最容易犯的错',
      );
    });

    test('与顺序无关：分段打乱后还原出的时长一样', () {
      expect(
        Track.imageOf(segments().reversed.toList())!.durationMs,
        4338000,
      );
    });

    test('刻意不给 title —— 整轨的展示名用文件名推出来的那个', () {
      final image = Track.imageOf(segments())!;
      expect(image.title, isNull);
      expect(
        image.displayTitle,
        isNot('精选到无朋友'),
        reason: 'CUE 的 TITLE 是**专辑**名，当整轨的曲名会串味',
      );
    });

    test('空列表 / 非分段 / 混了两张整轨 —— 一律返回 null', () {
      expect(Track.imageOf(const []), isNull);
      expect(
        Track.imageOf([imageFile()]),
        isNull,
        reason: '整轨本身不是分段，不该被「还原」成自己',
      );
      expect(
        Track.imageOf([
          ...segments(),
          Track.cueSegment(
            source: imageFile(remoteId: 'wav766', name: '...CD2](2014)[WAV].wav'),
            trackNo: 1,
            startMs: 0,
            durationMs: 1000,
          ),
        ]),
        isNull,
        reason: '混了两张整轨时必须拒绝，而不是悄悄挑一张 —— '
            '挑错了用户点「整轨连播」只会听到 CD1，还会以为是 bug',
      );
    });

    test('所有分段都拿不到时长时，整轨时长留 null 而不是 0', () {
      final image = Track.imageOf([
        Track.cueSegment(source: imageFile(), trackNo: 1, startMs: 0),
      ])!;

      expect(image.durationMs, isNull);
      expect(image.duration, isNull, reason: '界面显示 --:-- 比显示 0:00 诚实');
    });
  });
}
