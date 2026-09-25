import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/audio/just_audio_output.dart';
import '../../data/auth/quark_authorizer.dart';
import '../../data/auth/quark_qr_login.dart';
import '../../data/auth/resilient_credential_store.dart';
import '../../data/auth/secure_credential_store.dart';
import '../../data/covers/album_cover_cache.dart';
import '../../data/db/app_database.dart';
import '../../data/db/library_repository_impl.dart';
import '../../data/db/settings_store.dart';
import '../../data/http/dio_http_client.dart';
import '../../data/http/http_client.dart';
import '../../data/registry/drive_adapter_registry.dart';
import '../../data/remote/quark/quark_adapter.dart';
import '../../domain/adapters/audio_output.dart';
import '../../domain/adapters/browser_auth.dart';
import '../../domain/adapters/library_repository.dart';
import '../../domain/services/playback_controller.dart';
import '../../domain/services/scan_service.dart';
import '../webview/cookie_reader.dart';

/// 组合根。
///
/// **所有具体实现的唯一装配点。** 领域层只认抽象，这里把它们接到一起。
/// 新增一家网盘 = 在 [adapterRegistryProvider] 里多传一个适配器实例，
/// 其余 provider、页面、播放引擎都不用动。

/// 本地索引数据库。
///
/// 在 `main()` 里初始化后通过 `ProviderScope.overrides` 注入 —— 打开数据库
/// 是异步的（要先拿应用支持目录），不适合塞进同步的 Provider 里。
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(
    'databaseProvider 必须在 main() 里用 ProviderScope.overrides 注入',
  ),
);

/// 凭证存储。外面包一层降级，钥匙串不可用时退化为内存。
final credentialStoreProvider = Provider<ResilientCredentialStore>(
  (ref) => ResilientCredentialStore(SecureCredentialStore()),
);

final httpClientProvider = Provider<HttpClientLike>((ref) => DioHttpClient());

/// 已接入的网盘适配器。目前只有夸克。
final adapterRegistryProvider = Provider<DefaultDriveAdapterRegistry>((ref) {
  final registry = DefaultDriveAdapterRegistry([
    QuarkAdapter(
      http: ref.watch(httpClientProvider),
      credentialStore: ref.watch(credentialStoreProvider),
    ),
  ]);
  ref.onDispose(registry.disposeAll);
  return registry;
});

final libraryProvider = Provider<LibraryRepository>(
  (ref) => DriftLibraryRepository(ref.watch(databaseProvider)),
);

/// 应用设置的读写（`settings` 表的薄封装）。
///
/// 目前只有「联网获取歌词」一个键，但它刻意做成通用的 KV ——
/// 下一个偏好设置不必再动数据库结构。
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(databaseProvider)),
);

/// 专辑封面的磁盘缓存目录。
///
/// 和 [databaseProvider] 一样在 `main()` 里按应用支持目录注入：拿目录是异步的，
/// 塞进同步的 Provider 里就得在每次读封面时重新 await 一次平台通道。
final coverCacheDirProvider = Provider<String>(
  (ref) => throw UnimplementedError(
    'coverCacheDirProvider 必须在 main() 里用 ProviderScope.overrides 注入',
  ),
);

/// 封面字节的取用与缓存。专辑网格与专辑详情页都读它。
final albumCoverCacheProvider = Provider<AlbumCoverCache>(
  (ref) => AlbumCoverCache(
    registry: ref.watch(adapterRegistryProvider),
    cacheDirPath: ref.watch(coverCacheDirProvider),
  ),
);

final scanServiceProvider = Provider<ScanService>(
  (ref) => ScanService(
    registry: ref.watch(adapterRegistryProvider),
    library: ref.watch(libraryProvider),
  ),
);

final audioOutputProvider = Provider<AudioOutput>((ref) {
  final output = JustAudioOutput();
  ref.onDispose(output.dispose);
  return output;
});

final playbackControllerProvider = Provider<PlaybackController>((ref) {
  final controller = PlaybackController(
    registry: ref.watch(adapterRegistryProvider),
    library: ref.watch(libraryProvider),
    output: ref.watch(audioOutputProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// 浏览器登录授权器（备选链路）。
final browserAuthorizerProvider = Provider<BrowserAuthorizer>(
  (ref) => QuarkBrowserAuthorizer(readCookies: readCookiesFromWebView),
);

/// 手动粘贴凭证授权器（兜底链路）。
final manualAuthorizerProvider = Provider<QuarkManualCookieAuthorizer>(
  (ref) => QuarkManualCookieAuthorizer(),
);

/// 扫码登录客户端（主登录链路）。
///
/// 只依赖 [httpClientProvider]，所以它跟网盘适配器共用同一个 HTTP 抽象 ——
/// 单元测试里换成假客户端就能覆盖全部状态分支。
final qrLoginClientProvider = Provider<QuarkQrLoginClient>(
  (ref) => QuarkQrLoginClient(http: ref.watch(httpClientProvider)),
);
