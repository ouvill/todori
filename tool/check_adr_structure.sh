#!/bin/sh

set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
index_file="$repo_root/docs/05_設計判断記録.md"
adr_dir="$repo_root/docs/adr"
index_ids=$(mktemp)
file_ids=$(mktemp)
index_ids_unsorted=$(mktemp)
file_ids_unsorted=$(mktemp)
trap 'rm -f "$index_ids" "$file_ids" "$index_ids_unsorted" "$file_ids_unsorted"' EXIT HUP INT TERM

if [ ! -f "$index_file" ]; then
  echo "ADR index is missing: $index_file" >&2
  exit 1
fi

if [ ! -d "$adr_dir" ]; then
  echo "ADR directory is missing: $adr_dir" >&2
  exit 1
fi

awk '/^## ADR-[0-9][0-9][0-9]: / { print substr($2, 1, 7) }' \
  "$index_file" >"$index_ids_unsorted"
sort "$index_ids_unsorted" >"$index_ids"

for adr_file in "$adr_dir"/ADR-*.md; do
  if [ ! -f "$adr_file" ]; then
    echo "no per-ADR files found in $adr_dir" >&2
    exit 1
  fi
  filename=$(basename -- "$adr_file")
  id=${filename%.md}
  case "$id" in
    ADR-[0-9][0-9][0-9]) ;;
    *)
      echo "invalid ADR filename: $filename" >&2
      exit 1
      ;;
  esac
  printf '%s\n' "$id" >>"$file_ids_unsorted"
done
sort "$file_ids_unsorted" >"$file_ids"

record_count=$(wc -l <"$file_ids" | tr -d ' ')
if [ "$record_count" -lt 24 ]; then
  echo "ADR history is incomplete: expected at least 24 records, found $record_count" >&2
  exit 1
fi

if [ -n "$(uniq -d "$index_ids")" ]; then
  echo "duplicate ADR ID in index" >&2
  exit 1
fi

if ! diff -u "$index_ids" "$file_ids"; then
  echo "ADR index and per-file IDs differ" >&2
  exit 1
fi

expected=1
while IFS= read -r id; do
  expected_id=$(printf 'ADR-%03d' "$expected")
  if [ "$id" != "$expected_id" ]; then
    echo "ADR sequence gap: expected $expected_id, found $id" >&2
    exit 1
  fi

  adr_file="$adr_dir/$id.md"
  file_heading=$(sed -n '1p' "$adr_file")
  index_heading=$(grep "^## $id: " "$index_file")
  expected_file_heading=$(printf '%s\n' "$index_heading" | sed 's/^## /# /')
  if [ "$file_heading" != "$expected_file_heading" ]; then
    echo "$id title differs between index and file" >&2
    exit 1
  fi

  date=$(sed -n 's/^\*\*日付\*\*: //p' "$adr_file")
  status=$(sed -n 's/^\*\*状態\*\*: //p' "$adr_file")
  if [ -z "$date" ] || [ -z "$status" ]; then
    echo "$id is missing date or status" >&2
    exit 1
  fi

  section=$(awk -v id="$id" '
    $0 ~ "^## " id ": " { capture = 1 }
    capture && $0 ~ "^## ADR-[0-9][0-9][0-9]: " && $0 !~ "^## " id ": " { exit }
    capture { print }
  ' "$index_file")

  printf '%s\n' "$section" | grep -Fqx -- "- **日付**: $date"
  printf '%s\n' "$section" | grep -Fqx -- "- **状態**: $status"
  printf '%s\n' "$section" | grep -Fqx -- "- **本文**: [$id](./adr/$id.md)"

  expected=$((expected + 1))
done <"$file_ids"

echo "ADR structure OK: $((expected - 1)) records"
