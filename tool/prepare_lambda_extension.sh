#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <pinned-layer-version-arn> <output-directory>" >&2
  exit 64
fi

layer_arn="$1"
output_directory="$2"

if [[ ! "$layer_arn" =~ ^arn:aws:lambda:eu-central-1:187925254637:layer:AWS-Parameters-and-Secrets-Lambda-Extension:[1-9][0-9]*$ ]]; then
  echo "the layer ARN must name a pinned official x86_64 Parameters and Secrets extension version in eu-central-1" >&2
  exit 64
fi

region="${layer_arn#arn:aws:lambda:}"
region="${region%%:*}"
download_url="$(aws lambda get-layer-version-by-arn \
  --arn "$layer_arn" \
  --region "$region" \
  --query 'Content.Location' \
  --output text)"

temporary_directory="$(mktemp -d)"
cleanup() {
  rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

curl --fail --silent --show-error --location \
  --output "$temporary_directory/extension.zip" \
  "$download_url"
mkdir -p "$output_directory"
unzip -q "$temporary_directory/extension.zip" -d "$temporary_directory/unpacked"
install -m 0755 \
  "$temporary_directory/unpacked/extensions/AWSParametersAndSecretsLambdaExtension" \
  "$output_directory/AWSParametersAndSecretsLambdaExtension"
