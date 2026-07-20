#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <output-directory>" >&2
  exit 64
fi

version="1.7.12"
output_directory="$1"
operating_system="$(uname -s)"
architecture="$(uname -m)"

case "${operating_system}/${architecture}" in
  Darwin/arm64)
    artifact="actionlint_${version}_darwin_arm64.tar.gz"
    expected_sha256="aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f"
    ;;
  Linux/x86_64)
    artifact="actionlint_${version}_linux_amd64.tar.gz"
    expected_sha256="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
    ;;
  Linux/aarch64|Linux/arm64)
    artifact="actionlint_${version}_linux_arm64.tar.gz"
    expected_sha256="325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6"
    ;;
  *)
    echo "unsupported actionlint platform: ${operating_system}/${architecture}" >&2
    exit 64
    ;;
esac

temporary_directory="$(mktemp -d)"
cleanup() {
  rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

archive="$temporary_directory/$artifact"
curl --fail --location --silent --show-error \
  "https://github.com/rhysd/actionlint/releases/download/v${version}/${artifact}" \
  --output "$archive"

if command -v sha256sum >/dev/null 2>&1; then
  actual_sha256="$(sha256sum "$archive" | awk '{print $1}')"
else
  actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
fi
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo "actionlint archive checksum mismatch" >&2
  exit 1
fi

tar -xzf "$archive" -C "$temporary_directory" actionlint
mkdir -p "$output_directory"
install -m 0755 "$temporary_directory/actionlint" "$output_directory/actionlint"
