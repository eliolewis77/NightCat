#!/bin/bash
# NightCat release pipeline:
#   archive → Developer ID export → notarize → staple → DMG → EdDSA sign → appcast item
#
# =====================================================================
# ONE-TIME SETUP (do these once, in order)
# =====================================================================
#
# 1. Sparkle EdDSA keypair (signs every update; the private key must
#    never leave your machine/keychain):
#      xcodebuild -resolvePackageDependencies -scheme NightCat \
#        -derivedDataPath build/DerivedData
#      build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
#    → prints the base64 PUBLIC key. Put it in project.yml's
#      `SUPublicEDKey` (replacing the placeholder). The private key is
#      stored in your login keychain — back it up:
#      .../bin/generate_keys -x private-key-backup.pem
#
# 2. Notarytool keychain profile (notarizes the DMG):
#      xcrun notarytool store-credentials nightcat-notary \
#        --apple-id "you@example.com" --team-id UAT3Y8UXCQ --password <app-specific-pw>
#
# 3. Feed hosting (appcast.xml + DMG files must be publicly reachable).
#    Default shape: GitHub Releases for the DMGs, GitHub Pages for
#    appcast.xml. Set FEED_BASE below to the Pages URL and put
#    appcast.xml into the repo's /docs (Pages serves it).
#
# 4. Fill in `SUFeedURL` in project.yml with the same Pages URL.
#
# After setup, every release is:  bump MARKETING_VERSION in project.yml,
#   ./scripts/release.sh
# then push the DMG to GitHub Releases and appcast.xml to Pages.
#
# PUBLISH=0 does everything locally but skips nothing (this script does
# not upload by itself; it prints what to upload).
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="NightCat"
APP_NAME="NightCat"
TEAM="UAT3Y8UXCQ"
NOTARY_PROFILE="${NOTARY_PROFILE:-nightcat-notary}"
FEED_BASE="${FEED_BASE:-https://eliolewis77.github.io/NightCat}"

BUILD="build/release"
ARCHIVE="$BUILD/$APP_NAME.xcarchive"
EXPORT="$BUILD/export"
SIGN_TOOL="$(ls build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update 2>/dev/null || true)"
[ -n "$SIGN_TOOL" ] || { echo "error: sign_update not found — run: xcodebuild -resolvePackageDependencies -scheme NightCat -derivedPath build/DerivedData"; exit 1; }

# Version from project.yml (single source of truth)
VERSION=$(grep -E 'MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"([0-9.]+)".*/\1/')
BUILD_NUM=$(grep -E 'CURRENT_PROJECT_VERSION' project.yml | head -1 | sed -E 's/.*"([0-9]+)".*/\1/')
DMG="$BUILD/$APP_NAME-$VERSION.dmg"

echo "==> Release $APP_NAME $VERSION (build $BUILD_NUM)"

# 1. Archive (Release config, signed for Developer ID via automatic signing)
echo "==> Archiving"
xcodebuild archive -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" -derivedDataPath build/DerivedData \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$TEAM"

# 2. Export the .app with a Developer ID application certificate
echo "==> Exporting"
cat > "$BUILD/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD/ExportOptions.plist" -exportPath "$EXPORT"

APP="$EXPORT/$APP_NAME.app"

# 3. Notarize + staple
echo "==> Notarizing (this talks to Apple; takes a minute or two)"
ditto -c -k --keepParent "$APP" "$BUILD/app.zip"
xcrun notarytool submit "$BUILD/app.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl -a -t exec -vv "$APP"

# 4. DMG
echo "==> Packing DMG"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$APP" -ov -format UDZO "$DMG"

# 5. Sign the DMG with the Sparkle EdDSA key
echo "==> Signing"
SIGN_OUTPUT=$("$SIGN_TOOL" "$DMG")
echo "    $SIGN_OUTPUT"
SIG=$(echo "$SIGN_OUTPUT" | sed -E 's/.*sparkle:edSignature="([^"]*)".*/\1/')
LENGTH=$(stat -f %z "$DMG")

# 6. Emit the appcast item (and a whole appcast if none exists yet)
echo "==> Appcast item"
DATE=$(date -u "+%a, %d %b %Y %H:%M:%S %z")
ITEM="    <item>
      <title>Version $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:version>$BUILD_NUM</sparkle:version>
      <enclosure url=\"$FEED_BASE/$(basename "$DMG")\"
                 sparkle:edSignature=\"$SIG\"
                 length=\"$LENGTH\"
                 type=\"application/octet-stream\" />
    </item>"

if [ -f docs/appcast.xml ]; then
  python3 - "$ITEM" docs/appcast.xml <<'PY'
import sys
item, path = sys.argv[1], sys.argv[2]
s = open(path).read()
marker = "</channel>"
assert marker in s, "appcast.xml missing </channel>"
s = s.replace(marker, item + "\n  " + marker)
open(path, "w").write(s)
PY
  echo "    appended item to docs/appcast.xml"
else
  mkdir -p docs
  cat > docs/appcast.xml <<EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>NightCat</title>
    <link>$FEED_BASE/appcast.xml</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
$ITEM
  </channel>
</rss>
EOF
  echo "    created docs/appcast.xml with the first item"
fi

echo
echo "==> Done. To publish:"
echo "    1. Upload $(basename "$DMG") to a GitHub Release tagged v$VERSION"
echo "    2. Commit + push docs/appcast.xml (GitHub Pages serves /docs)"
echo "    App already installed with SUFeedURL set will pick it up within an hour."
