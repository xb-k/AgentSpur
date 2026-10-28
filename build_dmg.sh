#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# AgentSpur — 纯原生 macOS AppKit 一键编译并打包 DMG 脚本
# 零第三方依赖：仅使用 macOS 系统自带 swift / sips / iconutil / codesign / hdiutil
# ==============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="AgentSpur"
DMG_NAME="${APP_NAME}.dmg"
BUILD_WORK_DIR="${ROOT_DIR}/.dmg-build"
STAGING_DIR="${BUILD_WORK_DIR}/staging"
APP_BUNDLE="${STAGING_DIR}/${APP_NAME}.app"
ICONSET_DIR="${BUILD_WORK_DIR}/AppIcon.iconset"
OUTPUT_DMG="${ROOT_DIR}/${DMG_NAME}"

echo "==> [1/6] 检查 macOS 编译环境..."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误：请在 macOS 系统上运行此打包脚本。"
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "错误：未检测到 Swift 工具链，请先运行: xcode-select --install"
  exit 1
fi

rm -rf "$BUILD_WORK_DIR"
mkdir -p "$STAGING_DIR" "$ICONSET_DIR"

# 若覆盖解压到旧目录，自动清理旧版残留的 main.swift，避免与 @main (AgentSpurApp.swift) 冲突
if [[ -f "${ROOT_DIR}/Sources/AgentSpur/main.swift" && -f "${ROOT_DIR}/Sources/AgentSpur/AgentSpurApp.swift" ]]; then
  rm -f "${ROOT_DIR}/Sources/AgentSpur/main.swift"
fi

echo "==> [2/6] 编译原生 AppKit 可执行文件 (Release)..."
BIN_PATH=""
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
  echo "    已生成 Universal 通用二进制 (Apple Silicon arm64 + Intel x86_64)"
  BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/${APP_NAME}"
else
  echo "    正在按本机原生架构编译 Release 二进制..."
  swift build -c release
  BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
fi

if [[ ! -f "$BIN_PATH" ]]; then
  echo "错误：未找到编译产物 $BIN_PATH"
  exit 1
fi

echo "==> [3/6] 生成高清冰瓷流体专属图标 (AppIcon.icns)..."
BASE_PNG="${BUILD_WORK_DIR}/icon_1024.png"
"$BIN_PATH" --export-icon "$BASE_PNG"

sips -z 16 16     "$BASE_PNG" --out "${ICONSET_DIR}/icon_16x16.png"      >/dev/null
sips -z 32 32     "$BASE_PNG" --out "${ICONSET_DIR}/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$BASE_PNG" --out "${ICONSET_DIR}/icon_32x32.png"      >/dev/null
sips -z 64 64     "$BASE_PNG" --out "${ICONSET_DIR}/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$BASE_PNG" --out "${ICONSET_DIR}/icon_128x128.png"    >/dev/null
sips -z 256 256   "$BASE_PNG" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$BASE_PNG" --out "${ICONSET_DIR}/icon_256x256.png"    >/dev/null
sips -z 512 512   "$BASE_PNG" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$BASE_PNG" --out "${ICONSET_DIR}/icon_512x512.png"    >/dev/null
cp "$BASE_PNG" "${ICONSET_DIR}/icon_512x512@2x.png"

ICON_ICNS="${BUILD_WORK_DIR}/AppIcon.icns"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"

echo "==> [4/6] 组装原生应用包 ${APP_NAME}.app..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "$BIN_PATH" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${ROOT_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "$ICON_ICNS" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

if [[ -f "${ROOT_DIR}/Resources/sample-deepseek-pack.json" ]]; then
  cp "${ROOT_DIR}/Resources/sample-deepseek-pack.json" "${APP_BUNDLE}/Contents/Resources/sample-deepseek-pack.json"
fi

echo "==> [5/6] 执行本地 Ad-Hoc 代码签名..."
xattr -cr "$APP_BUNDLE" || true
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> [6/6] 制作拖拽安装镜像 ${DMG_NAME} 并同步驻留 /Applications..."
ln -s /Applications "${STAGING_DIR}/Applications"
rm -f "$OUTPUT_DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG" >/dev/null

INSTALLED_APP="/Applications/${APP_NAME}.app"
if [[ -w "/Applications" ]]; then
  osascript -e 'tell application id "app.agentspur.macos" to quit' >/dev/null 2>&1 || true
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  sleep 0.35
  rm -rf "$INSTALLED_APP"
  ditto "$APP_BUNDLE" "$INSTALLED_APP"
  xattr -cr "$INSTALLED_APP" || true
fi

rm -rf "$BUILD_WORK_DIR"

echo ""
echo "========================================================"
echo " 打包与独立后台驻留完成！"
echo " DMG 镜像路径: ${OUTPUT_DMG}"
if [[ -d "$INSTALLED_APP" ]]; then
  echo " 已自动安装至: ${INSTALLED_APP}"
  echo " 正在通过 macOS LaunchServices 独立拉起菜单栏常驻进程（完全脱离当前终端会话）..."
  open -a "$INSTALLED_APP" || true
else
  echo " 双击打开 ${DMG_NAME}，将 AgentSpur 拖入 Applications 即可全局常驻。"
  if command -v open >/dev/null 2>&1; then
    open -R "$OUTPUT_DMG" || true
  fi
fi
echo " 提示：若菜单栏右侧图标过多被刘海屏遮挡，可按住 ⌘ 键将小鲸鱼图标向右拖到控制中心旁，macOS 永不折叠。"
echo "========================================================"

