#!/usr/bin/env bash
# Rise Log pinned simulator CI (issue #4).
#
# Phases: helper tests -> exact toolchain pin -> simulator selection/boot
# -> Linux-style RiseKit tests (on Apple toolchain) -> Release app build
# with iPhone-only post-build assertion -> XCUITest journey.
#
# Evidence discipline: every phase writes provenance under
# build/ci-artifacts; a nonzero exit in any phase fails the run.
# Simulator results are SIMULATOR results — never device results.
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

expected_sha="${1:-}"
if [[ -z "$expected_sha" ]]; then
  echo "usage: Scripts/ci.sh <expected-commit-sha>" >&2
  exit 2
fi

artifact_root="${RISELOG_ARTIFACT_DIR:-$repo_root/build/ci-artifacts}"
mkdir -p "$artifact_root" "$repo_root/build"
artifact_dir="$(mktemp -d "$artifact_root/run.XXXXXX")"
derived_data="$(mktemp -d "$repo_root/build/DerivedData.XXXXXX")"
phase="initialization"

write_provenance() {
  local result=$?
  {
    echo "expected_sha=$expected_sha"
    echo "actual_sha=$(git rev-parse HEAD 2>/dev/null || echo unavailable)"
    echo "runner_os=${RUNNER_OS:-unknown}"
    echo "runner_arch=${RUNNER_ARCH:-unknown}"
    echo "developer_dir=${DEVELOPER_DIR:-unselected}"
    echo "simulator_udid=${simulator_udid:-unselected}"
    echo "phase=$phase"
    echo "exit_status=$result"
  } > "$artifact_dir/provenance.txt"
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    python3 Scripts/boot_simulator.py capture \
      --timeout 15 --output "$artifact_dir/xcode-version.txt" \
      -- xcodebuild -version || true
    python3 Scripts/boot_simulator.py capture \
      --timeout 15 --output "$artifact_dir/iphoneos-sdk-version.txt" \
      -- xcrun --sdk iphoneos --show-sdk-version || true
    python3 Scripts/boot_simulator.py capture \
      --timeout 20 --output "$artifact_dir/simulator-devices-exit.log" \
      -- xcrun simctl list devices available --json || true
  fi
}
trap write_provenance EXIT

actual_sha="$(git rev-parse HEAD)"
if [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "Checked out SHA $actual_sha does not equal requested SHA $expected_sha" >&2
  exit 1
fi

phase="helper_tests"
python3 -m unittest discover -s Scripts/tests -v 2>&1 | tee "$artifact_dir/helper-tests.log"

phase="toolchain_selection"
# A missing exact pin (Xcode 26.0.1 / 17A400 / iOS SDK 26.0) is an
# ENVIRONMENT ACCEPTANCE BLOCKER — never a silent substitute.
python3 Scripts/select_xcode.py \
  --toolchain toolchain.json \
  > "$artifact_dir/developer-dir.txt" \
  2> >(tee "$artifact_dir/toolchain-selection.log" >&2)
export DEVELOPER_DIR
DEVELOPER_DIR="$(<"$artifact_dir/developer-dir.txt")"
echo "Exact pin found: $DEVELOPER_DIR"
xcodebuild -version

phase="zero_network_gate"
bash scripts/check_zero_network.sh

phase="iphone_only_guard"
echo "--- asserting TARGETED_DEVICE_FAMILY = 1 in RiseLog.xcodeproj ---"
grep -q "TARGETED_DEVICE_FAMILY = 1;" RiseLog.xcodeproj/project.pbxproj \
  || { echo "::error::TARGETED_DEVICE_FAMILY = 1 missing from project"; exit 1; }
if grep -q "TARGETED_DEVICE_FAMILY = 1,2;" RiseLog.xcodeproj/project.pbxproj; then
  echo "::error::iPad family (1,2) found — iPhone-only directive violated"
  exit 1
fi
bad=$(grep -E "TARGETED_DEVICE_FAMILY = [^1;]" RiseLog.xcodeproj/project.pbxproj || true)
if [ -n "$bad" ]; then
  echo "::error::Non-iPhone TARGETED_DEVICE_FAMILY values found:"
  echo "$bad"
  exit 1
fi
count=$(grep -c "TARGETED_DEVICE_FAMILY = 1;" RiseLog.xcodeproj/project.pbxproj || echo 0)
echo "TARGETED_DEVICE_FAMILY = 1 asserted in $count places"

phase="simulator_selection"
sdk_version="$(python3 -c 'import json; print(json.load(open("toolchain.json", encoding="utf-8"))["iphoneos_sdk"])')"
simulator_udid="$(python3 Scripts/select_simulator.py \
  --sdk "$sdk_version" \
  --devices-json-out "$artifact_dir/simulator-devices.json")"
echo "platform=iOS Simulator,id=$simulator_udid" > "$artifact_dir/destination.txt"

phase="simulator_boot"
python3 Scripts/boot_simulator.py boot \
  --udid "$simulator_udid" \
  --devices-json "$artifact_dir/simulator-devices.json" \
  --log "$artifact_dir/simulator-boot.log" \
  --boot-timeout 120 \
  --bootstatus-timeout 180 \
  2> >(tee -a "$artifact_dir/simulator-boot.log" >&2)

phase="package_tests"
xcrun swift test \
  --package-path Packages/RiseKit \
  2>&1 | tee "$artifact_dir/package-tests.log"

phase="app_build"
xcodebuild build \
  -project RiseLog.xcodeproj \
  -scheme RiseLog \
  -configuration Release \
  -destination "platform=iOS Simulator,id=$simulator_udid" \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$artifact_dir/build.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee "$artifact_dir/xcodebuild-build.log"

phase="iphone_only_postbuild"
app_plist="$derived_data/Build/Products/Release-iphonesimulator/RiseLog.app/Info.plist"
if [[ ! -f "$app_plist" ]]; then
  echo "Built app Info.plist missing at $app_plist" >&2
  exit 1
fi
plutil -convert json -o "$artifact_dir/app-info.json" "$app_plist"
python3 - "$artifact_dir/app-info.json" <<'PYTHON'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    info = json.load(handle)
family = info.get("UIDeviceFamily")
if family != [1]:
    raise SystemExit(f"Built app UIDeviceFamily must be [1], observed {family!r}")
print("Built app UIDeviceFamily == [1]: PASS")
bundle_id = info.get("CFBundleIdentifier")
if bundle_id != "com.infinityball.riselog":
    raise SystemExit(f"Built app bundle id must be com.infinityball.riselog, observed {bundle_id!r}")
print(f"Bundle id {bundle_id}: PASS")
PYTHON
app_bundle="$(dirname "$app_plist")"
if [[ ! -f "$app_bundle/PrivacyInfo.xcprivacy" ]]; then
  echo "::error::PrivacyInfo.xcprivacy not embedded in app bundle"
  exit 1
fi
echo "Privacy manifest embedded: PASS"

phase="ui_tests"
xcodebuild test \
  -project RiseLog.xcodeproj \
  -scheme RiseLog \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_udid" \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$artifact_dir/tests.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee "$artifact_dir/xcodebuild-test.log"

phase="complete"
echo "All phases complete; artifacts under $artifact_dir"
