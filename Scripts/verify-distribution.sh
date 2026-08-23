#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="$project_dir/dist/VibeIsland.app"
executable="$app_dir/Contents/MacOS/VibeIsland"
icon="$app_dir/Contents/Resources/VibeIsland.icns"
widget_dir="$app_dir/Contents/PlugIns/VibeIslandWidget.appex"
widget_executable="$widget_dir/Contents/MacOS/VibeIslandWidget"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")"
archive_path="$project_dir/dist/VibeIsland-$version-macOS-arm64.zip"
checksum_path="$archive_path.sha256"

if [[ ! -d "$app_dir" || ! -f "$executable" || ! -f "$icon" || ! -f "$widget_executable" ]]; then
    echo "Distribution app is missing. Run Scripts/build-app.sh first." >&2
    exit 1
fi

plutil -lint "$app_dir/Contents/Info.plist"
plutil -lint "$widget_dir/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app_dir"
codesign --verify --strict --verbose=2 "$widget_dir"

icon_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$app_dir/Contents/Info.plist")"
if [[ "$icon_name" != "VibeIsland.icns" ]]; then
    echo "Invalid app icon reference: $icon_name" >&2
    exit 1
fi

widget_extension_point="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$widget_dir/Contents/Info.plist")"
if [[ "$widget_extension_point" != "com.apple.widgetkit-extension" ]]; then
    echo "Invalid WidgetKit extension point: $widget_extension_point" >&2
    exit 1
fi

widget_entitlements="$(codesign -d --entitlements :- "$widget_dir" 2>/dev/null)"
if [[ "$widget_entitlements" != *"com.apple.security.app-sandbox"* || "$widget_entitlements" != *"com.apple.security.network.client"* ]]; then
    echo "Widget sandbox or local network entitlement is missing." >&2
    exit 1
fi

architectures="$(lipo -archs "$executable")"
widget_architectures="$(lipo -archs "$widget_executable")"
if [[ "$architectures" != "arm64" || "$widget_architectures" != "arm64" ]]; then
    echo "Expected arm64-only binaries, found app=$architectures widget=$widget_architectures" >&2
    exit 1
fi

unexpected_files="$(find "$app_dir" -type f \
    \! -path "$executable" \
    \! -path "$app_dir/Contents/Info.plist" \
    \! -path "$icon" \
    \! -path "$app_dir/Contents/_CodeSignature/CodeResources" \
    \! -path "$widget_executable" \
    \! -path "$widget_dir/Contents/Info.plist" \
    \! -path "$widget_dir/Contents/_CodeSignature/CodeResources" \
    -print)"
if [[ -n "$unexpected_files" ]]; then
    echo "Unexpected files in app bundle:" >&2
    echo "$unexpected_files" >&2
    exit 1
fi

if rg -a -q '/Users/|BEGIN [A-Z ]*PRIVATE KEY|sk-[A-Za-z0-9]{16,}' "$executable" "$widget_executable"; then
    echo "Potential personal path or secret found in distribution binary." >&2
    exit 1
fi

if otool -L "$executable" "$widget_executable" | rg -q '^[[:space:]]+/Users/'; then
    echo "Local build dependency found in distribution binary." >&2
    exit 1
fi

if [[ -f "$archive_path" ]]; then
    if unzip -Z1 "$archive_path" | rg -q '(^|/)(__MACOSX|\._)'; then
        echo "Finder metadata found in distribution archive." >&2
        exit 1
    fi
    if [[ ! -f "$checksum_path" ]]; then
        echo "Distribution checksum is missing." >&2
        exit 1
    fi
    (
        cd "${archive_path:h}"
        shasum -a 256 -c "${checksum_path:t}"
    )
fi

echo "Verified: $app_dir"
echo "Architectures: app=$architectures widget=$widget_architectures"
