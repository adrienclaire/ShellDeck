#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf "FAIL: %s\n" "$*" >&2
  exit 1
}

ui_can_prompt_body="$(awk '
  /^ui_can_prompt\(\) \{/ { in_func = 1 }
  in_func { print }
  in_func && /^\}/ { exit }
' install.sh)"

[ -n "$ui_can_prompt_body" ] || fail "ui_can_prompt function not found"

if printf "%s\n" "$ui_can_prompt_body" | grep -Eq '\[ -t 1 \]'; then
  fail "ui_can_prompt must not require stdout to be a TTY; ui_choose captures stdout for the selected value"
fi

if ! printf "%s\n" "$ui_can_prompt_body" | grep -Fq '/dev/tty'; then
  fail "ui_can_prompt should validate /dev/tty so captured Gum choices remain interactive"
fi

printf "installer UI prompt regression checks passed\n"
