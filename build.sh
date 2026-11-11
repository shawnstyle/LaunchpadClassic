#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/ModuleCache
app="$PWD/build/Launchpad Classic.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
motion_flags=("-swift-version" "5")
if [[ "${LAUNCHPAD_TRACE:-0}" == "1" ]]; then motion_flags+=("-D" "LAUNCHPAD_TRACE"); fi
xcrun swiftc "${motion_flags[@]}" -O -target arm64-apple-macosx14.0 \
  -module-cache-path "$PWD/.build/ModuleCache" \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement \
  Sources/LauncherCore.swift Sources/InteractionPhysics.swift Sources/LauncherModel.swift Sources/LauncherInteraction.swift Sources/NativeInteraction.swift Sources/LauncherView.swift Sources/LauncherApp.swift \
  -o "$app/Contents/MacOS/LaunchpadClassic"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LaunchpadClassic</string>
<key>CFBundleIdentifier</key><string>org.launchpadclassic.app</string>
<key>CFBundleName</key><string>Launchpad Classic</string>
<key>CFBundleDisplayName</key><string>Launchpad Classic</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
<key>CFBundleAllowMixedLocalizations</key><true/>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.2</string>
<key>CFBundleVersion</key><string>7</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHumanReadableCopyright</key><string>Launchpad Classic contributors.</string>
</dict></plist>
PLIST
"$app/Contents/MacOS/LaunchpadClassic" --generate-icon "$PWD/.build/icon.png"
mkdir -p .build/AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" .build/icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" .build/icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
printf '已生成：%s\n' "$app"
