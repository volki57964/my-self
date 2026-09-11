#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
OUT="$ROOT/netcheck/output"
mkdir -p "$OUT"
exec > >(tee -a "$OUT/build.log") 2>&1
PHASE=prepare
trap 'code=$?; if [ "$code" -ne 0 ]; then python3 "$ROOT/netcheck/ci_status.py" failed "$PHASE" || true; fi' EXIT
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
SM="$SDK/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SM" ]; then echo 'Android SDK manager not installed on this runner'; exit 1; fi
PHASE=sdk
python3 "$ROOT/netcheck/ci_status.py" running "$PHASE"
yes | "$SM" --licenses >/dev/null 2>&1 || true
"$SM" --install 'platform-tools' 'platforms;android-37' 'build-tools;37.0.0' 'ndk;28.2.13676358' 'cmake;3.22.1'
PHASE=clone
WORK="${RUNNER_TEMP:-/tmp}/netcheck-build"
mkdir -p "$WORK"
SRC="$WORK/netcheck-source"
if [ -e "$SRC" ]; then echo 'Isolated source path already exists'; exit 1; fi
git clone --filter=blob:none --no-checkout https://github.com/emanuele-f/PCAPdroid.git "$SRC"
git -C "$SRC" checkout dbfd5e04f560adf02f88c8fd0a8d3588e39fa71f
git -C "$SRC" submodule update --init --recursive --depth 1 submodules/nDPI submodules/zdtun submodules/libpcap submodules/MaxMind-DB-Reader-java submodules/zstd
python3 "$ROOT/netcheck/prepare.py" "$SRC"
python3 "$ROOT/netcheck/finish_prepare.py" "$SRC"
printf 'sdk.dir=%s\n' "$SDK" > "$SRC/local.properties"
chmod +x "$SRC/gradlew"
PHASE=gradle
python3 "$ROOT/netcheck/ci_status.py" running "$PHASE"
(cd "$SRC" && ./gradlew --no-daemon --console=plain --stacktrace :app:assembleWithoutUsharkDebug :app:assembleWithoutUsharkDebugAndroidTest)
PHASE=verify
APK="$(find "$SRC/app/build/outputs/apk" -type f -name '*.apk' ! -name '*androidTest*' ! -path '*/androidTest/*' | head -n 1)"
TEST="$(find "$SRC/app/build/outputs/apk/androidTest" -type f -name '*.apk' | head -n 1)"
test -s "$APK"
test -s "$TEST"
cp "$APK" "$OUT/NetCheck.apk"
cp "$TEST" "$OUT/NetCheck-tests.apk"
"$SDK/build-tools/37.0.0/apksigner" verify --verbose --print-certs "$OUT/NetCheck.apk" | tee "$OUT/verification.txt"
"$SDK/build-tools/37.0.0/aapt" dump badging "$OUT/NetCheck.apk" > "$OUT/apk-badging.txt"
PHASE=source_archive
mkdir -p "$SRC/netcheck-build-recipes"
cp -r "$ROOT/netcheck/overlay" "$SRC/netcheck-build-recipes/"
cp "$ROOT/netcheck/"*.py "$ROOT/netcheck/"*.sh "$ROOT/netcheck/"*.java "$ROOT/netcheck/README.md" "$SRC/netcheck-build-recipes/"
cp "$ROOT/.github/workflows/netcheck-apk.yml" "$SRC/netcheck-build-recipes/"
printf '%s\n' 'PCAPdroid upstream: https://github.com/emanuele-f/PCAPdroid' 'Pinned commit: dbfd5e04f560adf02f88c8fd0a8d3588e39fa71f' "NetCheck recipes commit: ${GITHUB_SHA:-local}" > "$SRC/NETCHECK_SOURCE_ORIGIN.txt"
tar --exclude=.git --exclude=.gradle --exclude=.cxx --exclude=build --exclude=local.properties -czf "$OUT/NetCheck-source.tar.gz" -C "$WORK" netcheck-source
(cd "$OUT" && sha256sum NetCheck.apk NetCheck-source.tar.gz > SHA256SUMS.txt)
python3 "$ROOT/netcheck/ci_status.py" built awaiting_emulator
printf '%s\n' 'Actual signed APK compiled and verified. Awaiting emulator smoke.'
