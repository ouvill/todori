#!/bin/sh
set -eu

command -v git >/dev/null
command -v grep >/dev/null

secret_pattern='-----BEGIN (ENCRYPTED |RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----|-----BEGIN PGP PRIVATE KEY BLOCK-----|A(KIA|SIA)[0-9A-Z]{16}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{36,}|(^|[^A-Za-z0-9_-])sk-(proj-)?[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}'

set +e
git grep --untracked -nI -E -e "$secret_pattern" -- . ':(exclude)tool/check_secret_patterns.sh'
grep_status=$?
set -e
case $grep_status in
  0)
    echo "possible committed secret value found" >&2
    exit 1
    ;;
  1) ;;
  *)
    echo "secret pattern scan failed" >&2
    exit "$grep_status"
    ;;
esac

tracked_files=$(git ls-files --cached --others --exclude-standard)
set +e
printf '%s\n' "$tracked_files" \
  | grep -Ei '(^|/)(device\.key|[^/]+\.(key|der|pk8|pem|p12|pfx|jks|keystore))$'
file_status=$?
set -e
case $file_status in
  0)
    echo "possible committed private key artifact found" >&2
    exit 1
    ;;
  1) ;;
  *)
    echo "private key artifact scan failed" >&2
    exit "$file_status"
    ;;
esac
