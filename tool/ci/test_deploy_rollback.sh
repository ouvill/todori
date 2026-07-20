#!/usr/bin/env bash
set -euo pipefail

fixture_directory="$(mktemp -d)"
trap 'rm -rf "$fixture_directory"' EXIT
mock_bin="$fixture_directory/bin"
worker_directory="$fixture_directory/worker"
log_file="$fixture_directory/calls.log"
mkdir -p "$mock_bin" "$worker_directory"

printf '%s\n' '#!/usr/bin/env bash' 'printf "aws %s\\n" "$*" >> "$ROLLBACK_TEST_LOG"' '[[ "${ROLLBACK_TEST_FAIL_AWS:-false}" != true ]]' >"$mock_bin/aws"
printf '%s\n' '#!/usr/bin/env bash' 'printf "npx %s\\n" "$*" >> "$ROLLBACK_TEST_LOG"' '[[ "${ROLLBACK_TEST_FAIL_NPX:-false}" != true ]]' >"$mock_bin/npx"
chmod +x "$mock_bin/aws" "$mock_bin/npx"

run_fixture() {
  local lambda_moved="$1"
  local worker_moved="$2"
  : >"$log_file"
  PATH="$mock_bin:$PATH" \
    ROLLBACK_TEST_LOG="$log_file" \
    ROLLBACK_TEST_FAIL_AWS=false \
    ROLLBACK_TEST_FAIL_NPX=false \
    LAMBDA_ALIAS_MOVED="$lambda_moved" \
    WORKER_DEPLOYMENT_MOVED="$worker_moved" \
    LAMBDA_FUNCTION="taskveil-staging-server" \
    LAMBDA_ALIAS="staging" \
    PREVIOUS_LAMBDA_VERSION="41" \
    WORKER_DIRECTORY="$worker_directory" \
    DEPLOY_SHA="0123456789abcdef0123456789abcdef01234567" \
    ./tool/deploy/rollback_staging.sh
}

run_fixture false false
test ! -s "$log_file"

run_fixture true false
grep -Fxq 'aws lambda update-alias --function-name taskveil-staging-server --name staging --function-version 41' "$log_file"
test "$(wc -l <"$log_file" | tr -d ' ')" -eq 1

run_fixture true true
grep -Fxq 'aws lambda update-alias --function-name taskveil-staging-server --name staging --function-version 41' "$log_file"
grep -Fxq 'npx wrangler rollback --env staging --yes --message rollback failed commit 0123456789abcdef0123456789abcdef01234567' "$log_file"
test "$(wc -l <"$log_file" | tr -d ' ')" -eq 2

: >"$log_file"
set +e
PATH="$mock_bin:$PATH" \
  ROLLBACK_TEST_LOG="$log_file" \
  ROLLBACK_TEST_FAIL_AWS=true \
  ROLLBACK_TEST_FAIL_NPX=false \
  LAMBDA_ALIAS_MOVED=true \
  WORKER_DEPLOYMENT_MOVED=true \
  LAMBDA_FUNCTION="taskveil-staging-server" \
  LAMBDA_ALIAS="staging" \
  PREVIOUS_LAMBDA_VERSION="41" \
  WORKER_DIRECTORY="$worker_directory" \
  DEPLOY_SHA="0123456789abcdef0123456789abcdef01234567" \
  ./tool/deploy/rollback_staging.sh
rollback_status=$?
set -e
test "$rollback_status" -eq 1
grep -q '^aws ' "$log_file"
grep -q '^npx ' "$log_file"

echo "staging rollback failure fixtures: ok"
