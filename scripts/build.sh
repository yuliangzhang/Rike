#!/usr/bin/env bash
# 组装 日课 / Rike.app —— SPM 编译 + 手工 bundle + 图标 + ad-hoc 签名
#
# 注意：产品名改成「日课 / Rike」，但 **BUNDLE_ID 保持 com.ybjv.gong 不变**。
# 数据目录是 <ApplicationSupport>/com.ybjv.gong/，导出文件里的 marker 也是
# `gong:generated`。改这些会让既有记录和已导出文件失联，得不偿失。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Rike"
DISPLAY_ZH="日课"
BUNDLE_ID="com.ybjv.gong"
VERSION="${GONG_VERSION:-0.2.0}"
BUILD_NO="${GONG_BUILD:-2}"
CONFIG="${GONG_CONFIG:-release}"

OUT="$ROOT/build"
APP="$OUT/$APP_NAME.app"

echo "==> swift build ($CONFIG)"
cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
[ -x "$BIN" ] || { echo "构建产物不存在: $BIN" >&2; exit 1; }

echo "==> 生成图标"
rm -rf "$OUT/$APP_NAME.iconset"
swift "$ROOT/scripts/make_icon.swift" "$OUT/$APP_NAME.iconset" >/dev/null
iconutil -c icns "$OUT/$APP_NAME.iconset" -o "$OUT/$APP_NAME.icns"

echo "==> 组装 bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" \
         "$APP/Contents/Resources/en.lproj" \
         "$APP/Contents/Resources/zh-Hans.lproj"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$OUT/$APP_NAME.icns" "$APP/Contents/Resources/$APP_NAME.icns"

# Info.plist 的本地化：Finder / Dock / 强制退出面板里显示的名字。
# CFBundle 原生支持，手工组装的 bundle 也吃这一套，不需要代码配合。
printf '"CFBundleDisplayName" = "%s";\n"CFBundleName" = "%s";\n' \
  "$APP_NAME" "$APP_NAME" > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
printf '"CFBundleDisplayName" = "%s";\n"CFBundleName" = "%s";\n' \
  "$DISPLAY_ZH" "$DISPLAY_ZH" > "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>           <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>            <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>              <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundleVersion</key>               <string>$BUILD_NO</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundleDevelopmentRegion</key>     <string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>zh-Hans</string></array>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>NSPrincipalClass</key>              <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>LSUIElement</key>                   <true/>
    <key>NSHumanReadableCopyright</key>      <string>Personal build</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> ad-hoc 签名"
codesign --force --sign - --timestamp=none "$APP" 2>&1 | sed 's/^/    /'

echo "==> 校验"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" >/dev/null

echo "==> 完成: $APP"
