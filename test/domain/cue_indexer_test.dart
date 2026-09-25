import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudtune/core/error/drive_error.dart';
import 'package:cloudtune/domain/entities/drive_entry.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/domain/services/cue_indexer.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一张整轨专辑的 CUE：一个 72:18 的 WAV 切出 3 轨。
///
/// 用的是仓库里真实存在的那张专辑的形状
/// （`李克勤.-.[精选到无朋友 CD1](2014)[WAV].wav` = 765145628B / 4338s）。
const _singleImageCue = '''
PERFORMER "李克勤"
TITLE "精选到无朋友"
REM GENRE Pop
FILE "CD1.wav" WAVE
  TRACK 01 AUDIO
    TITLE "红日"
    INDEX 00 00:00:00
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "月半小夜曲"
    INDEX 01 03:20:37
  TRACK 03 AUDIO
    TITLE "护花使者"
    INDEX 01 07:00:00
''';

/// 分轨专辑的 CUE：音频文件本来就是分开的。
const _multiFileCue = '''
PERFORMER "李克勤"
TITLE "精选到无朋友"
FILE "01 红日.flac" WAVE
  TRACK 01 AUDIO
    TITLE "红日"
    INDEX 01 00:00:00
FILE "02 月半小夜曲.flac" WAVE
  TRACK 02 AUDIO
    TITLE "月半小夜曲"
    INDEX 01 00:00:00
''';

Track audio(
  String remoteId,
  String name, {
  int? durationMs,
  String? artist,
  String? album,
  String path = '/音乐/精选/',
}) =>
    Track(
      provider: DriveProvider.quark,
      remoteId: remoteId,
      name: name,
      path: path,
      sizeBytes: 765145628,
      durationMs: durationMs,
      artist: artist,
      album: album,
    );

DriveEntry cueEntry(String id, String name) =>
    DriveEntry(id: id, name: name, isDirectory: false, sizeBytes: 4096);

/// 测试用的小包装：把「怎么读 CUE」与「跑一次目录处理」绑在一起，
/// 让每个用例只关心 tracks / cueFiles 这两份输入。
///
/// 用包装而不是让 `CueIndexer` 持有读取闭包，是因为生产代码里读取能力
/// 来自「扫描时才知道是哪个网盘的适配器」，索引器本身保持无状态。
class CueIndexHarness {
  CueIndexHarness(this.cueTexts, {this.failWith, this.rawBytes});

  final Map<String, String> cueTexts;
  final Object? failWith;
  final Map<String, List<int>>? rawBytes;

  Future<CueIndexResult> indexDirectory({
    required List<Track> tracks,
    required List<DriveEntry> cueFiles,
  }) =>
      const CueIndexer().indexDirectory(
        readFile: (id) async {
          if (failWith != null) throw failWith!;
          final raw = rawBytes?[id];
          if (raw != null) return Uint8List.fromList(raw);
          final text = cueTexts[id];
          if (text == null) {
            throw const DriveException(
              type: DriveErrorType.notFound,
              message: '无此文件',
            );
          }
          return Uint8List.fromList(utf8.encode(text));
        },
        tracks: tracks,
        cueFiles: cueFiles,
      );
}

/// 用一份「id → CUE 文本」的表造一个目录处理器。
///
/// [failWith] 非空时读取一律抛它，用来测读取失败的降级。
CueIndexHarness buildIndexer(
  Map<String, String> cueTexts, {
  Object? failWith,
  Map<String, List<int>>? rawBytes,
}) =>
    CueIndexHarness(cueTexts, failWith: failWith, rawBytes: rawBytes);

void main() {
  group('整轨展开', () {
    test('1 个 FILE + 3 轨 → 切出 3 首，整轨本身被取代', () async {
      final image = audio('wav1', 'CD1.wav', durationMs: 4338000);
      final result = await buildIndexer({'c1': _singleImageCue}).indexDirectory(
        tracks: [image],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );

      expect(result.extraTracks, hasLength(3));
      expect(result.replacedImageIds, {image.id});
      expect(result.patchedTracks, isEmpty);

      final segs = result.extraTracks;
      expect(segs.map((t) => t.id),
          ['quark:wav1#c1', 'quark:wav1#c2', 'quark:wav1#c3']);
      expect(segs.map((t) => t.title), ['红日', '月半小夜曲', '护花使者']);
      // INDEX 00 是 pregap，起点必须取 INDEX 01
      expect(segs.map((t) => t.cueStartMs), [0, 200493, 420000]);
      expect(segs.map((t) => t.cueTrackNo), [1, 2, 3]);
      expect(segs.every((t) => t.isCueSegment), isTrue);
    });

    test('每首的时长是「本轨」时长，不是整轨时长', () async {
      final image = audio('wav1', 'CD1.wav', durationMs: 4338000);
      final result = await buildIndexer({'c1': _singleImageCue}).indexDirectory(
        tracks: [image],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );

      final segs = result.extraTracks;
      expect(segs[0].duration, const Duration(milliseconds: 200493));
      expect(segs[1].duration, const Duration(milliseconds: 219507));
      // 末轨终点由整轨真实时长补齐：4338000 - 420000
      expect(segs[2].duration, const Duration(milliseconds: 3918000));
      expect(segs[2].cueEndMs, 4338000);
    });

    test('拿不到整轨时长时，末轨时长为 null（不编造数字）', () async {
      // 网盘没刮削出 duration 是常态
      final image = audio('wav1', 'CD1.wav');
      final result = await buildIndexer({'c1': _singleImageCue}).indexDirectory(
        tracks: [image],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );

      final segs = result.extraTracks;
      expect(segs[0].duration, isNotNull, reason: '有下一轨的起点，就能算出终点');
      expect(segs[2].duration, isNull);
      expect(segs[2].cueEndMs, isNull);
    });

    test('继承整轨文件：remoteId / name / 体积 / 路径', () async {
      final image = audio('wav1', 'CD1.wav', durationMs: 4338000);
      final result = await buildIndexer({'c1': _singleImageCue}).indexDirectory(
        tracks: [image],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );

      final seg = result.extraTracks.first;
      expect(seg.remoteId, 'wav1', reason: '取流要用整轨文件的 id');
      expect(seg.name, 'CD1.wav', reason: '格式识别要靠真实扩展名');
      expect(seg.sizeBytes, 765145628);
      expect(seg.path, '/音乐/精选/');
    });

    test('专辑级 PERFORMER / TITLE 落到每首的 artist / album', () async {
      final image = audio('wav1', 'CD1.wav', durationMs: 4338000);
      final result = await buildIndexer({'c1': _singleImageCue}).indexDirectory(
        tracks: [image],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );

      for (final seg in result.extraTracks) {
        expect(seg.artist, '李克勤');
        expect(seg.album, '精选到无朋友');
      }
    });

    test('只有一轨的「整轨」不展开（和普通单行曲目没区别）', () async {
      const oneTrack = 'FILE "CD1.wav" WAVE\n'
          '  TRACK 01 AUDIO\n'
          '    TITLE "唯一一首"\n'
          '    INDEX 01 00:00:00\n';
      final image = audio('wav1', 'CD1.wav', durationMs: 1000);
      final result = await buildIndexer({'c1': oneTrack}).indexDirectory(
        tracks: [image],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );

      expect(result.extraTracks, isEmpty);
      expect(result.replacedImageIds, isEmpty);
    });
  });

  group('分轨元数据增强', () {
    test('多个 FILE → 只覆盖元数据，不动曲目结构', () async {
      final t1 = audio('f1', '01 红日.flac');
      final t2 = audio('f2', '02 月半小夜曲.flac');
      final result = await buildIndexer({'c1': _multiFileCue}).indexDirectory(
        tracks: [t1, t2],
        cueFiles: [cueEntry('c1', 'album.cue')],
      );

      expect(result.extraTracks, isEmpty, reason: '分轨不该再切出虚拟曲目');
      expect(result.replacedImageIds, isEmpty);
      expect(result.patchedTracks, hasLength(2));

      final byId = {for (final t in result.patchedTracks) t.id: t};
      final p1 = byId['quark:f1']!;
      expect(p1.title, '红日');
      expect(p1.artist, '李克勤');
      expect(p1.album, '精选到无朋友');
      // 有轨号（界面要显示「第 1 轨」），但没有「整轨内起点」
      expect(p1.cueTrackNo, 1);
      expect(p1.cueStartMs, isNull);
      expect(p1.isCueSegment, isFalse);
      expect(p1.isFromCue, isTrue);
    });

    test('分轨的 id 保持原样（主键不能因为 CUE 而变）', () async {
      final t1 = audio('f1', '01 红日.flac');
      final result = await buildIndexer({'c1': _multiFileCue}).indexDirectory(
        tracks: [t1],
        cueFiles: [cueEntry('c1', 'album.cue')],
      );

      expect(result.patchedTracks.single.id, 'quark:f1');
    });

    test('只匹配上部分文件时，匹配上的照样增强', () async {
      // 目录里只有第 2 首，第 1 首在别处
      final t2 = audio('f2', '02 月半小夜曲.flac');
      final result = await buildIndexer({'c1': _multiFileCue}).indexDirectory(
        tracks: [t2],
        cueFiles: [cueEntry('c1', 'album.cue')],
      );

      expect(result.patchedTracks, hasLength(1));
      expect(result.patchedTracks.single.id, 'quark:f2');
      expect(result.patchedTracks.single.title, '月半小夜曲');
    });

    test('每轨自己的 PERFORMER 优先于专辑级 PERFORMER', () async {
      const withTrackPerformer = 'PERFORMER "群星"\n'
          'TITLE "合辑"\n'
          'FILE "01 a.flac" WAVE\n'
          '  TRACK 01 AUDIO\n'
          '    TITLE "甲"\n'
          '    PERFORMER "歌手甲"\n'
          '    INDEX 01 00:00:00\n'
          'FILE "02 b.flac" WAVE\n'
          '  TRACK 02 AUDIO\n'
          '    TITLE "乙"\n'
          '    INDEX 01 00:00:00\n';
      final result = await buildIndexer({'c1': withTrackPerformer})
          .indexDirectory(
        tracks: [audio('f1', '01 a.flac'), audio('f2', '02 b.flac')],
        cueFiles: [cueEntry('c1', 'album.cue')],
      );

      final byId = {for (final t in result.patchedTracks) t.id: t};
      expect(byId['quark:f1']!.artist, '歌手甲');
      expect(byId['quark:f2']!.artist, '群星', reason: '没写就退回专辑级');
    });
  });

  group('文件名匹配', () {
    test('忽略大小写（Windows 抓轨常见）', () async {
      const mixedCase = 'FILE "CDImage.WAV" WAVE\n'
          '  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n'
          '  TRACK 02 AUDIO\n    INDEX 01 01:00:00\n';
      final image = audio('wav1', 'cdimage.wav', durationMs: 120000);
      final result = await buildIndexer({'c1': mixedCase}).indexDirectory(
        tracks: [image],
        cueFiles: [cueEntry('c1', 'x.cue')],
      );

      expect(result.extraTracks, hasLength(2));
    });

    test('忽略扩展名（CUE 写 .wav 而实际是 .flac）', () async {
      final image = audio('wav1', 'CD1.flac', durationMs: 120000);
      final result = await buildIndexer({'c1': _singleImageCue}).indexDirectory(
        tracks: [image],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );

      expect(result.extraTracks, hasLength(3));
      expect(result.replacedImageIds, {image.id});
    });

    test('CUE 里带路径前缀时按最后一段匹配', () async {
      const withPath = 'FILE "sub\\\\CD1.wav" WAVE\n'
          '  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n'
          '  TRACK 02 AUDIO\n    INDEX 01 01:00:00\n';
      final image = audio('wav1', 'CD1.wav', durationMs: 120000);
      final result = await buildIndexer({'c1': withPath}).indexDirectory(
        tracks: [image],
        cueFiles: [cueEntry('c1', 'x.cue')],
      );

      expect(result.extraTracks, hasLength(2));
    });

    test('CUE 引用的文件在本目录不存在 → 空结果，不抛异常', () async {
      final result = await buildIndexer({'c1': _singleImageCue}).indexDirectory(
        tracks: [audio('other', '别的歌.flac')],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );

      expect(result.isEmpty, isTrue);
    });
  });

  group('编码', () {
    test('GBK 的 CUE 也能读出中文曲名', () async {
      // 中文 Windows 上 EAC / foobar2000 默认写本地代码页
      final gbkBytes = gbk.encode(_singleImageCue);
      expect(
        () => const Utf8Decoder().convert(gbkBytes),
        throwsFormatException,
        reason: '前提：这些字节确实不是合法 UTF-8，否则测不到 GBK 分支',
      );

      final image = audio('wav1', 'CD1.wav', durationMs: 4338000);
      final result = await buildIndexer(
        const {},
        rawBytes: {'c1': gbkBytes},
      ).indexDirectory(
        tracks: [image],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );

      expect(result.extraTracks.map((t) => t.title),
          ['红日', '月半小夜曲', '护花使者']);
      expect(result.extraTracks.first.artist, '李克勤');
    });
  });

  group('降级：CUE 出任何问题都不该影响扫描', () {
    test('网盘不支持读文件 → 空结果', () async {
      final result = await buildIndexer(
        const {},
        failWith: const DriveException(
          type: DriveErrorType.unsupported,
          message: '该网盘不支持读取文件内容',
        ),
      ).indexDirectory(
        tracks: [audio('wav1', 'CD1.wav')],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );

      expect(result.isEmpty, isTrue);
    });

    test('读取失败（网络 / 不存在）→ 空结果', () async {
      for (final type in [
        DriveErrorType.network,
        DriveErrorType.notFound,
        DriveErrorType.permissionDenied,
      ]) {
        final result = await buildIndexer(
          const {},
          failWith: DriveException(type: type, message: 'x'),
        ).indexDirectory(
          tracks: [audio('wav1', 'CD1.wav')],
          cueFiles: [cueEntry('c1', 'CD1.cue')],
        );
        expect(result.isEmpty, isTrue, reason: '$type 应降级为空');
      }
    });

    test('读取抛出非 DriveException 也不外溢', () async {
      final result = await buildIndexer(
        const {},
        failWith: StateError('适配器内部炸了'),
      ).indexDirectory(
        tracks: [audio('wav1', 'CD1.wav')],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );

      expect(result.isEmpty, isTrue);
    });

    test('内容不是 CUE（比如其实是个文本文件）→ 空结果', () async {
      final result = await buildIndexer({
        'c1': '这不是 cue，只是一段普通文本\n随便写点什么\n',
      }).indexDirectory(
        tracks: [audio('wav1', 'CD1.wav')],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );

      expect(result.isEmpty, isTrue);
    });

    test('CUE 里没有任何 INDEX 01 → 空结果', () async {
      final result = await buildIndexer({
        'c1': 'FILE "CD1.wav" WAVE\n  TRACK 01 AUDIO\n    TITLE "没有起点"\n',
      }).indexDirectory(
        tracks: [audio('wav1', 'CD1.wav')],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );

      expect(result.isEmpty, isTrue);
    });

    test('目录里没有音频 / 没有 CUE 时短路，一次文件都不读', () async {
      var reads = 0;
      final indexer = const CueIndexer();
      Future<CueIndexResult> run({
        required List<Track> tracks,
        required List<DriveEntry> cueFiles,
      }) =>
          indexer.indexDirectory(
            readFile: (id) async {
              reads++;
              return Uint8List.fromList(const []);
            },
            tracks: tracks,
            cueFiles: cueFiles,
          );

      final noTracks = await run(
        tracks: const [],
        cueFiles: [cueEntry('c1', 'CD1.cue')],
      );
      final noCues = await run(
        tracks: [audio('wav1', 'CD1.wav')],
        cueFiles: const [],
      );

      expect(noTracks.isEmpty, isTrue);
      expect(noCues.isEmpty, isTrue);
      expect(reads, 0);
    });
  });

  group('多个 CUE', () {
    test('同目录两份 CUE 各自处理', () async {
      const cd2 = 'PERFORMER "李克勤"\n'
          'TITLE "精选到无朋友 CD2"\n'
          'FILE "CD2.wav" WAVE\n'
          '  TRACK 01 AUDIO\n    TITLE "深深深"\n    INDEX 01 00:00:00\n'
          '  TRACK 02 AUDIO\n    TITLE "旧欢如梦"\n    INDEX 01 04:00:00\n';

      final result = await buildIndexer({
        'c1': _singleImageCue,
        'c2': cd2,
      }).indexDirectory(
        tracks: [
          audio('wav1', 'CD1.wav', durationMs: 4338000),
          audio('wav2', 'CD2.wav', durationMs: 240000),
        ],
        cueFiles: [
          cueEntry('c1', 'CD1.cue'),
          cueEntry('c2', 'CD2.cue'),
        ],
      );

      expect(result.extraTracks, hasLength(5));
      expect(result.replacedImageIds, {'quark:wav1', 'quark:wav2'});
      final byAlbum = {for (final t in result.extraTracks) t.id: t.album};
      expect(byAlbum['quark:wav1#c1'], '精选到无朋友');
      expect(byAlbum['quark:wav2#c1'], '精选到无朋友 CD2');
    });

    test('一份读失败不影响另一份', () async {
      var calls = 0;
      final result = await const CueIndexer().indexDirectory(
        readFile: (id) async {
          calls++;
          if (id == 'bad') {
            throw const DriveException(
              type: DriveErrorType.network,
              message: '读不到',
            );
          }
          return Uint8List.fromList(utf8.encode(_singleImageCue));
        },
        tracks: [audio('wav1', 'CD1.wav', durationMs: 4338000)],
        cueFiles: [
          cueEntry('bad', 'broken.cue'),
          cueEntry('good', 'CD1.cue'),
        ],
      );

      expect(calls, 2);
      expect(result.extraTracks, hasLength(3), reason: '好的那份照常展开');
    });
  });
}
