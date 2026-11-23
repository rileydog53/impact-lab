#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build --disable-sandbox -c release --product ImpactLab
binary="$(swift build --disable-sandbox -c release --show-bin-path)/ImpactLab"
bundle=".build/Impact Lab.app"
mkdir -p "$bundle/Contents/MacOS"
cp "$binary" "$bundle/Contents/MacOS/ImpactLab"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ImpactLab</string>
<key>CFBundleIdentifier</key><string>local.shopping.impactlab</string>
<key>CFBundleName</key><string>Impact Lab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.9</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$bundle"
open -n "$bundle" --args "$@"
