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
ui_choose_body="$(awk '
  /^ui_choose\(\) \{/ { in_func = 1 }
  in_func { print }
  in_func && /^\}/ { exit }
' install.sh)"

[ -n "$ui_can_prompt_body" ] || fail "ui_can_prompt function not found"
[ -n "$ui_choose_body" ] || fail "ui_choose function not found"

if printf "%s\n" "$ui_can_prompt_body" | grep -Eq '\[ -t 1 \]'; then
  fail "ui_can_prompt must not require stdout to be a TTY; ui_choose captures stdout for the selected value"
fi

if ! printf "%s\n" "$ui_can_prompt_body" | grep -Fq '/dev/tty'; then
  fail "ui_can_prompt should validate /dev/tty so captured Gum choices remain interactive"
fi

if printf "%s\n" "$ui_choose_body" | grep -Fq 'gum style'; then
  fail "ui_choose must not call gum style before gum choose; some terminals leak cursor-position responses"
fi

if printf "%s\n" "$ui_choose_body" | grep -Eq 'gum choose .*--height|2>/dev/null'; then
  fail "ui_choose should call plain gum choose without hidden stderr so the TUI remains visible"
fi

printf "installer UI prompt regression checks passed\n"
