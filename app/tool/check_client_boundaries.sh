#!/bin/sh
set -eu

status=0
root="${TODORI_BOUNDARY_ROOT:-.}"

fail() {
  printf '%s\n' "$1" >&2
  status=1
}

for relative_manifest in cli/Cargo.toml mcp-server/Cargo.toml; do
  manifest="$root/$relative_manifest"
  if grep -E '^[[:space:]]*todori-' "$manifest" |
    grep -Ev '^[[:space:]]*todori-client([.]workspace)?[[:space:]]*=' >/dev/null ||
    grep -En 'package[[:space:]]*=[[:space:]]*"todori-(crypto|domain|storage|sync)"|path[[:space:]]*=[[:space:]]*"[^"]*core/(crypto|domain|storage|sync)"' "$manifest" >/dev/null; then
    fail "$manifest: frontend adapter must depend on todori-client, not lower Todori crates"
  fi
done

app_dependencies="$(
  awk '
    /^\[dependencies\]$/ { in_dependencies = 1; next }
    /^\[/ { in_dependencies = 0 }
    in_dependencies && match($0, /^[[:space:]]*[A-Za-z0-9_-]+/) {
      dependency = substr($0, RSTART, RLENGTH)
      gsub(/[[:space:]]/, "", dependency)
      print dependency
    }
  ' "$root/app/rust/Cargo.toml" | sort
)"
if [ "$app_dependencies" != "$(printf '%s\n' flutter_rust_bridge todori-client | sort)" ]; then
  fail 'app/rust/Cargo.toml: only flutter_rust_bridge and todori-client are allowed dependencies'
fi
if grep -En 'package[[:space:]]*=[[:space:]]*"todori-(crypto|domain|storage|sync)"|path[[:space:]]*=[[:space:]]*"[^"]*core/(crypto|domain|storage|sync)"' "$root/app/rust/Cargo.toml" >/dev/null; then
  fail 'app/rust/Cargo.toml: lower Todori crates must not be hidden behind dependency aliases'
fi

for legacy_source in "$root/app/rust/src/support.rs" "$root/app/rust/src/sync_store.rs" \
  "$root/app/rust/src/profile_handle.rs"; do
  if [ -e "$legacy_source" ]; then
    fail "$legacy_source: legacy bridge implementation must be removed"
  fi
done

if find "$root/app/rust/src" -type f -name '*.rs' ! -name 'frb_generated.rs' \
  -exec grep -En 'todori_(crypto|domain|storage|sync)|open_encrypted|Sqlite[A-Za-z0-9_]*|[A-Za-z0-9_]*Repository|AccountClient|LocalSyncStore|LocalMutationContext|load_or_create_device_key|tokio|zeroize' {} + \
  >/dev/null; then
  fail 'app/rust/src: handwritten bridge code must not reference lower-layer implementation'
fi

if find "$root/app/rust/src" -type f -name '*.rs' ! -name 'frb_generated.rs' ! -name 'client_handle.rs' \
  -exec grep -En 'OnceLock' {} + >/dev/null; then
  fail 'app/rust/src: process-global TodoriClient handle is only allowed in client_handle.rs'
fi

if find "$root" -type d \( -name .git -o -name target -o -name build \) -prune -o \
  -type f -name 'Cargo.toml' -exec grep -En '^name[[:space:]]*=[[:space:]]*"core"' {} + \
  >/dev/null; then
  fail 'Cargo manifest: bare core package/lib name is forbidden'
fi

if find "$root" -type d \( -name .git -o -name target -o -name build \) -prune -o \
  -type f -name 'Cargo.toml' -exec grep -En '^[[:space:]]*core([.]workspace)?[[:space:]]*=' {} + \
  >/dev/null; then
  fail 'Cargo manifest: core dependency alias is forbidden'
fi

exit "$status"
