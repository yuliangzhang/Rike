#!/usr/bin/env bash
# 安装 日课 / Rike.app 到 /Applications
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Rike.app"
DEST="/Applications/Rike.app"
OLD="/Applications/Gong.app"

[ -d "$APP" ] || { echo "先运行 ./scripts/build.sh" >&2; exit 1; }

for proc in "Rike.app/Contents/MacOS/Rike" "Gong.app/Contents/MacOS/Gong"; do
  if pgrep -f "$proc" >/dev/null; then
    echo "==> 退出正在运行的实例：$proc"
    pkill -f "$proc" || true
    sleep 2
  fi
done

echo "==> 安装到 $DEST"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# 改名前装过的旧包留在 /Applications 会同时出现在 Spotlight 里，
# 两个都能启动、共用同一份数据，很容易搞混。这里明确提示，但不替用户删。
if [ -d "$OLD" ]; then
  echo
  echo "注意：检测到改名前的旧应用 $OLD"
  echo "     它和新版共用同一份数据（bundle id 未变），建议删掉避免混淆："
  echo "       rm -rf \"$OLD\""
fi

echo "==> 完成。启动："
echo "    open $DEST"
echo
echo "首次启动后：菜单栏会出现「工」图标，桌面出现挂件。"
echo "无 Dock 图标是设计如此（LSUIElement），从菜单栏图标进入主窗口。"
