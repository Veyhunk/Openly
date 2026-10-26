#!/bin/bash
trap 'printf "\n"' INT

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHER="$PROJECT_DIR/scripts/project-launcher.sh"

if [ ! -f "$LAUNCHER" ]; then
  printf '启动脚本不存在：%s\n' "$LAUNCHER"
  status=1
else
  /bin/bash "$LAUNCHER" "$@"
  status=$?
fi

printf '\n项目启动器已结束，退出码：%s\n' "$status"
if [ -t 0 ] && [ -t 1 ]; then
  user_shell="${SHELL:-/bin/zsh}"
  if [ ! -x "$user_shell" ]; then
    user_shell="/bin/zsh"
  fi
  cd "$PROJECT_DIR" || exit "$status"
  printf '已进入项目终端。重新启动：./scripts/project-launcher.sh\n'
  printf '输入 exit 可结束当前终端会话。\n\n'
  exec "$user_shell" -l
  printf '无法启动终端 shell：%s\n' "$user_shell"
fi

exit "$status"
