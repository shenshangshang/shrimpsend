#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
action="${1:-run}"
if [ "$#" -gt 0 ]; then shift; fi
flutter_bin="${FLUTTER_BIN:-$(command -v flutter || true)}"
if [ -z "$flutter_bin" ]; then echo '请设置 FLUTTER_BIN 指向 Flutter SDK。' >&2; exit 1; fi
config="${FLUTTER_LOCAL_CONFIG:-$ROOT/.local/flutter.json}"
if [ ! -f "$config" ]; then
  mkdir -p "$(dirname "$config")"
  cp "$ROOT/app/config/local.example.json" "$config"
fi
cd "$ROOT/app"
for name in env openpanel_env feedmatter_env; do
  if [ ! -f "lib/config/$name.secrets.dart" ]; then
    cp "lib/config/$name.secrets.example.dart" "lib/config/$name.secrets.dart"
  fi
done
case "$action" in
  run) exec "$flutter_bin" run -d macos --dart-define-from-file="$config" "$@" ;;
  android)
    adb_bin="${ADB_BIN:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb}"
    device="${FLUTTER_DEVICE:-$("$adb_bin" devices | awk 'NR > 1 && $2 == "device" {print $1; exit}')}"
    if [ -z "$device" ]; then echo '未找到已连接且允许调试的安卓手机。' >&2; exit 1; fi
    # USB forwards let the phone use the same localhost configuration as Mac.
    # File transfers and discovery still use each device's real LAN address.
    for port in 9000 5200 3000; do "$adb_bin" -s "$device" reverse "tcp:$port" "tcp:$port"; done
    # Install explicitly first: Flutter's normal install fallback may uninstall
    # a differently signed package. adb install -r fails without deleting data.
    case "$("$adb_bin" -s "$device" shell getprop ro.product.cpu.abi | tr -d '\r')" in
      arm64-v8a) target_platform=android-arm64 ;;
      armeabi-v7a) target_platform=android-arm ;;
      x86_64) target_platform=android-x64 ;;
      *) echo '不支持的安卓设备架构。' >&2; exit 1 ;;
    esac
    "$flutter_bin" build apk --debug --flavor direct --target-platform="$target_platform" --dart-define-from-file="$config"
    apk="$ROOT/app/build/app/outputs/flutter-apk/app-direct-debug.apk"
    "$adb_bin" -s "$device" install -r "$apk"
    exec "$flutter_bin" run -d "$device" --flavor direct --use-application-binary="$apk" --dart-define-from-file="$config" "$@"
    ;;
  build) exec "$flutter_bin" build macos --debug --dart-define-from-file="$config" "$@" ;;
  test) exec "$flutter_bin" test "$@" ;;
  analyze) exec "$flutter_bin" analyze "$@" ;;
  *) echo '用法：scripts/flutter-local.sh [run|android|build|test|analyze] [Flutter 参数]' >&2; exit 2 ;;
esac
