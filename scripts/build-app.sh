#!/bin/zsh
# Builds "WindFree Bar.app" with SwiftPM (no Xcode needed) and ad-hoc signs it.
#   scripts/build-app.sh            → build/WindFree Bar.app
#   scripts/build-app.sh --install  → also copies it to ~/Applications and relaunches it
set -euo pipefail
cd "${0:A:h}/.."
VERSION=${VERSION:-1.0.0}
BUILD=${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}

swift build -c release --arch arm64

APP="build/WindFree Bar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build
cp "$(swift build -c release --arch arm64 --show-bin-path)/WindFreeBar" "$APP/Contents/MacOS/WindFreeBar"
# The icon is generated (scripts/make-icon.swift) on first build.
[[ -f build/AppIcon.icns ]] || swift scripts/make-icon.swift build/AppIcon.icns
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# English and Brazilian Portuguese; macOS picks one from the system's preferred languages.
cp -R Localization/*.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>        <string>com.pedroseibel.WindFreeBar</string>
    <key>CFBundleName</key>              <string>WindFree Bar</string>
    <key>CFBundleDisplayName</key>       <string>WindFree Bar</string>
    <key>CFBundleExecutable</key>        <string>WindFreeBar</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key> <string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>pt-BR</string></array>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>__VERSION__</string>
    <key>CFBundleVersion</key>           <string>__BUILD__</string>
    <key>LSMinimumSystemVersion</key>    <string>26.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>   <string>com.pedroseibel.WindFreeBar.oauth</string>
            <key>CFBundleURLSchemes</key><array><string>windfreebar</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

sed -i '' -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
# Register the windfreebar:// scheme so the OAuth redirect finds this copy.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x WindFreeBar 2>/dev/null || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/"WindFree Bar.app"
    cp -R "$APP" ~/Applications/
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/"WindFree Bar.app"
    open ~/Applications/"WindFree Bar.app"
    echo "Installed to ~/Applications"
fi
