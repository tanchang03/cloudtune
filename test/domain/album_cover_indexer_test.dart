import 'package:cloudtune/domain/entities/drive_entry.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/services/album_cover_indexer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 专辑封面挑选。
///
/// 挑错的代价是「这张专辑显示的是封底 / 碟面」—— 比没有封面更糟，
/// 因为它看起来像是**读错了**。所以这里逐条钉住判分规则。
void main() {
  const indexer = AlbumCoverIndexer();

  DriveEntry image(String name, {int size = 200 * 1024, String id = ''}) =>
      DriveEntry(
        id: id.isEmpty ? name : id,
        name: name,
        isDirectory: false,
        sizeBytes: size,
      );

  DriveEntry dir(String name, {String id = ''}) =>
      DriveEntry(id: id.isEmpty ? name : id, name: name, isDirectory: true);

  /// 挑一次，返回选中的文件名
  String? pick(
    List<DriveEntry> sameDir, {
    Map<String, List<DriveEntry>> subDirs = const {},
    String dirPath = '/音乐/周杰伦 - 叶惠美/',
  }) =>
      indexer
          .pick(
            provider: DriveProvider.quark,
            dirPath: dirPath,
            sameDir: sameDir,
            artworkDirs: subDirs,
          )
          ?.fileName;

  group('同目录', () {
    test('cover.jpg 胜过 back.jpg', () {
      expect(
        pick([image('back.jpg', size: 5 << 20), image('cover.jpg')]),
        'cover.jpg',
        reason: '档位优先于体积：大一点的封底也还是封底',
      );
    });

    test('folder.jpg / 封面.jpg 都算「明确写着封面」', () {
      expect(pick([image('back.jpg'), image('folder.jpg')]), 'folder.jpg');
      expect(pick([image('back.jpg'), image('封面.jpg')]), '封面.jpg');
    });

    test('都是普通图片时取体积大的', () {
      expect(
        pick([image('01.jpg', size: 100 << 10), image('02.jpg', size: 2 << 20)]),
        '02.jpg',
      );
    });

    test('档位与体积都相同时按文件名，保证结果确定', () {
      final a = pick([image('b.jpg'), image('a.jpg')]);
      final b = pick([image('a.jpg'), image('b.jpg')]);
      expect(a, 'a.jpg');
      expect(b, 'a.jpg', reason: '两次调用必须挑出同一张，否则缓存与索引会抖');
    });

    test('没有图片时返回 null', () {
      expect(pick([image('readme.txt'), dir('CD2')]), isNull);
      expect(pick(const []), isNull);
    });

    test('0 字节的图片不算候选（那是坏文件）', () {
      expect(pick([image('cover.jpg', size: 0), image('02.jpg')]), '02.jpg');
      expect(pick([image('cover.jpg', size: 0)]), isNull);
    });

    test('体积未知的图片仍算候选', () {
      expect(pick([image('cover.jpg', size: 0), image('x.jpg')]), 'x.jpg');
    });

    test('目录条目不会被当成图片', () {
      expect(pick([dir('cover.jpg')]), isNull);
    });

    test('返回的 dirPath 已归一化（去掉结尾斜杠）', () {
      final cover = indexer.pick(
        provider: DriveProvider.quark,
        dirPath: '/音乐/周杰伦/叶惠美/',
        sameDir: [image('cover.jpg', id: 'img1')],
      );
      expect(cover!.dirPath, '/音乐/周杰伦/叶惠美');
      expect(cover.fileId, 'img1');
      expect(cover.key, 'quark:img1');
    });
  });

  group('子目录', () {
    test('同目录没有封面时去翻 Cover/ 子目录', () {
      expect(
        pick(
          [image('back.jpg')],
          subDirs: {
            'Cover': [image('front.jpg')],
          },
        ),
        'front.jpg',
      );
    });

    test('Cover/ 里名字普通的图也算「封面目录里的图」', () {
      expect(
        pick(
          [image('back.jpg')],
          subDirs: {
            'Cover': [image('01.jpg')],
          },
        ),
        '01.jpg',
        reason: '目录名已经说了「这里就是封面」，里面的 01.jpg 比封底可信',
      );
    });

    test('同目录的 folder.jpg 胜过 Cover/front.jpg', () {
      expect(
        pick(
          [image('folder.jpg')],
          subDirs: {
            'Cover': [image('front.jpg')],
          },
        ),
        'folder.jpg',
      );
    });

    test('子目录里「明确写着封面」的图胜过同目录的普通图', () {
      expect(
        pick(
          [image('01.jpg')],
          subDirs: {
            'Scans': [image('front.jpg')],
          },
        ),
        'front.jpg',
        reason: '文件名是比位置更强的信号：`front.jpg` 明确说了自己是正面封面，'
            '而 `01.jpg` 只说明它是「这个目录里的第一张图」',
      );
    });

    test('两边都认不出名字时，同目录的图更可信', () {
      expect(
        pick(
          [image('01.jpg')],
          subDirs: {
            'Scans': [image('02.jpg')],
          },
        ),
        '01.jpg',
        reason: '扫描件目录里多半是内页，同目录的图至少和音频放在一起',
      );
    });

    test('两个子目录都像封面目录时，按档位与体积分胜负', () {
      expect(
        pick(
          const [],
          subDirs: {
            'Cover': [image('a.jpg', size: 100 << 10)],
            'Artwork': [image('b.jpg', size: 3 << 20)],
          },
        ),
        'b.jpg',
      );
    });
  });

  group('辅助判据', () {
    test('isUsableImage', () {
      expect(AlbumCoverIndexer.isUsableImage(image('cover.jpg')), isTrue);
      expect(AlbumCoverIndexer.isUsableImage(image('cover.jpg', size: 0)), isFalse);
      expect(AlbumCoverIndexer.isUsableImage(image('a.flac')), isFalse);
      expect(AlbumCoverIndexer.isUsableImage(dir('Cover')), isFalse);
      expect(
        AlbumCoverIndexer.isUsableImage(
          DriveEntry(id: 'x', name: '无扩展名', isDirectory: false, mimeType: 'image/jpeg'),
        ),
        isTrue,
      );
    });

    test('hasNamedCover —— 有它就不必再翻子目录', () {
      expect(AlbumCoverIndexer.hasNamedCover([image('cover.jpg')]), isTrue);
      expect(AlbumCoverIndexer.hasNamedCover([image('folder.png')]), isTrue);
      expect(AlbumCoverIndexer.hasNamedCover([image('back.jpg')]), isFalse);
      expect(AlbumCoverIndexer.hasNamedCover([image('01.jpg')]), isFalse);
      expect(
        AlbumCoverIndexer.hasNamedCover([image('cover.jpg', size: 0)]),
        isFalse,
        reason: '坏文件不算，还得继续找',
      );
    });
  });
}
