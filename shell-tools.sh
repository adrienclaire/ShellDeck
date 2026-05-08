# Shell Alias Tools - Bash/Zsh profile runtime
# Source this file from ~/.bashrc or ~/.zshrc.

export SHELL_ALIAS_TOOLS_HOME="${SHELL_ALIAS_TOOLS_HOME:-$HOME/.shell-alias-tools}"
export ALIAS_TOOLS_FILE="${ALIAS_TOOLS_FILE:-$SHELL_ALIAS_TOOLS_HOME/aliases.sh}"
export INFRA_HOSTS_FILE="${INFRA_HOSTS_FILE:-$SHELL_ALIAS_TOOLS_HOME/infra-hosts.csv}"

_shell_tools_has_tty() {
  [ -t 1 ]
}

if _shell_tools_has_tty; then
  ST_RESET="$(printf '\033[0m')"
  ST_CYAN="$(printf '\033[36m')"
  ST_GREEN="$(printf '\033[32m')"
  ST_YELLOW="$(printf '\033[33m')"
  ST_RED="$(printf '\033[31m')"
  ST_MAGENTA="$(printf '\033[35m')"
  ST_DIM="$(printf '\033[2m')"
else
  ST_RESET=""
  ST_CYAN=""
  ST_GREEN=""
  ST_YELLOW=""
  ST_RED=""
  ST_MAGENTA=""
  ST_DIM=""
fi

shell-tools-ensure-home() {
  mkdir -p "$SHELL_ALIAS_TOOLS_HOME" "$HOME/.ssh" 2>/dev/null || true
  [ -f "$ALIAS_TOOLS_FILE" ] || : > "$ALIAS_TOOLS_FILE"
  if [ ! -f "$INFRA_HOSTS_FILE" ]; then
    printf "Name,HostName,User,Port,Role,CheckPorts,Url,SshEnabled\n" > "$INFRA_HOSTS_FILE"
  fi
}

shell-tools-ensure-home

alias-tools-load() {
  [ -f "$ALIAS_TOOLS_FILE" ] && . "$ALIAS_TOOLS_FILE"
}

_alias_tools_valid_name() {
  case "$1" in
    ""|[0-9]*|*[!A-Za-z0-9_-]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

_alias_tools_escape_single_quotes() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

alias-tools-save() {
  local name="$1"
  local cmd="$2"
  local escaped
  local tmp

  if [ -z "$name" ] || [ -z "$cmd" ]; then
    echo 'Usage: alias-tools-save alias_name "command"'
    return 1
  fi

  if ! _alias_tools_valid_name "$name"; then
    echo "Alias names can use letters, numbers, underscore, and dash, and cannot start with a number."
    return 1
  fi

  shell-tools-ensure-home
  tmp="${ALIAS_TOOLS_FILE}.tmp.$$"
  grep -vE "^alias ${name}=" "$ALIAS_TOOLS_FILE" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$ALIAS_TOOLS_FILE"

  escaped="$(_alias_tools_escape_single_quotes "$cmd")"
  printf "alias %s='%s'\n" "$name" "$escaped" >> "$ALIAS_TOOLS_FILE"
  alias "$name=$cmd"
  printf "%sAlias added:%s %s -> %s\n" "$ST_GREEN" "$ST_RESET" "$name" "$cmd"
}

add-alias() {
  local name="$1"
  shift || true
  alias-tools-save "$name" "$*"
}

alias-tools-get-last-command() {
  fc -ln -1 | sed 's/^[[:space:]]*//'
}

add-alias-last() {
  local name="$1"
  local cmd

  if [ -z "$name" ]; then
    echo 'Usage: add-alias-last alias_name'
    return 1
  fi

  cmd="$(fc -ln -2 -2 2>/dev/null | sed 's/^[[:space:]]*//')"
  if [ -z "$cmd" ]; then
    echo "Could not read the previous command."
    return 1
  fi

  case "$cmd" in
    aa\ *|add-alias-last\ *|add-alias\ *|rm-alias\ *|list-alias*)
      echo "Ignored command: $cmd"
      return 1
      ;;
  esac

  alias-tools-save "$name" "$cmd"
}

add-alias-from-history() {
  local name="$1"
  shift || true
  local cmd="$*"

  if [ -z "$name" ] || [ -z "$cmd" ]; then
    echo 'Usage: add-alias-from-history alias_name !!'
    return 1
  fi

  if [ "$cmd" = "!!" ]; then
    cmd="$(fc -ln -2 -2 2>/dev/null | sed 's/^[[:space:]]*//')"
  fi

  [ -n "$cmd" ] || return 1
  alias-tools-save "$name" "$cmd"
}

rm-alias() {
  local name="$1"
  local tmp

  if [ -z "$name" ]; then
    echo 'Usage: rm-alias alias_name'
    return 1
  fi

  if [ ! -f "$ALIAS_TOOLS_FILE" ]; then
    echo "No alias file found: $ALIAS_TOOLS_FILE"
    return 1
  fi

  tmp="${ALIAS_TOOLS_FILE}.tmp.$$"
  grep -vE "^alias ${name}=" "$ALIAS_TOOLS_FILE" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$ALIAS_TOOLS_FILE"
  unalias "$name" 2>/dev/null || true
  printf "%sAlias removed:%s %s\n" "$ST_YELLOW" "$ST_RESET" "$name"
}

list-alias() {
  if [ ! -f "$ALIAS_TOOLS_FILE" ]; then
    echo "No custom aliases found."
    return 1
  fi

  printf "%sCustom aliases%s\n" "$ST_CYAN" "$ST_RESET"
  printf "--------------------\n"

  while IFS= read -r line; do
    case "$line" in
      alias\ *=*) ;;
      alias\ *) ;;
      *) continue ;;
    esac

    local name="${line#alias }"
    name="${name%%=*}"
    local cmd="${line#*=}"
    cmd="$(printf "%s" "$cmd" | sed "s/^[\"']//; s/[\"']$//")"
    printf "%-20s -> %s\n" "$name" "$cmd"
  done < "$ALIAS_TOOLS_FILE"
}

_shell_tools_read_default() {
  local prompt="$1"
  local default="$2"
  local answer

  if [ -n "$default" ]; then
    printf "%s [%s]: " "$prompt" "$default" >&2
    read -r answer
    printf "%s" "${answer:-$default}"
  else
    printf "%s: " "$prompt" >&2
    read -r answer
    printf "%s" "$answer"
  fi
}

_shell_tools_yes_no() {
  local prompt="$1"
  local default="${2:-yes}"
  local suffix
  local answer

  if [ "$default" = "yes" ]; then
    suffix="Y/n"
  else
    suffix="y/N"
  fi

  while true; do
    printf "%s [%s]: " "$prompt" "$suffix" >&2
    read -r answer
    answer="$(printf "%s" "$answer" | tr '[:upper:]' '[:lower:]')"

    if [ -z "$answer" ]; then
      [ "$default" = "yes" ]
      return
    fi

    case "$answer" in
      y|yes|o|oui) return 0 ;;
      n|no|non) return 1 ;;
      *) echo "Please answer yes or no." >&2 ;;
    esac
  done
}

_shell_tools_csv_safe() {
  case "$1" in
    *","*|*$'\n'*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

_shell_tools_host_exists() {
  local name="$1"
  [ -f "$INFRA_HOSTS_FILE" ] && awk -F, -v host="$name" 'NR > 1 && $1 == host { found = 1 } END { exit found ? 0 : 1 }' "$INFRA_HOSTS_FILE"
}

_shell_tools_add_ssh_config() {
  local name="$1"
  local host="$2"
  local user="$3"
  local port="$4"
  local config="$HOME/.ssh/config"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh" 2>/dev/null || true
  touch "$config"
  chmod 600 "$config" 2>/dev/null || true

  if grep -Eq "^[[:space:]]*Host[[:space:]]+$name([[:space:]]|\$)" "$config"; then
    printf "%sSSH config already has Host %s.%s\n" "$ST_YELLOW" "$name" "$ST_RESET"
    return 0
  fi

  {
    printf "\nHost %s\n" "$name"
    printf "  HostName %s\n" "$host"
    printf "  User %s\n" "$user"
    printf "  Port %s\n" "$port"
    printf "  ServerAliveInterval 30\n"
    printf "  ServerAliveCountMax 3\n"
  } >> "$config"

  printf "%sSSH host added:%s ssh %s\n" "$ST_GREEN" "$ST_RESET" "$name"
}

_shell_tools_ensure_ssh_key() {
  local key="$HOME/.ssh/id_ed25519"
  local pub="$key.pub"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh" 2>/dev/null || true

  if [ ! -f "$pub" ]; then
    if _shell_tools_yes_no "No ed25519 SSH key found. Generate one now?" "yes"; then
      ssh-keygen -t ed25519 -C "$(id -un)@$(hostname)-shell-alias-tools" -f "$key"
    fi
  fi

  if [ -f "$pub" ]; then
    printf "\n%sPublic key ready:%s %s\n" "$ST_CYAN" "$ST_RESET" "$pub"
    cat "$pub"
    printf "\nCopy it to the remote host with:\n"
    printf "  ssh-copy-id -p <port> <user>@<host>\n"
  fi
}

infra-add() {
  local name="${1:-}"
  local host="${2:-}"
  local user="${3:-}"
  local port="${4:-22}"
  local role="${5:-}"
  local check_ports="${6:-}"
  local url="${7:-}"
  local ssh_enabled="true"
  local tmp

  shell-tools-ensure-home
  printf "\n%sInfra host onboarding%s\n" "$ST_CYAN" "$ST_RESET"

  [ -n "$name" ] || name="$(_shell_tools_read_default "Host alias" "proxmox")"
  [ -n "$host" ] || host="$(_shell_tools_read_default "Host/IP" "192.168.1.185")"
  [ -n "$user" ] || user="$(_shell_tools_read_default "SSH user" "root")"
  [ -n "$port" ] || port="$(_shell_tools_read_default "SSH port" "22")"
  [ -n "$role" ] || role="$(_shell_tools_read_default "Role" "proxmox")"

  if [ -z "$check_ports" ]; then
    case "$role" in
      *proxmox*|*Proxmox*) check_ports="$(_shell_tools_read_default "Ports to check, semicolon separated" "22;8006")" ;;
      *) check_ports="$(_shell_tools_read_default "Ports to check, semicolon separated" "22")" ;;
    esac
  fi

  if [ -z "$url" ]; then
    case "$role" in
      *proxmox*|*Proxmox*) url="https://$host:8006" ;;
      *) url="$(_shell_tools_read_default "Web URL, optional" "")" ;;
    esac
  fi

  for value in "$name" "$host" "$user" "$port" "$role" "$check_ports" "$url"; do
    if ! _shell_tools_csv_safe "$value"; then
      echo "Commas and newlines are not supported in infra values yet."
      return 1
    fi
  done

  if _shell_tools_yes_no "Add this host to ~/.ssh/config?" "yes"; then
    _shell_tools_ensure_ssh_key
    _shell_tools_add_ssh_config "$name" "$host" "$user" "$port"
    printf "When the key is installed on the host, connect with: ssh %s\n" "$name"
  else
    ssh_enabled="false"
  fi

  tmp="${INFRA_HOSTS_FILE}.tmp.$$"
  awk -F, -v host="$name" 'NR == 1 || $1 != host' "$INFRA_HOSTS_FILE" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$INFRA_HOSTS_FILE"
  printf "%s,%s,%s,%s,%s,%s,%s,%s\n" "$name" "$host" "$user" "$port" "$role" "$check_ports" "$url" "$ssh_enabled" >> "$INFRA_HOSTS_FILE"
  printf "%sInfra host saved:%s %s (%s)\n" "$ST_GREEN" "$ST_RESET" "$name" "$host"
}

infra-list() {
  shell-tools-ensure-home
  if [ "$(tail -n +2 "$INFRA_HOSTS_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" = "0" ]; then
    echo "No infra hosts configured."
    return 1
  fi

  awk -F, 'NR == 1 { next } { printf "%-14s %-15s %-10s %-6s %-12s %s\n", $1, $2, $3, $4, $5, $7 }' "$INFRA_HOSTS_FILE"
}

_shell_tools_primary_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }'
    return
  fi

  if command -v ipconfig >/dev/null 2>&1; then
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null
    return
  fi

  if command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{ print $1 }'
  fi
}

_shell_tools_uptime() {
  if uptime -p >/dev/null 2>&1; then
    uptime -p
  else
    uptime | sed 's/^[[:space:]]*//'
  fi
}

_shell_tools_disk() {
  df -h "$HOME" 2>/dev/null | awk 'NR == 2 { print $4 " free on " $6 }'
}

_shell_tools_ping() {
  local host="$1"

  case "$(uname -s)" in
    Darwin) ping -c 1 -W 1000 "$host" >/dev/null 2>&1 ;;
    *) ping -c 1 -W 1 "$host" >/dev/null 2>&1 ;;
  esac
}

_shell_tools_port_open() {
  local host="$1"
  local port="$2"

  if command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "$host" "$port" >/dev/null 2>&1
    return
  fi

  if [ -n "${BASH_VERSION:-}" ]; then
    (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1
    return
  fi

  return 2
}

_shell_tools_docker_scan() {
  local name="$1"
  local host="$2"
  local ssh_enabled="$3"
  local containers

  [ "$ssh_enabled" = "true" ] || return 0
  command -v ssh >/dev/null 2>&1 || return 0

  containers="$(ssh -o BatchMode=yes -o ConnectTimeout=3 "$name" "docker ps --format '{{.Names}}|{{.Ports}}'" 2>/dev/null || true)"
  [ -n "$containers" ] || return 0

  printf "\n%sDocker services on %s%s\n" "$ST_YELLOW" "$name" "$ST_RESET"
  printf "%s\n" "$containers" | while IFS='|' read -r container ports; do
    case "$ports" in
      *:[0-9]*-\>*)
        port="$(printf "%s" "$ports" | sed -n 's/.*:\([0-9][0-9]*\)->.*/\1/p' | head -n 1)"
        printf "  %sOK%s   %-22s http://%s:%s\n" "$ST_GREEN" "$ST_RESET" "$container" "$host" "$port"
        ;;
      *)
        printf "  %sINT%s  %-22s internal\n" "$ST_YELLOW" "$ST_RESET" "$container"
        ;;
    esac
  done
}

shellsetup() {
  printf "\n%sShell Alias Tools setup%s\n" "$ST_CYAN" "$ST_RESET"

  if [ "$(tail -n +2 "$INFRA_HOSTS_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" = "0" ]; then
    if _shell_tools_yes_no "Add your default Proxmox host at 192.168.1.185?" "yes"; then
      infra-add proxmox 192.168.1.185 root 22 proxmox "22;8006" "https://192.168.1.185:8006"
    fi
  fi

  while _shell_tools_yes_no "Add another infra server?" "no"; do
    infra-add
  done

  printf "%sSetup complete.%s Run init to open the infra dashboard.\n" "$ST_GREEN" "$ST_RESET"
}

init() {
  shell-tools-ensure-home
  printf "\n%sHOMELAB COMMAND CENTER%s\n\n" "$ST_CYAN" "$ST_RESET"

  if [ "$(tail -n +2 "$INFRA_HOSTS_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" = "0" ]; then
    echo "No infra hosts configured yet."
    if _shell_tools_yes_no "Run interactive setup now?" "yes"; then
      shellsetup
    else
      return 0
    fi
  fi

  tail -n +2 "$INFRA_HOSTS_FILE" 2>/dev/null | while IFS=, read -r name host user port role check_ports url ssh_enabled; do
    [ -n "$name" ] || continue

    if _shell_tools_ping "$host"; then
      printf "%s%-14s %-15s %-8s %-12s%s\n" "$ST_GREEN" "$name" "$host" "UP" "$role" "$ST_RESET"
    else
      printf "%s%-14s %-15s %-8s %-12s%s\n" "$ST_RED" "$name" "$host" "DOWN" "$role" "$ST_RESET"
    fi

    old_ifs="$IFS"
    IFS=';'
    for check_port in $check_ports; do
      IFS="$old_ifs"
      [ -n "$check_port" ] || continue
      if _shell_tools_port_open "$host" "$check_port"; then
        printf "  %sport %-6s OPEN%s\n" "$ST_GREEN" "$check_port" "$ST_RESET"
      else
        printf "  %sport %-6s CLOSED%s\n" "$ST_RED" "$check_port" "$ST_RESET"
      fi
      IFS=';'
    done
    IFS="$old_ifs"

    [ -n "$url" ] && printf "  %surl%s        %s\n" "$ST_CYAN" "$ST_RESET" "$url"

    case "$role" in
      *docker*|*Docker*) _shell_tools_docker_scan "$name" "$host" "$ssh_enabled" ;;
    esac
  done

  printf "\n"
}

sshhosts() {
  local config="$HOME/.ssh/config"
  local selected
  local choice

  if [ ! -f "$config" ]; then
    echo "No SSH config found."
    return 1
  fi

  if command -v fzf >/dev/null 2>&1; then
    selected="$(awk '/^[[:space:]]*Host[[:space:]]+/ && $2 !~ /[*?]/ { print $2 }' "$config" | sort -u | fzf --height 40% --layout reverse --border --prompt "SSH > ")"
  else
    awk '/^[[:space:]]*Host[[:space:]]+/ && $2 !~ /[*?]/ { print $2 }' "$config" | sort -u | nl -w2 -s') '
    printf "Connect to host number [1]: "
    read -r choice
    choice="${choice:-1}"
    selected="$(awk '/^[[:space:]]*Host[[:space:]]+/ && $2 !~ /[*?]/ { print $2 }' "$config" | sort -u | sed -n "${choice}p")"
  fi

  [ -n "$selected" ] && ssh "$selected"
}

check-tools() {
  local tool
  for tool in git ssh curl fzf gh docker multipass jq nc; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf "%-10s %sOK%s %s\n" "$tool" "$ST_GREEN" "$ST_RESET" "$(command -v "$tool")"
    else
      printf "%-10s %smissing%s\n" "$tool" "$ST_RED" "$ST_RESET"
    fi
  done
}

myhelp() {
  printf "\n%sCOMMANDS%s\n\n" "$ST_CYAN" "$ST_RESET"
  printf "init          Infra dashboard\n"
  printf "shellsetup    Interactive first-run setup\n"
  printf "infra-add     Add a server to infra config\n"
  printf "infra-list    List configured servers\n"
  printf "sshhosts      Pick an SSH host and connect\n"
  printf "check-tools   Check local CLI dependencies\n"
  printf "aa            Save the previous command as an alias\n"
  printf "laa           List aliases\n"
  printf "rma           Remove alias\n"
  printf "reloadp       Reload this shell runtime\n"
  printf "myhelp        Show this help\n\n"
}

reloadp() {
  . "$SHELL_ALIAS_TOOLS_HOME/shell-tools.sh"
  echo "Profile runtime reloaded."
}

shell-tools-dashboard() {
  [ "${SHELL_TOOLS_NO_DASHBOARD:-}" = "1" ] && return 0

  local ip
  local uptime_text
  local disk_text
  local host_count
  local shell_name

  ip="$(_shell_tools_primary_ip)"
  [ -n "$ip" ] || ip="unknown"
  uptime_text="$(_shell_tools_uptime)"
  disk_text="$(_shell_tools_disk)"
  host_count="$(tail -n +2 "$INFRA_HOSTS_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  shell_name="$(basename "${SHELL:-shell}")"

  printf "\n%s==========================================================%s\n" "$ST_DIM" "$ST_RESET"
  printf "%sENV READY - %s@%s%s\n" "$ST_CYAN" "$(id -un 2>/dev/null || whoami)" "$(hostname -s 2>/dev/null || hostname)" "$ST_RESET"
  printf "%sIP: %s | OS: %s | Shell: %s%s\n" "$ST_MAGENTA" "$ip" "$(uname -s)" "$shell_name" "$ST_RESET"
  printf "%sDisk: %s | Uptime: %s | Infra hosts: %s%s\n" "$ST_CYAN" "$disk_text" "$uptime_text" "$host_count" "$ST_RESET"
  printf "%s==========================================================%s\n" "$ST_DIM" "$ST_RESET"
  printf "init       -> infra dashboard\n"
  printf "sshhosts   -> connect to SSH host\n"
  printf "infra-add  -> add server\n"
  printf "check-tools-> dependency check\n"
  printf "myhelp     -> all commands\n\n"
}

alias aa='add-alias-last'
alias laa='list-alias'
alias rma='rm-alias'

alias-tools-load

case "$-" in
  *i*) shell-tools-dashboard ;;
esac
