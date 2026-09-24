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
}
