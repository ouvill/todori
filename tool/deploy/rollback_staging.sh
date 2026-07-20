#!/usr/bin/env bash
set -uo pipefail

: "${LAMBDA_ALIAS_MOVED:?LAMBDA_ALIAS_MOVED is required}"
: "${WORKER_DEPLOYMENT_MOVED:?WORKER_DEPLOYMENT_MOVED is required}"
: "${LAMBDA_FUNCTION:?LAMBDA_FUNCTION is required}"
: "${LAMBDA_ALIAS:?LAMBDA_ALIAS is required}"
: "${PREVIOUS_LAMBDA_VERSION:?PREVIOUS_LAMBDA_VERSION is required}"
: "${WORKER_DIRECTORY:?WORKER_DIRECTORY is required}"
: "${DEPLOY_SHA:?DEPLOY_SHA is required}"

status=0

if [[ "$LAMBDA_ALIAS_MOVED" == true ]]; then
  aws lambda update-alias \
    --function-name "$LAMBDA_FUNCTION" \
    --name "$LAMBDA_ALIAS" \
    --function-version "$PREVIOUS_LAMBDA_VERSION" >/dev/null || status=1
fi

if [[ "$WORKER_DEPLOYMENT_MOVED" == true ]]; then
  (
    cd "$WORKER_DIRECTORY"
    npx wrangler rollback --env staging --yes \
      --message "rollback failed commit $DEPLOY_SHA"
  ) || status=1
fi

exit "$status"
