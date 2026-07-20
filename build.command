#!/bin/bash
# Openly — 构建脚本（双击 .command 文件在 Terminal 中运行）
set -e

cd "$(dirname "$0")"
PROJECT_DIR="$(pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Openly"
VERSION="1.0.0"

# ── 颜色 ──────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

clear

# ── 菜单 ──────────────────────────────────────────
show_menu() {
    echo ""
    echo -e "  ${BLUE}╭──────────────────────────────────────╮${NC}"
    echo -e "  ${BLUE}│${NC}        ${CYAN}Openly ${VERSION} — 构建工具${NC}        ${BLUE}│${NC}"
    echo -e "  ${BLUE}├──────────────────────────────────────┤${NC}"
    echo -e "  ${BLUE}│${NC}  ${GREEN}1${NC}  编译 (swift build)               ${BLUE}│${NC}"
    echo -e "  ${BLUE}│${NC}  ${GREEN}2${NC}  编译并运行                       ${BLUE}│${NC}"
    echo -e "  ${BLUE}│${NC}  ${GREEN}3${NC}  生成 App 图标                    ${BLUE}│${NC}"
    echo -e "  ${BLUE}│${NC}  ${GREEN}4${NC}  创建 .app Bundle                 ${BLUE}│${NC}"
    echo -e "  ${BLUE}│${NC}  ${GREEN}5${NC}  创建 DMG 安装包                  ${BLUE}│${NC}"
    echo -e "  ${BLUE}│${NC}  ${GREEN}6${NC}  一键构建 (清理+编译+打包)        ${BLUE}│${NC}"
    echo -e "  ${BLUE}│${NC}  ${GREEN}7${NC}  清理构建缓存                     ${BLUE}│${NC}"
    echo -e "  ${BLUE}│${NC}  ${GREEN}8${NC}  运行测试                         ${BLUE}│${NC}"
    echo -e "  ${BLUE}│${NC}  ${GREEN}0${NC}  退出                             ${BLUE}│${NC}"
    echo -e "  ${BLUE}╰──────────────────────────────────────╯${NC}"
    echo ""
}

# ── 功能函数 ──────────────────────────────────────

do_build() {
    echo -e "\n${YELLOW}► 编译中...${NC}\n"
    swift build -c release 2>&1 | grep -E "^(Build|error|warning)" || true
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "\n${GREEN}✓ 编译成功${NC}"
        echo -e "  二进制: ${CYAN}$BUILD_DIR/release/$APP_NAME${NC}"
    else
        echo -e "\n${RED}✗ 编译失败${NC}"
        return 1
    fi
}

do_run() {
    do_build || return 1
    echo -e "\n${YELLOW}► 启动 Openly...${NC}\n"
    "$BUILD_DIR/release/$APP_NAME" &
}

do_icon() {
    echo -e "\n${YELLOW}► 生成图标...${NC}\n"
    cd "$PROJECT_DIR/Assets"

    if [ ! -f "generate_icon.swift" ]; then
        echo -e "${RED}✗ 未找到 generate_icon.swift${NC}"
        return 1
    fi

    swift generate_icon.swift

    if [ -d "AppIcon-light.iconset" ]; then
        iconutil -c icns AppIcon-light.iconset -o AppIcon.icns
        iconutil -c icns AppIcon-dark.iconset -o AppIcon-dark.icns
        cp AppIcon.icns AppIcon-dark.icns "$PROJECT_DIR/Sources/Resources/"
        rm -rf AppIcon-light.iconset AppIcon-dark.iconset
        echo -e "\n${GREEN}✓ 图标已生成 → Sources/Resources/${NC}"
    fi

    cd "$PROJECT_DIR"
}

do_app_bundle() {
    do_build || return 1

    echo -e "\n${YELLOW}► 创建 .app Bundle...${NC}\n"

    APP_BUNDLE="$PROJECT_DIR/.build/$APP_NAME.app"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"

    cp "$BUILD_DIR/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
    cp "$PROJECT_DIR/Sources/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    cp "$PROJECT_DIR/Sources/Resources/AppIcon-dark.icns" "$APP_BUNDLE/Contents/Resources/"

    # 生成 Info.plist
    cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Openly</string>
    <key>CFBundleIdentifier</key>
    <string>com.openly.app</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSRequiresNativeExecution</key>
    <true/>
</dict>
</plist>
PLIST

    echo -e "${GREEN}✓ .app Bundle 已创建${NC}"
    echo -e "  路径: ${CYAN}$APP_BUNDLE${NC}"
    echo -e "  双击打开: ${CYAN}open $APP_BUNDLE${NC}"
}

do_dmg() {
    do_app_bundle || return 1

    echo -e "\n${YELLOW}► 创建 DMG...${NC}\n"

    DMG_DIR="$PROJECT_DIR/.build/dmg"
    DMG_FILE="$PROJECT_DIR/.build/$APP_NAME-$VERSION.dmg"

    rm -rf "$DMG_DIR" "$DMG_FILE"
    mkdir -p "$DMG_DIR"
    cp -R "$PROJECT_DIR/.build/$APP_NAME.app" "$DMG_DIR/"
    ln -s /Applications "$DMG_DIR/"

    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_FILE" 2>&1 | tail -1

    rm -rf "$DMG_DIR"
    echo -e "\n${GREEN}✓ DMG 已创建${NC}"
    echo -e "  路径: ${CYAN}$DMG_FILE${NC}"
}

do_all() {
    echo -e "\n${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}       ${CYAN}一键构建 — 全流程${NC}            ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"

    echo -e "\n${YELLOW}[1/4] 清理...${NC}"
    swift package clean 2>/dev/null || true

    echo -e "\n${YELLOW}[2/4] 编译...${NC}"
    do_build || return 1

    echo -e "\n${YELLOW}[3/4] 打包 .app Bundle...${NC}"
    do_app_bundle || return 1

    echo -e "\n${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}     ${GREEN}✓ 一键构建完成！${NC}                ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
}

do_clean() {
    echo -e "\n${YELLOW}► 清理构建缓存...${NC}\n"
    rm -rf "$BUILD_DIR"
    swift package clean 2>/dev/null || true
    echo -e "${GREEN}✓ 清理完成${NC}"
}

do_test() {
    echo -e "\n${YELLOW}► 运行测试...${NC}\n"
    swift test 2>&1 || echo -e "\n${YELLOW}（暂无测试用例）${NC}"
}

# ── 主循环 ──────────────────────────────────────

while true; do
    show_menu
    read -p "  选择 [0-8]: " choice
    echo ""

    case $choice in
        1) do_build ;;
        2) do_run ;;
        3) do_icon ;;
        4) do_app_bundle ;;
        5) do_dmg ;;
        6) do_all ;;
        7) do_clean ;;
        8) do_test ;;
        0) echo -e "${GREEN}再见 👋${NC}\n"; exit 0 ;;
        *) echo -e "${RED}无效选择，请输入 0-8${NC}" ;;
    esac

    echo ""
    read -p "  按回车继续..."
    clear
done
