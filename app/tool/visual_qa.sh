#!/bin/sh
set -eu

# Generates design-review screenshots of curated app states.
#
# Runs test/visual_qa/visual_qa_screenshots_test.dart with
# TODORI_VISUAL_QA=1 so its screenshot tests actually execute (they are
# skipped by default so a plain `flutter test`/CI never pays this cost).
# Loads real fonts (Material Icons + a macOS system font) so the output is
# legible instead of "tofu" boxes.
#
# Output: build/visual_qa/*.png (not committed; regenerate as needed).

cd "$(dirname "$0")/.."

output_dir="build/visual_qa"
mkdir -p "$output_dir"
# Remove only artifacts owned by this harness. This keeps a filtered or failed
# run from leaving screenshots from an older production contract beside the
# current evidence.
find "$output_dir" -maxdepth 1 -type f \
  \( -name '*.png' -o -name 'current-manifest.txt' \) -delete

TODORI_VISUAL_QA=1 flutter test test/visual_qa/visual_qa_screenshots_test.dart

test -s "$output_dir/current-manifest.txt"
png_count=$(find "$output_dir" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')
manifest_count=$(wc -l < "$output_dir/current-manifest.txt" | tr -d ' ')
test "$png_count" -eq "$manifest_count"
