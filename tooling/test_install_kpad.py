"""Exercise the installer with fake SDK commands; never connect to a device."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class InstallerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ngsl_installer_")
        self.addCleanup(self.temp.cleanup)
        # Include spaces to cover invocation from any directory and quoted APKs.
        self.root = Path(self.temp.name) / "NGSL project"
        self.bin = self.root / "fake-sdk-bin"
        self.bin.mkdir(parents=True)
        (self.root / "tooling").mkdir()
        (self.root / "app").mkdir()
        source = Path(__file__).resolve().parent
        for name in ["install_kpad.sh", "verify_and_build.sh"]:
            shutil.copy2(source / name, self.root / "tooling" / name)
        self.log = self.root / "commands.log"
        self.apk = self.root / "app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "TEST_LOG": str(self.log),
            "TEST_APK": str(self.apk),
            "TEST_DEVICES": "List of devices attached\nkpad123 device usb:1 model:KPad\n",
            "TEST_PACKAGE": "com.jonlimx.ngsl_go",
        }
        self.command("flutter", r'''
printf 'flutter %s\n' "$*" >> "$TEST_LOG"
if [[ -n "${FAIL_STAGE:-}" && "$*" == "$FAIL_STAGE" ]]; then exit 1; fi
if [[ "$1 $2" == 'build apk' && "${CREATE_APK:-1}" == 1 ]]; then
  mkdir -p "$(dirname "$TEST_APK")"
  printf 'built apk' > "$TEST_APK"
fi
''')
        self.command("dart", 'printf "dart %s\\n" "$*" >> "$TEST_LOG"\n')
        self.command("python3", 'printf "python3 %s\\n" "$*" >> "$TEST_LOG"\n[[ "${FAIL_STAGE:-}" != contentcheck ]]\n')
        self.command("aapt", r'''
printf 'aapt %s\n' "$*" >> "$TEST_LOG"
printf "package: name='%s' versionCode='1'\n" "$TEST_PACKAGE"
''')
        self.command("adb", r'''
printf 'adb %s\n' "$*" >> "$TEST_LOG"
case "$1" in
  start-server) exit 0 ;;
  devices) printf '%s\n' "$TEST_DEVICES"; exit 0 ;;
esac
[[ "$1" == -s ]] || exit 99
shift 2
case "$1" in
  get-state) printf '%s\n' "${TEST_STATE_AFTER:-device}" ;;
  install)
    if [[ "${INSTALL_FAIL:-0}" == 1 ]]; then
      printf 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]\n' >&2
      exit 1
    fi
    printf 'Success\n'
    ;;
  shell)
    case "$2" in
      getprop)
        case "$3" in
          ro.product.model) printf 'KPad\n' ;;
          ro.build.version.sdk) printf '%s\n' "${TEST_API:-35}" ;;
          ro.product.cpu.abilist) printf '%s\n' "${TEST_ABIS:-arm64-v8a,armeabi-v7a}" ;;
        esac
        ;;
      am) printf 'Status: ok\n' ;;
    esac
    ;;
  *) exit 99 ;;
esac
''')

    def command(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body)
        path.chmod(0o755)

    def run_installer(self, *args, **env):
        result = subprocess.run(
            ["bash", str(self.root / "tooling/install_kpad.sh"), *args],
            cwd=self.temp.name,
            env={**self.env, **env},
            text=True,
            capture_output=True,
            timeout=15,
        )
        log = self.log.read_text() if self.log.exists() else ""
        self.assertNotIn(" uninstall ", log)
        self.assertNotIn("pm clear", log)
        self.assertNotIn("flutter run", log)
        self.assertNotIn("install -r -d", log)
        return result, log

    def test_checks_builds_verifies_then_updates_and_opens_exact_package(self):
        result, log = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        commands = [
            "python3 ../tooling/test_word_material.py", "flutter pub get", "flutter analyze", "flutter test",
            "dart run tooling/check_core.dart", "flutter build apk",
            "aapt dump badging", "adb -s kpad123 install -r",
            "adb -s kpad123 shell am start -W -n com.jonlimx.ngsl_go/.MainActivity",
        ]
        positions = [log.index(command) for command in commands]
        self.assertEqual(positions, sorted(positions))
        self.assertIn(str(self.apk), log)

    def test_failed_checks_or_build_never_install_an_old_apk(self):
        self.apk.parent.mkdir(parents=True)
        self.apk.write_text("old apk")
        for stage in ["contentcheck", "test", "build apk --release --split-per-abi --target-platform android-arm64"]:
            with self.subTest(stage=stage):
                self.log.unlink(missing_ok=True)
                result, log = self.run_installer(FAIL_STAGE=stage)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(" install ", log)
                self.assertNotIn("aapt ", log)

    def test_missing_apk_stops_before_install(self):
        result, log = self.run_installer(CREATE_APK="0")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(" install ", log)

    def test_other_application_package_is_rejected(self):
        result, log = self.run_installer(TEST_PACKAGE="com.example.fce_go")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(" install ", log)

    def test_no_device_and_unauthorized_device_stop_before_build(self):
        for device_line in ["", "kpad123 unauthorized usb:1", "kpad123 offline usb:1"]:
            with self.subTest(device=device_line):
                self.log.unlink(missing_ok=True)
                result, log = self.run_installer(TEST_DEVICES=f"List of devices attached\n{device_line}\n")
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("flutter ", log)
                self.assertNotIn(" install ", log)

    def test_multiple_devices_require_a_serial(self):
        devices = "List of devices attached\nkpad123 device usb:1\nphone456 device usb:2\n"
        result, log = self.run_installer(TEST_DEVICES=devices)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("flutter ", log)
        self.assertNotIn(" install ", log)

    def test_explicit_serial_remains_fixed_for_all_device_commands(self):
        devices = "List of devices attached\nphone456 device usb:1\nkpad123 device usb:2\n"
        result, log = self.run_installer("--serial", "kpad123", TEST_DEVICES=devices)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("adb -s kpad123 install -r", log)
        self.assertNotIn("adb -s phone456", log)

    def test_emulator_does_not_displace_the_connected_tablet(self):
        devices = "List of devices attached\nemulator-5554 device\nkpad123 device usb:1\n"
        result, log = self.run_installer(TEST_DEVICES=devices)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("adb -s kpad123 install -r", log)

    def test_incompatible_android_or_cpu_stops_before_build(self):
        for env in [{"TEST_API": "30"}, {"TEST_ABIS": "x86_64,x86"}]:
            with self.subTest(env=env):
                self.log.unlink(missing_ok=True)
                result, log = self.run_installer(**env)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("flutter ", log)
                self.assertNotIn(" install ", log)

    def test_disconnect_during_build_never_installs_to_another_device(self):
        result, log = self.run_installer(TEST_STATE_AFTER="offline")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(" install ", log)

    def test_signature_failure_stops_without_uninstall_or_launch(self):
        result, log = self.run_installer(INSTALL_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(" install -r ", log)
        self.assertNotIn("shell am start", log)


if __name__ == "__main__":
    unittest.main(verbosity=2)
