#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P)"
work_dir="$(mktemp -d)"
home_dir="$work_dir/home"
tools_dir="$work_dir/tools"
fakebin="$work_dir/fakebin"
log_file="$work_dir/flow.log"

mkdir -p "$home_dir" "$tools_dir" "$fakebin"
cp "$repo_root/install.sh" "$work_dir/install.sh"
cp "$repo_root/shell-tools.sh" "$work_dir/shell-tools.sh"

make_fake() {
  local name="$1"
  shift
  printf '%s\n' "$@" > "$fakebin/$name"
  chmod +x "$fakebin/$name"
}

make_fake sudo \
  '#!/usr/bin/env bash' \
  'exec "$@"'

make_fake apt-get \
  '#!/usr/bin/env bash' \
  'printf "fake apt-get %s\n" "$*" >&2' \
  'exit 0'

make_fake apt \
  '#!/usr/bin/env bash' \
  'if [ "${1:-}" = "list" ] && [ "${2:-}" = "--upgradable" ]; then' \
  '  printf "Listing...\n"' \
  'fi' \
  'exit 0'

make_fake curl \
  '#!/usr/bin/env bash' \
  'out=""' \
  'url=""' \
  'while [ "$#" -gt 0 ]; do' \
  '  case "$1" in' \
  '    -o) shift; out="${1:-}" ;;' \
  '    -*) ;;' \
  '    *) url="$1" ;;' \
  '  esac' \
  '  shift || true' \
  'done' \
  'if [ -n "$out" ] && [ "${url#file://}" != "$url" ]; then' \
  '  cp "${url#file://}" "$out"' \
  'elif [ -n "$out" ]; then' \
  '  : > "$out"' \
  'fi'

make_fake nano \
  '#!/usr/bin/env bash' \
  'if [ ! -t 0 ] || [ ! -t 1 ] || [ ! -t 2 ]; then' \
  '  printf "FAKE_NANO_TTYS failed stdin=%s stdout=%s stderr=%s\n" "$([ -t 0 ] && echo tty || echo notty)" "$([ -t 1 ] && echo tty || echo notty)" "$([ -t 2 ] && echo tty || echo notty)" >&2' \
  '  exit 64' \
  'fi' \
  'printf "FAKE_NANO_TTYS ok\n" >&2' \
  'printf "# fake control-node key\n" >> "$1"'

make_fake sshd \
  '#!/usr/bin/env bash' \
  'exit 0'

for name in systemctl service ufw fail2ban-client fail2ban-server git ssh wget gum fzf bat eza zoxide starship rg fd jq yq nc tree unzip zip rsync tmux btop htop duf nvim gh docker multipass; do
  make_fake "$name" '#!/usr/bin/env bash' 'exit 0'
done

answers="$work_dir/answers.txt"
cat > "$answers" <<'ANSWERS'
y
y
y
n
n
n
n
ANSWERS

command_to_run=$(
  printf "cd %q && env HOME=%q SHELL=%q SHELL_ALIAS_TOOLS_HOME=%q SHELL_ALIAS_TOOLS_RAW_BASE=%q PATH=%q bash -lc %q" \
    "$work_dir" \
    "$home_dir" \
    "/bin/bash" \
    "$tools_dir" \
    "file://$work_dir" \
    "$fakebin:$PATH" \
    'cat install.sh | bash -s -- --classic-ui --profile workstation --mode basic --os linux'
)

if ! command -v script >/dev/null 2>&1; then
  printf "script command is required for this integration test\n" >&2
  exit 77
fi

script -q -e -c "$command_to_run" "$log_file" < "$answers"

if ! grep -Fq "FAKE_NANO_TTYS ok" "$log_file"; then
  printf "fake nano did not receive a terminal on stdin/stdout/stderr\n" >&2
  cat "$log_file" >&2
  exit 1
fi

if grep -Fq "standard input is not a terminal" "$log_file"; then
  printf "installer leaked a non-terminal editor invocation\n" >&2
  cat "$log_file" >&2
  exit 1
fi

if [ ! -f "$home_dir/.ssh/authorized_keys" ]; then
  printf "authorized_keys was not created\n" >&2
  exit 1
fi

printf "workstation SSH onboarding integration flow passed\n"
