import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/track.dart';
import 'package:cloudtune/domain/services/library_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

/// 分组与元数据推断。
///
/// 目录名与文件名全部抄自真实曲库（一次 444 首 / 47 个目录的全库扫描结果），
/// 包括几种互相冲突的命名习惯：
///   - `凤凰传奇(FLAC 24bit 192khz)/凤凰传奇 - 一代天骄.flac`  左=艺术家
///   - `群星 - 古惑仔最强精选集 flac/爱情岁月 - 郑伊健.flac`     右=艺术家
///   - `周传雄 烟雨平生/01 - Über den Wolken(qobuz)24 48.flac` 无分隔符
///   - `小虎队 - 爱 (2025 Remastered)(2025) [16B-44.1kHz][Q]/`  同一专辑两个音质目录
void main() {
  Track track(String id, String dir, String name) => Track(
        provider: DriveProvider.quark,
        remoteId: id,
        name: name,
        path: dir,
      );

  const dirFengHuang = '/音乐/凤凰传奇(FLAC 24bit 192khz)/';
  const dirGuHuoZai = '/来自：分享/群星 - 古惑仔最强精选集 flac/';
  const dirXiaoHuDui16 =
      '/来自：分享/小虎队 (2025 Remastered)(2025) 21张/'
      '小虎队 - 爱 (2025 Remastered)(2025) [16B-44.1kHz][Q]/';
  const dirXiaoHuDui24 =
      '/来自：分享/小虎队 (2025 Remastered)(2025) 21张/'
      '小虎队 - 爱 (2025 Remastered)(2025) [24B-48kHz][Q]/';
  const dirZhouChuanXiong = '/来自：分享/周传雄 烟雨平生/';

  /// 一份缩小版的真实曲库：4 种命名习惯各来一点。
  List<Track> miniLibrary() => [
        track('f1', dirFengHuang, '凤凰传奇 - 一代天骄.flac'),
        track('f2', dirFengHuang, '凤凰传奇 - 爱的狂怒.flac'),
        track('f3', dirFengHuang, '凤凰传奇 - 传奇.flac'),
        track('g1', dirGuHuoZai, '爱情岁月 - 郑伊健.flac'),
        track('g2', dirGuHuoZai, '甘心替代你 - 郑伊健.flac'),
        track('g3', dirGuHuoZai, '扑火 - 陈小春.flac'),
        track('g4', dirGuHuoZai, '古古惑惑 - 谢天华朱永棠林晓峰.flac'),
        track('x1', dirXiaoHuDui16, '01 - 蝴蝶飞呀 (2025 Remastered).flac'),
        track('x2', dirXiaoHuDui16, '02 - 天天想我 (2025 Remastered).flac'),
        track('y1', dirXiaoHuDui24, '01 - 蝴蝶飞呀 (2025 Remastered).flac'),
        track('z1', dirZhouChuanXiong, '01 - Über den Wolken(qobuz)24 48.flac'),
        track('z2', dirZhouChuanXiong, '周传雄 烟雨平生 24 192臻品母带.flac'),
      ];

  group('deriveMetadata', () {
    /// `deriveMetadata` 的键是 `Track.id`（形如 `quark:f1`），
    /// 这里换成用 remoteId 索引，读起来更接近曲库里的文件名。
    Map<String, DerivedMetadata> metaOf(List<Track> tracks) {
      final meta = LibraryGrouping.deriveMetadata(tracks);
      return {
        for (final t in tracks) t.remoteId: meta[t.id]!,
      };
    }

    test('常规专辑：从文件名解析出艺术家与曲名', () {
      final meta = metaOf(miniLibrary());
      expect(meta['f1']!.artist, '凤凰传奇');
      expect(meta['f1']!.title, '一代天骄');
      expect(meta['f1']!.album, '凤凰传奇');
    });

    test('精选集反向命名：曲名与艺术家不再颠倒（回归）', () {
      final meta = metaOf(miniLibrary());
      expect(meta['g1']!.title, '爱情岁月');
      expect(meta['g1']!.artist, '郑伊健');
      expect(meta['g3']!.title, '扑火');
      expect(meta['g3']!.artist, '陈小春');
      // 合辑目录名里的「群星」不该盖掉真正的演唱者
      expect(meta['g4']!.artist, '谢天华朱永棠林晓峰');
    });

    test('目录名兜底：文件名里没有分隔符时用「艺术家 专辑」拆出的艺术家', () {
      final meta = metaOf(miniLibrary());
      expect(meta['z1']!.artist, '周传雄');
      expect(meta['z1']!.album, '烟雨平生');
      // 曲名里的 (qobuz) 与码率尾巴会被清掉
      expect(meta['z1']!.title, 'Über den Wolken(qobuz)');
    });

    test('专辑名从目录名推导，并去掉音质噪声', () {
      final meta = metaOf(miniLibrary());
      expect(meta['x1']!.album, '爱 (2025 Remastered)');
      expect(meta['g1']!.album, '古惑仔最强精选集');
      expect(meta['f1']!.album, '凤凰传奇');
    });

    test('没有目录信息时退化为「未知专辑」，不抛异常', () {
      final orphan = Track(
        provider: DriveProvider.quark,
        remoteId: 'o1',
        name: '无目录的歌.flac',
      );
      final meta = metaOf([orphan]);
      expect(meta['o1']!.album, LibraryGrouping.unknownAlbum);
      expect(meta['o1']!.title, '无目录的歌');
    });
  });

  group('group(artist)', () {
    test('同一位歌手的曲目归到一组，跨目录也能合并', () {
      final groups =
          LibraryGrouping.group(miniLibrary(), LibraryGroupMode.artist);
      final byTitle = {for (final g in groups) g.title: g};

      expect(byTitle['凤凰传奇']!.length, 3);
      // 郑伊健的两首在同一目录，陈小春一首在另一处
      expect(byTitle['郑伊健']!.length, 2);
      expect(byTitle['陈小春']!.length, 1);
      // 周传雄靠目录名兜底，两首都归到他名下
      expect(byTitle['周传雄']!.length, 2);
      // 小虎队：16B 与 24B 两个目录，艺术家相同 → 合并成一组
      expect(byTitle['小虎队']!.length, 3);
    });

    test('没有曲目丢失', () {
      final tracks = miniLibrary();
      final groups = LibraryGrouping.group(tracks, LibraryGroupMode.artist);
      expect(
        groups.expand((g) => g.tracks).toSet(),
        tracks.toSet(),
      );
    });

    test('推不出艺术家时归到「未知艺术家」', () {
      final groups = LibraryGrouping.group(
        [Track(provider: DriveProvider.quark, remoteId: 'u', name: '纯曲名.flac')],
        LibraryGroupMode.artist,
      );
      expect(groups.single.title, LibraryGrouping.unknownArtist);
    });
  });

  group('group(album)', () {
    test('一个目录 = 一张专辑，按目录名推出展示名', () {
      final groups =
          LibraryGrouping.group(miniLibrary(), LibraryGroupMode.album);
      final byTitle = {for (final g in groups) g.title: g};

      expect(byTitle['古惑仔最强精选集']!.length, 4);
      expect(byTitle['烟雨平生']!.length, 2);
    });

    test('同名专辑（16bit / 24bit 两个目录）用音质标记区分，不合并也不重名', () {
      final groups =
          LibraryGrouping.group(miniLibrary(), LibraryGroupMode.album);
      final titles = groups.map((g) => g.title).toList();

      expect(titles.where((t) => t.startsWith('爱 (2025 Remastered)')).length, 2);
      expect(titles.toSet().length, titles.length, reason: '分组标题不能重复');
      expect(
        titles.any((t) => t.contains('[16B-44.1kHz]')),
        isTrue,
        reason: '同名专辑必须能区分出是哪一档音质',
      );
      expect(titles.any((t) => t.contains('[24B-48kHz]')), isTrue);
    });

    test('分组键是目录路径，所以猜歪的专辑名不会让曲目串组', () {
      final groups =
          LibraryGrouping.group(miniLibrary(), LibraryGroupMode.album);
      for (final g in groups) {
        final dirs = g.tracks.map(LibraryGrouping.dirOf).toSet();
        expect(dirs.length, 1, reason: '「${g.title}」里混进了不同目录的曲目');
      }
    });

    test('两个目录专辑名与音质标记都一样时，仍然保证标题唯一（回归）', () {
      // 真实库里同一次演唱会有两份不同来源，目录名只差一个 `(1)`，
      // 清洗后专辑名和 `[香港首版]` 标记完全相同
      const a = '/来自：分享/刘德华(1).2002-《你是我的骄傲演唱会》 2CD[香港首版]WAV+CUE/';
      const b = '/来自：分享/刘德华.2002-《你是我的骄傲演唱会》 2CD[香港首版]WAV+CUE/';
      final groups = LibraryGrouping.group(
        [
          track('h1', a, '刘德华.-.[你是我的骄傲演唱会 CD1](2002)[WAV].wav'),
          track('h2', b, '刘德华.-.[你是我的骄傲演唱会 CD2](2002)[WAV].wav'),
        ],
        LibraryGroupMode.album,
      );

      expect(groups.length, 2);
      final titles = groups.map((g) => g.title).toList();
      expect(titles.toSet().length, titles.length, reason: '分组标题不能重复');
    });
  });

  group('group(none)', () {
    test('平铺模式返回单个无标题组，保持原顺序', () {
      final tracks = miniLibrary();
      final groups = LibraryGrouping.group(tracks, LibraryGroupMode.none);
      expect(groups.length, 1);
      expect(groups.single.title, '');
      expect(groups.single.tracks, tracks);
    });

    test('空列表也不炸', () {
      expect(
        LibraryGrouping.group(const [], LibraryGroupMode.artist).single.tracks,
        isEmpty,
      );
      expect(
        LibraryGrouping.group(const [], LibraryGroupMode.none).single.tracks,
        isEmpty,
      );
    });
  });

  group('TrackGroup / LibraryGroupMode', () {
    test('模式标签是给用户看的中文', () {
      expect(LibraryGroupMode.none.label, '列表');
      expect(LibraryGroupMode.artist.label, '艺术家');
      expect(LibraryGroupMode.album.label, '专辑');
    });

    test('组数量词用来拼「23 位艺术家」「47 张专辑」', () {
      expect('23 ${LibraryGroupMode.artist.groupNoun}', '23 位艺术家');
      expect('47 ${LibraryGroupMode.album.groupNoun}', '47 张专辑');
    });

    test('length 等于组内曲目数', () {
      final group = TrackGroup(
        key: 'k',
        title: 't',
        tracks: [
          Track(provider: DriveProvider.quark, remoteId: '1', name: 'a.flac'),
          Track(provider: DriveProvider.quark, remoteId: '2', name: 'b.flac'),
        ],
      );
      expect(group.length, 2);
    });
  });
}
