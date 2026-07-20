#!/usr/bin/env bash
set -euo pipefail

: "${API_BASE_URL:?API_BASE_URL is required}"
: "${REALTIME_BASE_URL:?REALTIME_BASE_URL is required}"

assert_json() {
  local url="$1"
  local expected="$2"
  local response
  response="$(curl --fail --silent --show-error --max-time 15 "$url")"
  [[ "$response" == "$expected" ]] || {
    echo "unexpected response for public smoke endpoint" >&2
    return 1
  }
}

assert_rejected() {
  local method="$1"
  local url="$2"
  shift 2
  local status
  status="$(curl --silent --show-error --max-time 15 --output /dev/null \
    --write-out '%{http_code}' --request "$method" "$@" "$url")"
  case "$status" in
    401|403) ;;
    *)
      echo "expected authentication rejection, got HTTP $status" >&2
      return 1
      ;;
  esac
}

assert_json "$API_BASE_URL/health" '{"status":"ok"}'
assert_json "$API_BASE_URL/ready" '{"status":"ready"}'
assert_rejected GET "$API_BASE_URL/v2/tenants/00000000-0000-0000-0000-000000000000/preflight"
assert_rejected GET "$REALTIME_BASE_URL/v1/connect" \
  --header 'Upgrade: websocket' \
  --header 'Authorization: Bearer invalid-ticket'
assert_rejected POST "$REALTIME_BASE_URL/v1/publish" \
  --header 'Content-Type: application/json' \
  --data '{}'

echo "staging smoke tests: ok"
