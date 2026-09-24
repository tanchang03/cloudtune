import 'package:cloudtune/domain/entities/drive_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DriveEntry file({String id = 'f1', String name = 'a.mp3', int? size = 1024}) =>
      DriveEntry(id: id, name: name, isDirectory: false, sizeBytes: size);

  DriveEntry dir({String id = 'd1', String name = '音乐'}) =>
      DriveEntry(id: id, name: name, isDirectory: true);

  group('基本语义', () {
    test('isFile 是 isDirectory 的取反', () {
      expect(file().isFile, isTrue);
      expect(file().isDirectory, isFalse);
      expect(dir().isFile, isFalse);
      expect(dir().isDirectory, isTrue);
    });

    test('fileSizeBytes 对目录返回 0（而非 null）', () {
      // 关键：目录的 null 体积不能被上层误判成「体积未知」
      expect(dir().fileSizeBytes, 0);
      expect(file(size: 1024).fileSizeBytes, 1024);
      expect(file(size: null).fileSizeBytes, isNull);
    });
  });

  group('copyWith', () {
    test('只覆盖传入字段', () {
      final e = file();
      final e2 = e.copyWith(path: '/音乐/');
      expect(e2.path, '/音乐/');
      expect(e2.id, e.id);
      expect(e2.name, e.name);
      expect(e2.isDirectory, e.isDirectory);
      expect(e2.sizeBytes, e.sizeBytes);
    });

    test('可覆盖 parentId', () {
      final e = file().copyWith(parentId: 'p9');
      expect(e.parentId, 'p9');
    });
  });

  group('DrivePage', () {
    final page = DrivePage(
      entries: [
        dir(id: 'd1', name: '华语'),
        dir(id: 'd2', name: '欧美'),
        file(id: 'f1', name: 'a.mp3'),
        file(id: 'f2', name: 'b.flac'),
      ],
      nextPageToken: 'cursor-2',
      total: 4,
    );

    test('directories / files 过滤正确', () {
      expect(page.directories.map((e) => e.id).toList(), ['d1', 'd2']);
      expect(page.files.map((e) => e.id).toList(), ['f1', 'f2']);
    });

    test('hasMore 由 nextPageToken 决定', () {
      expect(page.hasMore, isTrue);
      expect(DrivePage(entries: const []).hasMore, isFalse);
      expect(DrivePage(entries: const [], nextPageToken: '').hasMore, isFalse);
    });

    test('isEmpty', () {
      expect(page.isEmpty, isFalse);
      expect(const DrivePage.empty().isEmpty, isTrue);
      expect(const DrivePage.empty().total, isNull);
    });
  });
}
