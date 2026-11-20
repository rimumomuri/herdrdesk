#!/bin/sh
# Isolated local unit + generic Simulator ad-hoc build; never boots a Simulator.
set -u
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=/private/tmp/herdrdesk-000008/validation
mkdir -p "$TEST_ROOT" "$IOS_ROOT/evidence"
export CLANG_MODULE_CACHE_PATH="$TEST_ROOT/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TEST_ROOT/module-cache"
cd "$IOS_ROOT" || exit 1
xcodegen generate --spec "$IOS_ROOT/project.yml" --project "$IOS_ROOT" > "$IOS_ROOT/evidence/xcodegen.log" 2>&1
GEN_STATUS=$?
python3 "$IOS_ROOT/scripts/pin-source.py"
swift test --package-path "$IOS_ROOT" --scratch-path "$TEST_ROOT/swift-build" --cache-path "$TEST_ROOT/swift-cache" > "$IOS_ROOT/evidence/unit-final.log" 2>&1
UNIT_STATUS=$?
if [ "$GEN_STATUS" -eq 0 ]; then
    xcodebuild -project "$IOS_ROOT/HerdrMobile.xcodeproj" -scheme HerdrMobile -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$TEST_ROOT/DerivedData" build > "$IOS_ROOT/evidence/build-final.log" 2>&1
    BUILD_STATUS=$?
else
    BUILD_STATUS=125
fi
python3 - "$GEN_STATUS" "$UNIT_STATUS" "$BUILD_STATUS" <<'PY'
import hashlib, json, sys
from datetime import datetime, timezone
from pathlib import Path
Path('evidence/verification.json').write_text(json.dumps({
 'recordedAt': datetime.now(timezone.utc).isoformat(),
 'sourceManifestSHA256': hashlib.sha256(Path('evidence/source-manifest.json').read_bytes()).hexdigest(),
 'xcodegenExit': int(sys.argv[1]), 'swiftUnitExit': int(sys.argv[2]),
 'genericSimulatorBuildExit': int(sys.argv[3]),
 'simulatorSigning': 'ad-hoc via iphonesimulator SDK conditions; iphoneos signing remains disabled',
 'simulatorBoot': 'NOT RUN - lead owned', 'nativeUI': 'NOT RUN - lead owned',
 'liveNetwork': 'NOT RUN', 'keychainRuntime': 'NOT RUN', 'realDevice': 'NOT RUN',
 'note': 'Nonzero codes require log inspection; environment errors are BLOCKED, not product test failures.'
}, ensure_ascii=False, indent=2)+'\n')
PY
cat "$IOS_ROOT/evidence/verification.json"
[ "$GEN_STATUS" -eq 0 ] && [ "$UNIT_STATUS" -eq 0 ] && [ "$BUILD_STATUS" -eq 0 ]
