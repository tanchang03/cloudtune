import 'package:cloudtune/core/utils/audio_formats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extensionOf', () {
    test('常规扩展名取小写', () {
      expect(extensionOf('song.mp3'), 'mp3');
      expect(extensionOf('song.FLAC'), 'flac');
    });

    test('多个点时取最后一段', () {
      expect(extensionOf('artist - title.live.mp3'), 'mp3');
    });

    test('无扩展名返回空串', () {
      expect(extensionOf('README'), '');
      expect(extensionOf('noext'), '');
    });

    test('隐藏文件与结尾点号不算扩展名', () {
      expect(extensionOf('.mp3'), '');
      expect(extensionOf('song.'), '');
    });

    test('目录风格路径也按文件名处理', () {
      expect(extensionOf('/音乐/华语/晴天.mp3'), 'mp3');
    });
  });

  group('isAudioFile', () {
    test('扩展名命中即为音频', () {
      for (final ext in kAudioExtensions) {
        expect(isAudioFile('x.$ext'), isTrue, reason: '.$ext 应被识别为音频');
      }
    });

    test('MIME 命中即为音频（扩展名不认识时）', () {
      expect(isAudioFile('mystery.bin', mimeType: 'audio/mpeg'), isTrue);
      expect(isAudioFile('mystery', mimeType: 'AUDIO/FLAC'), isTrue);
    });

    test('非音频返回 false', () {
      expect(isAudioFile('cover.jpg'), isFalse);
      expect(isAudioFile('movie.mp4'), isFalse);
      expect(isAudioFile('notes.txt'), isFalse);
      expect(isAudioFile('cover.png', mimeType: 'image/png'), isFalse);
    });

    test('无扩展名无 MIME 返回 false', () {
      expect(isAudioFile('unknown'), isFalse);
    });
  });

  group('isHighRes', () {
    test('DSD / WAV / AIFF 属于高解析', () {
      expect(isHighRes('a.dsf'), isTrue);
      expect(isHighRes('a.dff'), isTrue);
      expect(isHighRes('a.wav'), isTrue);
      expect(isHighRes('a.aiff'), isTrue);
    });

    test('mp3 / flac 不算高解析标记', () {
      expect(isHighRes('a.mp3'), isFalse);
      expect(isHighRes('a.flac'), isFalse);
    });
  });

  group('guessTitleArtist', () {
    test('去掉音轨号前缀', () {
      expect(guessTitleArtist('01. 晴天.mp3').title, '晴天');
      expect(guessTitleArtist('02 - 稻香.flac').title, '稻香');
      expect(guessTitleArtist('03_七里香.mp3').title, '七里香');
      expect(guessTitleArtist('1. 夜曲.mp3').title, '夜曲');
    });

    test('拆分「艺术家 - 曲名」', () {
      final r = guessTitleArtist('周杰伦 - 晴天.flac');
      expect(r.title, '晴天');
      expect(r.artist, '周杰伦');
    });

    test('支持 en dash 与 em dash 分隔', () {
      expect(guessTitleArtist('A – B.mp3').artist, 'A');
      expect(guessTitleArtist('A — B.mp3').artist, 'A');
    });

    test('不带空格的单连字符不拆分（避免误伤曲名）', () {
      final r = guessTitleArtist('Love-Me-Tender.mp3');
      expect(r.title, 'Love-Me-Tender');
      expect(r.artist, isNull);
    });

    test('解析不出来时退化为去扩展名的文件名', () {
      final r = guessTitleArtist('晴天.mp3');
      expect(r.title, '晴天');
      expect(r.artist, isNull);
    });

    test('左侧过长时不认为是艺术家（防止整句被当人名）', () {
      final long = 'a' * 50;
      final r = guessTitleArtist('$long - 短名.mp3');
      expect(r.artist, isNull);
      expect(r.title, contains('短名'));
    });

    test('同时带音轨号与艺术家时两者都处理', () {
      final r = guessTitleArtist('01. 周杰伦 - 晴天.mp3');
      expect(r.title, '晴天');
      expect(r.artist, '周杰伦');
    });

    test('括号后缀保留在曲名里', () {
      expect(guessTitleArtist('Artist - Title (Live).mp3').title, 'Title (Live)');
    });
  });

  // 下面这些目录名 / 文件名全部抄自真实曲库（一次 444 首的全库扫描结果），
  // 不是编出来的理想样例 —— 这些网盘分享目录的命名非常不统一，
  // 解析规则必须扛得住真实数据。
  group('detectNameStyle（靠同一目录里的重复度判断谁是艺术家）', () {
    test('常规专辑：左侧是艺术家', () {
      final style = detectNameStyle([
        '凤凰传奇 - 一代天骄.flac',
        '凤凰传奇 - 爱的狂怒.flac',
        '凤凰传奇 - 爱的天下.flac',
      ]);
      expect(style.order, NameOrder.artistFirst);
      expect(style.bareHyphen, isFalse);
    });

    test('精选集反向命名：右侧才是艺术家（回归：曾把曲名当艺术家）', () {
      final style = detectNameStyle([
        '爱情岁月 - 郑伊健.flac',
        '甘心替代你 - 郑伊健.flac',
        '古古惑惑 - 谢天华朱永棠林晓峰.flac',
        '扑火 - 陈小春.flac',
      ]);
      expect(style.order, NameOrder.titleFirst);
    });

    test('带音轨号也不影响判断', () {
      final style = detectNameStyle([
        '01.风继续吹 (Remastered 2026) - 张国荣.flac',
        '02.不羁的风 (Remastered 2026) - 张国荣.flac',
        '03.Monica (Remastered 2026) - 张国荣.flac',
      ]);
      expect(style.order, NameOrder.titleFirst);
    });

    test('整目录都不带空格连字符时才敢拆裸连字符', () {
      final style = detectNameStyle([
        '任素汐-别来无恙[无损音质].flac',
        '任素汐-本末[无损音质].flac',
        '任素汐-夜灯[无损音质].flac',
      ]);
      expect(style.order, NameOrder.artistFirst);
      expect(style.bareHyphen, isTrue);
    });

    test('只有一首时不敢下结论，退回保守默认', () {
      expect(detectNameStyle(['蔡琴 - 渡口.flac']).order,
          NameOrder.artistFirst);
      expect(detectNameStyle(const <String>[]).order, NameOrder.artistFirst);
      expect(detectNameStyle(['Love-Me-Tender.mp3']).bareHyphen, isFalse);
    });

    test('两侧唯一度相同时按通用约定（左=艺术家）', () {
      expect(detectNameStyle(['A - B.mp3', 'C - D.mp3']).order,
          NameOrder.artistFirst);
    });
  });

  group('splitTrackName', () {
    test('按 titleFirst 约定拆出真正的曲名与艺术家', () {
      const style = NameStyle(order: NameOrder.titleFirst);
      final r = splitTrackName('爱情岁月 - 郑伊健.flac', style);
      expect(r.title, '爱情岁月');
      expect(r.artist, '郑伊健');
    });

    test('bareHyphen 打开后才拆不带空格的连字符', () {
      const style = NameStyle(bareHyphen: true);
      final r = splitTrackName('任素汐-别来无恙.flac', style);
      expect(r.title, '别来无恙');
      expect(r.artist, '任素汐');

      // 同一个文件名，没开 bareHyphen 时不该被拆
      final guarded = splitTrackName('任素汐-别来无恙.flac');
      expect(guarded.title, '任素汐-别来无恙');
      expect(guarded.artist, isNull);
    });

    test('titleFirst 下过长的右侧（被当成艺术家）不拆分', () {
      const style = NameStyle(order: NameOrder.titleFirst);
      final r = splitTrackName('短 - ${'a' * 50}.mp3', style);
      expect(r.artist, isNull);
      expect(r.title, contains('短'));
    });
  });

  group('cleanDisplayName（去掉音质/格式噪声）', () {
    test('方括号里的音质标记全部丢掉', () {
      expect(
        cleanDisplayName('小虎队 - 爱 (2025 Remastered)(2025) [16B-44.1kHz][Q]'),
        '小虎队 - 爱 (2025 Remastered)',
      );
      expect(
        cleanDisplayName('群星.2016 -《鉴听天碟合唱篇》华纳SACD[DSF+分轨]'),
        '群星.2016 -《鉴听天碟合唱篇》华纳SACD',
      );
    });

    test('版本信息必须保留（Remastered 属于专辑身份，不是噪声）', () {
      expect(cleanDisplayName('爱 (2025 Remastered)'), '爱 (2025 Remastered)');
      expect(cleanDisplayName('浮尘几章 (2026)'), '浮尘几章');
    });

    test('结尾散落的格式词与年份', () {
      expect(
        cleanDisplayName('周华健 - 小天堂(周华健&EASY BAND) - 1996   Flac'),
        '周华健 - 小天堂(周华健&EASY BAND)',
      );
      expect(
        cleanDisplayName('李克勤.2014-《精选到无朋友》 4CD[香港首版]WAV+CUE'),
        '李克勤.2014-《精选到无朋友》',
      );
    });

    test('长串音质尾巴一次清干净', () {
      expect(
        cleanDisplayName(
          '任素汐 浮尘几章(2026) FLAC Hi-Res 24bit 48khz 臻品母带 24 192khz',
        ),
        '任素汐 浮尘几章',
      );
    });

    test('不含噪声时原样返回', () {
      expect(cleanDisplayName('周传雄 烟雨平生'), '周传雄 烟雨平生');
    });

    test('括号里的 CD1 是「第 1 张碟」，不能当噪声抹掉（回归）', () {
      expect(
        cleanDisplayName('[你是我的骄傲演唱会 CD1](2002)[WAV]'),
        '[你是我的骄傲演唱会 CD1]',
      );
    });

    test('没配平的括号 + 长串音质尾巴（回归）', () {
      expect(
        cleanDisplayName(
          '张靓颖 执棋(2026) FLAC Hi-Res 24bit 48khz)+192khz 臻品母带 24 192khz',
        ),
        '张靓颖 执棋',
      );
    });
  });

  group('splitTrackName 修掉两侧残留的分隔符', () {
    test('真实库里的 `刘德华.-.[专辑]` 写法（回归：曾解析成 `刘德华.`）', () {
      const style = NameStyle(bareHyphen: true);
      final r = splitTrackName(
        '刘德华.-.[你是我的骄傲演唱会 CD1](2002)[WAV].wav',
        style,
      );
      expect(r.artist, '刘德华');
      expect(r.title, '[你是我的骄傲演唱会 CD1](2002)[WAV]');
      // 接着清洗就得到可以直接显示的曲名
      expect(cleanDisplayName(r.title), '[你是我的骄傲演唱会 CD1]');
    });
  });

  group('folderArtistHint / folderAlbumName', () {
    test('「艺术家 - 专辑」结构', () {
      expect(folderArtistHint('周华健 - 小天堂(周华健&EASY BAND) - 1996   Flac'),
          '周华健');
      expect(folderAlbumName('周华健 - 小天堂(周华健&EASY BAND) - 1996   Flac'),
          '小天堂(周华健&EASY BAND)');

      expect(folderArtistHint('小虎队 - 爱 (2025 Remastered)(2025) [16B-44.1kHz][Q]'),
          '小虎队');
      expect(
        folderAlbumName('小虎队 - 爱 (2025 Remastered)(2025) [16B-44.1kHz][Q]'),
        '爱 (2025 Remastered)',
      );
    });

    test('连字符直接贴着书名号也认', () {
      expect(folderArtistHint('李克勤.2014-《精选到无朋友》 4CD[香港首版]WAV+CUE'),
          '李克勤');
      expect(folderAlbumName('李克勤.2014-《精选到无朋友》 4CD[香港首版]WAV+CUE'),
          '《精选到无朋友》');
    });

    test('两段式空格命名（艺术家 专辑）', () {
      expect(folderArtistHint('周传雄 烟雨平生'), '周传雄');
      expect(folderAlbumName('周传雄 烟雨平生'), '烟雨平生');
      expect(folderArtistHint('任素汐 浮尘几章(2026) FLAC Hi-Res 24bit 48khz'),
          '任素汐');
    });

    test('只有艺术家没有专辑时，整段当专辑名', () {
      expect(folderArtistHint('凤凰传奇(FLAC 24bit 192khz)'), isNull);
      expect(folderAlbumName('凤凰传奇(FLAC 24bit 192khz)'), '凤凰传奇');
    });

    test('目录名为空返回 null', () {
      expect(folderArtistHint(''), isNull);
      expect(folderAlbumName(''), isNull);
    });

    test('书名号前没有连字符也能拆（`蔡琴《试音蔡琴》`）', () {
      expect(folderArtistHint('蔡琴《试音蔡琴》24K金碟 [低速原抓WAV+CUE]'), '蔡琴');
      expect(
        folderAlbumName('陈慧娴《经典重逢DSD[银合金CD]》[正版CD原抓WAV+CUE]'),
        contains('经典重逢'),
      );
    });

    test('整张专辑信息不能当艺术家（回归：曾把专辑名当歌手）', () {
      const folder = '张学友.2018《真情流露》HQ+S 纯银深度[低速原抓WAV+CUE]';
      expect(folderArtistHint(folder), '张学友');
      expect(folderAlbumName(folder), '《真情流露》HQ+S 纯银深度');
    });

    test('推不出人名时宁可不给提示，也不要给个错的', () {
      // 三段以上、又没有可用的分隔符 → 放弃，而不是硬取第一段
      const folder = '张国荣 張國榮 ETERNAL (2026) (FLAC 24bit 48khz)';
      expect(folderArtistHint(folder), isNull);
      expect(folderAlbumName(folder), '张国荣 張國榮 ETERNAL');
    });
  });

  group('lastPathSegment / normalizeDirPath', () {
    test('末尾有无斜杠都取最后一段', () {
      expect(lastPathSegment('/音乐/华语/凤凰传奇/'), '凤凰传奇');
      expect(lastPathSegment('/音乐/华语/凤凰传奇'), '凤凰传奇');
      expect(lastPathSegment(''), '');
      expect(lastPathSegment(null), '');
    });

    test('归一化去掉结尾斜杠，便于当分组键', () {
      expect(normalizeDirPath('/音乐/华语/'), '/音乐/华语');
      expect(normalizeDirPath('/音乐/华语'), '/音乐/华语');
      expect(normalizeDirPath(null), '');
    });
  });

  group('audioQualityOf —— 音质家族', () {
    test('DSD', () {
      expect(audioQualityOf('01. 还有.dsf'), AudioQuality.dsd);
      expect(audioQualityOf('a.DFF'), AudioQuality.dsd);
    });

    test('无损压缩', () {
      for (final ext in const ['flac', 'alac', 'ape', 'wv', 'tak', 'tta']) {
        expect(audioQualityOf('x.$ext'), AudioQuality.lossless, reason: '.$ext');
      }
    });

    test('未压缩 PCM', () {
      for (final ext in const ['wav', 'aiff', 'aif']) {
        expect(
          audioQualityOf('x.$ext'),
          AudioQuality.uncompressed,
          reason: '.$ext',
        );
      }
    });

    test('有损', () {
      for (final ext in const ['mp3', 'aac', 'ogg', 'opus', 'wma']) {
        expect(audioQualityOf('x.$ext'), AudioQuality.lossy, reason: '.$ext');
      }
    });

    test('多声道封装', () {
      for (final ext in const ['dts', 'ac3', 'mka']) {
        expect(audioQualityOf('x.$ext'), AudioQuality.surround, reason: '.$ext');
      }
    });

    test('认不出的扩展名 → unknown，不瞎猜成有损', () {
      expect(audioQualityOf('a.bin'), AudioQuality.unknown);
      expect(audioQualityOf('noext'), AudioQuality.unknown);
    });

    test('m4a 靠码率分 AAC 与 ALAC（扩展名自证不了）', () {
      // 拿不到码率时按更常见的 AAC 算
      expect(audioQualityOf('a.m4a'), AudioQuality.lossy);
      expect(audioQualityOf('a.m4a', bitrateKbps: 256), AudioQuality.lossy);
      // 分界线在 kAlacMinKbps 上，正好取到它算无损
      expect(audioQualityOf('a.m4a', bitrateKbps: kAlacMinKbps - 1),
          AudioQuality.lossy);
      expect(audioQualityOf('a.m4a', bitrateKbps: kAlacMinKbps),
          AudioQuality.lossless);
      expect(audioQualityOf('a.m4a', bitrateKbps: 1411), AudioQuality.lossless);
    });

    test('mp4a 与 m4a 同一套判定', () {
      expect(audioQualityOf('a.mp4a', bitrateKbps: 128), AudioQuality.lossy);
      expect(audioQualityOf('a.mp4a', bitrateKbps: 1000),
          AudioQuality.lossless);
    });
  });

  group('averageBitrateKbps —— 平均码率', () {
    // 这一组的「实测样本」来自夸克列目录接口的真实返回值，
    // 不是编出来的数字 —— 算出来的值必须和物理真值对得上，否则口径就是错的。
    test('实测：CD 规格的 WAV 算出来正好 1411kbps', () {
      // `李克勤.-.[精选到无朋友 CD1](2014)[WAV].wav`
      // size=765145628 字节、duration=4338 秒
      expect(
        averageBitrateKbps(sizeBytes: 765145628, durationMs: 4338 * 1000),
        1411,
        reason: '44.1kHz / 16bit / 立体声 未压缩 = 1411kbps，'
            '推得对才会落在这个数上',
      );
    });

    test('实测：24bit/48kHz 的 flac 落在 1700 上下', () {
      // `01 - Über den Wolken(qobuz)24 48.flac`
      // size=39258174 字节、duration=186 秒
      expect(averageBitrateKbps(sizeBytes: 39258174, durationMs: 186000), 1689);
    });

    test('320kbps 的 mp3 算出来就是 320', () {
      // 320kbps × 200 秒 = 64,000,000 bit = 8,000,000 字节
      expect(averageBitrateKbps(sizeBytes: 8000000, durationMs: 200000), 320);
    });

    test('大文件不溢出（4GiB 整轨）', () {
      expect(
        averageBitrateKbps(
          sizeBytes: 4 * 1024 * 1024 * 1024,
          durationMs: 3600 * 1000,
        ),
        9544,
      );
    });

    test('体积或时长缺失 / 非正一律 null，绝不用 0 除出个假数字', () {
      expect(averageBitrateKbps(sizeBytes: null, durationMs: 1000), isNull);
      expect(averageBitrateKbps(sizeBytes: 1000, durationMs: null), isNull);
      expect(averageBitrateKbps(sizeBytes: 0, durationMs: 1000), isNull);
      expect(averageBitrateKbps(sizeBytes: 1000, durationMs: 0), isNull);
      expect(averageBitrateKbps(sizeBytes: -1, durationMs: 1000), isNull);
      expect(averageBitrateKbps(sizeBytes: 1000, durationMs: -1), isNull);
      expect(averageBitrateKbps(), isNull);
    });
  });

  group('formatLabelOf —— 展示用格式标签', () {
    test('大写扩展名', () {
      expect(formatLabelOf('a.flac'), 'FLAC');
      expect(formatLabelOf('a.Mp3'), 'MP3');
      expect(formatLabelOf('周杰伦 - 晴天.dsf'), 'DSF');
    });

    test('没有扩展名时说「音频」而不是「未知」', () {
      // 能走到展示这一层的曲目一定是被 MIME（audio/*）判成音频的，
      // 说「音频」比说「未知」诚实
      expect(formatLabelOf('mystery'), '音频');
      expect(formatLabelOf('.mp3'), '音频');
    });
  });
}
