#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
dist_dir="$project_dir/dist"
app_dir="$dist_dir/VibeIsland.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")"
archive_path="$dist_dir/VibeIsland-$version-macOS-arm64.zip"
checksum_path="$archive_path.sha256"
signing_identity="${VIBE_ISLAND_SIGNING_IDENTITY:--}"
notary_profile="${VIBE_ISLAND_NOTARY_PROFILE:-}"
build_arguments=(-c release --arch arm64)
icon_source="$project_dir/Resources/VibeIslandAppIcon.png"
iconset_dir="$project_dir/.build/VibeIsland.iconset"
icon_path="$project_dir/.build/VibeIsland.icns"

cd "$project_dir"
swift build "${build_arguments[@]}" --product VibeIsland
release_bin_dir="$(swift build "${build_arguments[@]}" --show-bin-path)"
widget_build_dir="$project_dir/.build/widget-extension"
xcodebuild \
    -project "$project_dir/WidgetExtension/VibeIslandWidget.xcodeproj" \
    -target VibeIslandWidget \
    -configuration Release \
    -sdk macosx \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CONFIGURATION_BUILD_DIR="$widget_build_dir" \
    build

rm -rf "$iconset_dir"
mkdir -p "$iconset_dir"
for icon_spec in \
    "16:icon_16x16.png" \
    "32:icon_16x16@2x.png" \
    "32:icon_32x32.png" \
    "64:icon_32x32@2x.png" \
    "128:icon_128x128.png" \
    "256:icon_128x128@2x.png" \
    "256:icon_256x256.png" \
    "512:icon_256x256@2x.png" \
    "512:icon_512x512.png" \
    "1024:icon_512x512@2x.png"
do
    icon_size="${icon_spec%%:*}"
    icon_name="${icon_spec#*:}"
    sips -z "$icon_size" "$icon_size" "$icon_source" --out "$iconset_dir/$icon_name" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$icon_path"

if [[ "$app_dir" != "$project_dir/dist/VibeIsland.app" ]]; then
    echo "Refusing to replace unexpected app path: $app_dir" >&2
    exit 1
fi

mkdir -p "$dist_dir"
rm -rf "$app_dir"
rm -f "$archive_path" "$checksum_path"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
mkdir -p "$app_dir/Contents/PlugIns"
widget_dir="$app_dir/Contents/PlugIns/VibeIslandWidget.appex"
cp "$release_bin_dir/VibeIsland" "$app_dir/Contents/MacOS/VibeIsland"
cp -R "$widget_build_dir/VibeIslandWidget.appex" "$widget_dir"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$icon_path" "$app_dir/Contents/Resources/VibeIsland.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$widget_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$project_dir/Resources/Info.plist")" "$widget_dir/Contents/Info.plist"
strip -S -x "$app_dir/Contents/MacOS/VibeIsland"
strip -S -x "$widget_dir/Contents/MacOS/VibeIslandWidget"

if [[ "$signing_identity" == "-" ]]; then
    codesign --force --sign - --entitlements "$project_dir/Resources/Widget.entitlements" "$widget_dir"
    codesign --force --sign - "$app_dir"
else
    codesign --force --options runtime --timestamp --sign "$signing_identity" --entitlements "$project_dir/Resources/Widget.entitlements" "$widget_dir"
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_dir"
fi
codesign --verify --deep --strict --verbose=2 "$app_dir"

ditto -c -k --norsrc --noextattr --keepParent "$app_dir" "$archive_path"

if [[ -n "$notary_profile" ]]; then
    if [[ "$signing_identity" == "-" ]]; then
        echo "Notarization requires VIBE_ISLAND_SIGNING_IDENTITY." >&2
        exit 1
    fi
    xcrun notarytool submit "$archive_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$app_dir"
    rm -f "$archive_path"
    ditto -c -k --norsrc --noextattr --keepParent "$app_dir" "$archive_path"
fi

(
    cd "$dist_dir"
    shasum -a 256 "${archive_path:t}" > "${checksum_path:t}"
)

echo "$app_dir"
echo "$archive_path"
echo "$checksum_path"
