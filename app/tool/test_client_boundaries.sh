#!/bin/sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/app/rust/src" "$fixture/cli" "$fixture/mcp-server"
cp "$repo_root/app/rust/Cargo.toml" "$fixture/app/rust/Cargo.toml"
cp "$repo_root/app/rust/src/api.rs" "$repo_root/app/rust/src/lib.rs" \
  "$repo_root/app/rust/src/profile_handle.rs" "$fixture/app/rust/src/"
cp "$repo_root/cli/Cargo.toml" "$fixture/cli/Cargo.toml"
cp "$repo_root/mcp-server/Cargo.toml" "$fixture/mcp-server/Cargo.toml"

check="$repo_root/app/tool/check_client_boundaries.sh"
TODORI_BOUNDARY_ROOT="$fixture" sh "$check"

expect_failure() {
  label="$1"
  if TODORI_BOUNDARY_ROOT="$fixture" sh "$check" >/dev/null 2>&1; then
    printf '%s\n' "boundary fixture unexpectedly passed: $label" >&2
    exit 1
  fi
}

printf '%s\n' 'use todori_storage as forbidden;' > "$fixture/app/rust/src/rogue.rs"
expect_failure lower-source
rm "$fixture/app/rust/src/rogue.rs"

printf '%s\n' 'todori-storage.workspace = true' >> "$fixture/cli/Cargo.toml"
expect_failure cli-lower-dependency
cp "$repo_root/cli/Cargo.toml" "$fixture/cli/Cargo.toml"

printf '%s\n' 'rogue = { package = "todori-storage", path = "../../../core/storage" }' >> \
  "$fixture/app/rust/Cargo.toml"
expect_failure hidden-app-alias
cp "$repo_root/app/rust/Cargo.toml" "$fixture/app/rust/Cargo.toml"

printf '%s\n' '// legacy' > "$fixture/app/rust/src/support.rs"
expect_failure legacy-source
rm "$fixture/app/rust/src/support.rs"

mkdir -p "$fixture/rogue"
printf '%s\n' '[package]' 'name = "core"' > "$fixture/rogue/Cargo.toml"
expect_failure bare-core
