#!/bin/sh
set -eu

# Simple UI-string guard for M2-04.
#
# Scope:
# - app/lib/main.dart
# - app/lib/src/screens/*.dart
# - app/lib/src/ui/*.dart
#
# Patterns:
# - Text('...') / Text("...")
# - tooltip: '...' / tooltip: "..."
# - labelText: '...' / labelText: "..."
# - title: '...' / title: "..."
#
# Known exclusions:
# - Dynamic data such as Text(task.title) is intentionally allowed.
# - Non-UI string literals such as route paths, status values, imports, and
#   debug logs are outside this task's detection scope.

root_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
targets="$root_dir/lib/main.dart $root_dir/lib/src/screens $root_dir/lib/src/ui"

matches="$(
  grep -RInE \
    -e "Text[[:space:]]*\\([[:space:]]*['\"]" \
    -e "tooltip:[[:space:]]*['\"]" \
    -e "labelText:[[:space:]]*['\"]" \
    -e "title:[[:space:]]*['\"]" \
    $targets || true
)"

if [ -n "$matches" ]; then
  printf '%s\n' "Hardcoded UI strings detected:"
  printf '%s\n' "$matches"
  exit 1
fi
