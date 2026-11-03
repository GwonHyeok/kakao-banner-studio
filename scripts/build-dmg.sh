#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:-}"
output="${2:-}"
if [[ ( "$mode" != --local && "$mode" != --sign-only && "$mode" != --release ) || -z "$output" || "$#" -ne 2 ]]; then
    echo "Usage: $0 --local|--sign-only|--release output.dmg" >&2
    exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if [[ "$mode" != --local ]]; then
    : "${DEVELOPER_ID_IDENTITY:?Set the Developer ID Application signing identity}"
    : "${APP_PROFILE:?Set the app Developer ID provisioning profile path}"
    : "${PROXY_PROFILE:?Set the extension Developer ID provisioning profile path}"
    if [[ "$mode" == --release ]]; then
        : "${NOTARY_PROFILE:?Set the notarytool Keychain profile name}"
    fi
    for profile in "$APP_PROFILE" "$PROXY_PROFILE"; do
        security cms -D -i "$profile" > "$work/profile.plist"
        /usr/libexec/PlistBuddy -c 'Print Entitlements:com.apple.developer.networking.networkextension' "$work/profile.plist" |
            grep -qw app-proxy-provider-systemextension || {
                echo "Missing Developer ID app proxy entitlement in $profile" >&2
                exit 1
            }
    done
    [[ "$DEVELOPER_ID_IDENTITY" == "Developer ID Application:"* ]]
    signing=(CODE_SIGNING_ALLOWED=NO)
else
    signing=(-allowProvisioningUpdates)
fi

xcodebuild -project "$root/KakaoBanner.xcodeproj" -scheme KakaoBanner \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$work/build" "${signing[@]}" build

mkdir "$work/image"
products="$work/build/Build/Products/Release"
apps=("$products"/*.app)
[[ ${#apps[@]} -eq 1 && -d "${apps[0]}" ]]
app="$work/image/$(basename "${apps[0]}")"
ditto "${apps[0]}" "$app"
ln -s /Applications "$work/image/Applications"

if [[ "$mode" != --local ]]; then
    extensions=("$app"/Contents/Library/SystemExtensions/*.systemextension)
    [[ ${#extensions[@]} -eq 1 && -d "${extensions[0]}" ]]
    proxy="${extensions[0]}"
    for target in App Proxy; do
        cp "$root/$target/$target.entitlements" "$work/$target.entitlements"
        /usr/libexec/PlistBuddy -c 'Set com.apple.developer.networking.networkextension:0 app-proxy-provider-systemextension' "$work/$target.entitlements"
    done
    cp "$PROXY_PROFILE" "$proxy/Contents/embedded.provisionprofile"
    cp "$APP_PROFILE" "$app/Contents/embedded.provisionprofile"
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_IDENTITY" \
        --entitlements "$work/Proxy.entitlements" "$proxy"
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_IDENTITY" \
        --entitlements "$work/App.entitlements" "$app"
fi

codesign --verify --deep --strict "$app"
dmg="$work/KakaoBannerStudio.dmg"
hdiutil create -fs HFS+ -format UDZO -volname '카카오톡 배너 스튜디오' -srcfolder "$work/image" "$dmg"

if [[ "$mode" != --local ]]; then
    codesign --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$dmg"
fi
if [[ "$mode" == --release ]]; then
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
fi
hdiutil verify "$dmg"
mkdir -p "$(dirname "$output")"
cp "$dmg" "$output"
echo "Created $output"
