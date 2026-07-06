#!/bin/sh
set -eu

# Downloads Design Lab-only fonts that are NOT bundled with the app and must
# NOT be committed to the repository (see docs/design/ui-spec.md セクション6).
#
# Currently fetches Zen Old Mincho (SemiBold), used only by the
# `design_lab_typo_*` typography comparison screenshots (D案) in
# test/visual_qa/visual_qa_screenshots_test.dart. If the download fails (no
# network, API shape change, etc.) this script prints a warning and exits 0
# so `sh tool/visual_qa.sh` can still generate the other screenshots; the
# D案 screenshot test skips itself when the font file is missing.
#
# Output: build/lab_fonts/ZenOldMincho-SemiBold.ttf (gitignored, never
# added to pubspec.yaml -- app/build/ is excluded from version control).

cd "$(dirname "$0")/.."

font_dir="build/lab_fonts"
font_path="$font_dir/ZenOldMincho-SemiBold.ttf"

if [ -f "$font_path" ]; then
  echo "fetch_lab_fonts: $font_path already present, skipping download."
  exit 0
fi

mkdir -p "$font_dir"

css_url='https://fonts.googleapis.com/css2?family=Zen+Old+Mincho:wght@600'
css="$(curl -fsSL -A 'curl' "$css_url" 2>/dev/null || true)"

if [ -z "$css" ]; then
  echo "fetch_lab_fonts: WARNING: could not fetch Google Fonts CSS for Zen Old Mincho; skipping (D案 screenshot will be skipped)." >&2
  exit 0
fi

ttf_url="$(printf '%s' "$css" | grep -o "https://[^)]*\.ttf" | head -n 1 || true)"

if [ -z "$ttf_url" ]; then
  echo "fetch_lab_fonts: WARNING: no .ttf URL found in Google Fonts CSS response; skipping (D案 screenshot will be skipped)." >&2
  exit 0
fi

tmp_path="$font_path.download"
if ! curl -fsSL -A 'curl' "$ttf_url" -o "$tmp_path"; then
  echo "fetch_lab_fonts: WARNING: failed to download $ttf_url; skipping (D案 screenshot will be skipped)." >&2
  rm -f "$tmp_path"
  exit 0
fi

if ! file "$tmp_path" | grep -qi "TrueType"; then
  echo "fetch_lab_fonts: WARNING: downloaded file at $ttf_url is not a TrueType font; skipping (D案 screenshot will be skipped)." >&2
  rm -f "$tmp_path"
  exit 0
fi

mv "$tmp_path" "$font_path"
echo "fetch_lab_fonts: downloaded $font_path"
