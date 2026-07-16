#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
classifier=$script_dir/classify_changes.sh
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM

git -C "$fixture" init -q
git -C "$fixture" config user.name "Todori CI test"
git -C "$fixture" config user.email "ci-test@todori.invalid"

mkdir -p "$fixture/docs" "$fixture/core/domain/src" "$fixture/.github/workflows"
printf '%s\n' '# Readme' > "$fixture/README.md"
printf '%s\n' '# Initial' > "$fixture/docs/guide.md"
printf '%s\n' 'pub fn initial() {}' > "$fixture/core/domain/src/lib.rs"
printf '%s\n' 'name: initial' > "$fixture/.github/workflows/ci.yml"
git -C "$fixture" add .
git -C "$fixture" commit -qm initial
initial=$(git -C "$fixture" rev-parse HEAD)

assert_result() {
    expected=$1
    description=$2
    shift 2
    actual=$(cd "$fixture" && sh "$classifier" "$@")
    if [ "$actual" != "$expected" ]; then
        echo "not ok - $description: expected $expected, got $actual" >&2
        exit 1
    fi
    echo "ok - $description"
}

printf '%s\n' '# Docs only' >> "$fixture/docs/guide.md"
printf '%s\n' '# 日本語文書' > "$fixture/docs/日本語.md"
git -C "$fixture" add docs/guide.md docs/日本語.md
git -C "$fixture" commit -qm docs-only
docs_commit=$(git -C "$fixture" rev-parse HEAD)
assert_result true "docs-only push" push "$initial" "" "$docs_commit"
assert_result true "docs-only pull request" pull_request "" "$initial" "$docs_commit"

printf '%s\n' '# Root docs' >> "$fixture/README.md"
git -C "$fixture" add README.md
git -C "$fixture" commit -qm root-docs
root_docs_commit=$(git -C "$fixture" rev-parse HEAD)
assert_result true "root Markdown is documentation" push "$docs_commit" "" "$root_docs_commit"

printf '%s\n' 'pub fn changed() {}' >> "$fixture/core/domain/src/lib.rs"
git -C "$fixture" add core/domain/src/lib.rs
git -C "$fixture" commit -qm code-change
code_commit=$(git -C "$fixture" rev-parse HEAD)
assert_result false "code change requires full CI" push "$root_docs_commit" "" "$code_commit"
assert_result false "mixed docs and code require full CI" pull_request "" "$docs_commit" "$code_commit"

printf '%s\n' 'name: changed' > "$fixture/.github/workflows/ci.yml"
git -C "$fixture" add .github/workflows/ci.yml
git -C "$fixture" commit -qm workflow-change
workflow_commit=$(git -C "$fixture" rev-parse HEAD)
assert_result false "workflow change requires full CI" push "$code_commit" "" "$workflow_commit"

git -C "$fixture" rm -q docs/guide.md
git -C "$fixture" commit -qm docs-deletion
docs_deletion_commit=$(git -C "$fixture" rev-parse HEAD)
assert_result true "documentation deletion is docs-only" push "$workflow_commit" "" "$docs_deletion_commit"

mkdir -p "$fixture/docs"
mv "$fixture/core/domain/src/lib.rs" "$fixture/docs/renamed-code.md"
git -C "$fixture" add -A
git -C "$fixture" commit -qm code-renamed-to-docs
rename_commit=$(git -C "$fixture" rev-parse HEAD)
assert_result false "code renamed into docs requires full CI" push "$docs_deletion_commit" "" "$rename_commit"

assert_result false "schedule always runs full CI" schedule "" "" "$rename_commit"
assert_result false "unknown event runs full CI" unknown "$docs_deletion_commit" "" "$rename_commit"
assert_result false "new branch push runs full CI" push 0000000000000000000000000000000000000000 "" "$rename_commit"
assert_result false "empty diff runs full CI" push "$rename_commit" "" "$rename_commit"
assert_result false "invalid comparison runs full CI" push deadbeef "" "$rename_commit"
