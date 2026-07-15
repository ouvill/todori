#!/bin/sh
set -eu

require_exact_rust() {
  file=$1
  dependency=$2
  if ! grep -Eq "^${dependency} = (\"=[0-9][^\"]*\"|\\{ version = \"=[0-9][^\"]*\")" "$file"; then
    echo "dependency is not fixed exactly: $dependency" >&2
    exit 1
  fi
}

for dependency in \
  aws-lc-rs aws-lc-sys argon2 bip39 chacha20poly1305 hkdf opaque-ke rand sha2 \
  x25519-dalek zeroize rusqlite security-framework security-framework-sys jni
do
  require_exact_rust Cargo.toml "$dependency"
done
require_exact_rust fuzz/Cargo.toml libfuzzer-sys
require_exact_rust fuzz/Cargo.toml uuid

if ! grep -Eq '^  flutter_rust_bridge: [0-9]+\.[0-9]+\.[0-9]+$' app/pubspec.yaml; then
  echo "flutter_rust_bridge is not fixed exactly" >&2
  exit 1
fi

if grep -Eq '^source = "git\+' Cargo.lock fuzz/Cargo.lock; then
  echo "git dependency found in a Cargo.lock" >&2
  exit 1
fi

cargo metadata --locked --format-version 1 >/dev/null
cargo metadata --locked --manifest-path fuzz/Cargo.toml --format-version 1 >/dev/null
