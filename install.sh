#!/usr/bin/env bash
set -euo pipefail

SHELL_TOOLS_VERSION="${SHELL_TOOLS_VERSION:-0.1.2}"
SHELL_ALIAS_TOOLS_REF="${SHELL_ALIAS_TOOLS_REF:-v$SHELL_TOOLS_VERSION}"
RAW_BASE="${SHELL_ALIAS_TOOLS_RAW_BASE:-https://raw.githubusercontent.com/adrienclaire/ShellDeck/$SHELL_ALIAS_TOOLS_REF}"
INSTALL_DIR="${SHELL_ALIAS_TOOLS_HOME:-$HOME/.shell-alias-tools}"
ASSUME_YES=0
SKIP_DEPS=0
SKIP_INFRA=0
DRY_RUN=0
OS_OVERRIDE=""
INSTALL_MODE=""
MACHINE_PROFILE=""

usage() {
  cat <<'USAGE'
ShellDeck installer for Linux and macOS.

Usage:
  bash install.sh [--yes] [--dry-run] [--profile control|workstation] [--mode basic|complete|manual] [--skip-deps] [--skip-infra] [--os linux|macos]

Examples:
  curl -fsSLO https://raw.githubusercontent.com/adrienclaire/ShellDeck/v0.1.2/install.sh && bash install.sh
  bash install.sh --dry-run
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)
      ASSUME_YES=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --skip-deps)
      SKIP_DEPS=1
      ;;
    --skip-infra)
      SKIP_INFRA=1
      ;;
    --mode)
      shift
      if [ $# -eq 0 ]; then
        echo "Missing value for --mode" >&2
        usage
        exit 1
      fi
      INSTALL_MODE="${1:-}"
      ;;
    --profile|--role)
      shift
      if [ $# -eq 0 ]; then
        echo "Missing value for --profile" >&2
        usage
        exit 1
      fi
      MACHINE_PROFILE="${1:-}"
      ;;
    --os)
      shift
      if [ $# -eq 0 ]; then
        echo "Missing value for --os" >&2
        usage
        exit 1
      fi
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
  color "33" "$*" >&2
}

dry_run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    color "35" "[dry-run] $*" >&2
  fi
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

normalize_install_mode() {
  case "$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')" in
    1|b|basic) printf "basic" ;;
    2|c|complete|complet|full) printf "complete" ;;
    3|m|manual) printf "manual" ;;
    *) return 1 ;;
  esac
}

normalize_machine_profile() {
  case "$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')" in
    1|control|control-node|controlnode|management|manager|management-host|management-computer|admin|infra)
      printf "control"
      ;;
    2|workstation|desktop|laptop|dev|developer|personal)
      printf "workstation"
      ;;
    *)
      return 1
      ;;
  esac
}

choose_machine_profile() {
  local choice
  local normalized

  if [ -n "$MACHINE_PROFILE" ]; then
    normalized="$(normalize_machine_profile "$MACHINE_PROFILE" 2>/dev/null || true)"
    if [ -n "$normalized" ]; then
      printf "%s" "$normalized"
      return
    fi
    warn "Unknown machine profile '$MACHINE_PROFILE'. Use control or workstation." >&2
  fi

  if [ "$ASSUME_YES" -eq 1 ]; then
    printf "control"
    return
  fi

  info "Machine profile" >&2
  printf "  1) Control node - smart shell plus infra dashboard, SSH shortcuts, host/service checks\n" >&2
  printf "  2) Workstation  - smart shell only, no infra dashboard or SSH host management\n" >&2

  while true; do
    choice="$(read_default "Choose machine profile" "1")"
    normalized="$(normalize_machine_profile "$choice" 2>/dev/null || true)"
    if [ -n "$normalized" ]; then
      printf "%s" "$normalized"
      return
    fi
    warn "Choose 1 for Control node or 2 for Workstation." >&2
  done
}

choose_install_mode() {
  local choice
  local normalized

  if [ -n "$INSTALL_MODE" ]; then
    normalized="$(normalize_install_mode "$INSTALL_MODE" 2>/dev/null || true)"
    if [ -n "$normalized" ]; then
      printf "%s" "$normalized"
      return
    fi
    warn "Unknown install mode '$INSTALL_MODE'. Use basic, complete, or manual." >&2
  fi

  if [ "$ASSUME_YES" -eq 1 ]; then
    printf "basic"
    return
  fi

  info "Setup mode" >&2
  printf "  1) Basic    - install required smart-shell dependencies automatically\n" >&2
  printf "  2) Complete - install required dependencies plus Docker, Multipass, and GitHub CLI\n" >&2
  printf "  3) Manual   - ask before installing every dependency\n" >&2

  while true; do
    choice="$(read_default "Choose setup mode" "1")"
    normalized="$(normalize_install_mode "$choice" 2>/dev/null || true)"
    if [ -n "$normalized" ]; then
      printf "%s" "$normalized"
      return
    fi
    warn "Choose 1 for Basic, 2 for Complete, or 3 for Manual." >&2
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
  if [ "$DRY_RUN" -eq 1 ]; then
    dry_run "would run: $*"
    return 0
  fi

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

write_runtime_config() {
  local machine_profile="$1"
  local config_file="$INSTALL_DIR/config"

  if [ "$DRY_RUN" -eq 1 ]; then
    dry_run "would write $config_file with SHELLDECK_MACHINE_PROFILE=$machine_profile"
    return
  fi

  printf "SHELLDECK_MACHINE_PROFILE=%s\n" "$machine_profile" > "$config_file"
}

copy_runtime() {
  local machine_profile="$1"
  local script_path
  local script_dir

  if [ "$DRY_RUN" -eq 1 ]; then
    dry_run "would create $INSTALL_DIR and install shell-tools.sh, aliases.sh, and profile config"
    if [ "$machine_profile" = "control" ]; then
      dry_run "would create infra-hosts.csv for the control node profile"
    fi
    write_runtime_config "$machine_profile"
    return
  fi

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
  write_runtime_config "$machine_profile"
  if [ "$machine_profile" = "control" ] && [ ! -f "$INSTALL_DIR/infra-hosts.csv" ]; then
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

  if [ "$DRY_RUN" -eq 1 ]; then
    dry_run "would add shell profile hook to $profile"
    return
  fi

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
    apt:ufw) printf "ufw" ;;
    apt:fail2ban) printf "fail2ban" ;;
    apt:google-authenticator) printf "libpam-google-authenticator" ;;
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
    dnf:ufw) printf "ufw" ;;
    dnf:fail2ban) printf "fail2ban" ;;
    dnf:google-authenticator) printf "google-authenticator" ;;
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
    pacman:ufw) printf "ufw" ;;
    pacman:fail2ban) printf "fail2ban" ;;
    pacman:google-authenticator) printf "libpam-google-authenticator" ;;
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
    apk:ufw) printf "ufw" ;;
    apk:fail2ban) printf "fail2ban" ;;
    apk:google-authenticator) printf "" ;;
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

  if [ "$DRY_RUN" -eq 1 ]; then
    dry_run "would run apt-get update"
    dry_run "would count available upgrades and ask before apt-get upgrade -y"
    return
  fi

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

    if command -v curl >/dev/null 2>&1 && { [ "${SHELL_TOOLS_ALLOW_REMOTE_INSTALLERS:-0}" = "1" ] || prompt_yes_no "Package install failed for Starship. Use the official Starship installer?" "no"; }; then
      if [ "$(id -u)" -eq 0 ]; then
        curl -fsSL https://starship.rs/install.sh | sh -s -- -y
      else
        curl -fsSL https://starship.rs/install.sh | sudo sh -s -- -y
      fi
    else
      warn "Starship remote installer skipped. Set SHELL_TOOLS_ALLOW_REMOTE_INSTALLERS=1 to allow it non-interactively."
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

  if [ "$DRY_RUN" -eq 1 ]; then
    case "$tool" in
      docker|multipass) dry_run "would run: brew install --cask $tool" ;;
      bash-completion) dry_run "would run: brew install bash-completion@2" ;;
      ssh) dry_run "would run: brew install openssh" ;;
      nc) dry_run "would run: brew install netcat" ;;
      *) dry_run "would run: brew install $tool" ;;
    esac
    return
  fi

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
    fail2ban)
      command -v fail2ban-client 2>/dev/null || command -v fail2ban-server 2>/dev/null
      ;;
    *)
      command -v "$tool" 2>/dev/null
      ;;
  esac
}

install_dependencies() {
  local os="$1"
  local mode="$2"
  local machine_profile="${3:-control}"
  local manager=""
  local tool
  local default
  local status
  local install_label
  local command_path
  local required_tools="git ssh curl wget fzf bash-completion bat eza zoxide starship ripgrep fd jq yq nc tree unzip zip rsync tmux btop htop duf neovim"
  local optional_tools="gh docker multipass"

  if [ "$os" = "linux" ] && [ "$machine_profile" = "control" ]; then
    required_tools="$required_tools ufw fail2ban"
  fi

  if [ "$os" = "linux" ]; then
    manager="$(detect_linux_package_manager)"
    if [ -n "$manager" ] && [ "$manager" = "apt" ]; then
      apt_update_and_offer_upgrade
    fi
  fi

  info "Dependency setup"
  case "$mode" in
    basic)
      info "Basic mode: installing required smart-shell dependencies automatically."
      ;;
    complete)
      info "Complete mode: installing required dependencies plus Docker, Multipass, and GitHub CLI."
      ;;
    manual)
      info "Manual mode: you will be asked about every dependency."
      ;;
  esac

  for tool in $required_tools; do
    status="missing"
    command_path=""
    command_path="$(dependency_path "$tool" 2>/dev/null || true)"
    if [ -n "$command_path" ]; then
      status="installed at $command_path"
    fi

    if [ "$mode" = "manual" ]; then
      default="yes"
      if [ -n "$command_path" ]; then
        default="no"
      fi

      install_label="Install/update smart-shell dependency '$tool'? ($status)"
      if ! prompt_yes_no "$install_label" "$default"; then
        warn "$tool is required for the best Shell Alias Tools experience. Some commands may fall back or fail."
        continue
      fi
    elif [ -n "$command_path" ]; then
      ok "$tool already installed ($command_path)"
      continue
    else
      info "Installing required dependency: $tool"
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

  if [ "$mode" = "basic" ]; then
    info "Basic mode skips optional dependencies: $optional_tools"
    return
  fi

  for tool in $optional_tools; do
    status="missing"
    command_path=""
    command_path="$(dependency_path "$tool" 2>/dev/null || true)"
    if [ -n "$command_path" ]; then
      status="installed at $command_path"
    fi

    if [ "$mode" = "manual" ]; then
      default="yes"
      if [ -n "$command_path" ] || [ "$tool" = "docker" ] || [ "$tool" = "multipass" ]; then
        default="no"
      fi

      install_label="Install/update optional dependency '$tool'? ($status)"
      if ! prompt_yes_no "$install_label" "$default"; then
        continue
      fi
    elif [ -n "$command_path" ]; then
      ok "$tool already installed ($command_path)"
      continue
    else
      info "Installing optional dependency: $tool"
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

valid_positive_int() {
  case "$1" in
    ""|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] 2>/dev/null
}

valid_fail2ban_duration() {
  printf "%s" "$1" | grep -Eq '^[0-9]+[smhdw]?$'
}

valid_firewall_source() {
  local value="$1"
  local ip
  local prefix

  value="$(printf "%s" "$value" | tr '[:upper:]' '[:lower:]')"

  case "$value" in
    ""|*[[:space:]]*|*";"*|*","*) return 1 ;;
    "*"|any) return 0 ;;
  esac

  if printf "%s" "$value" | grep -Eq '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.\*$'; then
    ip="${value%.*}.0"
    valid_ipv4 "$ip"
    return
  fi

  case "$value" in
    */*)
      ip="${value%/*}"
      prefix="${value#*/}"
      valid_ipv4 "$ip" || return 1
      case "$prefix" in ""|*[!0-9]*) return 1 ;; esac
      [ "$prefix" -ge 0 ] 2>/dev/null && [ "$prefix" -le 32 ] 2>/dev/null
      ;;
    *)
      valid_ipv4 "$value"
      ;;
  esac
}

normalize_firewall_source() {
  local value="$1"

  value="$(printf "%s" "$value" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    "*"|any) printf "any" ;;
    *.*.*.\*) printf "%s.0/24" "${value%.*}" ;;
    *) printf "%s" "$value" ;;
  esac
}

read_firewall_source() {
  local prompt="$1"
  local default="$2"
  local value

  while true; do
    value="$(read_default "$prompt" "$default")"
    if valid_firewall_source "$value"; then
      normalize_firewall_source "$value"
      return
    fi
    warn "Use * for anywhere, an IPv4 like 192.168.1.10, a CIDR like 192.168.1.0/24, or a LAN wildcard like 192.168.1.*."
  done
}

valid_firewall_protocol() {
  case "$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')" in
    tcp|udp|both) return 0 ;;
    *) return 1 ;;
  esac
}

running_over_ssh() {
  [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_CLIENT:-}" ]
}

ufw_allow_port_rule() {
  local port="$1"
  local protocol="$2"
  local source="$3"

  protocol="$(printf "%s" "$protocol" | tr '[:upper:]' '[:lower:]')"
  if [ "$protocol" = "both" ]; then
    ufw_allow_port_rule "$port" "tcp" "$source"
    ufw_allow_port_rule "$port" "udp" "$source"
    return
  fi

  if [ "$source" = "any" ]; then
    sudo_cmd ufw allow "$port/$protocol"
  else
    sudo_cmd ufw allow from "$source" to any port "$port" proto "$protocol"
  fi
}

ufw_allow_icmp() {
  local source="$1"
  local source_arg=""
  local rule
  local tmp
  local before_rules="/etc/ufw/before.rules"

  if [ "$source" != "any" ]; then
    source_arg="-s $source "
  fi

  rule="-A ufw-before-input ${source_arg}-p icmp --icmp-type echo-request -j ACCEPT"

  if [ "$DRY_RUN" -eq 1 ]; then
    dry_run "would add ICMP echo-request rule to $before_rules: $rule"
    return
  fi

  if [ ! -f "$before_rules" ]; then
    warn "UFW before.rules was not found. Install/configure ufw first."
    return 1
  fi

  if sudo_cmd grep -Fq "$rule" "$before_rules"; then
    ok "ICMP rule already exists."
    return
  fi

  tmp="$(mktemp)"
  awk -v rule="$rule" '
    BEGIN { added = 0 }
    /^COMMIT$/ && !added {
      print rule
      added = 1
    }
    { print }
    END {
      if (!added) print rule
    }
  ' "$before_rules" > "$tmp"

  sudo_cmd cp "$before_rules" "${before_rules}.shell-alias-tools.bak"
  sudo_cmd cp "$tmp" "$before_rules"
  rm -f "$tmp"
  ok "ICMP echo-request rule added to UFW before.rules."
}

configure_ufw_firewall() {
  local ssh_port="22"
  local ssh_source
  local rule_type
  local port
  local protocol
  local source

  if [ "$DRY_RUN" -eq 0 ] && ! command -v ufw >/dev/null 2>&1; then
    warn "UFW is not installed, skipping firewall configuration."
    return
  fi

  if ! prompt_yes_no "Configure UFW firewall now?" "yes"; then
    return
  fi

  info "UFW defaults: deny incoming, allow outgoing."
  sudo_cmd ufw default deny incoming
  sudo_cmd ufw default allow outgoing

  if prompt_yes_no "Allow inbound SSH before enabling the firewall?" "yes"; then
    ssh_port="$(read_validated "SSH inbound port" "22" valid_port "Use a port number from 1 to 65535.")"
    ssh_source="$(read_firewall_source "SSH source (*, IPv4, CIDR, or 192.168.1.*)" "*")"
    ufw_allow_port_rule "$ssh_port" "tcp" "$ssh_source"
    CONFIGURED_SSH_PORT="$ssh_port"
  fi

  while prompt_yes_no "Add another firewall rule?" "no"; do
    rule_type="$(read_default "Rule type: port or icmp" "port")"
    rule_type="$(printf "%s" "$rule_type" | tr '[:upper:]' '[:lower:]')"

    case "$rule_type" in
      port)
        port="$(read_validated "Inbound port" "80" valid_port "Use a port number from 1 to 65535.")"
        protocol="$(read_validated "Protocol (tcp, udp, or both)" "tcp" valid_firewall_protocol "Use tcp, udp, or both.")"
        source="$(read_firewall_source "Source (*, IPv4, CIDR, or 192.168.1.*)" "*")"
        ufw_allow_port_rule "$port" "$protocol" "$source"
        ;;
      icmp|ping)
        source="$(read_firewall_source "ICMP source (*, IPv4, CIDR, or 192.168.1.*)" "*")"
        ufw_allow_icmp "$source" || true
        ;;
      *)
        warn "Use port for TCP/UDP services or icmp for ping."
        ;;
    esac
  done

  if running_over_ssh; then
    warn "Active SSH session detected. Enabling UFW can disconnect you if the SSH rule is wrong."
    if ! prompt_yes_no "I allowed the active SSH port and want to enable UFW now" "no"; then
      warn "UFW rules were prepared, but UFW was not enabled."
      sudo_cmd ufw status verbose || true
      return
    fi
    sudo_cmd ufw --force enable
  elif prompt_yes_no "Enable UFW now?" "yes"; then
    sudo_cmd ufw --force enable
  fi

  sudo_cmd ufw status verbose || true
}

configure_fail2ban() {
  local jail_file="/etc/fail2ban/jail.d/shell-alias-tools-sshd.conf"
  local tmp
  local ssh_port="${CONFIGURED_SSH_PORT:-22}"
  local maxretry
  local findtime
  local bantime

  if [ "$DRY_RUN" -eq 0 ] && ! command -v fail2ban-client >/dev/null 2>&1 && ! command -v fail2ban-server >/dev/null 2>&1; then
    warn "fail2ban is not installed, skipping fail2ban configuration."
    return
  fi

  if ! prompt_yes_no "Configure fail2ban protection for SSH?" "yes"; then
    return
  fi

  ssh_port="$(read_validated "SSH port for fail2ban jail" "$ssh_port" valid_port "Use a port number from 1 to 65535.")"
  maxretry="$(read_validated "Max SSH retries before ban" "5" valid_positive_int "Use a positive number.")"
  findtime="$(read_validated "Find time window (examples: 10m, 1h)" "10m" valid_fail2ban_duration "Use a value like 10m, 1h, or 3600.")"
  bantime="$(read_validated "Ban time (examples: 1h, 24h)" "1h" valid_fail2ban_duration "Use a value like 1h, 24h, or 3600.")"

  if [ "$DRY_RUN" -eq 1 ]; then
    dry_run "would write $jail_file with sshd port=$ssh_port maxretry=$maxretry findtime=$findtime bantime=$bantime"
    dry_run "would enable/restart fail2ban and check fail2ban-client status sshd"
    return
  fi

  tmp="$(mktemp)"
  {
    printf "[sshd]\n"
    printf "enabled = true\n"
    printf "port = %s\n" "$ssh_port"
    printf "filter = sshd\n"
    printf "backend = auto\n"
    printf "maxretry = %s\n" "$maxretry"
    printf "findtime = %s\n" "$findtime"
    printf "bantime = %s\n" "$bantime"
  } > "$tmp"

  sudo_cmd mkdir -p "$(dirname "$jail_file")"
  if [ -f "$jail_file" ]; then
    sudo_cmd cp "$jail_file" "${jail_file}.bak"
  fi
  sudo_cmd cp "$tmp" "$jail_file"
  rm -f "$tmp"

  if command -v systemctl >/dev/null 2>&1; then
    sudo_cmd systemctl enable --now fail2ban 2>/dev/null || sudo_cmd systemctl restart fail2ban 2>/dev/null || true
  else
    sudo_cmd service fail2ban restart 2>/dev/null || true
  fi

  sudo_cmd fail2ban-client status sshd 2>/dev/null || warn "fail2ban config was written, but the sshd jail is not reporting status yet."
}

pam_add_google_authenticator() {
  local service="$1"
  local module_line="$2"
  local pam_file="/etc/pam.d/$service"
  local tmp

  if [ "$DRY_RUN" -eq 1 ]; then
    dry_run "would prepend '$module_line' to $pam_file after creating a backup"
    return
  fi

  if [ ! -f "$pam_file" ]; then
    warn "PAM file not found: $pam_file"
    return 1
  fi

  if sudo_cmd grep -Eq 'pam_google_authenticator\.so' "$pam_file"; then
    ok "PAM already references google-authenticator for $service."
    return
  fi

  tmp="$(mktemp)"
  {
    printf "%s\n" "$module_line"
    cat "$pam_file"
  } > "$tmp"

  if [ ! -f "${pam_file}.shell-alias-tools.bak" ]; then
    sudo_cmd cp "$pam_file" "${pam_file}.shell-alias-tools.bak"
  fi
  sudo_cmd cp "$tmp" "$pam_file"
  rm -f "$tmp"
  ok "PAM MFA enabled for $service."
}

sshd_set_option() {
  local key="$1"
  local value="$2"
  local file="/etc/ssh/sshd_config"
  local tmp

  if [ "$DRY_RUN" -eq 1 ]; then
    dry_run "would set $key $value in $file after creating a backup"
    return
  fi

  if [ ! -f "$file" ]; then
    warn "sshd_config was not found. Install/enable the SSH server first."
    return 1
  fi

  tmp="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    BEGIN { lkey = tolower(key); done = 0 }
    {
      line = $0
      sub(/^[#[:space:]]*/, "", line)
      split(line, parts, /[[:space:]]+/)
      if (tolower(parts[1]) == lkey) {
        if (!done) {
          print key " " value
          done = 1
        }
        next
      }
      print
    }
    END {
      if (!done) print key " " value
    }
  ' "$file" > "$tmp"

  if [ ! -f "${file}.shell-alias-tools.bak" ]; then
    sudo_cmd cp "$file" "${file}.shell-alias-tools.bak"
  fi
  sudo_cmd cp "$tmp" "$file"
  rm -f "$tmp"
}

validate_sshd_config() {
  local sshd_cmd=""
  local file="/etc/ssh/sshd_config"
  local backup="${file}.shell-alias-tools.bak"

  if [ "$DRY_RUN" -eq 1 ]; then
    dry_run "would validate sshd config with sshd -t before reloading SSH"
    return 0
  fi

  sshd_cmd="$(command -v sshd 2>/dev/null || true)"
  if [ -z "$sshd_cmd" ] && [ -x /usr/sbin/sshd ]; then
    sshd_cmd="/usr/sbin/sshd"
  fi

  if [ -z "$sshd_cmd" ]; then
    warn "Could not find sshd to validate config. Skipping SSH reload."
    return 1
  fi

  if sudo_cmd "$sshd_cmd" -t; then
    return 0
  fi

  warn "sshd config validation failed."
  if [ -f "$backup" ]; then
    sudo_cmd cp "$backup" "$file"
    warn "Restored $file from $backup."
  fi
  return 1
}

reload_ssh_service() {
  if [ "$DRY_RUN" -eq 1 ]; then
    dry_run "would reload ssh/sshd"
    return
  fi

  if command -v systemctl >/dev/null 2>&1; then
    sudo_cmd systemctl reload ssh 2>/dev/null || sudo_cmd systemctl reload sshd 2>/dev/null || true
  else
    sudo_cmd service ssh reload 2>/dev/null || sudo_cmd service sshd reload 2>/dev/null || true
  fi
}

configure_linux_mfa() {
  local manager
  local target
  local module_line="auth required pam_google_authenticator.so nullok"

  if ! prompt_yes_no "Configure TOTP MFA with PAM for SSH/local login?" "no"; then
    return
  fi

  manager="$(detect_linux_package_manager)"
  if ! command -v google-authenticator >/dev/null 2>&1; then
    if [ -n "$manager" ]; then
      install_linux_dependency "google-authenticator" "$manager" || true
    fi
  fi

  if [ "$DRY_RUN" -eq 0 ] && ! command -v google-authenticator >/dev/null 2>&1; then
    warn "google-authenticator is not available on this system. Skipping MFA setup."
    return
  fi

  while true; do
    target="$(read_default "MFA target: ssh, local, both, or none" "ssh")"
    target="$(printf "%s" "$target" | tr '[:upper:]' '[:lower:]')"
    case "$target" in
      ssh|local|both|none) break ;;
      *) warn "Use ssh, local, both, or none." ;;
    esac
  done

  [ "$target" = "none" ] && return

  if prompt_yes_no "Require MFA immediately for every user? (no keeps nullok until users enroll)" "no"; then
    module_line="auth required pam_google_authenticator.so"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    dry_run "would run google-authenticator for user $(id -un) if requested"
  elif prompt_yes_no "Run google-authenticator now for user $(id -un)?" "yes"; then
    if [ -e /dev/tty ]; then
      google-authenticator < /dev/tty
    else
      google-authenticator
    fi
  fi

  case "$target" in
    ssh|both)
      pam_add_google_authenticator "sshd" "$module_line" || true
      sshd_set_option "UsePAM" "yes" || true
      sshd_set_option "KbdInteractiveAuthentication" "yes" || true
      sshd_set_option "ChallengeResponseAuthentication" "yes" || true
      if validate_sshd_config; then
        reload_ssh_service
      else
        warn "SSH service was not reloaded because validation failed."
      fi
      ;;
  esac

  case "$target" in
    local|both)
      pam_add_google_authenticator "login" "$module_line" || true
      ;;
  esac

  ok "TOTP MFA configuration step complete."
}

configure_linux_security() {
  local os="$1"

  [ "$os" = "linux" ] || return

  info "Linux security setup"
  configure_ufw_firewall
  configure_fail2ban
  configure_linux_mfa
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
  local machine_profile
  local profile
  local profile_list
  local mode="basic"

  os="$(detect_os)"
  machine_profile="$(choose_machine_profile)"
  info "Installing ShellDeck for $os as $machine_profile profile..."
  if [ "$DRY_RUN" -eq 1 ]; then
    warn "Dry run enabled: no files, packages, profiles, firewall rules, services, or PAM files will be changed."
  fi

  copy_runtime "$machine_profile"

  profile_list="$(profile_candidates "$os")"
  printf "%s\n" "$profile_list" | while IFS= read -r profile; do
    [ -n "$profile" ] && install_profile_hook "$profile"
  done

  if [ "$SKIP_DEPS" -eq 0 ]; then
    mode="$(choose_install_mode)"
    install_dependencies "$os" "$mode" "$machine_profile"
    if [ "$machine_profile" = "control" ]; then
      configure_local_ssh_server "$os"
      configure_linux_security "$os"
    else
      info "Workstation profile: skipping inbound SSH server, UFW/fail2ban, MFA, and infra host setup."
    fi
  fi

  if [ "$machine_profile" = "control" ] && [ "$SKIP_INFRA" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    configure_infra
  elif [ "$machine_profile" = "control" ] && [ "$SKIP_INFRA" -eq 0 ]; then
    dry_run "would load the runtime and offer interactive infra host setup"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    ok "Dry run complete."
    return
  fi

  ok "Install complete."
  printf "\nIMPORTANT: restart your terminal to apply the effect.\n"
  printf "Run this now to reload your current shell profile:\n"
  printf "  source \"%s\"\n" "$(printf "%s\n" "$profile_list" | sed -n '1p')"
  printf "If that profile file is not the one your shell uses, load the runtime directly:\n"
  printf "  source \"%s/shell-tools.sh\"\n" "$INSTALL_DIR"
  printf "\nThen try:\n"
  printf "  ll\n"
  printf "  ff\n"
  printf "  check-tools\n"
  if [ "$machine_profile" = "control" ]; then
    printf "  init\n"
    printf "  sshhosts\n"
    printf "  infra-add\n"
  fi
}

main
