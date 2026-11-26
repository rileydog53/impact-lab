#!/bin/bash
# Opens Impact Lab. By default it opens the shared test build as it is, with no rebuild, so it can never
# replace a newer build with older code from whatever branch this folder happens to be on.
#   ./launch.command            open the shared test build
#   ./launch.command --rebuild  rebuild first, only when this folder is on an up-to-date main
# Any other arguments are passed to the app.
set -euo pipefail
cd "$(dirname "$0")"
bundle=".build/Impact Lab.app"

if [ "${1:-}" = "--rebuild" ]; then
  shift
  git fetch -q origin main 2>/dev/null || true
  if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main 2>/dev/null)" ]; then
    echo "Not rebuilding: this folder is not on the latest main, so a rebuild would make an older app."
    echo "Opening the shared test build instead."
  else
    scripts/build.sh build -c release --product ImpactLab
    mkdir -p "$bundle/Contents/MacOS"
    cp ".build/release/ImpactLab" "$bundle/Contents/MacOS/ImpactLab"
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
  fi
fi

if [ ! -d "$bundle" ]; then
  echo "There is no test build yet. Ask Claude to build one, or run ./launch.command --rebuild while on main."
  exit 1
fi
open -n "$bundle" --args "$@"
