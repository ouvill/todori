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

sh tool/fetch_lab_fonts.sh || echo "visual_qa: WARNING: tool/fetch_lab_fonts.sh failed; continuing without it." >&2

TODORI_VISUAL_QA=1 flutter test test/visual_qa/visual_qa_screenshots_test.dart
