#!/bin/sh
set -eu

status=0

fail() {
  printf '%s\n' "$1" >&2
  status=1
}

for manifest in cli/Cargo.toml mcp-server/Cargo.toml; do
  if rg '^todori-' "$manifest" | rg -v '^todori-client([.]workspace)?[[:space:]]*=' >/dev/null; then
    fail "$manifest: frontend adapter must depend on todori-client, not lower Todori crates"
  fi
done

legacy_match_count="$(
  rg -o 'todori_(crypto|domain|storage|sync)|open_encrypted|Sqlite[A-Za-z0-9_]*|AccountClient|LocalSyncStore|LocalMutationContext|load_or_create_device_key' \
    app/rust/src/api.rs app/rust/src/support.rs | wc -l | tr -d ' '
)"
if [ "$legacy_match_count" -gt 94 ]; then
  fail 'app/rust/src/api.rs/support.rs: legacy lower-layer reference count must only decrease'
fi

if rg -n 'todori_(crypto|domain|storage|sync)|open_encrypted|Sqlite[A-Za-z0-9_]*|AccountClient|LocalSyncStore|LocalMutationContext|load_or_create_device_key' \
  app/rust/src \
  -g '*.rs' \
  -g '!frb_generated.rs' \
  -g '!api.rs' \
  -g '!support.rs' \
  -g '!sync_store.rs' >/dev/null; then
  fail 'app/rust/src: lower-layer implementation is only temporarily allowed in api.rs/support.rs'
fi

if ! rg -q '^pub use todori_client::SqliteSyncStore as BridgeSyncStore;$' app/rust/src/sync_store.rs ||
  [ "$(wc -l < app/rust/src/sync_store.rs | tr -d ' ')" -gt 3 ]; then
  fail 'app/rust/src/sync_store.rs: only the temporary todori-client compatibility re-export is allowed'
fi

if rg -n '^name[[:space:]]*=[[:space:]]*"core"' \
  -g 'Cargo.toml' . >/dev/null; then
  fail 'Cargo manifest: bare core package/lib name is forbidden'
fi

if rg -n '^core[[:space:]]*=[[:space:]]*\{' \
  -g 'Cargo.toml' . >/dev/null; then
  fail 'Cargo manifest: core dependency alias is forbidden'
fi

exit "$status"
