import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'core/diagnostics/diag_log.dart';
import 'data/db/app_database.dart';
import 'ui/app.dart';
import 'ui/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 最小化 A/B 验证：macOS 临时切到 FFmpeg/mpv 后端，
  // 用来区分「文件/直链问题」与「AVFoundation 兼容性问题」。
  // 只启用 macOS，不影响 Linux/Windows；验证完成后可恢复默认 just_audio。
  if (Platform.isMacOS) {
    JustAudioMediaKit.ensureInitialized(
      linux: false,
      windows: false,
      macOS: true,
    );
  }

  // 索引库放在「应用支持目录」：沙箱里可写，随应用卸载清理，
  // 不进凭证、不进用户文档目录。
  //
  // 拿目录本身也可能失败（权限、容器损坏）。失败时退到临时目录，
  // 只为**让日志还能写下来** —— 否则「启动就挂」这类问题会一点痕迹都不留，
  // 因为日志目录正是从这个路径推出来的。
  String supportPath;
  Object? supportDirError;
  try {
    supportPath = (await getApplicationSupportDirectory()).path;
  } catch (e) {
    supportPath = Directory.systemTemp.path;
    supportDirError = e;
  }

  // 诊断日志必须在任何业务代码之前起来。release 没有控制台可看，
  // 而「拿目录 → 开库 → 恢复凭证 → 扫描」这段启动链路恰恰最容易出事 ——
  // 日志晚一步初始化，出问题的正好是没被记下的那一段。
  await diag.start(supportDirPath: supportPath);
  if (supportDirError != null) {
    diag.error(
      '环境',
      '拿不到应用支持目录，已退到临时目录：曲库会变成空库，且每次启动都不一样',
      error: supportDirError,
    );
  }

  final dbFile =
      File('$supportPath${Platform.pathSeparator}cloudtune.sqlite');
  final coverDir = '$supportPath${Platform.pathSeparator}covers';
  _logEnvironment(supportPath, dbFile.path);

  // 未捕获异常也要落进日志。release 里没人看得到控制台，但日志文件会留着。
  FlutterError.onError = (details) {
    diag.error(
      '未捕获',
      details.exceptionAsString(),
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    diag.error('未捕获', 'Dart 未捕获异常', error: error, stackTrace: stack);
    return true;
  };

  final database = AppDatabase(NativeDatabase(dbFile));
  diag.info('数据库', '索引库已打开：${dbFile.path}');

  runApp(
    ProviderScope(
      // 打开数据库是异步的，必须在这里初始化后注入；领域层只认抽象。
      // 封面缓存目录同理 —— 它也要先 await 平台通道才知道在哪。
      overrides: [
        databaseProvider.overrideWithValue(database),
        coverCacheDirProvider.overrideWithValue(coverDir),
      ],
      child: const CloudTuneApp(),
    ),
  );
}

/// 把「跑在什么环境里」记成日志的第一段。
///
/// 这几行是排查「同一个 app 换个 build 就行为不一样」的起点：
/// 数据目录、是否沙箱、日志文件在哪，都必须留下**实际值**而不是推断。
void _logEnvironment(String supportPath, String dbPath) {
  diag.section('启动');
  diag.info('环境', 'Dart ${Platform.version.split(' ').first} · '
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  diag.info('环境', '应用支持目录 $supportPath');
  diag.info(
    '环境',
    diag.isSandboxed
        ? '沙箱容器：是（数据目录被重定向到 Containers 内，'
            '与未沙箱的 build 不共享曲库与钥匙串访问组）'
        : '沙箱容器：否',
  );
  diag.info('环境', '日志文件 ${diag.filePath ?? "（目录不可写，本次仅内存日志）"}');
  diag.info('环境', '索引库 $dbPath');
  diag.info(
    '环境',
    '封面缓存 $supportPath${Platform.pathSeparator}covers'
        '（清掉它只会让封面重新取一次，不影响曲库）',
  );
}
