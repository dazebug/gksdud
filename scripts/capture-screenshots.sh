#!/bin/bash
# README screenshots from a built gksdud.app. The app runs only in its test modes, beside the user's own gksdud, and each language
# first passes the strict localization walk, so no Korean text or clipped label reaches a screenshot. The terminal needs Screen
# Recording, and nothing may be typed or clicked while a language is captured (about 10 s each).
set -euo pipefail
usage='Usage: scripts/capture-screenshots.sh [--dark] <path/to/gksdud.app> [language ...]'
appearance=light
if [[ "${1:-}" == --dark ]]; then appearance=dark; shift; fi
[[ $# -gt 0 && -x "${1%/}/Contents/MacOS/gksdud" ]] || { echo "$usage" >&2; exit 1; }
binary="$(cd "$1" && pwd)/Contents/MacOS/gksdud"; shift
cd "$(dirname "$0")/.."
if [[ $# -eq 0 ]]; then set -- ja zh-Hant; fi
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
