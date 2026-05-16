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
open_file_in_editor_body="$(awk '
  /^open_file_in_editor\(\) \{/ { in_func = 1 }
  in_func { print }
  in_func && /^\}/ { exit }
' install.sh)"
run_interactive_command_body="$(awk '
  /^run_interactive_command\(\) \{/ { in_func = 1 }
  in_func { print }
  in_func && /^\}/ { exit }
' install.sh)"

[ -n "$ui_can_prompt_body" ] || fail "ui_can_prompt function not found"
[ -n "$ui_choose_body" ] || fail "ui_choose function not found"
[ -n "$open_file_in_editor_body" ] || fail "open_file_in_editor function not found"

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

if printf "%s\n" "$open_file_in_editor_body" | grep -Fq 'sudo_cmd "$editor" "$file"'; then
  fail "open_file_in_editor must not run editors through inherited stdin; curl-piped installs need /dev/tty"
fi

[ -n "$run_interactive_command_body" ] || fail "run_interactive_command function not found"

if ! printf "%s\n" "$run_interactive_command_body" | grep -Fq '/dev/tty'; then
  fail "run_interactive_command must attach stdin/stdout/stderr to /dev/tty"
fi

printf "installer UI prompt regression checks passed\n"
