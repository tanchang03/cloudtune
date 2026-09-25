import 'package:cloudtune/core/utils/image_formats.dart';
import 'package:flutter_test/flutter_test.dart';

/// 图片识别与「哪张图更像封面」的判据。
///
/// 这里的用例全部取自**真实音乐包的文件名**——封面挑选错一次，
/// 用户看到的就是反过来的封底或者碟面，而且完全不知道为什么。
void main() {
  group('isImageFile', () {
    test('常见图片扩展名', () {
      for (final name in const [
        'cover.jpg',
        'cover.JPEG',
        'folder.png',
        'front.webp',
        'scan.tif',
        'x.bmp',
        'y.heic',
        'z.avif',
        'a.jfif',
      ]) {
        expect(isImageFile(name), isTrue, reason: name);
      }
    });

    test('音频 / CUE / 文档都不是图片', () {
      for (final name in const [
        '01.flac',
        'CDImage.wav',
        'album.cue',
        '说明.txt',
        'booklet.pdf',
        'noextension',
      ]) {
        expect(isImageFile(name), isFalse, reason: name);
      }
    });

    test('没有扩展名时看 MIME', () {
      expect(isImageFile('封面', mimeType: 'image/jpeg'), isTrue);
      expect(isImageFile('封面', mimeType: 'IMAGE/PNG'), isTrue);
      expect(isImageFile('封面', mimeType: 'audio/flac'), isFalse);
      expect(isImageFile('封面'), isFalse);
    });

    test('svg / ico / psd 刻意不算 —— 它们不是专辑封面会用的格式', () {
      expect(isImageFile('logo.svg'), isFalse);
      expect(isImageFile('favicon.ico'), isFalse);
      expect(isImageFile('cover.psd'), isFalse);
    });
  });

  group('normalizeCoverStem', () {
    test('去扩展名、转小写、去掉所有分隔符与符号', () {
      expect(normalizeCoverStem('Album_Cover (Hires).jpg'), 'albumcoverhires');
      expect(normalizeCoverStem('封面 01.PNG'), '封面01');
      expect(normalizeCoverStem('cover'), 'cover');
    });

    test('保留汉字与数字', () {
      expect(normalizeCoverStem('专辑封面-2.jpeg'), '专辑封面2');
    });
  });

  group('coverNameRank', () {
    test('明确写着封面的名字是最优档', () {
      for (final name in const [
        'cover.jpg',
        'Cover.PNG',
        'folder.jpg',
        'front.jpg',
        'FrontCover.jpeg',
        'albumart.jpg',
        'artwork.png',
        'cover1.jpg',
        'cover01.jpg',
        '封面.jpg',
        '专辑封面.png',
        '正面.jpg',
      ]) {
        expect(coverNameRank(name), kCoverRankNamed, reason: name);
      }
    });

    test('封底 / 碟面 / 内页 / 歌词页必须排在最后', () {
      for (final name in const [
        'back.jpg',
        'backcover.jpg',
        'inlay.jpg',
        'disc1.jpg',
        'cd2.png',
        'booklet.jpg',
        'lyric.jpg',
        'inside.jpg',
        '封底.jpg',
        '碟面.jpg',
        '内页.jpg',
        '歌词.jpg',
      ]) {
        expect(coverNameRank(name), kCoverRankBackside, reason: name);
      }
    });

    test('backcover 同时含 back 与 cover，必须判成封底而不是封面', () {
      // 这是本文件里最容易写错的一条：判定顺序反了就会把封底当正面
      expect(coverNameRank('backcover.jpg'), kCoverRankBackside);
      expect(coverNameRank('back_cover_hires.jpg'), kCoverRankBackside);
    });

    test('scan 刻意不算反证据 —— 封面的扫描件也叫 scan', () {
      // `Scans/scan001.jpg` 是内页，`front-cover-scan.jpg` 是正面封面，
      // 同一个词两边都出现。判成「普通图片」比判成「封底」安全：
      // 前者仍能被选中，后者会被明确排除。
      expect(coverNameRank('scan001.jpg'), kCoverRankOther);
      expect(coverNameRank('front-cover-scan.jpg'), kCoverRankHinted);
    });

    test('带封面词但夹着别的东西的是次优档', () {
      for (final name in const [
        'album_cover_hires.jpg',
        'front-cover-scan.jpg',
        '专辑封面-小图.jpg',
        'the_cover_art.jpg',
      ]) {
        expect(coverNameRank(name), kCoverRankHinted, reason: name);
      }
    });

    test('认不出来的图片是普通档', () {
      for (final name in const [
        '01.jpg',
        'image1.png',
        'cdimage.png',
        'IMG_0001.jpg',
        's-l1600.jpg',
      ]) {
        expect(coverNameRank(name), kCoverRankOther, reason: name);
      }
    });

    test('disc / cd 只在整体匹配时才算碟面', () {
      // `cdimage` / `dvdrip` 里的 cd / dvd 不是「第几张碟」，不能判成碟面
      expect(coverNameRank('cdimage.png'), kCoverRankOther);
      expect(coverNameRank('dvdrip.jpg'), kCoverRankOther);
      // 反过来也要承认子串匹配的局限：`discovery` 里恰好含 `cover`，
      // 于是被当成「带封面词」。它不造成实际损失（档位只从 2 升到 1，
      // 依然排在 `cover.jpg` 之后），而收紧到词边界会让 `album_cover`
      // 这类真实命名漏掉 —— 宁可在这里宽松一点。
      expect(coverNameRank('discovery.jpg'), kCoverRankHinted);
    });
  });

  group('目录名分档', () {
    test('明确是封面目录', () {
      for (final name in const [
        'Cover',
        'covers',
        'Artwork',
        'AlbumArt',
        'Front',
        'Folder',
        '封面',
        '专辑封面',
        'CD封面',
        'album covers',
      ]) {
        expect(isCoverDirName(name), isTrue, reason: name);
      }
    });

    test('只是图片目录（可能是封面也可能是扫描件）', () {
      for (final name in const [
        'Scans',
        'scan',
        'images',
        'Image',
        'pics',
        'photos',
        '图片',
        '照片',
        '插图',
      ]) {
        expect(isImageDirName(name), isTrue, reason: name);
        expect(isCoverDirName(name), isFalse, reason: name);
      }
    });

    test('普通目录名不是图片目录', () {
      for (final name in const [
        'CD1',
        'Disc2',
        '华语',
        'cartoon',
        'party',
        '周杰伦',
      ]) {
        expect(isArtworkDirName(name), isFalse, reason: name);
      }
    });

    test('isArtworkDirName 是两者的并集', () {
      expect(isArtworkDirName('Cover'), isTrue);
      expect(isArtworkDirName('Scans'), isTrue);
      expect(isArtworkDirName('CD1'), isFalse);
    });
  });
}
