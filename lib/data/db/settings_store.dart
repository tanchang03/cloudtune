import 'package:drift/drift.dart';

import 'app_database.dart';

/// 应用设置的键名。**集中在这里，不要在别处写字符串字面量。**
///
/// 散落的字面量迟早会出现拼写不一致（`lyrics.network` vs
/// `lyrics.network_enabled`），而那种错误的表象是「开关明明打开了，
/// 行为却像没打开」—— 一个几乎没法从现象反推原因的 bug。
class SettingKeys {
  const SettingKeys._();

  /// 是否允许联网获取歌词（LRCLIB）。**默认关闭。**
  ///
  /// 默认关闭不只是产品偏好，也是合规要求：打开之后本应用会把
  /// 「曲名 / 艺术家 / 专辑 / 时长」发给第三方接口，并把拿回来的歌词正文
  /// 存进本地索引库。这两件事都超出了「只播放你自己网盘里的文件」这个
  /// 既定边界，必须由用户明确同意。见 README 的合规说明。
  static const String lyricsNetworkEnabled = 'lyrics.network_enabled';

  /// 用户上次「看完新歌」的时间（水位）。
  ///
  /// 一首歌「新不新」取决于它第一次进库的时间是否晚于这个值。这个键为
  /// `null` 表示水位还没建立 —— 由扫描服务在**第一次成功扫描后**写入
  /// 「现在」，把当时已有的曲库变成基线，之后进库的新歌才被算作「新」。
  ///
  /// 用 RFC 3339 字符串存储（`DateTime.toIso8601String`），读写走
  /// `readDateTime` / `writeDateTime`，不要在调用方自己拼格式。
  static const String newSongsSeenAt = 'new_songs.seen_at';
}

/// 应用设置的读写（`settings` 表的薄封装）。
///
/// 只做「字符串进、字符串出」，类型转换由调用方决定 —— 表本身是 KV，
/// 装什么类型是使用方的事，包成泛型反而要在这里引入一堆 `T` 的分支。
class SettingsStore {
  SettingsStore(this._db);

  final AppDatabase _db;

  Future<String?> read(String key) async {
    final row = await (_db.select(_db.settings)
          ..where((s) => s.settingKey.equals(key))
          ..limit(1))
        .getSingleOrNull();
    return row?.settingValue;
  }

  /// 读布尔值。[fallback] 是**没写过这个键**时的取值。
  ///
  /// 只把 `'true'` / `'1'` 认成真：一个认不出的值（被手工改坏、或未来换了
  /// 编码方式）应当退回保守的那一侧，而不是因为「非空字符串」就当成真。
  Future<bool> readBool(String key, {bool fallback = false}) async {
    final v = await read(key);
    if (v == null) return fallback;
    return v == 'true' || v == '1';
  }

  Future<void> write(String key, String value) async {
    await _db.into(_db.settings).insert(
          SettingsCompanion.insert(settingKey: key, settingValue: value),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<void> writeBool(String key, {required bool value}) =>
      write(key, value ? 'true' : 'false');

  /// 读时间（ISO 8601 字符串）。[fallback] 是**没写过这个键**或写坏了的取值。
  Future<DateTime?> readDateTime(String key, {DateTime? fallback}) async {
    final v = await read(key);
    if (v == null) return fallback;
    return DateTime.tryParse(v) ?? fallback;
  }

  /// 写时间（存成 ISO 8601 字符串）。
  Future<void> writeDateTime(String key, DateTime value) =>
      write(key, value.toIso8601String());

  Future<void> remove(String key) async {
    await (_db.delete(_db.settings)
          ..where((s) => s.settingKey.equals(key)))
        .go();
  }
}
