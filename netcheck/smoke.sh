#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
OUT="$ROOT/netcheck/output"
mkdir -p "$OUT"
exec > >(tee -a "$OUT/smoke.log") 2>&1
TEMP="$(mktemp -d)"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TEMP/key.pem" -out "$TEMP/cert.pem" -days 1 -subj '/CN=netcheck-ci.invalid' -addext 'subjectAltName=IP:10.0.2.2' >/dev/null 2>&1
sudo python3 "$ROOT/netcheck/echo_server.py" "$TEMP/cert.pem" "$TEMP/key.pem" > "$OUT/control-server.log" 2>&1 &
SERVER=$!
trap 'sudo kill "$SERVER" 2>/dev/null || true; rm -rf "$TEMP"' EXIT
for i in $(seq 1 30); do grep -q NETCHECK_LOOPBACK_READY "$OUT/control-server.log" && break; sleep 1; done
if ! grep -q NETCHECK_LOOPBACK_READY "$OUT/control-server.log"; then cat "$OUT/control-server.log"; exit 1; fi
adb wait-for-device
adb install -r "$OUT/NetCheck.apk"
adb install -r "$OUT/NetCheck-tests.apk"
adb shell pm grant org.netcheck.pilot.debug android.permission.POST_NOTIFICATIONS || true
adb shell appops set org.netcheck.pilot.debug ACTIVATE_VPN allow
adb shell am instrument -w org.netcheck.pilot.debug.test/com.emanuelef.remote_capture.netcheck.NetSmoke | tee "$OUT/instrumentation.txt"
if ! grep -q 'NETCHECK_SMOKE_OK' "$OUT/instrumentation.txt"; then adb logcat -d -t 350 > "$OUT/emulator-failure.log"; cat "$OUT/control-server.log"; exit 1; fi
adb shell am start -n org.netcheck.pilot.debug/com.emanuelef.remote_capture.netcheck.NetCheckActivity
sleep 3
adb shell uiautomator dump /sdcard/netcheck-ui.xml >/dev/null
adb pull /sdcard/netcheck-ui.xml "$OUT/netcheck-ui.xml" >/dev/null
adb exec-out screencap -p > "$OUT/NetCheck-emulator.png"
if adb logcat -d -b crash | grep -q 'Process: org.netcheck.pilot.debug'; then adb logcat -d -b crash; exit 1; fi
printf '%s\n' 'Controlled emulator tests passed. Third-party app UI and Russian network conditions require separate physical-device testing.'
