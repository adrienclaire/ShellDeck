#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
export HOME="$test_root/home"
export SHELL_ALIAS_TOOLS_HOME="$test_root/data"
export SHELL_TOOLS_NO_DASHBOARD=1 SHELL_TOOLS_NO_PROMPT=1
mkdir -p "$HOME"
cd "$repo_root"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for os in linux macos; do
  for profile in workstation control; do
    for mode in basic complete manual; do
      if ! bash install.sh --dry-run --yes --classic-ui --profile "$profile" --mode "$mode" --os "$os" > "$test_root/dry-$os-$profile-$mode.log" 2>&1; then
        tail -n 15 "$test_root/dry-$os-$profile-$mode.log" >&2
        fail "dry-run failed: $os / $profile / $mode"
      fi
      [ ! -e "$SHELL_ALIAS_TOOLS_HOME" ] || fail "dry-run created data on $os"
      [ ! -e "$HOME/.bashrc" ] && [ ! -e "$HOME/.zshrc" ] || fail "dry-run wrote a profile on $os"
    done
  done
done

mkdir -p "$SHELL_ALIAS_TOOLS_HOME" "$HOME/.ssh"
printf '# keep comment\nSHELLDECK_MACHINE_PROFILE=workstation\nCUSTOM_SETTING=keep\n' > "$SHELL_ALIAS_TOOLS_HOME/config"
printf 'function ll { printf "user-ll"; }\nalias gs="echo user-gs"\nfunction aa { printf "user-aa"; }\nfunction infra-list { printf "user-infra"; }\n' > "$SHELL_ALIAS_TOOLS_HOME/aliases.sh"
printf 'Name,HostName\nserver1,192.0.2.1\n' > "$SHELL_ALIAS_TOOLS_HOME/infra-hosts.csv"
printf '# personal profile mentions shell-alias-tools without a hook\n' > "$HOME/.bashrc"
printf 'Host server1\n  HostName 192.0.2.1\n' > "$HOME/.ssh/config"
cp "$SHELL_ALIAS_TOOLS_HOME/aliases.sh" "$test_root/aliases.before"
cp "$SHELL_ALIAS_TOOLS_HOME/infra-hosts.csv" "$test_root/hosts.before"
cp "$HOME/.ssh/config" "$test_root/ssh.before"
for repeat in 1 2; do
  bash install.sh --yes --classic-ui --skip-deps --skip-infra --os linux > "$test_root/install-$repeat.log" 2>&1
done
grep -q '^CUSTOM_SETTING=keep$' "$SHELL_ALIAS_TOOLS_HOME/config" || fail 'lost custom setting'
grep -q '^SHELLDECK_MACHINE_PROFILE=workstation$' "$SHELL_ALIAS_TOOLS_HOME/config" || fail 'lost saved profile'
[ "$(grep -c '^# >>> shell-alias-tools >>>$' "$HOME/.bashrc")" = 1 ] || fail 'missing/duplicate hook'
compgen -G "$SHELL_ALIAS_TOOLS_HOME/shell-tools.sh.bak.*" >/dev/null || fail 'no reinstall backup'
cp "$SHELL_ALIAS_TOOLS_HOME/config" "$test_root/config.before"
export SHELLDECK_TEST_RUNTIME="$test_root/updated-runtime.sh"
sed 's/docker ps/docker ps --all/g' shell-tools.sh > "$SHELLDECK_TEST_RUNTIME"

# Same assertions run in Bash, and Zsh when installed. No commands contact real hosts.
for test_shell in bash zsh; do
  command -v "$test_shell" >/dev/null 2>&1 || continue
  "$test_shell" -f -c '
    if [ -n "${ZSH_VERSION:-}" ] && [ -n "${SHELLDECK_TEST_ZSH_MODULES:-}" ]; then
      module_path=("$SHELLDECK_TEST_ZSH_MODULES" $module_path)
    fi
    function ff { printf "caller-ff"; }
    alias gp="echo caller-gp"
    . "$SHELL_ALIAS_TOOLS_HOME/shell-tools.sh"
    typeset -f ff | grep -q caller-ff || { echo "caller ff lost at first load" >&2; exit 1; }
    if [ -n "${BASH_VERSION:-}" ]; then shopt -s expand_aliases; fi
    . "$SHELL_ALIAS_TOOLS_HOME/shell-tools.sh"
    [ "$(ll)" = user-ll ] && [ "$(ff)" = caller-ff ] && [ "$(aa)" = user-aa ] || { type ll ff aa >&2; echo "ll/ff/aa lost at reload" >&2; exit 1; }
    [ "$(infra-list)" = user-infra ] || { echo "user infra-list lost" >&2; exit 1; }
    alias gp | grep -q caller-gp || { echo "caller gp alias lost" >&2; exit 1; }
    alias gs | grep -q user-gs || { echo "user gs alias lost" >&2; exit 1; }
    typeset -f init >/dev/null 2>&1 && exit 1
    export SHELLDECK_CONFIG_FILE="$SHELLDECK_TEST_RUNTIME.profile"
    printf "SHELLDECK_MACHINE_PROFILE=control\n" > "$SHELLDECK_CONFIG_FILE"
    . "$SHELL_ALIAS_TOOLS_HOME/shell-tools.sh"
    typeset -f init >/dev/null 2>&1 || exit 1
    printf "SHELLDECK_MACHINE_PROFILE=workstation\n" > "$SHELLDECK_CONFIG_FILE"
    . "$SHELL_ALIAS_TOOLS_HOME/shell-tools.sh"
    typeset -f init >/dev/null 2>&1 && exit 1
    [ "$(infra-list)" = user-infra ] || exit 1
    function curl { cp "$SHELLDECK_TEST_RUNTIME" "$4"; }
    shelldeck-update || exit 1
    [ "$(ll)" = user-ll ] && [ "$(ff)" = caller-ff ] || exit 1
    typeset -f dps | grep -q "docker ps --all" || exit 1
    printf "function broken {\n" > "$SHELLDECK_TEST_RUNTIME"
    cp "$SHELL_ALIAS_TOOLS_HOME/shell-tools.sh" "$SHELLDECK_TEST_RUNTIME.before"
    shelldeck-update && exit 1
    cmp "$SHELLDECK_TEST_RUNTIME.before" "$SHELL_ALIAS_TOOLS_HOME/shell-tools.sh" || exit 1
  ' || fail "$test_shell lost user commands or did not update defaults"
  sed 's/docker ps/docker ps --all/g' shell-tools.sh > "$SHELLDECK_TEST_RUNTIME"
  printf '%s preservation checks passed\n' "$test_shell"
done

# Interactive defaults must not hide user functions when alias expansion is active.
bash --noprofile --norc -i -c '
  function ff { printf "caller-ff"; }
  . "$SHELL_ALIAS_TOOLS_HOME/shell-tools.sh"
  . "$SHELL_ALIAS_TOOLS_HOME/shell-tools.sh"
  [ "$(ll)" = user-ll ] && [ "$(ff)" = caller-ff ] && [ "$(aa)" = user-aa ]
' > "$test_root/interactive.log" 2>&1 || { tail -n 15 "$test_root/interactive.log" >&2; fail 'interactive Bash lost overrides'; }

# Hook-only uninstall keeps user data and unrelated profile content.
. "$SHELL_ALIAS_TOOLS_HOME/shell-tools.sh"
_shell_tools_yes_no() { [ "$2" = yes ]; }
shelluninstall > "$test_root/uninstall.log"
! grep -q '^# >>> shell-alias-tools >>>$' "$HOME/.bashrc" || fail 'uninstall kept hook'
grep -q 'personal profile' "$HOME/.bashrc" || fail 'uninstall removed personal content'
cmp "$test_root/aliases.before" "$SHELL_ALIAS_TOOLS_HOME/aliases.sh"
cmp "$test_root/hosts.before" "$SHELL_ALIAS_TOOLS_HOME/infra-hosts.csv"
cmp "$test_root/ssh.before" "$HOME/.ssh/config"
cmp "$test_root/config.before" "$SHELL_ALIAS_TOOLS_HOME/config"

printf 'Name,HostName,User,Port,Role,CheckPorts,Url,SshEnabled\nserver1,192.0.2.1,admin,22,docker,22;80,http://192.0.2.1,true\n' > "$INFRA_HOSTS_FILE"
cp "$INFRA_HOSTS_FILE" "$test_root/legacy.before"
_shell_tools_migrate_infra_hosts
legacy_backups=("$INFRA_HOSTS_FILE".bak.*)
cmp "$test_root/legacy.before" "${legacy_backups[0]}"

export SHELLDECK_TEST_SOURCE=1
. ./install.sh
mkdir -p "$HOME/.local/bin"
DRY_RUN=0
PATH="$PATH:$HOME/.local/bin/"
original_path="$PATH"
refresh_installer_session_path
case "$PATH" in "$original_path"*) ;; *) fail 'PATH refresh changed search order' ;; esac
refreshed_path="$PATH"
refresh_installer_session_path
[ "$PATH" = "$refreshed_path" ] || fail 'PATH refresh added duplicates'
DRY_RUN=1
refresh_installer_session_path
[ "$PATH" = "$refreshed_path" ] || fail 'dry-run changed PATH'
printf 'Bash preservation and Linux/macOS dry-run checks passed\n'
