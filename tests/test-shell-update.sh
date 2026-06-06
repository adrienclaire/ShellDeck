#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf "FAIL: %s\n" "$*" >&2
  exit 1
}

update_body="$(awk '
  /^shelldeck-update\(\) \{/ { in_func = 1 }
  in_func && /^shell-tools-dashboard\(\) \{/ { exit }
  in_func { print }
' shell-tools.sh)"

[ -n "$update_body" ] || fail "shelldeck-update function not found"
printf "%s\n" "$update_body" | grep -Fq 'shell-tools.sh' || fail "update must replace only the shell runtime"
printf "%s\n" "$update_body" | grep -Fq 'bash -n' || fail "downloaded Bash runtime must be syntax checked"
printf "%s\n" "$update_body" | grep -Fq '.bak.' || fail "current runtime must be backed up before replacement"

if printf "%s\n" "$update_body" | grep -Eq 'rm[[:space:]].*(infra-hosts|aliases|config)'; then
  fail "update must not delete user data"
fi

printf "shell update safety regression checks passed\n"
