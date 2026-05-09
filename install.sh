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
  local tty="/dev/tty"

  [ -e "$tty" ] || tty=""

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
    if [ -n "$tty" ]; then
      printf "%s [%s]: " "$prompt" "$suffix" > "$tty"
      IFS= read -r answer < "$tty"
    else
      printf "%s [%s]: " "$prompt" "$suffix"
      IFS= read -r answer
    fi
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
  local tty="/dev/tty"

  [ -e "$tty" ] || tty=""

  if [ "$ASSUME_YES" -eq 1 ]; then
    printf "%s" "$default"
    return
  fi

  if [ -n "$default" ]; then
    if [ -n "$tty" ]; then
      printf "%s [%s]: " "$prompt" "$default" > "$tty"
      IFS= read -r answer < "$tty"
    else
      printf "%s [%s]: " "$prompt" "$default" >&2
      IFS= read -r answer
    fi
    printf "%s" "${answer:-$default}"
  else
    if [ -n "$tty" ]; then
      printf "%s: " "$prompt" > "$tty"
      IFS= read -r answer < "$tty"
    else
      printf "%s: " "$prompt" >&2
      IFS= read -r answer
    fi
    printf "%s" "$answer"
  fi
}

valid_name() {
  printf "%s" "$1" | grep -Eq '^[A-Za-z][A-Za-z0-9._-]*$'
}

valid_ipv4() {
  printf "%s" "$1" |
    awk -F. '
      NF != 4 { exit 1 }
      {
        for (i = 1; i <= 4; i++) {
          if ($i !~ /^[0-9][0-9]?[0-9]?$/ || $i < 0 || $i > 255) exit 1
        }
      }
    '
}

valid_user() {
  printf "%s" "$1" | grep -Eq '^[A-Za-z0-9._-]+[$]?$'
}

valid_role() {
  [ -n "$1" ] && printf "%s" "$1" | grep -Eq '^[^,]+$'
}

valid_url() {
  [ -z "$1" ] || printf "%s" "$1" | grep -Eq '^https?://[^[:space:],]+$'
}

valid_port() {
  case "$1" in
    ""|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

normalize_ports() {
  printf "%s" "$1" |
    tr ',;[:space:]' '\n' |
    sed '/^$/d' |
    awk '
      $0 !~ /^[0-9]+$/ || $0 < 1 || $0 > 65535 { bad = 1; next }
      !seen[$0]++ { out = out sep $0; sep = ";" }
      END {
        if (bad || out == "") exit 1
        print out
      }
    '
}

read_validated() {
  local prompt="$1"
  local default="$2"
  local validator="$3"
  local error="$4"
  local value

  while true; do
    value="$(read_default "$prompt" "$default")"
    if "$validator" "$value"; then
      printf "%s" "$value"
      return
    fi
    warn "$error"
  done
}

read_ports() {
  local prompt="$1"
  local default="$2"
  local value
  local normalized

  while true; do
    value="$(read_default "$prompt" "$default")"
    normalized="$(normalize_ports "$value" 2>/dev/null || true)"
    if [ -n "$normalized" ]; then
      printf "%s" "$normalized"
      return
    fi
    warn "This is not a valid port list. Use values like 22;8006 or 22, 8006."
  done
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
    printf "Name,HostName,SshEnabled,User,Port,InSshConfig,Docker,Services\n" > "$INSTALL_DIR/infra-hosts.csv"
  fi
}

profile_candidates() {
  local os="$1"

  if [ "$os" = "macos" ]; then
    printf "%s\n" "$HOME/.zshrc"
    [ -f "$HOME/.bashrc" ] && printf "%s\n" "$HOME/.bashrc"
    return 0
  fi

  case "${SHELL:-}" in
    *zsh) printf "%s\n" "$HOME/.zshrc" ;;
    *) printf "%s\n" "$HOME/.bashrc" ;;
  esac

  [ -f "$HOME/.zshrc" ] && printf "%s\n" "$HOME/.zshrc"
  return 0
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

ensure_homebrew() {
  local default="${1:-yes}"

  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew is not installed."
    if prompt_yes_no "Install Homebrew now?" "$default"; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"
    else
      return
    fi
  fi
}

linux_package_for_tool() {
  local tool="$1"
  local manager="$2"

  case "$manager:$tool" in
    apt:git) printf "git" ;;
    apt:ssh) printf "openssh-client" ;;
    apt:curl) printf "curl" ;;
    apt:wget) printf "wget" ;;
    apt:fzf) printf "fzf" ;;
    apt:bash-completion) printf "bash-completion" ;;
    apt:bat) printf "bat" ;;
    apt:eza) printf "eza" ;;
    apt:zoxide) printf "zoxide" ;;
    apt:starship) printf "starship" ;;
    apt:ripgrep) printf "ripgrep" ;;
    apt:fd) printf "fd-find" ;;
    apt:jq) printf "jq" ;;
    apt:yq) printf "yq" ;;
    apt:nc) printf "netcat-openbsd" ;;
    apt:tree) printf "tree" ;;
    apt:unzip) printf "unzip" ;;
    apt:zip) printf "zip" ;;
    apt:rsync) printf "rsync" ;;
    apt:tmux) printf "tmux" ;;
    apt:btop) printf "btop" ;;
    apt:htop) printf "htop" ;;
    apt:duf) printf "duf" ;;
    apt:neovim) printf "neovim" ;;
    apt:gh) printf "gh" ;;
    apt:docker) printf "docker.io" ;;
    apt:multipass) printf "multipass" ;;
    dnf:git) printf "git" ;;
    dnf:ssh) printf "openssh-clients" ;;
    dnf:curl) printf "curl" ;;
    dnf:wget) printf "wget" ;;
    dnf:fzf) printf "fzf" ;;
    dnf:bash-completion) printf "bash-completion" ;;
    dnf:bat) printf "bat" ;;
    dnf:eza) printf "eza" ;;
    dnf:zoxide) printf "zoxide" ;;
    dnf:starship) printf "starship" ;;
    dnf:ripgrep) printf "ripgrep" ;;
    dnf:fd) printf "fd-find" ;;
    dnf:jq) printf "jq" ;;
    dnf:yq) printf "yq" ;;
    dnf:nc) printf "nmap-ncat" ;;
    dnf:tree) printf "tree" ;;
    dnf:unzip) printf "unzip" ;;
    dnf:zip) printf "zip" ;;
    dnf:rsync) printf "rsync" ;;
    dnf:tmux) printf "tmux" ;;
    dnf:btop) printf "btop" ;;
    dnf:htop) printf "htop" ;;
    dnf:duf) printf "duf" ;;
    dnf:neovim) printf "neovim" ;;
    dnf:gh) printf "gh" ;;
    dnf:docker) printf "docker" ;;
    dnf:multipass) printf "multipass" ;;
    pacman:git) printf "git" ;;
    pacman:ssh) printf "openssh" ;;
    pacman:curl) printf "curl" ;;
    pacman:wget) printf "wget" ;;
    pacman:fzf) printf "fzf" ;;
    pacman:bash-completion) printf "bash-completion" ;;
    pacman:bat) printf "bat" ;;
    pacman:eza) printf "eza" ;;
    pacman:zoxide) printf "zoxide" ;;
    pacman:starship) printf "starship" ;;
    pacman:ripgrep) printf "ripgrep" ;;
    pacman:fd) printf "fd" ;;
    pacman:jq) printf "jq" ;;
    pacman:yq) printf "yq" ;;
    pacman:nc) printf "gnu-netcat" ;;
    pacman:tree) printf "tree" ;;
    pacman:unzip) printf "unzip" ;;
    pacman:zip) printf "zip" ;;
    pacman:rsync) printf "rsync" ;;
    pacman:tmux) printf "tmux" ;;
    pacman:btop) printf "btop" ;;
    pacman:htop) printf "htop" ;;
    pacman:duf) printf "duf" ;;
    pacman:neovim) printf "neovim" ;;
    pacman:gh) printf "github-cli" ;;
    pacman:docker) printf "docker" ;;
    pacman:multipass) printf "multipass" ;;
    apk:git) printf "git" ;;
    apk:ssh) printf "openssh-client" ;;
    apk:curl) printf "curl" ;;
    apk:wget) printf "wget" ;;
    apk:fzf) printf "fzf" ;;
    apk:bash-completion) printf "bash-completion" ;;
    apk:bat) printf "bat" ;;
    apk:eza) printf "eza" ;;
    apk:zoxide) printf "zoxide" ;;
    apk:starship) printf "starship" ;;
    apk:ripgrep) printf "ripgrep" ;;
    apk:fd) printf "fd" ;;
    apk:jq) printf "jq" ;;
    apk:yq) printf "yq" ;;
    apk:nc) printf "netcat-openbsd" ;;
    apk:tree) printf "tree" ;;
    apk:unzip) printf "unzip" ;;
    apk:zip) printf "zip" ;;
    apk:rsync) printf "rsync" ;;
    apk:tmux) printf "tmux" ;;
    apk:btop) printf "btop" ;;
    apk:htop) printf "htop" ;;
    apk:duf) printf "duf" ;;
    apk:neovim) printf "neovim" ;;
    apk:gh) printf "github-cli" ;;
    apk:docker) printf "docker" ;;
    apk:multipass) printf "" ;;
    *) printf "" ;;
  esac
}

detect_linux_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    printf "apt"
  elif command -v dnf >/dev/null 2>&1; then
    printf "dnf"
  elif command -v pacman >/dev/null 2>&1; then
    printf "pacman"
  elif command -v apk >/dev/null 2>&1; then
    printf "apk"
  fi
}

apt_update_and_offer_upgrade() {
  local upgrades

  sudo_cmd apt-get update

  upgrades="$(apt list --upgradable 2>/dev/null | sed '1d' | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  upgrades="${upgrades:-0}"

  if [ "$upgrades" -gt 0 ] 2>/dev/null; then
    if prompt_yes_no "$upgrades package upgrade(s) are available. Run apt-get upgrade now?" "no"; then
      sudo_cmd apt-get upgrade -y
    fi
  fi
}

install_linux_dependency() {
  local tool="$1"
  local manager="$2"
  local package

  if [ "$tool" = "starship" ]; then
    package="$(linux_package_for_tool "$tool" "$manager")"
    if [ -n "$package" ]; then
      case "$manager" in
        apt) sudo_cmd apt-get install -y "$package" && return ;;
        dnf) sudo_cmd dnf install -y "$package" && return ;;
        pacman) sudo_cmd pacman -Sy --needed --noconfirm "$package" && return ;;
        apk) sudo_cmd apk add --no-cache "$package" && return ;;
      esac
    fi

    if command -v curl >/dev/null 2>&1 && prompt_yes_no "Package install failed for Starship. Use the official Starship installer?" "yes"; then
      if [ "$(id -u)" -eq 0 ]; then
        curl -fsSL https://starship.rs/install.sh | sh -s -- -y
      else
        curl -fsSL https://starship.rs/install.sh | sudo sh -s -- -y
      fi
    else
      return 1
    fi
    return
  fi

  if [ "$tool" = "multipass" ] && command -v snap >/dev/null 2>&1; then
    sudo_cmd snap install multipass
    return
  fi

  package="$(linux_package_for_tool "$tool" "$manager")"
  if [ -z "$package" ]; then
    warn "No known package mapping for $tool on this Linux distribution."
    return
  fi

  case "$manager" in
    apt) sudo_cmd apt-get install -y "$package" ;;
    dnf) sudo_cmd dnf install -y "$package" ;;
    pacman) sudo_cmd pacman -Sy --needed --noconfirm "$package" ;;
    apk) sudo_cmd apk add --no-cache "$package" ;;
  esac
}

install_macos_dependency() {
  local tool="$1"
  local required="${2:-yes}"

  ensure_homebrew "$required"
  command -v brew >/dev/null 2>&1 || return

  case "$tool" in
    docker) brew install --cask docker ;;
    multipass) brew install --cask multipass ;;
    bash-completion) brew install bash-completion@2 ;;
    ssh) brew install openssh ;;
    nc) brew install netcat ;;
    *) brew install "$tool" ;;
  esac
}

dependency_path() {
  local tool="$1"
  local candidate

  case "$tool" in
    bash-completion)
      for candidate in \
        /etc/bash_completion \
        /usr/share/bash-completion/bash_completion \
        /opt/homebrew/etc/profile.d/bash_completion.sh \
        /usr/local/etc/profile.d/bash_completion.sh; do
        [ -f "$candidate" ] && printf "%s" "$candidate" && return 0
      done
      return 1
      ;;
    bat)
      command -v bat 2>/dev/null || command -v batcat 2>/dev/null
      ;;
    nc)
      command -v nc 2>/dev/null || command -v ncat 2>/dev/null
      ;;
    ripgrep)
      command -v rg 2>/dev/null
      ;;
    fd)
      command -v fd 2>/dev/null || command -v fdfind 2>/dev/null
      ;;
    neovim)
      command -v nvim 2>/dev/null
      ;;
    *)
      command -v "$tool" 2>/dev/null
      ;;
  esac
}

install_dependencies() {
  local os="$1"
  local manager=""
  local tool
  local default
  local status
  local install_label
  local command_path
  local required_tools="git ssh curl wget fzf bash-completion bat eza zoxide starship ripgrep fd jq yq nc tree unzip zip rsync tmux btop htop duf neovim"
  local optional_tools="gh docker multipass"

  if [ "$os" = "linux" ]; then
    manager="$(detect_linux_package_manager)"
    if [ -n "$manager" ] && [ "$manager" = "apt" ]; then
      apt_update_and_offer_upgrade
    fi
  fi

  info "Dependency setup"
  info "On a new VM, answer yes to the smart-shell dependencies for the full cockpit experience."
  info "You will be asked about each dependency directly."

  for tool in $required_tools; do
    status="missing"
    command_path=""
    command_path="$(dependency_path "$tool" 2>/dev/null || true)"
    if [ -n "$command_path" ]; then
      status="installed at $command_path"
    fi

    default="yes"
    if [ -n "$command_path" ]; then
      default="no"
    fi

    install_label="Install/update smart-shell dependency '$tool'? ($status)"
    if ! prompt_yes_no "$install_label" "$default"; then
      warn "$tool is required for the best Shell Alias Tools experience. Some commands may fall back or fail."
      continue
    fi

    case "$os" in
      linux)
        if [ -z "$manager" ]; then
          warn "No supported package manager found. Please install $tool manually."
        else
          install_linux_dependency "$tool" "$manager" || warn "Could not install $tool automatically."
        fi
        ;;
      macos)
        install_macos_dependency "$tool" "yes" || warn "Could not install $tool automatically."
        ;;
    esac
  done

  for tool in $optional_tools; do
    status="missing"
    command_path=""
    command_path="$(dependency_path "$tool" 2>/dev/null || true)"
    if [ -n "$command_path" ]; then
      status="installed at $command_path"
    fi

    default="yes"
    if [ -n "$command_path" ] || [ "$tool" = "docker" ] || [ "$tool" = "multipass" ]; then
      default="no"
    fi

    install_label="Install/update optional dependency '$tool'? ($status)"
    if ! prompt_yes_no "$install_label" "$default"; then
      continue
    fi

    case "$os" in
      linux)
        if [ -z "$manager" ]; then
          warn "No supported package manager found. Please install $tool manually."
        else
          install_linux_dependency "$tool" "$manager" || warn "Could not install $tool automatically."
        fi
        ;;
      macos)
        install_macos_dependency "$tool" "no" || warn "Could not install $tool automatically."
        ;;
    esac
  done
}

enable_ssh_server_linux() {
  if command -v apt-get >/dev/null 2>&1; then
    apt_update_and_offer_upgrade
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

  name="$(read_validated "Host alias" "$name" valid_name "Use a host alias like server1, docker-vm, or app01. Letters, numbers, dot, dash, underscore; start with a letter.")"
  host="$(read_validated "Host IPv4, example 192.168.1.X" "$host" valid_ipv4 "This is not an IPv4 address. Example: 192.168.1.187.")"
  user="$(read_validated "SSH user" "$user" valid_user "Use a simple SSH user, like admin, ubuntu, or deploy.")"
  port="$(read_validated "SSH port" "$port" valid_port "This is not a valid TCP port. Use a number from 1 to 65535.")"
  role="$(read_validated "Role" "$role" valid_role "Role cannot be empty and cannot contain commas.")"
  check_ports="$(read_ports "Ports to check, semicolon separated" "$check_ports")"
  url="$(read_validated "Web URL, optional" "$url" valid_url "Use a full URL like http://192.168.1.187:8000, or leave it empty.")"

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

  export SHELL_TOOLS_NO_DASHBOARD=1
  # shellcheck disable=SC1091
  . "$INSTALL_DIR/shell-tools.sh"

  host_count="$(tail -n +2 "$hosts_file" 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"

  if [ "$host_count" = "0" ]; then
    if prompt_yes_no "Configure your first infra host now?" "yes"; then
      infra-add
    fi
  fi

  while prompt_yes_no "Add another infra server?" "no"; do
    infra-add
  done
}

main() {
  local os
  local profile
  local profile_list

  os="$(detect_os)"
  info "Installing Shell Alias Tools for $os..."

  copy_runtime

  profile_list="$(profile_candidates "$os")"
  printf "%s\n" "$profile_list" | while IFS= read -r profile; do
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
  printf "\nIMPORTANT: restart your terminal to apply the effect.\n"
  printf "Run this now to reload your current shell profile:\n"
  printf "  source \"%s\"\n" "$(printf "%s\n" "$profile_list" | sed -n '1p')"
  printf "If that profile file is not the one your shell uses, load the runtime directly:\n"
  printf "  source \"%s/shell-tools.sh\"\n" "$INSTALL_DIR"
  printf "\nThen try:\n"
  printf "  init\n"
  printf "  ll\n"
  printf "  ff\n"
  printf "  sshhosts\n"
  printf "  check-tools\n"
}

main
