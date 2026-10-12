#!/bin/zsh
# Builds the app and zips it for a GitHub release.
#   VERSION=1.0.0 scripts/package-release.sh   → build/WindFreeBar-1.0.0.zip
set -euo pipefail
cd "${0:A:h}/.."
VERSION=${VERSION:-1.0.0}
VERSION=$VERSION scripts/build-app.sh
codesign --verify --strict "build/WindFree Bar.app"
ZIP="build/WindFreeBar-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/WindFree Bar.app" "$ZIP"
shasum -a 256 "$ZIP"
