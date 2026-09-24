import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 把 entitlements plist 里的布尔授权解析成 Map。
///
/// 故意不引 plist 依赖：这两个文件由 Xcode 生成、结构固定，
/// 先剥掉 `<!-- -->` 注释，再按 `<key>X</key><true/>` 抓就够可靠。
/// （必须剥注释 —— 注释里会写「app-sandbox = false」这种说明文字，
/// 不剥会把说明误当成真实配置。）
Map<String, bool> parseBoolEntitlements(String xml) {
  final stripped = xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  final pattern = RegExp(r'<key>([^<]+)</key>\s*<(true|false)\s*/>');
  return {
    for (final m in pattern.allMatches(stripped))
      m.group(1)!: m.group(2) == 'true',
  };
}

void main() {
  final releaseFile = File('macos/Runner/Release.entitlements');
  final debugFile = File('macos/Runner/DebugProfile.entitlements');
  final pbxprojFile = File('macos/Runner.xcodeproj/project.pbxproj');

  late Map<String, bool> release;
  late Map<String, bool> debug;

  setUpAll(() {
    release = parseBoolEntitlements(releaseFile.readAsStringSync());
    debug = parseBoolEntitlements(debugFile.readAsStringSync());
  });

  group('解析器自身', () {
    test('能读出键值', () {
      expect(parseBoolEntitlements('<key>a</key><true/>'), {'a': true});
      expect(parseBoolEntitlements('<key>a</key>\n\t<false/>'), {'a': false});
    });

    test('注释里的说明文字不会被误当成配置', () {
      const xml = '<dict><!-- 这里是 app-sandbox = false 的说明 -->'
          '<key>real</key><true/></dict>';
      expect(parseBoolEntitlements(xml), {'real': true});
    });

    test('真实文件都能解析出非空配置', () {
      expect(release, isNotEmpty);
      expect(debug, isNotEmpty);
    });
  });

  // ── 本次 bug 的核心：Release 漏了 Debug 有的授权 ──────────────────
  group('两个 build 的授权不许再分叉', () {
    test('两个文件的授权项集合与取值必须完全一致', () {
      // 必须双向比。原来那个 bug 是「Release **漏了** Debug 有的
      // network.server」——只顺着 Release 遍历是抓不到的。
      for (final entry in debug.entries) {
        expect(
          release.containsKey(entry.key),
          isTrue,
          reason: '${entry.key} 只在 Debug 里有，Release 漏了 —— '
              '这正是「debug 能播、release 不能播」的成因',
        );
        expect(
          release[entry.key],
          entry.value,
          reason: '${entry.key} 两个 build 取值不同：'
              'Release=${release[entry.key]}，Debug=${entry.value}',
        );
      }
      for (final entry in release.entries) {
        expect(
          debug.containsKey(entry.key),
          isTrue,
          reason: '${entry.key} 只在 Release 里有，Debug 没有 —— '
              '两个 build 会跑出不同行为',
        );
        expect(
          debug[entry.key],
          entry.value,
          reason: '${entry.key} 两个 build 取值不同：'
              'Release=${entry.value}，Debug=${debug[entry.key]}',
        );
      }
    });

    test('app-sandbox 两个 build 都必须是 false', () {
      // 开着沙箱会同时打断两件事：
      //   1) just_audio 为「带自定义头的音源」起的本地代理 bind() 被拒
      //      → 每首歌都在装载阶段失败（表现为「debug 能播、release 不能播」）
      //   2) 钥匙串报 -34018 → 凭证静默降级到内存 → 每次启动都要重登
      expect(release['com.apple.security.app-sandbox'], isFalse,
          reason: 'Release 又把沙箱打开了，播放和凭证都会坏');
      expect(debug['com.apple.security.app-sandbox'], isFalse);
    });

    test('network.client 两个 build 都必须开', () {
      expect(release['com.apple.security.network.client'], isTrue);
      expect(debug['com.apple.security.network.client'], isTrue);
    });

    test('network.server 两个 build 都必须开（本地代理依赖它）', () {
      expect(release['com.apple.security.network.server'], isTrue,
          reason: '缺这一项 → just_audio 的 _ProxyHttpServer bind() 失败');
      expect(debug['com.apple.security.network.server'], isTrue);
    });

    test('都不许带 get-task-allow', () {
      // 调试用授权，不该出现在授权文件里；若出现说明
      // pbxproj 的 CODE_SIGN_INJECT_BASE_ENTITLEMENTS 又没设成 NO。
      expect(release.containsKey('com.apple.security.get-task-allow'), isFalse);
      expect(debug.containsKey('com.apple.security.get-task-allow'), isFalse);
    });
  });

  group('pbxproj 构建配置', () {
    late String pbxproj;

    setUpAll(() => pbxproj = pbxprojFile.readAsStringSync());

    test('Release 配置指向 Release.entitlements，且关闭基础授权注入', () {
      final marker = 'CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;';
      final at = pbxproj.indexOf(marker);
      expect(at, greaterThan(-1), reason: '找不到 Release 的授权文件绑定');

      // 同一条 build settings 块内（前后各取一段窗口）必须紧跟注入开关。
      final window = pbxproj.substring(
        at,
        (at + 600).clamp(0, pbxproj.length),
      );
      expect(window, contains('CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;'),
          reason: 'Xcode 默认会注入 get-task-allow 等基础授权，'
              'Release 必须显式关掉');
    });

    test('Debug 配置仍然指向 DebugProfile.entitlements', () {
      expect(pbxproj, contains('CODE_SIGN_ENTITLEMENTS = Runner/DebugProfile.entitlements;'),
          reason: 'Debug 需要 get-task-allow 才能挂调试器，不许改成 Release 那份');
    });

    test('除首行标记外没有行注释 —— OpenStep plist 只认 /* */', () {
      // 首行 `// !$*UTF8*$!` 是 Xcode 写的编码标记，属于格式本身，必须放行。
      const magic = '// !\$*UTF8*\$!';
      final offenders = <int>[];
      final lines = pbxproj.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim() == magic) continue;
        if (RegExp(r'^\s*//').hasMatch(line)) offenders.add(i + 1);
      }
      expect(offenders, isEmpty,
          reason: '第 $offenders 行是 // 注释，会让 pbxproj 解析失败；'
              '要注释请用 /* */');
    });
  });

  // ── 签名身份不许落库（开源仓库的隐私与可构建性）──────────────────
  // 仓库里出现真实证书名 / Team ID 有两重害处：
  //   1) 把开发者的公司主体或个人身份公开出去；
  //   2) clone 者本机没有那张证书，构建会卡在签名环节。
  // 所以默认必须是 ad-hoc（"-"），真实身份写进
  // macos/Runner/Configs/Signing.local.xcconfig（已被 .gitignore 排除）。
  //
  // 之所以要写成断言：Xcode 图形界面里改一次签名，就会把证书名写回
  // pbxproj —— 没有这道防线，下次提交就把它带上去了。
  group('签名身份不许落库', () {
    late String pbxproj;

    setUpAll(() => pbxproj = pbxprojFile.readAsStringSync());

    List<String> valuesOf(String key) => RegExp('$key = "?([^";\\n]*)"?;')
        .allMatches(pbxproj)
        .map((m) => m.group(1)!.trim())
        .toList();

    test('pbxproj 里所有 CODE_SIGN_IDENTITY 都是 ad-hoc', () {
      final values = valuesOf('CODE_SIGN_IDENTITY');
      expect(values, isNotEmpty,
          reason: '一条都没匹配到，说明正则要跟着 pbxproj 的写法更新');
      for (final v in values) {
        expect(v, '-',
            reason: 'pbxproj 里写了具体签名身份「$v」。真实证书名不许进仓库，'
                '请留 "-"（ad-hoc）；个人身份写到 '
                'macos/Runner/Configs/Signing.local.xcconfig。');
      }
    });

    test('pbxproj 里所有 DEVELOPMENT_TEAM 都是空的', () {
      final values = valuesOf('DEVELOPMENT_TEAM');
      expect(values, isNotEmpty,
          reason: '一条都没匹配到，说明正则要跟着 pbxproj 的写法更新');
      for (final v in values) {
        expect(v, isEmpty,
            reason: 'pbxproj 里写了 Team ID「$v」，等于把账号身份公开出去');
      }
    });

    test('pbxproj 里不出现 Developer ID 证书全名', () {
      expect(pbxproj.contains('Developer ID Application:'), isFalse,
          reason: 'pbxproj 里残留了 Developer ID 证书全名');
    });

    test('签名默认值在 AppInfo.xcconfig，并留了本地覆盖入口', () {
      final f = File('macos/Runner/Configs/AppInfo.xcconfig');
      expect(f.existsSync(), isTrue,
          reason: 'AppInfo.xcconfig 是 Runner target 的 base config，签名默认值放这里');
      final text = f.readAsStringSync();

      expect(text, contains('CODE_SIGN_IDENTITY = -'),
          reason: '默认必须是 ad-hoc，否则 clone 者没有证书就构建不了');
      expect(text, contains('#include? "Signing.local.xcconfig"'),
          reason: '缺少本地签名覆盖入口 —— 出分发包时只能去改仓库里的文件');
      expect(text.contains('Developer ID Application:'), isFalse,
          reason: 'AppInfo.xcconfig 里不许写真实证书名');
    });
  });
}
