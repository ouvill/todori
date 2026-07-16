#!/bin/sh

set -eu

event_name=${1:-}
before_sha=${2:-}
base_sha=${3:-}
head_sha=${4:-}

full_ci() {
    echo false
    exit 0
}

case "$event_name" in
    pull_request)
        start_sha=$base_sha
        separator=...
        ;;
    push)
        start_sha=$before_sha
        separator=..
        ;;
    *)
        full_ci
        ;;
esac

case "$start_sha:$head_sha" in
    :*|*:|0000000000000000000000000000000000000000:*)
        full_ci
        ;;
esac

if ! changed_paths=$(git -c core.quotePath=false diff --name-only --no-renames "$start_sha$separator$head_sha" -- 2>/dev/null); then
    full_ci
fi

[ -n "$changed_paths" ] || full_ci

docs_only=true
while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
        docs/*)
            ;;
        */*)
            docs_only=false
            ;;
        *.md|LICENSE|LICENSE.*)
            ;;
        *)
            docs_only=false
            ;;
    esac
done <<EOF
$changed_paths
EOF

echo "$docs_only"
