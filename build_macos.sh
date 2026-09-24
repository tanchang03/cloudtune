#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# CloudTune macOS 本地构建脚本
#
# 用法：
#   ./build_macos.sh                      # 构建 Debug 包
#   ./build_macos.sh --release            # 构建 Release 包（ad-hoc 签名）
#   ./build_macos.sh --release <TeamID>   # 用 Developer ID 签名（出分发包用）
#
# 签名：仓库默认 ad-hoc，任何人都能直接构建，不需要开发者证书。
#       要出能分发给别人的包，传 TeamID —— 脚本会把证书名与 Team ID 写进
#       macos/Runner/Configs/Signing.local.xcconfig（已被 .gitignore 排除，
#       不会污染仓库）。证书名可用 SIGN_IDENTITY 环境变量显式指定。
#
# 前置条件：
#   - Flutter 3.29+ 已在 PATH 里（或设 FLUTTER 环境变量指向 flutter）
#   - Xcode 已装（或设 DEVELOPER_DIR 指向它）
#   - CocoaPods 已装（pod 在 PATH 里）
#
# 若命令行构建卡在「签名」，用 Xcode 打开 macos/Runner.xcworkspace，
# 选 Runner / My Mac，按 ▶ Run，Xcode 会引导你用免费 Apple ID 完成签名，
# 不需要付费开发者账号。
# ─────────────────────────────────────────────────────────────
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJ"

MODE="debug"
TEAM="${TEAM_ID:-}"
for arg in "$@"; do
  case "$arg" in
    --release) MODE="release" ;;
    --debug)   MODE="debug" ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *)         TEAM="$arg" ;;
  esac
done

# 1) 找 flutter。优先用 $FLUTTER，其次 PATH，最后试几个常见安装位置。
FLUTTER="${FLUTTER:-}"
if [ -z "$FLUTTER" ]; then
  FLUTTER="$(command -v flutter || true)"
fi
if [ -z "$FLUTTER" ]; then
  for c in /opt/homebrew/bin/flutter /usr/local/bin/flutter "$HOME/flutter/bin/flutter"; do
    if [ -x "$c" ]; then FLUTTER="$c"; break; fi
  done
fi
if [ -z "$FLUTTER" ]; then
  echo "❌ 找不到 flutter。请把它加进 PATH，或设 FLUTTER=/path/to/flutter" >&2
  exit 1
fi
echo "==> 使用 Flutter: $FLUTTER"

# 2) Xcode 开发者目录（没设就用系统当前选择的那个）
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# 3) 清掉代理：原生构建不需要，且 Dart 的 CONNECT 隧道在代理下会 502
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy

# 4) 确认 pod 存在。找不到 pod 时 flutter build 只会打印一行提示
#    然后以退出码 0 结束、留下旧产物 —— 看起来「构建成功」，其实什么都没做。
if ! command -v pod >/dev/null 2>&1; then
  echo "❌ 找不到 pod（CocoaPods）。" >&2
  echo "   安装：brew install cocoapods   或   sudo gem install cocoapods" >&2
  echo "   已装但不在 PATH：把它所在的 bin 目录加进 PATH 再跑。" >&2
  exit 1
fi
echo "==> CocoaPods: $(pod --version)"

# 5) 可选：生成本地签名配置。
#    写进 Signing.local.xcconfig（已被 .gitignore 排除），**不动**仓库里的文件。
#    不传 TeamID 就跳过 —— 默认 ad-hoc 签名，直接就能构建。
if [ -n "$TEAM" ]; then
  LOCAL=macos/Runner/Configs/Signing.local.xcconfig

  IDENT="${SIGN_IDENTITY:-}"
  if [ -z "$IDENT" ]; then
    IDENT="$(security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)"
  fi
  if [ -z "$IDENT" ]; then
    echo "⚠️  本机找不到 Developer ID Application 证书，回退到 ad-hoc 签名。" >&2
    echo "   要出分发包，先在 Xcode 里登录 Apple ID，或用 SIGN_IDENTITY=<证书名> 指定。" >&2
    IDENT="-"
  fi

  {
    echo "// 由 build_macos.sh 生成，已被 .gitignore 排除，不会进仓库。"
    echo "CODE_SIGN_IDENTITY = ${IDENT}"
    echo "DEVELOPMENT_TEAM = ${TEAM}"
  } > "$LOCAL"
  echo "==> 已写入本地签名配置 $LOCAL"
  echo "    证书：$IDENT"
fi

echo "==> flutter pub get"
"$FLUTTER" pub get

echo "==> pod install"
( cd macos && pod install )

if [ "$MODE" = "release" ]; then
  echo "==> flutter build macos --release"
  "$FLUTTER" build macos --release
  APP=build/macos/Build/Products/Release/cloudtune.app
else
  echo "==> flutter build macos"
  "$FLUTTER" build macos
  APP=build/macos/Build/Products/Debug/cloudtune.app
fi

if [ -d "$APP" ]; then
  echo "✅ 构建成功：$APP"
  echo "   运行：open \"$APP\"   或   $FLUTTER run -d macos"
else
  echo "⚠️  未找到产物，多半卡在签名步骤。"
  echo "   请用 Xcode 打开 macos/Runner.xcworkspace → Runner / My Mac → ▶ Run"
fi
