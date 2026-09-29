#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
sources=(main.swift SystemAccess.swift AppLanguage.swift InputLanguage.swift InputSources.swift StatusMenu.swift DudIcon.swift KeyboardManagement.swift KeyboardSettings.swift SettingsWindow.swift SpecialCharacters.swift UpdateChecking.swift UpdateInstaller.swift Preview.swift Screenshots.swift FeatureTests.swift KeyboardTests.swift InputLanguageTests.swift LocalizationTests.swift)
strict=""; if [[ "${GKSDUD_L10N_STRICT:-0}" == 1 ]]; then strict=--strict; fi
shopt -s nullglob
mode=${GKSDUD_SIGN_MODE:-local}
sign_args=()
case "$mode" in
  local)
    [[ -f signing/local-certificate.pem ]] || { echo 'Missing fixed signing certificate. Run signing/setup-local-signing.sh first.' >&2; exit 1; }
    fingerprint=$(openssl x509 -in signing/local-certificate.pem -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
    [[ "$fingerprint" =~ ^[A-Fa-f0-9]{40}$ ]] || exit 1
    sign_args=(--sign "$fingerprint" --timestamp=none --requirements "=designated => identifier \"io.gksdud.inputswitch\" and certificate leaf = H\"$fingerprint\"")
    ;;
  developer-id)
    : "${GKSDUD_SIGN_IDENTITY:?Set Developer ID Application signing identity}"
    sign_args=(--sign "$GKSDUD_SIGN_IDENTITY" --timestamp)
    ;;
  ad-hoc)
    echo 'WARNING: ad-hoc signing does not preserve app identity across updates.' >&2
    sign_args=(--sign - --timestamp=none)
    ;;
  *) echo 'GKSDUD_SIGN_MODE must be local, developer-id, or ad-hoc' >&2; exit 1 ;;
esac
output_dir=${GKSDUD_OUTPUT_DIR:-"$PWD/outputs"}
stage=$(mktemp -d /private/tmp/gksdud-build.XXXXXX)
mkdir -p "$stage/gksdud.app/Contents/MacOS" "$stage/gksdud.app/Contents/Resources" "$output_dir"
swiftc -parse-as-library -D ICON_GENERATOR -module-cache-path "$stage/module-cache" DudIcon.swift -o "$stage/icon-generator"
"$stage/icon-generator" "$stage/AppIcon.iconset"
iconutil -c icns "$stage/AppIcon.iconset" -o "$stage/gksdud.app/Contents/Resources/AppIcon.icns"
swiftc -parse-as-library -module-cache-path "$stage/module-cache" scripts/check-localization.swift -o "$stage/check-localization"
"$stage/check-localization" --self-test
bash -n scripts/capture-screenshots.sh
# A named defaults suite leaves its plist in ~/Library/Preferences, so suites open only in ScratchDefaults' marked line.
# Inside if, grep finding nothing (status 1) neither trips set -e nor reads as a match through pipefail.
if grep -nF 'UserDefaults(suiteName:' "${sources[@]}" | grep -vF '// build.sh: the only named suite'; then echo 'Open defaults suites with ScratchDefaults (Preview.swift).' >&2; exit 1; fi
for arch in arm64 x86_64; do
  # Only the arm64 compile extracts String(localized:) keys; the guarded expansion survives set -u in bash 3.2.
  extract=(); if [[ "$arch" == arm64 ]]; then extract=(-emit-localized-strings -emit-localized-strings-path "$stage/strings"); fi
  swiftc -swift-version 5 -O -target "$arch-apple-macos13.0" -module-cache-path "$stage/module-cache" -import-objc-header Bridge.h ${extract[@]+"${extract[@]}"} "${sources[@]}" -o "$stage/gksdud-$arch" -framework AppKit -framework IOKit -framework ServiceManagement
done
"$stage/check-localization" ${strict:+"$strict"} --stringsdata "$stage/strings" --info-plist Info.plist --resources Resources --readme README.md "${sources[@]}"
lipo -create "$stage/gksdud-arm64" "$stage/gksdud-x86_64" -output "$stage/gksdud.app/Contents/MacOS/gksdud"
cp Info.plist "$stage/gksdud.app/Contents/Info.plist"
cp LICENSE "$stage/gksdud.app/Contents/Resources/LICENSE"
cp Resources/github.svg Resources/OCTICONS-LICENSE "$stage/gksdud.app/Contents/Resources/"
for lproj in Resources/*.lproj; do cp -R "$lproj" "$stage/gksdud.app/Contents/Resources/"; done
if [[ -n "${GKSDUD_APP_VERSION:-}" ]]; then
  [[ "$GKSDUD_APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $GKSDUD_APP_VERSION" "$stage/gksdud.app/Contents/Info.plist"
fi
if [[ -n "${GKSDUD_BUILD_NUMBER:-}" ]]; then
  [[ "$GKSDUD_BUILD_NUMBER" =~ ^[0-9]+$ ]] || exit 1
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $GKSDUD_BUILD_NUMBER" "$stage/gksdud.app/Contents/Info.plist"
fi
codesign --force "${sign_args[@]}" --options runtime "$stage/gksdud.app"
codesign --verify --deep --strict "$stage/gksdud.app"
app="$stage/gksdud.app/Contents/MacOS/gksdud"
"$app" --self-test -AppleLanguages '(ko)'
# ko under an unsupported system language proves the Korean fallback for strings and Locale.
"$app" --localization-test ko ${strict:+"$strict"} -AppleLanguages '(en-US)'
for lproj in Resources/*.lproj; do language=$(basename "$lproj" .lproj); "$app" --localization-test "$language" ${strict:+"$strict"} -AppleLanguages "($language)"; done
echo "Localization data: $stage/strings"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$stage/gksdud.app/Contents/Info.plist")
ditto -c -k --keepParent --norsrc "$stage/gksdud.app" "$output_dir/gksdud-$version-macos-universal.zip"
codesign -d -r- "$stage/gksdud.app"
echo "Built app: $stage/gksdud.app"
