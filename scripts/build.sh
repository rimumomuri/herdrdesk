#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
node scripts/bundle-web.mjs
swift build -c release --product HerdrDesk
BIN="$(swift build -c release --show-bin-path)/HerdrDesk"
APP="build/HerdrDesk.app"
if [[ "${HERDRDESK_LEGACY_PROFILE:-}" == "1" ]]; then
  : "${HERDRDESK_BUNDLE_ID:?A legacy build requires the installed bundle identifier}"
  APP="build/HerdrDesk-Personal.app"
fi
STAGE="$(mktemp -d "$PWD/.build/app-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources/web/vendor" "$STAGE/Contents/Resources/web/icons" "$STAGE/Contents/Resources/cli"
cp "$BIN" "$STAGE/Contents/MacOS/HerdrDesk"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
if [[ "${HERDRDESK_LEGACY_PROFILE:-}" == "1" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $HERDRDESK_BUNDLE_ID" "$STAGE/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :HerdrDeskLegacyProfile bool true" "$STAGE/Contents/Info.plist"
  if [[ -n "${HERDRDESK_LEGACY_TEAMS:-}" ]]; then
    cp "$HERDRDESK_LEGACY_TEAMS" "$STAGE/Contents/Resources/legacy-teams.json"
  fi
  if [[ -n "${HERDRDESK_LEGACY_ICON:-}" ]]; then
    cp "$HERDRDESK_LEGACY_ICON" "$STAGE/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$STAGE/Contents/Info.plist"
  fi
fi
cp cli/herdr-reply "$STAGE/Contents/Resources/cli/herdr-team-message"
cp cli/herdr-reply "$STAGE/Contents/Resources/cli/herdr-progress"
cp cli/herdr-lineage "$STAGE/Contents/Resources/cli/herdr-lineage"
cp Resources/web/{index.html,app.css,bundle.js,companion.html,companion.css,companion-bundle.js} "$STAGE/Contents/Resources/web/"
cp Resources/web/icons/sheep-minimal-v5.png "$STAGE/Contents/Resources/web/icons/"
cp Resources/web/vendor/{xterm.js,xterm.css,xterm-LICENSE} "$STAGE/Contents/Resources/web/vendor/"
cp -R Resources/web/vendor/chat-icons "$STAGE/Contents/Resources/web/vendor/"
if [[ -n "${HERDRDESK_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --sign "$HERDRDESK_SIGN_IDENTITY" --timestamp "$STAGE"
else
  codesign --force --sign - --timestamp=none "$STAGE"
fi
codesign --verify --strict --verbose=1 "$STAGE"
mkdir -p build
rm -rf "$APP"
mv "$STAGE" "$APP"
echo "Built: $PWD/$APP"
