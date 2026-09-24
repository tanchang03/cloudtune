import 'dart:io';

import 'package:cloudtune/core/diagnostics/diag_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('cloudtune_diag_test');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  DiagLog newLog() => DiagLog.forTesting();

  File logFileOf(Directory dir) {
    final logs = Directory('${dir.path}${Platform.pathSeparator}logs');
    final files = logs
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList();
    expect(files, hasLength(1), reason: '应当只生成当天那一个日志文件');
    return files.single;
  }

  group('start', () {
    test('建立 logs 目录并落到按天命名的文件', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);

      expect(log.isStarted, isTrue);
      expect(log.filePath, isNotNull);

      final file = logFileOf(temp);
      final today = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      expect(
        file.path,
        endsWith('cloudtune-${today.year}-${two(today.month)}-${two(today.day)}.log'),
      );
    });

    test('启动时立刻写入会话头，日志文件当场就存在', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);

      expect(File(log.filePath!).existsSync(), isTrue);
      expect(log.lines.first, contains('会话开始'));
    });

    test('重复 start 只生效一次（不重开文件、不清空已有日志）', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);
      log.info('标签', '第一条');
      await log.start(supportDirPath: temp.path);

      expect(log.lines.where((l) => l.contains('第一条')), hasLength(1));
    });

    test('目录不可写时不抛异常，且仍保留内存日志', () async {
      final log = newLog();
      // /dev/null 是字符设备，不可能当目录用
      await log.start(supportDirPath: '/dev/null/nope');

      expect(log.filePath, isNull);
      expect(log.lines, isNotEmpty);
      expect(log.lines.first, contains('日志目录不可写'));
    });
  });

  group('add', () {
    test('格式为「时间 级别 [标签] 正文」，同时进内存与文件', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);
      log.info('取链', '开始取直链');

      final line = log.lines.last;
      expect(
        line,
        matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} '
            r'INFO  \[取链\] 开始取直链$')),
      );

      final written = logFileOf(temp).readAsStringSync();
      expect(written, contains('INFO  [取链] 开始取直链'));
    });

    test('四个级别的标签都是定宽 5 字符（日志正文才能左对齐）', () {
      for (final level in DiagLevel.values) {
        expect(level.label.length, 5, reason: '${level.name} 的标签宽度');
      }
    });

    test('error 会把异常对象拼进同一行', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);
      log.error('钥匙串', '读取失败', error: 'errSecMissingEntitlement(-34018)');

      final line = log.lines.last;
      expect(line, contains('ERROR [钥匙串] 读取失败'));
      expect(line, contains('errSecMissingEntitlement(-34018)'));
    });

    test('堆栈只留前 12 帧，不淹没日志', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);

      StackTrace stack = StackTrace.current;
      for (var i = 0; i < 40; i++) {
        stack = StackTrace.fromString(
          '${stack.toString()}#$i  frame_$i\n',
        );
      }
      log.error('未捕获', '炸了', error: 'boom', stackTrace: stack);

      final frames = log.lines.where((l) => l.startsWith('    #')).length;
      expect(frames, lessThanOrEqualTo(12));
    });

    test('落盘的内容经过脱敏 —— 凭证不允许写进磁盘', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);
      log.info('HTTP', 'Cookie: __puus=SUPERSECRETVALUE');

      final written = logFileOf(temp).readAsStringSync();
      expect(written, isNot(contains('SUPERSECRETVALUE')));
      expect(written, contains('__puus=<redacted>'));
    });
  });

  group('环形缓冲', () {
    test('超过上限后丢最旧的，不无限增长', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);

      for (var i = 0; i < DiagLog.maxLines + 50; i++) {
        log.info('压测', '第 $i 行');
      }

      expect(log.lines, hasLength(DiagLog.maxLines));
      expect(log.lines.first, contains('第 50 行'));
      expect(log.lines.last, contains('第 ${DiagLog.maxLines + 49} 行'));
    });

    test('缓冲满了不影响落盘（文件保留全量）', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);
      for (var i = 0; i < DiagLog.maxLines + 50; i++) {
        log.info('压测', '第 $i 行');
      }

      final written = logFileOf(temp).readAsStringSync();
      expect(written, contains('第 0 行'));
      expect(written, contains('第 ${DiagLog.maxLines + 49} 行'));
    });

    test('clearBuffer 只清内存，不删文件', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);
      log.info('标签', '会留在文件里');

      log.clearBuffer();

      expect(log.lines, isEmpty);
      expect(logFileOf(temp).readAsStringSync(), contains('会留在文件里'));
    });
  });

  group('revision', () {
    test('每写一行自增，供 UI 刷新', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);
      final before = log.revision.value;

      log.info('标签', '一');
      log.info('标签', '二');

      expect(log.revision.value, before + 2);
    });

    test('clearBuffer 也通知 UI', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);
      final before = log.revision.value;

      log.clearBuffer();

      expect(log.revision.value, before + 1);
    });
  });

  group('isSandboxed', () {
    test('路径在 Containers 里判为沙箱', () async {
      final log = newLog();
      await log.start(
        supportDirPath:
            '/Users/x/Library/Containers/com.cloudtune.cloudtune/Data/Library/'
            'Application Support/com.cloudtune.cloudtune',
      );
      expect(log.isSandboxed, isTrue);
    });

    test('普通应用支持目录判为非沙箱', () async {
      final log = newLog();
      await log.start(
        supportDirPath: '/Users/x/Library/Application Support/com.cloudtune.cloudtune',
      );
      expect(log.isSandboxed, isFalse);
    });

    test('未启动时不判为沙箱', () {
      expect(newLog().isSandboxed, isFalse);
    });
  });

  group('section / dump', () {
    test('section 产生可检索的分段标题', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);
      log.section('播放 某首歌');

      expect(log.lines.last, contains('[分段]'));
      expect(log.lines.last, contains('播放 某首歌'));
    });

    test('dump 返回全部内存日志，逐行拼接', () async {
      final log = newLog();
      await log.start(supportDirPath: temp.path);
      log.clearBuffer();
      log.info('标签', '一');
      log.info('标签', '二');

      final dumped = log.dump();
      expect(dumped.split('\n'), hasLength(2));
      expect(dumped, contains('一'));
      expect(dumped, contains('二'));
    });
  });

  group('清理旧日志', () {
    test('超过保留天数的文件会被删掉，当天的保留', () async {
      final logs = Directory('${temp.path}${Platform.pathSeparator}logs')
        ..createSync(recursive: true);

      final stale = File('${logs.path}${Platform.pathSeparator}cloudtune-2020-01-01.log')
        ..writeAsStringSync('old');
      // 把修改时间改到 30 天前
      stale.setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 30)),
      );

      final log = newLog();
      await log.start(supportDirPath: temp.path);

      expect(stale.existsSync(), isFalse, reason: '超期日志应被清理');
      expect(log.filePath, isNotNull);
      expect(File(log.filePath!).existsSync(), isTrue);
    });

    test('不认识的文件不动它', () async {
      final logs = Directory('${temp.path}${Platform.pathSeparator}logs')
        ..createSync(recursive: true);
      final other = File('${logs.path}${Platform.pathSeparator}notes.txt')
        ..writeAsStringSync('keep')
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 99)));

      final log = newLog();
      await log.start(supportDirPath: temp.path);

      expect(other.existsSync(), isTrue);
    });
  });
}
