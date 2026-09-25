import 'package:cloudtune/data/db/app_database.dart';
import 'package:cloudtune/data/db/library_repository_impl.dart';
import 'package:cloudtune/data/db/settings_store.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:cloudtune/ui/providers/app_providers.dart';
import 'package:cloudtune/ui/providers/lyrics_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 设置存储与「联网歌词」开关的回归测试。
///
/// 这里钉住的是一条**合规口径**：联网歌词默认关闭。
/// 它不是一个产品偏好 —— 打开之后本应用会把曲目元数据发给第三方接口，
/// 这是唯一一处超出「只播放自己网盘里的文件」的行为，必须由用户明确同意。
///
/// 所以「默认关」要按**真实数据库**测一遍：用一个假的 Notifier 测出来的
/// 「默认是 false」证明不了任何事（假的那份本来就是我写死的）。
/// 真实路径上的默认值来自「库里没有这一行」，这条断了没人会发现 ——
/// 界面看起来一切正常，只是每次启动都在偷偷联网。
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('SettingsStore', () {
    test('没写过的键：读出来是 null / 落到 fallback', () async {
      final store = SettingsStore(db);

      expect(await store.read(SettingKeys.lyricsNetworkEnabled), isNull);
      expect(await store.readBool(SettingKeys.lyricsNetworkEnabled), isFalse);
      expect(
        await store.readBool(SettingKeys.lyricsNetworkEnabled, fallback: true),
        isTrue,
        reason: 'fallback 的意义就是「没写过的时候该算什么」',
      );
    });

    test('写进去再读回来（字符串 KV）', () async {
      final store = SettingsStore(db);

      await store.write('k', 'v');
      expect(await store.read('k'), 'v');

      // 同一个键再写一次是覆盖，不是报错也不是追加
      await store.write('k', 'v2');
      expect(await store.read('k'), 'v2');
    });

    test('布尔值往返', () async {
      final store = SettingsStore(db);

      await store.writeBool(SettingKeys.lyricsNetworkEnabled, value: true);
      expect(await store.readBool(SettingKeys.lyricsNetworkEnabled), isTrue);

      await store.writeBool(SettingKeys.lyricsNetworkEnabled, value: false);
      expect(await store.readBool(SettingKeys.lyricsNetworkEnabled), isFalse);
    });

    test('值被写坏了退回保守的一侧：认不出的字符串不算真', () async {
      final store = SettingsStore(db);

      await store.write(SettingKeys.lyricsNetworkEnabled, 'yes');
      expect(
        await store.readBool(SettingKeys.lyricsNetworkEnabled),
        isFalse,
        reason: '「非空字符串即真」会让一个写坏的值打开联网 —— '
            '这是整个应用唯一会对外发数据的开关，宁可关着',
      );
    });

    test('删掉之后回到默认值', () async {
      final store = SettingsStore(db);

      await store.writeBool(SettingKeys.lyricsNetworkEnabled, value: true);
      await store.remove(SettingKeys.lyricsNetworkEnabled);

      expect(await store.readBool(SettingKeys.lyricsNetworkEnabled), isFalse);
    });

    test('设置不随「清空曲库」一起被删', () async {
      final store = SettingsStore(db);

      await store.writeBool(SettingKeys.lyricsNetworkEnabled, value: true);
      await DriftLibraryRepository(db).clearProvider(DriveProvider.quark);

      expect(
        await store.readBool(SettingKeys.lyricsNetworkEnabled),
        isTrue,
        reason: '清空曲库清的是曲目索引，不是用户偏好。'
            '把开关一起清掉，用户重扫一次就莫名其妙地不再联网了',
      );
    });
  });

  group('联网歌词开关（走真实数据库）', () {
    /// 用真实 `databaseProvider` 建容器 —— 不 fake 任何一层。
    ProviderContainer containerWith(AppDatabase database) => ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(database)],
        );

    test('默认关闭：库里没有这一行时，开关就是关的', () async {
      final container = containerWith(db);
      addTearDown(container.dispose);

      await expectLater(
        container.read(lyricsNetworkEnabledProvider.future),
        completion(isFalse),
      );
    });

    test('打开 → 写入 → 换一个容器（相当于重启）读出来仍是开的', () async {
      final first = containerWith(db);
      addTearDown(first.dispose);

      await first.read(lyricsNetworkEnabledProvider.notifier).setEnabled(true);
      expect(await first.read(lyricsNetworkEnabledProvider.future), isTrue);

      // 同一个库、全新的容器 —— 正是「关掉应用再打开」的状态
      final restarted = containerWith(db);
      addTearDown(restarted.dispose);

      expect(await restarted.read(lyricsNetworkEnabledProvider.future), isTrue);
    });

    // 这个用例钉的是「不等 build 完成就去点开关」这条路径。
    //
    // ⚠️ 它**测不出**那次竞态本身 —— 竞态要触发，得让 build 的读比写还慢
    // （内存库里读总是先回来，所以加不加保护这一条都是绿的）。
    // 真正挡住它的是 `setEnabled` 开头那句 `await future`（见该处注释）：
    // 库慢的时候，build 会在「写库之后、赋值之前」才回来，把刚写进去的状态
    // 盖成旧值 —— 现象是开关自己弹回去，而库里其实已经是新值了。
    // 这里保留的是「不等 build 也必须是自洽的」这个较弱但确定的性质。
    test('不等 build 完成就点开关：界面与库最终一致', () async {
      final container = containerWith(db);
      addTearDown(container.dispose);

      // 刻意**不**先 await build（真实场景：刚启动就有人去点那个开关）
      await container.read(lyricsNetworkEnabledProvider.notifier).setEnabled(true);
      expect(container.read(lyricsNetworkEnabledProvider).valueOrNull, isTrue);

      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(lyricsNetworkEnabledProvider).valueOrNull, isTrue);
      expect(
        await SettingsStore(db).readBool(SettingKeys.lyricsNetworkEnabled),
        isTrue,
        reason: '界面与库不一致的话，只有重启才能纠正',
      );
    });

    test('关回去 → 重启后仍是关的', () async {
      final container = containerWith(db);
      addTearDown(container.dispose);

      await container.read(lyricsNetworkEnabledProvider.notifier).setEnabled(true);
      await container.read(lyricsNetworkEnabledProvider.notifier).setEnabled(false);

      final restarted = containerWith(db);
      addTearDown(restarted.dispose);

      expect(await restarted.read(lyricsNetworkEnabledProvider.future), isFalse);
    });
  });
}
