import 'package:cloudtune/domain/entities/scan_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldEnterDir — 深度限制', () {
    const p = ScanPolicy(maxDepth: 3);

    test('深度内的目录允许进入', () {
      expect(p.shouldEnterDir('音乐', 1), isTrue);
      expect(p.shouldEnterDir('音乐', 3), isTrue);
    });

    test('超过深度不再入队', () {
      expect(p.shouldEnterDir('音乐', 4), isFalse);
    });
  });

  group('shouldEnterDir — 目录过滤', () {
    const p = ScanPolicy();

    test('跳过隐藏目录', () {
      expect(p.shouldEnterDir('.git', 1), isFalse);
      expect(p.shouldEnterDir('.hidden', 1), isFalse);
    });

    test('跳过系统与缓存目录（大小写不敏感）', () {
      expect(p.shouldEnterDir('node_modules', 1), isFalse);
      expect(p.shouldEnterDir('NODE_MODULES', 1), isFalse);
      expect(p.shouldEnterDir(r'$RECYCLE.BIN', 1), isFalse);
      expect(p.shouldEnterDir('__pycache__', 1), isFalse);
    });

    test('空名与纯空白不入队', () {
      expect(p.shouldEnterDir('', 1), isFalse);
      expect(p.shouldEnterDir('   ', 1), isFalse);
    });

    test('正常目录允许进入', () {
      expect(p.shouldEnterDir('华语流行', 1), isTrue);
      expect(p.shouldEnterDir('2024 新歌', 2), isTrue);
    });

    test('关闭 skipHiddenDirs 后隐藏目录可进入', () {
      const relaxed = ScanPolicy(skipHiddenDirs: false);
      expect(relaxed.shouldEnterDir('.hidden', 1), isTrue);
      // 但显式黑名单仍然生效
      expect(relaxed.shouldEnterDir('node_modules', 1), isFalse);
    });

    test('自定义黑名单覆盖默认值', () {
      const custom = ScanPolicy(skipDirNames: {'我的备份'});
      expect(custom.shouldEnterDir('我的备份', 1), isFalse);
      expect(custom.shouldEnterDir('node_modules', 1), isTrue);
    });
  });

  group('目录数上限', () {
    test('reachedDirLimit 到达阈值即停', () {
      const p = ScanPolicy(maxDirectories: 10);
      expect(p.reachedDirLimit(9), isFalse);
      expect(p.reachedDirLimit(10), isTrue);
      expect(p.reachedDirLimit(11), isTrue);
    });

    test('队列里的待扫目录也计入上限', () {
      const p = ScanPolicy(maxDirectories: 10);
      expect(p.reachedDirLimit(2, queuedDirs: 7), isFalse);
      expect(p.reachedDirLimit(2, queuedDirs: 8), isTrue);
      expect(p.reachedDirLimit(0, queuedDirs: 10), isTrue,
          reason: '一个含上万子目录的目录不能在单次遍历里全部入队');
    });
  });

  group('默认值合理性（对齐 PoC 实测）', () {
    test('默认节流间隔不低于 300ms（≈3 QPS 安全线）', () {
      const p = ScanPolicy();
      expect(p.minRequestInterval.inMilliseconds, greaterThanOrEqualTo(300));
    });

    test('默认分页 50（夸克实测单页返回上限）', () {
      expect(const ScanPolicy().pageSize, 50);
    });

    test('copyWith 只改指定字段', () {
      const p = ScanPolicy();
      final p2 = p.copyWith(maxDepth: 5);
      expect(p2.maxDepth, 5);
      expect(p2.pageSize, p.pageSize);
      expect(p2.minRequestInterval, p.minRequestInterval);
    });
  });

  group('shouldKeepQueuedDir', () {
    test('深度超限的排队目录应被丢弃', () {
      const p = ScanPolicy(maxDepth: 2);
      expect(p.shouldKeepQueuedDir(2), isTrue);
      expect(p.shouldKeepQueuedDir(3), isFalse);
    });
  });
}
