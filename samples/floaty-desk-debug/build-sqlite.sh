#!/usr/bin/env bash
set -euo pipefail

fixture_dir="$(cd "$(dirname "$0")" && pwd)"
temporary="$(mktemp "$fixture_dir/data/desk.sqlite.tmp.XXXXXX")"
trap 'rm -f "$temporary"' EXIT

sqlite3 "$temporary" < "$fixture_dir/data/desk.sql"
mv -f "$temporary" "$fixture_dir/data/desk.sqlite"
trap - EXIT
