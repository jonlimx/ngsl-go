#!/usr/bin/env bash
# Build and update NGSL Go without uninstalling or clearing any app data.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE='com.jonlimx.ngsl_go'
APK="$ROOT/app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
SERIAL=''

usage() {
  cat <<'EOF'
用法：bash tooling/install_kpad.sh [--serial 设备序列号]

连接 KPad 并开启 USB 调试，在平板上允许此电脑调试后运行。
自动检查、构建 ARM64 APK、保留数据覆盖安装，并打开 NGSL Go。
只连接一台实体设备时无需参数；多台设备时用 --serial 指定目标。
EOF
}

fail() { printf '\n错误：%s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --serial)
      (($# >= 2)) && [[ -n "$2" && "$2" != -* ]] || fail '--serial 后需要设备序列号。'
      [[ -z "$SERIAL" ]] || fail '只能指定一台目标设备。'
      SERIAL="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; fail "无法识别的参数：$1" ;;
  esac
done

command -v flutter >/dev/null 2>&1 || fail '找不到 flutter，请先安装 Flutter 并加入 PATH。'
command -v dart >/dev/null 2>&1 || fail '找不到 dart，请将 Flutter 的 bin 目录加入 PATH。'
command -v python3 >/dev/null 2>&1 || fail '找不到 python3；全量离线词库检查需要 Python 3，请安装后重试。'

sdk_from_project() {
  if [[ -f "$ROOT/app/android/local.properties" ]]; then
    sed -n 's/^sdk\.dir=//p' "$ROOT/app/android/local.properties" | head -n 1
  fi
}

ADB="$(command -v adb || true)"
if [[ -z "$ADB" ]]; then
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$(sdk_from_project)" "$HOME/Library/Android/sdk"; do
    if [[ -n "$sdk" && -x "$sdk/platform-tools/adb" ]]; then
      ADB="$sdk/platform-tools/adb"
      break
    fi
  done
fi
[[ -n "$ADB" ]] || fail '找不到 adb，请在 Android Studio 的 SDK Manager 中安装 Android SDK Platform-Tools。'

printf '\n[1/4] 检查 KPad 连接\n'
"$ADB" start-server || fail 'ADB 服务启动失败，请在本机终端运行此脚本。'
DEVICES="$("$ADB" devices -l)" || fail '无法读取 ADB 设备列表。'
if [[ -z "$SERIAL" ]]; then
  candidates=()
  while read -r device state details; do
    [[ -n "$device" && "$device" != 'List' && "$device" != emulator-* && -n "$state" ]] || continue
    candidates+=("$device")
  done <<< "$DEVICES"
  case "${#candidates[@]}" in
    0) fail '没有找到实体设备。请连接 KPad，开启“开发者选项 → USB 调试”，并在平板上允许此电脑调试。' ;;
    1) SERIAL="${candidates[0]}" ;;
    *)
      printf '%s\n' "$DEVICES" >&2
      fail '检测到多台实体设备。请只连接 KPad，或使用：bash tooling/install_kpad.sh --serial 设备序列号'
      ;;
  esac
fi
[[ "$SERIAL" != emulator-* ]] || fail '此脚本用于实体 KPad，请指定实体设备序列号。'

STATE="$(awk -v serial="$SERIAL" '$1 == serial {print $2; exit}' <<< "$DEVICES")"
case "$STATE" in
  device) ;;
  unauthorized) fail 'KPad 尚未授权。请解锁平板，在“允许 USB 调试”提示中允许此电脑，然后重新运行。' ;;
  offline) fail 'KPad 处于 offline 状态。请重新插拔 USB 线、解锁平板后重试。' ;;
  *) fail "目标设备 $SERIAL 未就绪。请检查连接和 USB 调试授权。" ;;
esac

device_adb() { "$ADB" -s "$SERIAL" "$@"; }
MODEL="$(device_adb shell getprop ro.product.model | tr -d '\r')"
API="$(device_adb shell getprop ro.build.version.sdk | tr -d '\r')"
ABIS="$(device_adb shell getprop ro.product.cpu.abilist | tr -d '\r')"
[[ "$API" =~ ^[0-9]+$ ]] && ((API >= 31)) || fail "NGSL Go 需要 Android 12 或更新版本，当前 SDK：${API}。"
[[ ",$ABIS," == *,arm64-v8a,* ]] || fail "此安装包需要 ARM64，当前设备架构：${ABIS}。"
printf '目标：%s（%s），Android SDK %s\n' "$MODEL" "$SERIAL" "$API"

printf '\n[2/4] 检查代码、运行测试并构建 APK\n'
# A failed build must never fall back to an APK left by an earlier build.
if ! bash "$ROOT/tooling/verify_and_build.sh"; then
  fail '检查或构建失败，已停止；没有安装旧 APK。请解决上方错误后重试。'
fi
[[ -s "$APK" ]] || fail "构建未生成预期 APK，停止安装：$APK"

# Read the compiled package identity, rather than trusting only its filename.
AAPT="$(command -v aapt || true)"
if [[ -z "$AAPT" ]]; then
  for sdk in "$(sdk_from_project)" "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk"; do
    [[ -n "$sdk" ]] || continue
    for candidate in "$sdk"/build-tools/*/aapt; do
      [[ ! -x "$candidate" ]] || AAPT="$candidate"
    done
    [[ -z "$AAPT" ]] || break
  done
fi
[[ -n "$AAPT" ]] || fail '找不到 aapt，无法核对 APK 包名。请在 SDK Manager 中安装 Android SDK Build-Tools。'
BADGING="$("$AAPT" dump badging "$APK")" || fail '无法读取 APK 信息，停止安装。'
BUILT_PACKAGE="$(awk -F "'" '/^package: name=/{print $2; exit}' <<< "$BADGING")"
[[ "$BUILT_PACKAGE" == "$PACKAGE" ]] || fail "APK 包名不符：${BUILT_PACKAGE}；只允许安装 ${PACKAGE}。"

printf '\n[3/4] 保留数据，覆盖安装 NGSL Go\n'
[[ "$(device_adb get-state | tr -d '\r')" == device ]] || fail '构建完成，但原目标设备已断开；请重新连接后再运行。'
if ! device_adb install -r "$APK"; then
  fail '覆盖安装失败。脚本不会卸载应用、清除数据或强制降级；如提示签名不兼容，请使用原签名重新构建。'
fi

printf '\n[4/4] 打开 NGSL Go\n'
if ! device_adb shell am start -W -n "$PACKAGE/.MainActivity"; then
  printf '安装已完成，但未能自动打开。请在 KPad 上手动打开 NGSL Go。\n' >&2
fi
printf '\nNGSL Go 已安装到 %s（%s）。学习数据保留。\n' "$MODEL" "$SERIAL"
