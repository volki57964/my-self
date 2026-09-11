#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
OUT="$ROOT/netcheck/output"
mkdir -p "$OUT"
exec > >(tee -a "$OUT/smoke.log") 2>&1
adb wait-for-device
adb install -r "$OUT/NetCheck.apk"
adb install -r "$OUT/NetCheck-tests.apk"
adb shell pm grant org.netcheck.pilot.debug android.permission.POST_NOTIFICATIONS || true
adb shell appops set org.netcheck.pilot.debug ACTIVATE_VPN allow
adb shell am instrument -w org.netcheck.pilot.debug.test/com.emanuelef.remote_capture.netcheck.NetSmoke | tee "$OUT/instrumentation.txt"
grep -q 'NETCHECK_SMOKE_OK' "$OUT/instrumentation.txt"
adb shell am start -n org.netcheck.pilot.debug/com.emanuelef.remote_capture.netcheck.NetCheckActivity
sleep 3
adb shell uiautomator dump /sdcard/netcheck-ui.xml >/dev/null
adb pull /sdcard/netcheck-ui.xml "$OUT/netcheck-ui.xml" >/dev/null
adb exec-out screencap -p > "$OUT/NetCheck-emulator.png"
if adb logcat -d -b crash | grep -q 'Process: org.netcheck.pilot.debug'; then
  adb logcat -d -b crash
  exit 1
fi
printf '%s\n' 'Emulator smoke passed. Third-party app scenarios require real-device testing.'
