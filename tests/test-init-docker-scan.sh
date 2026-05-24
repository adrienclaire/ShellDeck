#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf "FAIL: %s\n" "$*" >&2
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
fake_bin="$work_dir/bin"
mkdir -p "$fake_bin" "$work_dir/home/.shell-alias-tools"
trap 'rm -rf "$work_dir"' EXIT

cat > "$fake_bin/ping" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$fake_bin/nc" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$fake_bin/ssh" <<'EOF'
#!/usr/bin/env bash
read_stdin=1
for arg in "$@"; do
  [ "$arg" = "-n" ] && read_stdin=0
done
[ "$read_stdin" -eq 0 ] || cat >/dev/null
printf "paperless|0.0.0.0:8000->8000/tcp\n"
EOF

chmod +x "$fake_bin/ping" "$fake_bin/nc" "$fake_bin/ssh"

cat > "$work_dir/infra-hosts.csv" <<'EOF'
Name,HostName,SshEnabled,User,Port,InSshConfig,Docker,Services
first,192.168.1.10,true,admin,22,false,false,http://192.168.1.10:80
dockerhost,192.168.1.11,true,admin,22,false,true,http://192.168.1.11:8000
last,192.168.1.12,true,admin,22,false,false,http://192.168.1.12:8080
EOF

export HOME="$work_dir/home"
export PATH="$fake_bin:$PATH"
export INFRA_HOSTS_FILE="$work_dir/infra-hosts.csv"
export SHELL_ALIAS_TOOLS_HOME="$work_dir/home/.shell-alias-tools"
export SHELL_TOOLS_NO_DASHBOARD=1

# shellcheck source=../shell-tools.sh
. "$repo_root/shell-tools.sh"

output="$(init)"

printf "%s\n" "$output" | grep -Fq "first" || fail "init did not render the first host"
printf "%s\n" "$output" | grep -Fq "dockerhost" || fail "init did not render the Docker host"
printf "%s\n" "$output" | grep -Fq "last" || fail "init stopped before rendering the host after a Docker scan"

printf "init Docker scan stdin regression check passed\n"
