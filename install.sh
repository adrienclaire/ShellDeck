#!/usr/bin/env bash
set -euo pipefail

RAW_BASE="${SHELL_ALIAS_TOOLS_RAW_BASE:-https://raw.githubusercontent.com/adrienclaire/Shell-Alias-Tools/main}"
INSTALL_DIR="${SHELL_ALIAS_TOOLS_HOME:-$HOME/.shell-alias-tools}"
ASSUME_YES=0
SKIP_DEPS=0
SKIP_INFRA=0
OS_OVERRIDE=""

usage() {
  cat <<'USAGE'
Shell Alias Tools installer for Linux and macOS.

Usage:
  bash install.sh [--yes] [--skip-deps] [--skip-infra] [--os linux|macos]

Examples:
  curl -fsSL https://raw.githubusercontent.com/adrienclaire/Shell-Alias-Tools/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/adrienclaire/Shell-Alias-Tools/main/install.sh | bash -s -- --yes
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)
      ASSUME_YES=1
      ;;
    --skip-deps)
      SKIP_DEPS=1
      ;;
    --skip-infra)
      SKIP_INFRA=1
      ;;
    --os)
      shift
      OS_OVERRIDE="${1:-}"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

color() {
  local code="$1"
  shift
  if [ -t 1 ]; then
    printf "\033[%sm%s\033[0m\n" "$code" "$*"
  else
    printf "%s\n" "$*"
  fi
}

info() {
  color "36" "$*"
}

ok() {
  color "32" "$*"
}

warn() {
  color "33" "$*"
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-yes}"
  local suffix
  local answer

  if [ "$ASSUME_YES" -eq 1 ]; then
    [ "$default" = "yes" ]
    return
  fi

  if [ "$default" = "yes" ]; then
    suffix="Y/n"
  else
    suffix="y/N"
  fi

  while true; do
    printf "%s [%s]: " "$prompt" "$suffix"
    read -r answer
    answer="$(printf "%s" "$answer" | tr '[:upper:]' '[:lower:]')"

    if [ -z "$answer" ]; then
      [ "$default" = "yes" ]
      return
    fi

    case "$answer" in
      y|yes|o|oui) return 0 ;;
      n|no|non) return 1 ;;
      *) echo "Please answer yes or no." ;;
    esac
  done
}

read_default() {
  local prompt="$1"
  local default="$2"
  local answer

  if [ "$ASSUME_YES" -eq 1 ]; then
    printf "%s" "$default"
    return
  fi

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

detect_os() {
  if [ -n "$OS_OVERRIDE" ]; then
    case "$OS_OVERRIDE" in
      linux|macos) printf "%s" "$OS_OVERRIDE" ;;
      *) echo "Unsupported --os value: $OS_OVERRIDE" >&2; exit 1 ;;
    esac
    return
  fi

  case "$(uname -s)" in
    Linux) printf "linux" ;;
    Darwin) printf "macos" ;;
    *) echo "Unsupported operating system: $(uname -s)" >&2; exit 1 ;;
  esac
}

sudo_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

download_file() {
  local url="$1"
  local target="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$target"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$target" "$url"
  else
    echo "Neither curl nor wget is available to download $url" >&2
    return 1
  fi
}

copy_runtime() {
  local script_path
  local script_dir

  mkdir -p "$INSTALL_DIR"
  script_path="${BASH_SOURCE[0]:-$0}"
  script_dir="$(cd "$(dirname "$script_path")" >/dev/null 2>&1 && pwd -P || pwd)"

  if [ -f "$script_dir/shell-tools.sh" ]; then
    cp "$script_dir/shell-tools.sh" "$INSTALL_DIR/shell-tools.sh"
  else
    info "Downloading shell runtime..."
    download_file "$RAW_BASE/shell-tools.sh" "$INSTALL_DIR/shell-tools.sh"
  fi

  chmod 644 "$INSTALL_DIR/shell-tools.sh"
  [ -f "$INSTALL_DIR/aliases.sh" ] || : > "$INSTALL_DIR/aliases.sh"
  if [ ! -f "$INSTALL_DIR/infra-hosts.csv" ]; then
    printf "Name,HostName,User,Port,Role,CheckPorts,Url,SshEnabled\n" > "$INSTALL_DIR/infra-hosts.csv"
  fi
}

profile_candidates() {
  local os="$1"

  if [ "$os" = "macos" ]; then
    printf "%s\n" "$HOME/.zshrc"
    [ -f "$HOME/.bashrc" ] && printf "%s\n" "$HOME/.bashrc"
    return
  fi

  case "${SHELL:-}" in
    *zsh) printf "%s\n" "$HOME/.zshrc" ;;
    *) printf "%s\n" "$HOME/.bashrc" ;;
  esac

  [ -f "$HOME/.zshrc" ] && printf "%s\n" "$HOME/.zshrc"
}

install_profile_hook() {
  local profile="$1"
  local source_line

  mkdir -p "$(dirname "$profile")"
  touch "$profile"

  if grep -q "shell-alias-tools" "$profile"; then
    warn "Profile already contains Shell Alias Tools hook: $profile"
    return
  fi

  source_line="[ -f \"$INSTALL_DIR/shell-tools.sh\" ] && . \"$INSTALL_DIR/shell-tools.sh\""
  {
    printf "\n# >>> shell-alias-tools >>>\n"
    printf "%s\n" "$source_line"
    printf "# <<< shell-alias-tools <<<\n"
  } >> "$profile"

  ok "Profile hook added: $profile"
}

install_linux_packages() {
  local packages=""

  if command -v apt-get >/dev/null 2>&1; then
    packages="ca-certificates curl git openssh-client fzf jq netcat-openbsd"
    sudo_cmd apt-get update
    sudo_cmd apt-get install -y $packages
  elif command -v dnf >/dev/null 2>&1; then
    packages="ca-certificates curl git openssh-clients fzf jq nmap-ncat"
    sudo_cmd dnf install -y $packages
  elif command -v pacman >/dev/null 2>&1; then
    packages="ca-certificates curl git openssh fzf jq gnu-netcat"
    sudo_cmd pacman -Sy --needed --noconfirm $packages
  elif command -v apk >/dev/null 2>&1; then
    packages="ca-certificates curl git openssh-client fzf jq netcat-openbsd"
    sudo_cmd apk add --no-cache $packages
  else
    warn "No supported package manager found. Please install: git curl ssh fzf jq nc"
  fi
}

install_macos_packages() {
  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew is not installed."
    if prompt_yes_no "Install Homebrew now?" "no"; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"
    else
      return
    fi
  fi

  if command -v brew >/dev/null 2>&1; then
    brew install git fzf jq gh || true
  fi
}

install_dependencies() {
  local os="$1"
  local missing=""
  local tool

  for tool in git ssh curl fzf jq nc; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing="$missing $tool"
    fi
  done

  if [ -z "$missing" ]; then
    ok "Recommended CLI tools are already present."
    return
  fi

  warn "Missing recommended tools:$missing"
  if ! prompt_yes_no "Install recommended CLI dependencies?" "yes"; then
    return
  fi

  case "$os" in
    linux) install_linux_packages ;;
    macos) install_macos_packages ;;
  esac
}

enable_ssh_server_linux() {
  if command -v apt-get >/dev/null 2>&1; then
    sudo_cmd apt-get update
    sudo_cmd apt-get install -y openssh-server
  elif command -v dnf >/dev/null 2>&1; then
    sudo_cmd dnf install -y openssh-server
  elif command -v pacman >/dev/null 2>&1; then
    sudo_cmd pacman -Sy --needed --noconfirm openssh
  elif command -v apk >/dev/null 2>&1; then
    sudo_cmd apk add --no-cache openssh-server
  fi

  if command -v systemctl >/dev/null 2>&1; then
    sudo_cmd systemctl enable --now ssh 2>/dev/null || sudo_cmd systemctl enable --now sshd
  else
    sudo_cmd service ssh start 2>/dev/null || sudo_cmd service sshd start 2>/dev/null || true
  fi
}

enable_ssh_server_macos() {
  sudo_cmd systemsetup -setremotelogin on
}

configure_local_ssh_server() {
  local os="$1"

  if ! prompt_yes_no "Enable inbound SSH server on this machine/VM?" "no"; then
    return
  fi

  case "$os" in
    linux) enable_ssh_server_linux ;;
    macos) enable_ssh_server_macos ;;
  esac
}

ensure_ssh_key() {
  local key="$HOME/.ssh/id_ed25519"
  local pub="$key.pub"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh" 2>/dev/null || true

  if [ ! -f "$pub" ]; then
    if prompt_yes_no "Generate an ed25519 SSH key?" "yes"; then
      ssh-keygen -t ed25519 -C "$(id -un)@$(hostname)-shell-alias-tools" -f "$key"
    fi
  fi

  if [ -f "$pub" ]; then
    printf "\nPublic key:\n"
    cat "$pub"
    printf "\nCopy it to a remote host with:\n"
    printf "  ssh-copy-id -p <port> <user>@<host>\n\n"
  fi
}

add_ssh_config_host() {
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
    warn "SSH config already contains Host $name."
    return
  fi

  {
    printf "\nHost %s\n" "$name"
    printf "  HostName %s\n" "$host"
    printf "  User %s\n" "$user"
    printf "  Port %s\n" "$port"
    printf "  ServerAliveInterval 30\n"
    printf "  ServerAliveCountMax 3\n"
  } >> "$config"

  ok "SSH config added: ssh $name"
}

add_infra_host() {
  local name="$1"
  local host="$2"
  local user="$3"
  local port="$4"
  local role="$5"
  local check_ports="$6"
  local url="$7"
  local ssh_enabled="false"
  local hosts_file="$INSTALL_DIR/infra-hosts.csv"
  local tmp

  name="$(read_default "Host alias" "$name")"
  host="$(read_default "Host/IP" "$host")"
  user="$(read_default "SSH user" "$user")"
  port="$(read_default "SSH port" "$port")"
  role="$(read_default "Role" "$role")"
  check_ports="$(read_default "Ports to check, semicolon separated" "$check_ports")"
  url="$(read_default "Web URL, optional" "$url")"

  if prompt_yes_no "Add this host to ~/.ssh/config?" "yes"; then
    ssh_enabled="true"
    ensure_ssh_key
    add_ssh_config_host "$name" "$host" "$user" "$port"
    printf "When the key is installed on the host, connect with: ssh %s\n" "$name"
  fi

  tmp="${hosts_file}.tmp.$$"
  awk -F, -v host="$name" 'NR == 1 || $1 != host' "$hosts_file" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$hosts_file"
  printf "%s,%s,%s,%s,%s,%s,%s,%s\n" "$name" "$host" "$user" "$port" "$role" "$check_ports" "$url" "$ssh_enabled" >> "$hosts_file"
  ok "Infra host saved: $name ($host)"
}

configure_infra() {
  local hosts_file="$INSTALL_DIR/infra-hosts.csv"
  local host_count

  host_count="$(tail -n +2 "$hosts_file" 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"

  if [ "$host_count" = "0" ]; then
    if prompt_yes_no "Add your default Proxmox host at 192.168.1.185?" "yes"; then
      add_infra_host "proxmox" "192.168.1.185" "root" "22" "proxmox" "22;8006" "https://192.168.1.185:8006"
    fi
  fi

  while prompt_yes_no "Add another infra server?" "no"; do
    add_infra_host "server" "192.168.1.10" "$(id -un)" "22" "server" "22" ""
  done
}

main() {
  local os
  local profile

  os="$(detect_os)"
  info "Installing Shell Alias Tools for $os..."

  copy_runtime

  profile_candidates "$os" | while IFS= read -r profile; do
    [ -n "$profile" ] && install_profile_hook "$profile"
  done

  if [ "$SKIP_DEPS" -eq 0 ]; then
    install_dependencies "$os"
    configure_local_ssh_server "$os"
  fi

  if [ "$SKIP_INFRA" -eq 0 ]; then
    configure_infra
  fi

  ok "Install complete."
  printf "\nRestart your terminal or run:\n"
  printf "  source \"%s/shell-tools.sh\"\n" "$INSTALL_DIR"
  printf "\nThen try:\n"
  printf "  init\n"
  printf "  sshhosts\n"
  printf "  check-tools\n"
}

main
