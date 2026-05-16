#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf "FAIL: %s\n" "$*" >&2
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$work_dir/pam.d"

cat > "$work_dir/sshd_config" <<'CONFIG'
Port 22
#AuthenticationMethods password
PasswordAuthentication yes

Match User existing
    X11Forwarding no
CONFIG

cat > "$work_dir/pam.d/sshd" <<'PAM'
auth required pam_env.so
@include common-auth
account required pam_nologin.so
PAM

export SHELLDECK_TEST_SOURCE=1
export SHELLDECK_SSHD_CONFIG_FILE="$work_dir/sshd_config"
export SHELLDECK_PAM_DIR="$work_dir/pam.d"

# shellcheck source=../install.sh
. "$repo_root/install.sh"

sudo_cmd() {
  "$@"
}

sshd_set_option "AuthenticationMethods" "publickey,keyboard-interactive"

awk '
  /^Match[[:space:]]+/ { seen_match = 1 }
  /^AuthenticationMethods[[:space:]]+publickey,keyboard-interactive$/ {
    if (seen_match) exit 2
    found = 1
  }
  END { exit found ? 0 : 1 }
' "$work_dir/sshd_config" || fail "global AuthenticationMethods must be inserted before Match blocks"

sshd_set_match_user_option "adrienclaire" "AuthenticationMethods" "publickey,keyboard-interactive"

grep -Fxq "Match User adrienclaire" "$work_dir/sshd_config" || fail "Match User block was not added"
grep -Fxq "    AuthenticationMethods publickey,keyboard-interactive" "$work_dir/sshd_config" || fail "Match User AuthenticationMethods was not added"

pam_comment_sshd_common_auth

grep -Fxq "#@include common-auth" "$work_dir/pam.d/sshd" || fail "PAM common-auth include was not commented"
if grep -Eq '^[[:space:]]*@include[[:space:]]+common-auth' "$work_dir/pam.d/sshd"; then
  fail "PAM common-auth include is still active"
fi

printf "SSH MFA config regression checks passed\n"
