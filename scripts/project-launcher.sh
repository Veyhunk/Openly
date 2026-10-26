#!/bin/bash
# 基于全局 terminal-service-launcher 模板，使用 macOS Bash 3.2。
trap 'printf "\n"; exit 130' INT
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR" || exit 1
NAV_KEY=""
read_navigation_key() {
  local key suffix
  IFS= read -rsn 1 key || { NAV_KEY=eof; return; }
  case "$key" in
    '') NAV_KEY=enter ;;
    $'\033')
      suffix=""; IFS= read -rsn 2 -t 1 suffix 2>/dev/null || true
      case "$suffix" in '[A'|'OA') NAV_KEY=up ;; '[B'|'OB') NAV_KEY=down ;; *) NAV_KEY=escape ;; esac ;;
    *) NAV_KEY="$key" ;;
  esac
}
run_action() {
  case "$1" in
    build) swift build ;;
    package) python3 scripts/package-app.py release ;;
    run) python3 scripts/package-app.py debug && open "$PROJECT_DIR/.build/Openly.app" ;;
    test) swift build && bash scripts/test.sh && node scripts/test-browser-extension.cjs ;;
    integration) python3 scripts/package-app.py debug && bash scripts/test.sh --integration ;;
    dmg)
      python3 scripts/package-app.py release || return
      local stage archive
      stage="$(mktemp -d "$PROJECT_DIR/.build/dmg-stage.XXXXXX")" || return
      archive="$PROJECT_DIR/.build/Openly-$(date +%Y%m%d%H%M%S).dmg"
      ditto "$PROJECT_DIR/.build/Openly.app" "$stage/Openly.app" && ln -s /Applications "$stage/Applications" && hdiutil create -volname Openly -srcfolder "$stage" -format UDZO "$archive"
      local result=$?
      rm -rf "$stage"
      return "$result" ;;
    show) open "$PROJECT_DIR/.build" ;;
    *) printf '未知命令：%s\n' "$1"; return 2 ;;
  esac
}
if [ $# -gt 0 ]; then run_action "$1"; exit $?; fi
labels=("编译" "打包 Release 应用" "打包并运行 Debug" "自动化测试" "隔离系统接管测试" "生成 DMG" "打开构建目录" "退出")
actions=(build package run test integration dmg show quit)
selected=0
while true; do
  clear 2>/dev/null || true
  printf 'Openly — 开发与验证\n\n'
  for i in 0 1 2 3 4 5 6 7; do
    if [ "$i" -eq "$selected" ]; then printf '> '; else printf '  '; fi
    printf '%s  %s\n' "$((i + 1))" "${labels[$i]}"
  done
  printf '\n↑/↓ 选择，回车执行；数字单键立即执行，Esc/q 退出\n'
  read_navigation_key
  case "$NAV_KEY" in
    up) selected=$(((selected + 7) % 8)); continue ;;
    down) selected=$(((selected + 1) % 8)); continue ;;
    escape|q|Q|eof) exit 0 ;;
    enter) ;;
    [1-8]) selected=$((NAV_KEY - 1)) ;;
    *) continue ;;
  esac
  [ "${actions[$selected]}" = quit ] && exit 0
  run_action "${actions[$selected]}"
  result=$?
  printf '\n完成，退出码 %s。按回车返回。\n' "$result"
  while IFS= read -r reply; do [ -z "$reply" ] && break; done
 done
