#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="盲水印"

echo "=== 编译盲水印 macOS App ==="
echo "项目目录: $PROJECT_DIR"

# 编译
cd "$PROJECT_DIR"
swift build -c release --arch arm64 --arch x86_64 2>&1

# 查找可执行文件
EXEC_PATH="$PROJECT_DIR/.build/apple/Products/Release/BlindWatermark"

if [ ! -f "$EXEC_PATH" ]; then
    echo "错误：找不到编译产物 ($EXEC_PATH)"
    exit 1
fi

echo "可执行文件: $EXEC_PATH"

# 创建 .app bundle
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制可执行文件
cp "$EXEC_PATH" "$APP_BUNDLE/Contents/MacOS/BlindWatermark"
chmod +x "$APP_BUNDLE/Contents/MacOS/BlindWatermark"

# 复制 Info.plist
cp "$PROJECT_DIR/Sources/BlindWatermark/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# 复制图标
ICON_PATH="$PROJECT_DIR/Assets.xcassets/AppIcon.appiconset/AppIcon.icns"
if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "图标已嵌入"
fi

# 创建 PkgInfo
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "编译完成: $APP_BUNDLE"
echo "可通过以下命令运行: open \"$APP_BUNDLE\""
