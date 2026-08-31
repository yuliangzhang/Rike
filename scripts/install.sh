#!/usr/bin/env bash
# 安装 Gong.app 到 /Applications
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Gong.app"
DEST="/Applications/Gong.app"

[ -d "$APP" ] || { echo "先运行 ./scripts/build.sh" >&2; exit 1; }

if pgrep -f "Gong.app/Contents/MacOS/Gong" >/dev/null; then
  echo "==> 退出正在运行的 Gong"
  pkill -f "Gong.app/Contents/MacOS/Gong" || true
  sleep 2
fi

echo "==> 安装到 $DEST"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
# 本机构建产物通常无 quarantine；转移后仍以防万一
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> 完成。启动："
echo "    open $DEST"
echo
echo "首次启动后：菜单栏会出现「工」图标，桌面出现挂件。"
echo "无 Dock 图标是设计如此（LSUIElement），从菜单栏图标进入主窗口。"
