import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/domain/entities/scan_cursor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 9, 23, 10, 0, 0);
  final t1 = DateTime(2026, 9, 23, 10, 5, 0);

  ScanCursor fresh() => ScanCursor.fresh(
        provider: DriveProvider.quark,
        rootId: '0',
        now: t0,
      );

  group('ScanCursor.fresh', () {
    test('队列里只有根目录，阶段为 idle', () {
      final c = fresh();
      expect(c.pendingDirs.length, 1);
      expect(c.pendingDirs.first.id, '0');
      expect(c.pendingDirs.first.depth, 0);
      expect(c.stage, ScanStage.idle);
      expect(c.hasPendingWork, isTrue);
      expect(c.isComplete, isFalse);
      expect(c.scannedDirs, 0);
      expect(c.foundTracks, 0);
    });
  });

  group('dequeue', () {
    test('取出队首作为当前目录，并清空分页游标', () {
      final c = fresh().copyWith(currentPageToken: 'stale');
      final c2 = c.dequeue(t1);
      expect(c2.currentDir?.id, '0');
      expect(c2.currentPageToken, isNull);
      expect(c2.pendingDirs, isEmpty);
      expect(c2.stage, ScanStage.running);
      expect(c2.updatedAt, t1);
    });

    test('队列空时 dequeue 兜底标记完成', () {
      final c = ScanCursor(
        provider: DriveProvider.quark,
        rootId: '0',
        updatedAt: t0,
        stage: ScanStage.running,
      );
      final c2 = c.dequeue(t1);
      expect(c2.stage, ScanStage.completed);
      expect(c2.isComplete, isTrue);
      expect(c2.hasPendingWork, isFalse);
    });

    test('先进先出：BFS 顺序保持', () {
      var c = fresh();
      c = c.enqueue(const PendingDir(id: 'A', path: '/A/', depth: 1), t0);
      c = c.enqueue(const PendingDir(id: 'B', path: '/B/', depth: 1), t0);

      final first = c.dequeue(t0);
      expect(first.currentDir?.id, '0');
      final second = first.dequeue(t0);
      expect(second.currentDir?.id, 'A');
      final third = second.dequeue(t0);
      expect(third.currentDir?.id, 'B');
      // 取出最后一个目录时队列已空，但该目录还没扫、可能还有子目录，
      // 因此此时不能判定完成 —— 完成由 markCompleted 显式给出。
      expect(third.pendingDirs, isEmpty);
      expect(third.stage, ScanStage.running);
      expect(third.hasPendingWork, isTrue); // 还有 currentDir 要扫

      final done = third.markCompleted(t0);
      expect(done.stage, ScanStage.completed);
      expect(done.isComplete, isTrue);
      expect(done.hasPendingWork, isFalse);
    });

    test('dequeue 会清除上一次的错误信息', () {
      final c = fresh().copyWith(lastError: '上次失败了', stage: ScanStage.failed);
      final c2 = c.dequeue(t1);
      expect(c2.lastError, isNull);
    });
  });

  group('pause / fail / markCompleted', () {
    test('pause 保留队列以便续扫', () {
      var c = fresh().enqueue(const PendingDir(id: 'A', path: '/A/', depth: 1), t0);
      c = c.dequeue(t0).pause(t1);
      expect(c.stage, ScanStage.paused);
      expect(c.stage.canResume, isTrue);
      expect(c.pendingDirs.map((d) => d.id), ['A']);
      expect(c.currentDir?.id, '0');
    });

    test('fail 记录错误并保留队列', () {
      final c = fresh().fail('接口限流', t1);
      expect(c.stage, ScanStage.failed);
      expect(c.lastError, '接口限流');
      expect(c.stage.canResume, isTrue);
      expect(c.pendingDirs, isNotEmpty);
    });

    test('markCompleted 清空当前目录与分页游标', () {
      final c = fresh()
          .copyWith(currentPageToken: 'p1', currentDir: const PendingDir(id: '0', path: '/'))
          .markCompleted(t1);
      expect(c.stage, ScanStage.completed);
      expect(c.currentDir, isNull);
      expect(c.currentPageToken, isNull);
      expect(c.updatedAt, t1);
    });

    test('pause 后 dequeue 可继续（续扫回到 running）', () {
      final paused = fresh().pause(t1);
      expect(paused.dequeue(t1).stage, ScanStage.running);
    });
  });

  group('enqueue', () {
    test('追加到队尾', () {
      final c = fresh().enqueue(
        const PendingDir(id: 'A', path: '/A/', depth: 1),
        t1,
      );
      expect(c.pendingDirs.map((d) => d.id).toList(), ['0', 'A']);
      expect(c.updatedAt, t1);
    });
  });

  group('派生字段', () {
    test('averageTrackBytes 防除零', () {
      expect(fresh().averageTrackBytes, 0);
      expect(
        fresh().copyWith(foundTracks: 4, totalBytes: 400).averageTrackBytes,
        100,
      );
    });

    test('hasPendingWork：有当前目录或有排队目录', () {
      expect(fresh().copyWith(currentDir: const PendingDir(id: 'x', path: '/')).hasPendingWork, isTrue);
      expect(fresh().copyWith(pendingDirs: const []).hasPendingWork, isFalse);
    });
  });

  group('ScanStage', () {
    test('paused / failed 可续扫，completed 是终态', () {
      expect(ScanStage.paused.canResume, isTrue);
      expect(ScanStage.failed.canResume, isTrue);
      expect(ScanStage.running.canResume, isFalse);
      expect(ScanStage.completed.canResume, isFalse);
      expect(ScanStage.completed.isTerminal, isTrue);
    });
  });

  group('PendingDir 序列化', () {
    test('round-trip 保持字段', () {
      const d = PendingDir(id: 'abc', path: '/音乐/华语/', depth: 3);
      final back = PendingDir.fromJson(d.toJson());
      expect(back, d);
      expect(back.path, '/音乐/华语/');
      expect(back.depth, 3);
    });

    test('缺字段时给出安全默认值', () {
      final d = PendingDir.fromJson(const {});
      expect(d.id, '');
      expect(d.path, '/');
      expect(d.depth, 0);
    });

    test('相等性基于全部字段', () {
      expect(
        const PendingDir(id: 'a', path: '/', depth: 1),
        const PendingDir(id: 'a', path: '/', depth: 1),
      );
      expect(
        const PendingDir(id: 'a', path: '/', depth: 1),
        isNot(const PendingDir(id: 'a', path: '/', depth: 2)),
      );
    });
  });

  group('copyWith 语义', () {
    test('clearCurrentDir / clearPageToken / clearLastError 可显式清空', () {
      final c = fresh().copyWith(
        currentDir: const PendingDir(id: 'x', path: '/x/'),
        currentPageToken: 'p1',
        lastError: 'e',
      );
      final cleared = c.copyWith(
        clearCurrentDir: true,
        clearPageToken: true,
        clearLastError: true,
      );
      expect(cleared.currentDir, isNull);
      expect(cleared.currentPageToken, isNull);
      expect(cleared.lastError, isNull);
    });

    test('不传 clear 标志时保留原值', () {
      final c = fresh().copyWith(currentPageToken: 'p1');
      expect(c.copyWith(scannedDirs: 5).currentPageToken, 'p1');
    });
  });
}
