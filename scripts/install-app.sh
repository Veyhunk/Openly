#!/bin/bash
# Build on demand, install Openly.app into /Applications, restart it, and print machine-readable status.
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_APP="$PROJECT_DIR/.build/Openly.app"
BUILD_BINARY="$BUILD_APP/Contents/MacOS/Openly"
INSTALL_APP="/Applications/Openly.app"
BATCH_RECEIVER="$HOME/Library/Application Support/Openly/Receiver.app"
TEMP_APP="/Applications/.Openly.app.tmp.$$"
FORCE_BUILD=0
NO_BUILD=0
NO_LAUNCH=0

for argument in "$@"; do
  case "$argument" in
    --force) FORCE_BUILD=1 ;;
    --no-build) NO_BUILD=1 ;;
    --no-launch) NO_LAUNCH=1 ;;
    -h|--help)
      printf '%s\n' '用法：scripts/install-app.sh [--force] [--no-build] [--no-launch]'
      exit 0
      ;;
    *) printf 'OPENLY_INSTALL_STATUS=failed\nOPENLY_ERROR=unknown_argument:%s\n' "$argument"; exit 2 ;;
  esac
done

printf 'OPENLY_PROJECT=%s\n' "$PROJECT_DIR"
printf 'OPENLY_INSTALL_PATH=%s\n' "$INSTALL_APP"

needs_build() {
  [ "$FORCE_BUILD" -eq 1 ] && return 0
  [ -x "$BUILD_BINARY" ] || return 0
  if find "$PROJECT_DIR/Sources" "$PROJECT_DIR/BridgeHost" "$PROJECT_DIR/BrowserExtension" \
      "$PROJECT_DIR/Package.swift" "$PROJECT_DIR/scripts/package-app.py" \
      -type f -newer "$BUILD_BINARY" -print -quit 2>/dev/null | grep . >/dev/null; then
    return 0
  fi
  return 1
}

if [ "$NO_BUILD" -eq 1 ]; then
  if [ ! -x "$BUILD_BINARY" ]; then
    printf 'OPENLY_INSTALL_STATUS=failed\nOPENLY_ERROR=release_artifact_missing\n'
    exit 3
  fi
  printf 'OPENLY_BUILD_ACTION=reused_forced\n'
elif needs_build; then
  printf 'OPENLY_BUILD_ACTION=compile_release\n'
  python3 "$PROJECT_DIR/scripts/package-app.py" release >/tmp/openly-install-package.$$.log 2>&1 || {
    cat /tmp/openly-install-package.$$.log
    rm -f /tmp/openly-install-package.$$.log
    printf 'OPENLY_INSTALL_STATUS=failed\nOPENLY_ERROR=release_build_failed\n'
    exit 4
  }
  cat /tmp/openly-install-package.$$.log
  rm -f /tmp/openly-install-package.$$.log
else
  printf 'OPENLY_BUILD_ACTION=reused_current\n'
fi

if [ ! -d "$BUILD_APP" ] || [ ! -x "$BUILD_BINARY" ]; then
  printf 'OPENLY_INSTALL_STATUS=failed\nOPENLY_ERROR=release_bundle_invalid\n'
  exit 5
fi

printf 'OPENLY_BUILD_APP=%s\n' "$BUILD_APP"

stopped=0
for process_pattern in "$INSTALL_APP/Contents" "$BATCH_RECEIVER/Contents"; do
  for pid in $(pgrep -f "$process_pattern" 2>/dev/null || true); do
    if [ "$pid" != "$$" ]; then
      kill "$pid" 2>/dev/null || true
      stopped=$((stopped + 1))
    fi
  done
done
sleep 1
printf 'OPENLY_OLD_PROCESSES_STOPPED=%s\n' "$stopped"

rm -rf "$TEMP_APP"
ditto "$BUILD_APP" "$TEMP_APP" || {
  printf 'OPENLY_INSTALL_STATUS=failed\nOPENLY_ERROR=copy_to_application_staging_failed\n'
  rm -rf "$TEMP_APP"
  exit 6
}
rm -rf "$INSTALL_APP"
mv "$TEMP_APP" "$INSTALL_APP"
printf 'OPENLY_APP_REPLACED=true\n'

if [ -d "$BATCH_RECEIVER/Contents" ]; then
  atomic_receiver="$BATCH_RECEIVER/Contents/MacOS/.Openly-$$"
  cp "$INSTALL_APP/Contents/Helpers/Openly Receiver.app/Contents/MacOS/Openly" "$atomic_receiver"
  mv "$atomic_receiver" "$BATCH_RECEIVER/Contents/MacOS/Openly"
  if [ -d "$INSTALL_APP/Contents/Helpers/Openly Receiver.app/Contents/Resources" ]; then
    ditto "$INSTALL_APP/Contents/Helpers/Openly Receiver.app/Contents/Resources" "$BATCH_RECEIVER/Contents/Resources"
  fi
  codesign --force --deep --sign - "$BATCH_RECEIVER" >/dev/null 2>&1 || {
    printf 'OPENLY_INSTALL_STATUS=failed\nOPENLY_ERROR=batch_receiver_resign_failed\n'
    exit 8
  }
  printf 'OPENLY_BATCH_RECEIVER_UPDATED=true\n'
else
  printf 'OPENLY_BATCH_RECEIVER_UPDATED=false\n'
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL_APP/Contents/Info.plist" 2>/dev/null || true)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALL_APP/Contents/Info.plist" 2>/dev/null || true)"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALL_APP/Contents/Info.plist" 2>/dev/null || true)"
printf 'OPENLY_INSTALLED_BUNDLE_ID=%s\n' "$bundle_id"
printf 'OPENLY_INSTALLED_VERSION=%s\n' "$version"
printf 'OPENLY_INSTALLED_BUILD=%s\n' "$build"

if [ "$NO_LAUNCH" -eq 1 ]; then
  printf 'OPENLY_LAUNCH_ACTION=skipped\nOPENLY_PROCESS_STATUS=not_started\nOPENLY_INSTALL_STATUS=ok\n'
  exit 0
fi

printf 'OPENLY_LAUNCH_ACTION=start\n'
open "$INSTALL_APP"
sleep 1
if pgrep -f "$INSTALL_APP/Contents" >/dev/null 2>&1; then
  printf 'OPENLY_PROCESS_STATUS=running\nOPENLY_INSTALL_STATUS=ok\n'
else
  printf 'OPENLY_PROCESS_STATUS=missing\nOPENLY_INSTALL_STATUS=failed\nOPENLY_ERROR=launch_process_not_found\n'
  exit 7
fi
