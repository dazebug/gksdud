#!/bin/bash
# README screenshots from a built gksdud.app. The app runs only in its test modes, beside the user's own gksdud, and each language
# first passes the strict localization walk, so no Korean text or clipped label reaches a screenshot. The terminal needs Screen
# Recording, and nothing may be typed or clicked while a language is captured (about 10 s each).
set -euo pipefail
# An exported CDPATH makes cd print the directory it found, which would become part of the paths below.
unset CDPATH
usage='Usage: scripts/capture-screenshots.sh [--dark] <path/to/gksdud.app> [language ...]'
appearance=light
if [[ "${1:-}" == --dark ]]; then appearance=dark; shift; fi
[[ $# -gt 0 && -x "${1%/}/Contents/MacOS/gksdud" ]] || { echo "$usage" >&2; exit 1; }
app=$(cd -- "$1" && pwd -P); shift
binary="$app/Contents/MacOS/gksdud"
# Read without running the app: a build without this marker (LaunchMode.contract) may not know these arguments and start normally.
marker=$(/usr/libexec/PlistBuddy -c 'Print :GKSDUDLaunchModes' "$app/Contents/Info.plist" 2>/dev/null || true)
if [[ "$marker" != 1 ]]; then
  echo "$app is older than this script or is not gksdud: its Info.plist has no GKSDUDLaunchModes 1, so it could start normally beside the running gksdud." >&2
  exit 1
fi
if [[ $# -eq 0 ]]; then set -- ja zh-Hant; fi
# Languages become app arguments and folder names, so each must be ko or have an lproj in the app. All are checked before the first
# launch, so a bad one cannot end the run after an earlier language's capture replaced its docs/images.
pattern='^[A-Za-z]{2,3}(-[A-Za-z0-9]+)*$'
for language in "$@"; do
  if [[ ! "$language" =~ $pattern ]] || [[ "$language" != ko && ! -d "$app/Contents/Resources/$language.lproj" ]]; then
    echo "$language is neither ko nor a language of $app." >&2; echo "$usage" >&2; exit 1
  fi
done
cd "$(dirname "$0")/.."
for language in "$@"; do
  "$binary" --localization-test "$language" --strict -AppleLanguages "($language)"
  # Light captures are the README images; dark ones are for review only and stay out of the repository.
  if [[ "$appearance" == dark ]]; then directory="/private/tmp/gksdud-captures/$language-dark"; else directory="$PWD/docs/images/$language"; fi
  echo "Capturing $language ($appearance) into $directory. Do not type or click until it finishes."
  "$binary" --capture-screenshots "$directory" --appearance "$appearance" -AppleLanguages "($language)"
  for name in settings-general settings-caps settings-symbols menu badges; do
    sips -g pixelWidth -g pixelHeight "$directory/$name.png" | awk -v file="$directory/$name.png" '/pixelWidth/ { width = $2 } /pixelHeight/ { height = $2 } END { print file ": " width "×" height }'
  done
done
