#!/bin/zsh
# Builds the app and packages it as a disk image for a GitHub release.
#   VERSION=1.0.0 scripts/package-release.sh   → build/WindFreeBar-1.0.0.dmg
set -euo pipefail
cd "${0:A:h}/.."
VERSION=${VERSION:-1.0.0}
VERSION=$VERSION scripts/build-app.sh
codesign --verify --strict "build/WindFree Bar.app"

# dmgbuild lays out the Finder window (background, icon positions, volume icon) headlessly.
[[ -x build/venv/bin/dmgbuild ]] || { python3 -m venv build/venv && build/venv/bin/pip install --quiet dmgbuild; }
DMG="build/WindFreeBar-$VERSION.dmg"
rm -f "$DMG"
build/venv/bin/dmgbuild -s scripts/dmg/settings.py \
    -D app="build/WindFree Bar.app" -D icon=build/AppIcon.icns -D background=scripts/dmg/background.png \
    "WindFree Bar" "$DMG"
hdiutil verify "$DMG" >/dev/null
shasum -a 256 "$DMG"
