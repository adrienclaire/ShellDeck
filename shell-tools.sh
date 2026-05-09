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
  ST_BLUE="$(printf '\033[34m')"
  ST_MAGENTA="$(printf '\033[35m')"
  ST_DIM="$(printf '\033[2m')"
  ST_BOLD="$(printf '\033[1m')"
else
  ST_RESET=""
  ST_CYAN=""
  ST_GREEN=""
  ST_YELLOW=""
  ST_RED=""
  ST_BLUE=""
  ST_MAGENTA=""
  ST_DIM=""
  ST_BOLD=""
fi

shell-tools-ensure-home() {
  mkdir -p "$SHELL_ALIAS_TOOLS_HOME" "$HOME/.ssh" 2>/dev/null || true
  [ -f "$ALIAS_TOOLS_FILE" ] || : > "$ALIAS_TOOLS_FILE"
  if [ ! -f "$INFRA_HOSTS_FILE" ]; then
    printf "Name,HostName,SshEnabled,User,Port,InSshConfig,Docker,Services\n" > "$INFRA_HOSTS_FILE"
  elif head -n 1 "$INFRA_HOSTS_FILE" 2>/dev/null | grep -q '^Name,HostName,User,Port,Role,CheckPorts,Url,SshEnabled$'; then
    _shell_tools_migrate_infra_hosts
  fi
}

_shell_tools_migrate_infra_hosts() {
  local tmp="${INFRA_HOSTS_FILE}.tmp.$$"

  {
    printf "Name,HostName,SshEnabled,User,Port,InSshConfig,Docker,Services\n"
    tail -n +2 "$INFRA_HOSTS_FILE" 2>/dev/null |
      awk -F, 'NF >= 8 {
        docker = ($5 ~ /[Dd]ocker/) ? "true" : "false"
        services = $7
        print $1 "," $2 "," $8 "," $3 "," $4 "," $8 "," docker "," services
      }'
  } > "$tmp"

  mv "$tmp" "$INFRA_HOSTS_FILE"
}

shell-tools-ensure-home

_shell_tools_source_first() {
  local candidate

  for candidate in "$@"; do
    [ -f "$candidate" ] || continue
    # shellcheck disable=SC1090
    . "$candidate" >/dev/null 2>&1 || true
    return 0
  done

  return 1
}

_shell_tools_dependency_path() {
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

_shell_tools_fd_command() {
  _shell_tools_dependency_path fd
}

_shell_tools_editor() {
  if [ -n "${EDITOR:-}" ] && command -v "$EDITOR" >/dev/null 2>&1; then
    printf "%s" "$EDITOR"
  elif command -v nvim >/dev/null 2>&1; then
    printf "nvim"
  elif command -v vim >/dev/null 2>&1; then
    printf "vim"
  elif command -v nano >/dev/null 2>&1; then
    printf "nano"
  else
    printf "vi"
  fi
}

_shell_tools_sort_human() {
  if sort -h </dev/null >/dev/null 2>&1; then
    sort -h
  else
    sort
  fi
}

_shell_tools_smart_tool_list() {
  printf "%s\n" git ssh curl wget fzf bash-completion bat eza zoxide starship ripgrep fd jq yq nc tree unzip zip rsync tmux btop htop duf neovim gh docker multipass
}

_shell_tools_bat_command() {
  _shell_tools_dependency_path bat
}

_shell_tools_configure_history() {
  [ -n "${BASH_VERSION:-}" ] || return 0

  export HISTSIZE=100000
  export HISTFILESIZE=200000
  export HISTCONTROL=ignoreboth:erasedups

  shopt -s histappend cmdhist checkwinsize 2>/dev/null || true

  case ";${PROMPT_COMMAND:-};" in
    *";history -a; history -c; history -r;"*) ;;
    *)
      PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }history -a; history -c; history -r"
      export PROMPT_COMMAND
      ;;
  esac
}

_shell_tools_configure_completion() {
  [ -n "${BASH_VERSION:-}" ] || return 0

  _shell_tools_source_first \
    /etc/bash_completion \
    /usr/share/bash-completion/bash_completion \
    /opt/homebrew/etc/profile.d/bash_completion.sh \
    /usr/local/etc/profile.d/bash_completion.sh
}

_shell_tools_configure_fzf() {
  command -v fzf >/dev/null 2>&1 || return 0

  export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:---height 40% --layout=reverse --border --info=inline}"
  export FZF_CTRL_R_OPTS="${FZF_CTRL_R_OPTS:---height 40% --layout=reverse --border}"

  if [ -n "${BASH_VERSION:-}" ]; then
    _shell_tools_source_first \
      /usr/share/doc/fzf/examples/key-bindings.bash \
      /usr/share/doc/fzf/key-bindings.bash \
      /usr/share/fzf/key-bindings.bash \
      /usr/share/fzf/shell/key-bindings.bash \
      /opt/homebrew/opt/fzf/shell/key-bindings.bash \
      /usr/local/opt/fzf/shell/key-bindings.bash \
      "$HOME/.fzf/shell/key-bindings.bash"
    _shell_tools_source_first \
      /usr/share/doc/fzf/examples/completion.bash \
      /usr/share/doc/fzf/completion.bash \
      /usr/share/fzf/completion.bash \
      /usr/share/fzf/shell/completion.bash \
      /opt/homebrew/opt/fzf/shell/completion.bash \
      /usr/local/opt/fzf/shell/completion.bash \
      "$HOME/.fzf/shell/completion.bash"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    _shell_tools_source_first \
      /usr/share/doc/fzf/examples/key-bindings.zsh \
      /usr/share/fzf/key-bindings.zsh \
      /usr/share/fzf/shell/key-bindings.zsh \
      /opt/homebrew/opt/fzf/shell/key-bindings.zsh \
      /usr/local/opt/fzf/shell/key-bindings.zsh \
      "$HOME/.fzf/shell/key-bindings.zsh"
    _shell_tools_source_first \
      /usr/share/doc/fzf/examples/completion.zsh \
      /usr/share/fzf/completion.zsh \
      /usr/share/fzf/shell/completion.zsh \
      /opt/homebrew/opt/fzf/shell/completion.zsh \
      /usr/local/opt/fzf/shell/completion.zsh \
      "$HOME/.fzf/shell/completion.zsh"
  fi
}

_shell_tools_configure_zoxide() {
  command -v zoxide >/dev/null 2>&1 || return 0
  [ "${SHELL_TOOLS_ZOXIDE_READY:-}" = "1" ] && return 0

  if [ -n "${BASH_VERSION:-}" ]; then
    eval "$(zoxide init bash 2>/dev/null)" || true
  elif [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(zoxide init zsh 2>/dev/null)" || true
  fi

  export SHELL_TOOLS_ZOXIDE_READY=1
}

_shell_tools_configure_starship() {
  [ "${SHELL_TOOLS_NO_PROMPT:-}" = "1" ] && return 1
  command -v starship >/dev/null 2>&1 || return 1
  [ "${SHELL_TOOLS_STARSHIP_READY:-}" = "1" ] && return 0

  if [ -n "${BASH_VERSION:-}" ]; then
    eval "$(starship init bash 2>/dev/null)" || return 1
  elif [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(starship init zsh 2>/dev/null)" || return 1
  else
    return 1
  fi

  export SHELL_TOOLS_STARSHIP_READY=1
}

_shell_tools_git_branch() {
  local branch

  command -v git >/dev/null 2>&1 || return 0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  branch="$(git branch --show-current 2>/dev/null || true)"
  [ -n "$branch" ] || branch="$(git rev-parse --short HEAD 2>/dev/null || true)"
  [ -n "$branch" ] && printf " (%s)" "$branch"
}

_shell_tools_configure_prompt() {
  [ -n "${BASH_VERSION:-}" ] || return 0
  [ "${SHELL_TOOLS_NO_PROMPT:-}" = "1" ] && return 0
  [ "${SHELL_TOOLS_STARSHIP_READY:-}" = "1" ] && return 0

  PS1='\[\033[1;36m\]\u@\h\[\033[0m\] \[\033[1;34m\]\w\[\033[33m\]$(_shell_tools_git_branch)\[\033[0m\]\n\$ '
}

_shell_tools_alias_default() {
  local name="$1"
  shift || true

  alias "$name" >/dev/null 2>&1 || alias "$name=$*"
}

_shell_tools_apply_smart_aliases() {
  local bat_cmd

  if command -v eza >/dev/null 2>&1; then
    _shell_tools_alias_default ll "eza -lah --icons"
    _shell_tools_alias_default la "eza -a"
    _shell_tools_alias_default l "eza"
    _shell_tools_alias_default lt "eza --tree --level=2 --icons=auto --git"
  else
    _shell_tools_alias_default ll "ls -lah"
    _shell_tools_alias_default la "ls -A"
    _shell_tools_alias_default l "ls -CF"
  fi

  bat_cmd="$(_shell_tools_bat_command || true)"
  if [ -n "$bat_cmd" ]; then
    _shell_tools_alias_default cat "$bat_cmd"
    _shell_tools_alias_default catp "$bat_cmd --paging=always"
  fi

  _shell_tools_alias_default cls "clear"
  _shell_tools_alias_default c "clear"
  _shell_tools_alias_default h "history"
  _shell_tools_alias_default j "jobs -l"
  _shell_tools_alias_default g "git"
  _shell_tools_alias_default gs "git status"
  _shell_tools_alias_default ga "git add ."
  _shell_tools_alias_default gc "git commit -m"
  _shell_tools_alias_default gp "git push"
  _shell_tools_alias_default gl "git log --oneline --graph --decorate --all -20"
  _shell_tools_alias_default gd "git diff"
  _shell_tools_alias_default myip "curl ifconfig.me"
  _shell_tools_alias_default dfh "df -h"
  _shell_tools_alias_default .. "cd .."
  _shell_tools_alias_default ... "cd ../.."
  _shell_tools_alias_default .... "cd ../../.."
}

_shell_tools_configure_smart_shell() {
  _shell_tools_configure_history
  _shell_tools_configure_completion
  _shell_tools_configure_fzf
  _shell_tools_configure_zoxide
  _shell_tools_configure_starship || _shell_tools_configure_prompt
  _shell_tools_apply_smart_aliases
}

please() {
  local cmd

  cmd="$(fc -ln -2 -2 2>/dev/null | sed 's/^[[:space:]]*//')"
  [ -n "$cmd" ] || cmd="$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//')"
  if [ -z "$cmd" ]; then
    echo "No previous command found."
    return 1
  fi

  case "$cmd" in
    please|please\ *|sudo|sudo\ *)
      echo "Previous command already used privilege escalation."
      return 1
      ;;
  esac

  printf "%sRunning with sudo:%s %s\n" "$ST_YELLOW" "$ST_RESET" "$cmd"
  eval "sudo $cmd"
}

mkcd() {
  [ -n "${1:-}" ] || {
    echo "Usage: mkcd <directory>"
    return 1
  }

  mkdir -p "$1" && cd "$1" || return
}

cdf() {
  local root="${1:-.}"
  local dir
  local fd_cmd

  command -v fzf >/dev/null 2>&1 || {
    echo "fzf is missing. Run check-tools, then reinstall dependencies if needed."
    return 1
  }

  fd_cmd="$(_shell_tools_fd_command 2>/dev/null || true)"
  if [ -n "$fd_cmd" ]; then
    dir="$("$fd_cmd" --type d --hidden --exclude .git . "$root" 2>/dev/null | fzf --height 40% --layout=reverse --border --prompt "cd > ")" || return
  else
    dir="$(find "$root" -type d -not -path '*/.git/*' 2>/dev/null | fzf --height 40% --layout=reverse --border --prompt "cd > ")" || return
  fi

  [ -n "$dir" ] && cd "$dir" || return
}

ff() {
  local root="${1:-.}"
  local file
  local fd_cmd
  local bat_cmd
  local preview

  command -v fzf >/dev/null 2>&1 || {
    echo "fzf is missing. Run check-tools, then reinstall dependencies if needed."
    return 1
  }

  bat_cmd="$(_shell_tools_bat_command 2>/dev/null || true)"
  if [ -n "$bat_cmd" ]; then
    preview="$bat_cmd --style=numbers --color=always --line-range=:200 {} 2>/dev/null"
  else
    preview="sed -n '1,200p' {} 2>/dev/null"
  fi

  fd_cmd="$(_shell_tools_fd_command 2>/dev/null || true)"
  if [ -n "$fd_cmd" ]; then
    file="$("$fd_cmd" --type f --hidden --exclude .git . "$root" 2>/dev/null | fzf --height 70% --layout=reverse --border --preview "$preview" --prompt "file > ")" || return
  elif command -v rg >/dev/null 2>&1; then
    file="$(rg --files "$root" 2>/dev/null | fzf --height 70% --layout=reverse --border --preview "$preview" --prompt "file > ")" || return
  else
    file="$(find "$root" -type f -not -path '*/.git/*' 2>/dev/null | fzf --height 70% --layout=reverse --border --preview "$preview" --prompt "file > ")" || return
  fi

  [ -n "$file" ] && printf "%s\n" "$file"
}

fe() {
  local file
  local editor

  file="$(ff "${1:-.}")" || return
  [ -n "$file" ] || return 1
  editor="$(_shell_tools_editor)"
  "$editor" "$file"
}

extract() {
  local archive="${1:-}"

  [ -n "$archive" ] || {
    echo "Usage: extract <archive>"
    return 1
  }
  [ -f "$archive" ] || {
    echo "Archive not found: $archive"
    return 1
  }

  case "$archive" in
    *.tar.bz2|*.tbz2) tar xjf "$archive" ;;
    *.tar.gz|*.tgz) tar xzf "$archive" ;;
    *.tar.xz|*.txz) tar xJf "$archive" ;;
    *.tar) tar xf "$archive" ;;
    *.zip) unzip "$archive" ;;
    *.gz) gunzip "$archive" ;;
    *.bz2) bunzip2 "$archive" ;;
    *.xz) unxz "$archive" ;;
    *) echo "Unsupported archive: $archive"; return 1 ;;
  esac
}

serve() {
  local port="${1:-8000}"

  if command -v python3 >/dev/null 2>&1; then
    python3 -m http.server "$port"
  elif command -v python >/dev/null 2>&1; then
    python -m SimpleHTTPServer "$port"
  else
    echo "Python is missing, cannot start a quick file server."
    return 1
  fi
}

ports() {
  if command -v ss >/dev/null 2>&1; then
    ss -tulnp
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tulpen 2>/dev/null || netstat -an
  else
    echo "Neither ss nor netstat is available."
    return 1
  fi
}

dps() {
  if command -v docker >/dev/null 2>&1; then
    docker ps "$@"
  else
    echo "Docker is missing. Run check-tools, then install Docker if this VM should use it."
    return 1
  fi
}

dcu() {
  if command -v docker >/dev/null 2>&1; then
    docker compose up -d "$@"
  else
    echo "Docker is missing. Run check-tools, then install Docker if this VM should use it."
    return 1
  fi
}

dcd() {
  if command -v docker >/dev/null 2>&1; then
    docker compose down "$@"
  else
    echo "Docker is missing. Run check-tools, then install Docker if this VM should use it."
    return 1
  fi
}

dcl() {
  if command -v docker >/dev/null 2>&1; then
    docker compose logs -f "$@"
  else
    echo "Docker is missing. Run check-tools, then install Docker if this VM should use it."
    return 1
  fi
}

duh() {
  local target="${1:-.}"

  if du -h --max-depth=1 "$target" >/dev/null 2>&1; then
    du -h --max-depth=1 "$target" | _shell_tools_sort_human
  else
    du -hd 1 "$target" 2>/dev/null | _shell_tools_sort_human
  fi
}

pathlist() {
  printf "%s\n" "$PATH" | tr ':' '\n'
}

sysupdate() {
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get upgrade -y
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf upgrade -y
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Syu
  elif command -v apk >/dev/null 2>&1; then
    sudo apk update && sudo apk upgrade
  elif command -v brew >/dev/null 2>&1; then
    brew update && brew upgrade
  else
    echo "No supported package manager found."
    return 1
  fi
}

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
  local tty="/dev/tty"

  [ -e "$tty" ] || tty=""

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

_shell_tools_yes_no() {
  local prompt="$1"
  local default="${2:-yes}"
  local suffix
  local answer
  local tty="/dev/tty"

  [ -e "$tty" ] || tty=""

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
      printf "%s [%s]: " "$prompt" "$suffix" >&2
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
      *) echo "Please answer yes or no." >&2 ;;
    esac
  done
}

_shell_tools_valid_name() {
  printf "%s" "$1" | grep -Eq '^[A-Za-z][A-Za-z0-9._-]*$'
}

_shell_tools_valid_ipv4() {
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

_shell_tools_valid_user() {
  printf "%s" "$1" | grep -Eq '^[A-Za-z0-9._-]+[$]?$'
}

_shell_tools_valid_role() {
  [ -n "$1" ] && printf "%s" "$1" | grep -Eq '^[^,]+$'
}

_shell_tools_valid_url() {
  [ -z "$1" ] || printf "%s" "$1" | grep -Eq '^https?://[^[:space:],]+$'
}

_shell_tools_normalize_protocol() {
  printf "%s" "$1" | tr '[:upper:]' '[:lower:]'
}

_shell_tools_valid_protocol() {
  case "$(_shell_tools_normalize_protocol "$1")" in
    http|https) return 0 ;;
    *) return 1 ;;
  esac
}

_shell_tools_valid_service_address() {
  local value="$1"
  local port

  [ -n "$value" ] || return 1
  case "$value" in
    *","*|*";"*|*[[:space:]]*) return 1 ;;
  esac

  case "$value" in
    http://*|https://*) printf "%s" "$value" | grep -Eq '^https?://[^/:]+(:[0-9]{1,5})?(/.*)?$' ;;
    *:*) printf "%s" "$value" | grep -Eq '^[A-Za-z0-9._-]+:[0-9]{1,5}(/.*)?$' ;;
    *) printf "%s" "$value" | grep -Eq '^[A-Za-z0-9._-]+$' ;;
  esac || return 1

  port="$(_shell_tools_service_port "$value")"
  _shell_tools_valid_port "$port"
}

_shell_tools_normalize_service_address() {
  local value="$1"
  case "$value" in
    http://*|https://*) printf "%s" "$value" ;;
    *) printf "http://%s" "$value" ;;
  esac
}

_shell_tools_valid_port() {
  case "$1" in
    ""|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

_shell_tools_normalize_ports() {
  local input="$1"

  printf "%s" "$input" |
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

_shell_tools_read_validated() {
  local prompt="$1"
  local default="$2"
  local validator="$3"
  local error="$4"
  local value

  while true; do
    value="$(_shell_tools_read_default "$prompt" "$default")"
    if "$validator" "$value"; then
      printf "%s" "$value"
      return 0
    fi

    echo "$error" >&2
  done
}

_shell_tools_resolve_validated() {
  local value="$1"
  local prompt="$2"
  local default="$3"
  local validator="$4"
  local error="$5"

  if [ -n "$value" ] && "$validator" "$value"; then
    printf "%s" "$value"
    return 0
  fi

  if [ -n "$value" ]; then
    echo "'$value' is invalid. $error" >&2
  fi

  _shell_tools_read_validated "$prompt" "$default" "$validator" "$error"
}

_shell_tools_resolve_ports() {
  local value="$1"
  local prompt="$2"
  local default="$3"
  local normalized

  if [ -n "$value" ]; then
    normalized="$(_shell_tools_normalize_ports "$value" 2>/dev/null || true)"
    if [ -n "$normalized" ]; then
      printf "%s" "$normalized"
      return 0
    fi

    echo "'$value' is not a valid port list. Use values like 22;8006 or 22, 8006." >&2
  fi

  while true; do
    value="$(_shell_tools_read_default "$prompt" "$default")"
    normalized="$(_shell_tools_normalize_ports "$value" 2>/dev/null || true)"
    if [ -n "$normalized" ]; then
      printf "%s" "$normalized"
      return 0
    fi

    echo "This is not a valid port list. Use values like 22;8006 or 22, 8006." >&2
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

_shell_tools_read_services() {
  local host="$1"
  local existing="${2:-}"
  local services=""
  local service_protocol
  local service_port
  local normalized

  if [ -n "$existing" ]; then
    printf "\nExisting service endpoints:\n" >&2
    printf "%s\n" "$existing" | tr ';' '\n' | sed 's/^/  - /' >&2
    if _shell_tools_yes_no "Keep these service endpoints?" "yes"; then
      printf "%s" "$existing"
      return 0
    fi
  fi

  if ! _shell_tools_yes_no "Do you want to add a service endpoint?" "yes"; then
    printf ""
    return 0
  fi

  while true; do
    service_protocol="$(_shell_tools_read_validated "Service protocol, http or https" "http" _shell_tools_valid_protocol "Use http or https.")"
    service_protocol="$(_shell_tools_normalize_protocol "$service_protocol")"
    service_port="$(_shell_tools_read_default "Service port, example 8000, 80, 8222" "")"
    if _shell_tools_valid_port "$service_port"; then
      normalized="$service_protocol://$host:$service_port"
      if [ -z "$services" ]; then
        services="$normalized"
      else
        services="$services;$normalized"
      fi
    else
      echo "This is not a valid service port. Use a number from 1 to 65535, like 8000 or 8222." >&2
      continue
    fi

    _shell_tools_yes_no "Add another service endpoint?" "no" || break
  done

  printf "%s" "$services"
}

_shell_tools_host_exists() {
  local name="$1"
  [ -f "$INFRA_HOSTS_FILE" ] && awk -F, -v host="$name" 'NR > 1 && $1 == host { found = 1 } END { exit found ? 0 : 1 }' "$INFRA_HOSTS_FILE"
}

_shell_tools_save_infra_record() {
  local name="$1"
  local host="$2"
  local ssh_enabled="$3"
  local user="$4"
  local port="$5"
  local in_ssh_config="$6"
  local docker="$7"
  local services="$8"
  local old_name="${9:-}"
  local tmp

  shell-tools-ensure-home
  tmp="${INFRA_HOSTS_FILE}.tmp.$$"
  awk -F, -v host="$name" -v old="$old_name" 'NR == 1 || ($1 != host && (old == "" || $1 != old))' "$INFRA_HOSTS_FILE" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$INFRA_HOSTS_FILE"
  printf "%s,%s,%s,%s,%s,%s,%s,%s\n" "$name" "$host" "$ssh_enabled" "$user" "$port" "$in_ssh_config" "$docker" "$services" >> "$INFRA_HOSTS_FILE"
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

_shell_tools_remove_ssh_config_host() {
  local name="$1"
  local config="$HOME/.ssh/config"
  local tmp

  [ -f "$config" ] || return 0
  tmp="${config}.tmp.$$"
  awk -v host="$name" '
    /^[[:space:]]*Host[[:space:]]+/ {
      skip = 0
      for (i = 2; i <= NF; i++) {
        if ($i == host) skip = 1
      }
      if (skip) next
    }
    !skip { print }
  ' "$config" > "$tmp"
  mv "$tmp" "$config"
  chmod 600 "$config" 2>/dev/null || true
}

_shell_tools_set_ssh_config() {
  local name="$1"
  local host="$2"
  local user="$3"
  local port="$4"
  local old_name="${5:-}"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh" 2>/dev/null || true
  touch "$HOME/.ssh/config"
  chmod 600 "$HOME/.ssh/config" 2>/dev/null || true

  [ -z "$old_name" ] || _shell_tools_remove_ssh_config_host "$old_name"
  _shell_tools_remove_ssh_config_host "$name"

  {
    printf "\nHost %s\n" "$name"
    printf "  HostName %s\n" "$host"
    printf "  User %s\n" "$user"
    printf "  Port %s\n" "$port"
    printf "  ServerAliveInterval 30\n"
    printf "  ServerAliveCountMax 3\n"
  } >> "$HOME/.ssh/config"

  printf "%sSSH config updated:%s ssh %s\n" "$ST_GREEN" "$ST_RESET" "$name"
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
  local ssh_enabled="false"
  local user=""
  local port=""
  local in_ssh_config="false"
  local docker="false"
  local services=""

  shell-tools-ensure-home
  printf "\n%sInfra host onboarding%s\n" "$ST_CYAN" "$ST_RESET"

  name="$(_shell_tools_resolve_validated "$name" "Host alias" "server1" _shell_tools_valid_name "Use a host alias like server1, docker-vm, or app01. Letters, numbers, dot, dash, underscore; start with a letter.")"
  host="$(_shell_tools_resolve_validated "$host" "Host IPv4, example 192.168.1.X" "" _shell_tools_valid_ipv4 "This is not an IPv4 address. Example: 192.168.1.187.")"

  if _shell_tools_yes_no "SSH access to this host?" "yes"; then
    ssh_enabled="true"
    user="$(_shell_tools_resolve_validated "" "SSH user" "admin" _shell_tools_valid_user "Use a simple SSH user, like admin, ubuntu, or deploy.")"
    port="$(_shell_tools_resolve_validated "" "SSH port" "22" _shell_tools_valid_port "This is not a valid TCP port. Use a number from 1 to 65535.")"

    if _shell_tools_yes_no "Add this host to ~/.ssh/config?" "yes"; then
      in_ssh_config="true"
      _shell_tools_ensure_ssh_key
      _shell_tools_add_ssh_config "$name" "$host" "$user" "$port"
      printf "\nCopy the public key above to the host, then type:\n"
      printf "  ssh %s\n" "$name"
      printf "To list all SSH shortcuts, type:\n"
      printf "  sshhosts\n\n"
    fi
  fi

  if _shell_tools_yes_no "Does this host use Docker?" "no"; then
    docker="true"
    if [ "$ssh_enabled" != "true" ]; then
      echo "Docker discovery needs SSH later. You can still save the host now." >&2
    fi
  fi

  services="$(_shell_tools_read_services "$host" "")"

  for value in "$name" "$host" "$ssh_enabled" "$user" "$port" "$in_ssh_config" "$docker" "$services"; do
    if ! _shell_tools_csv_safe "$value"; then
      echo "Commas and newlines are not supported in infra values yet."
      return 1
    fi
  done

  _shell_tools_save_infra_record "$name" "$host" "$ssh_enabled" "$user" "$port" "$in_ssh_config" "$docker" "$services"
  printf "%sInfra host saved:%s %s (%s)\n" "$ST_GREEN" "$ST_RESET" "$name" "$host"
}

infra-list() {
  shell-tools-ensure-home
  if [ "$(tail -n +2 "$INFRA_HOSTS_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" = "0" ]; then
    echo "No infra hosts configured."
    return 1
  fi

  awk -F, 'NR == 1 { next } { printf "%-14s %-15s ssh:%-5s docker:%-5s services:%s\n", $1, $2, $3, $7, $8 }' "$INFRA_HOSTS_FILE"
}

_shell_tools_select_infra_host() {
  local requested="${1:-}"
  local selected
  local choice

  if [ -n "$requested" ] && _shell_tools_host_exists "$requested"; then
    printf "%s" "$requested"
    return 0
  fi

  if [ -n "$requested" ]; then
    echo "Infra host '$requested' was not found." >&2
  fi

  if [ "$(tail -n +2 "$INFRA_HOSTS_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" = "0" ]; then
    echo "No infra hosts configured." >&2
    return 1
  fi

  if command -v fzf >/dev/null 2>&1; then
    selected="$(tail -n +2 "$INFRA_HOSTS_FILE" | awk -F, '{ print $1 }' | sort -u | fzf --height 40% --layout reverse --border --prompt "Infra host > ")"
  else
    tail -n +2 "$INFRA_HOSTS_FILE" | awk -F, '{ print $1 }' | sort -u | nl -w2 -s') ' >&2
    choice="$(_shell_tools_read_default "Host number" "1")"
    choice="${choice:-1}"
    selected="$(tail -n +2 "$INFRA_HOSTS_FILE" | awk -F, '{ print $1 }' | sort -u | sed -n "${choice}p")"
  fi

  [ -n "$selected" ] || return 1
  printf "%s" "$selected"
}

infra-edit() {
  local requested="${1:-}"
  local selected
  local line
  local name host ssh_enabled user port in_ssh_config docker services
  local new_name new_host new_user new_port new_ssh_enabled new_in_ssh_config new_docker new_services

  shell-tools-ensure-home
  selected="$(_shell_tools_select_infra_host "$requested")" || return 1
  line="$(awk -F, -v host="$selected" 'NR > 1 && $1 == host { print; exit }' "$INFRA_HOSTS_FILE")"
  [ -n "$line" ] || return 1

  name="$(printf "%s\n" "$line" | awk -F, '{ print $1 }')"
  host="$(printf "%s\n" "$line" | awk -F, '{ print $2 }')"
  ssh_enabled="$(printf "%s\n" "$line" | awk -F, '{ print $3 }')"
  user="$(printf "%s\n" "$line" | awk -F, '{ print $4 }')"
  port="$(printf "%s\n" "$line" | awk -F, '{ print $5 }')"
  in_ssh_config="$(printf "%s\n" "$line" | awk -F, '{ print $6 }')"
  docker="$(printf "%s\n" "$line" | awk -F, '{ print $7 }')"
  services="$(printf "%s\n" "$line" | awk -F, '{ print $8 }')"

  printf "\n%sEditing infra host: %s%s\n" "$ST_CYAN" "$name" "$ST_RESET"
  new_name="$(_shell_tools_read_validated "Host alias" "$name" _shell_tools_valid_name "Use a host alias like server1, docker-vm, or app01.")"
  new_host="$(_shell_tools_read_validated "Host IPv4, example 192.168.1.X" "$host" _shell_tools_valid_ipv4 "This is not an IPv4 address. Example: 192.168.1.187.")"

  new_ssh_enabled="false"
  new_user=""
  new_port=""
  new_in_ssh_config="false"
  if _shell_tools_yes_no "SSH access to this host?" "$([ "$ssh_enabled" = "true" ] && printf yes || printf no)"; then
    new_ssh_enabled="true"
    new_user="$(_shell_tools_read_validated "SSH user" "${user:-admin}" _shell_tools_valid_user "Use a simple SSH user, like admin, ubuntu, or deploy.")"
    new_port="$(_shell_tools_read_validated "SSH port" "${port:-22}" _shell_tools_valid_port "This is not a valid TCP port. Use a number from 1 to 65535.")"

    if _shell_tools_yes_no "Update/add this host in ~/.ssh/config?" "$([ "$in_ssh_config" = "true" ] && printf yes || printf no)"; then
      new_in_ssh_config="true"
      _shell_tools_ensure_ssh_key
      _shell_tools_set_ssh_config "$new_name" "$new_host" "$new_user" "$new_port" "$name"
      printf "\nCopy the public key above to the host, then type:\n"
      printf "  ssh %s\n" "$new_name"
      printf "To list all SSH shortcuts, type:\n"
      printf "  sshhosts\n\n"
    fi
  fi

  new_docker="false"
  if _shell_tools_yes_no "Does this host use Docker?" "$([ "$docker" = "true" ] && printf yes || printf no)"; then
    new_docker="true"
  fi

  new_services="$(_shell_tools_read_services "$new_host" "$services")"

  _shell_tools_save_infra_record "$new_name" "$new_host" "$new_ssh_enabled" "$new_user" "$new_port" "$new_in_ssh_config" "$new_docker" "$new_services" "$name"
  printf "%sInfra host updated.%s\n" "$ST_GREEN" "$ST_RESET"
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

  if command -v ncat >/dev/null 2>&1; then
    ncat -z -w 2 "$host" "$port" >/dev/null 2>&1
    return
  fi

  if [ -n "${BASH_VERSION:-}" ]; then
    (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1
    return
  fi

  return 2
}

_shell_tools_service_host() {
  local service="$(_shell_tools_normalize_service_address "$1")"
  service="${service#http://}"
  service="${service#https://}"
  service="${service%%/*}"
  service="${service%%:*}"
  printf "%s" "$service"
}

_shell_tools_service_port() {
  local raw="$1"
  local service="$(_shell_tools_normalize_service_address "$raw")"
  local scheme="http"
  local authority
  local port

  case "$service" in
    https://*) scheme="https" ;;
  esac

  authority="${service#http://}"
  authority="${authority#https://}"
  authority="${authority%%/*}"

  case "$authority" in
    *:*)
      port="${authority##*:}"
      ;;
    *)
      if [ "$scheme" = "https" ]; then
        port="443"
      else
        port="80"
      fi
      ;;
  esac

  printf "%s" "$port"
}

_shell_tools_display_services() {
  local services="$1"
  local service
  local service_host
  local service_port

  [ -n "$services" ] || return 0

  printf "%s\n" "$services" | tr ';' '\n' | while IFS= read -r service; do
    [ -n "$service" ] || continue
    service_host="$(_shell_tools_service_host "$service")"
    service_port="$(_shell_tools_service_port "$service")"

    if _shell_tools_port_open "$service_host" "$service_port"; then
      printf "  %s%-9s%s %-34s %s%-6s%s %s:%s\n" "$ST_BLUE" "service" "$ST_RESET" "$service" "$ST_GREEN" "OPEN" "$ST_RESET" "$service_host" "$service_port"
    else
      printf "  %s%-9s%s %-34s %s%-6s%s %s:%s\n" "$ST_BLUE" "service" "$ST_RESET" "$service" "$ST_RED" "CLOSED" "$ST_RESET" "$service_host" "$service_port"
    fi
  done
}

_shell_tools_docker_scan() {
  local name="$1"
  local host="$2"
  local ssh_enabled="$3"
  local user="${4:-}"
  local port="${5:-22}"
  local in_ssh_config="${6:-false}"
  local containers
  local target

  [ "$ssh_enabled" = "true" ] || return 0
  command -v ssh >/dev/null 2>&1 || return 0

  if [ "$in_ssh_config" = "true" ]; then
    containers="$(ssh -o BatchMode=yes -o ConnectTimeout=3 "$name" "docker ps --format '{{.Names}}|{{.Ports}}'" 2>/dev/null || true)"
  elif [ -n "$user" ] && [ -n "$host" ] && [ -n "$port" ]; then
    target="$user@$host"
    containers="$(ssh -o BatchMode=yes -o ConnectTimeout=3 -p "$port" "$target" "docker ps --format '{{.Names}}|{{.Ports}}'" 2>/dev/null || true)"
  else
    return 0
  fi

  [ -n "$containers" ] || return 0

  printf "\n  %s%sDocker containers on %s%s\n" "$ST_YELLOW" "$ST_BOLD" "$name" "$ST_RESET"
  printf "%s\n" "$containers" | while IFS='|' read -r container ports; do
    case "$ports" in
      *:[0-9]*-\>*)
        port="$(printf "%s" "$ports" | sed -n 's/.*:\([0-9][0-9]*\)->.*/\1/p' | head -n 1)"
        printf "  %s%-9s%s %-34s %s%-6s%s http://%s:%s\n" "$ST_BLUE" "docker" "$ST_RESET" "$container" "$ST_GREEN" "OPEN" "$ST_RESET" "$host" "$port"
        ;;
      *)
        printf "  %s%-9s%s %-34s %s%-6s%s internal\n" "$ST_BLUE" "docker" "$ST_RESET" "$container" "$ST_YELLOW" "INT" "$ST_RESET"
        ;;
    esac
  done
}

shellsetup() {
  printf "\n%sShell Alias Tools setup%s\n" "$ST_CYAN" "$ST_RESET"

  if [ "$(tail -n +2 "$INFRA_HOSTS_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" = "0" ]; then
    if _shell_tools_yes_no "Configure your first infra host now?" "yes"; then
      infra-add
    fi
  fi

  while _shell_tools_yes_no "Add another infra server?" "no"; do
    infra-add
  done

  printf "%sSetup complete.%s Run init to open the infra dashboard.\n" "$ST_GREEN" "$ST_RESET"
}

init() {
  shell-tools-ensure-home
  printf "\n%s%s+------------------------------------------------------------+%s\n" "$ST_BLUE" "$ST_BOLD" "$ST_RESET"
  printf "%s%s| SHELL INFRA DASHBOARD                                      |%s\n" "$ST_BLUE" "$ST_BOLD" "$ST_RESET"
  printf "%s%s+------------------------------------------------------------+%s\n\n" "$ST_BLUE" "$ST_BOLD" "$ST_RESET"

  if [ "$(tail -n +2 "$INFRA_HOSTS_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" = "0" ]; then
    echo "No infra hosts configured yet."
    if _shell_tools_yes_no "Run interactive setup now?" "yes"; then
      shellsetup
    else
      return 0
    fi
  fi

  tail -n +2 "$INFRA_HOSTS_FILE" 2>/dev/null | while IFS=, read -r name host ssh_enabled user port in_ssh_config docker services; do
    [ -n "$name" ] || continue

    if _shell_tools_ping "$host"; then
      printf "%s%s%-14s%s %s%-15s%s %s%-6s%s ssh:%s%-5s%s docker:%s%-5s%s\n" "$ST_BOLD" "$ST_CYAN" "$name" "$ST_RESET" "$ST_MAGENTA" "$host" "$ST_RESET" "$ST_GREEN" "UP" "$ST_RESET" "$ST_YELLOW" "$ssh_enabled" "$ST_RESET" "$ST_YELLOW" "$docker" "$ST_RESET"
    else
      printf "%s%s%-14s%s %s%-15s%s %s%-6s%s ssh:%s%-5s%s docker:%s%-5s%s\n" "$ST_BOLD" "$ST_CYAN" "$name" "$ST_RESET" "$ST_MAGENTA" "$host" "$ST_RESET" "$ST_RED" "DOWN" "$ST_RESET" "$ST_YELLOW" "$ssh_enabled" "$ST_RESET" "$ST_YELLOW" "$docker" "$ST_RESET"
    fi

    if [ "$ssh_enabled" = "true" ] && [ -n "$port" ]; then
      if _shell_tools_port_open "$host" "$port"; then
        printf "  %s%-9s%s %-34s %s%-6s%s %s:%s\n" "$ST_BLUE" "ssh" "$ST_RESET" "ssh $name" "$ST_GREEN" "OPEN" "$ST_RESET" "$host" "$port"
      else
        printf "  %s%-9s%s %-34s %s%-6s%s %s:%s\n" "$ST_BLUE" "ssh" "$ST_RESET" "ssh $name" "$ST_RED" "CLOSED" "$ST_RESET" "$host" "$port"
      fi
    fi

    _shell_tools_display_services "$services"

    if [ "$docker" = "true" ]; then
      _shell_tools_docker_scan "$name" "$host" "$ssh_enabled" "$user" "$port" "$in_ssh_config"
    fi
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
  local tool_path

  _shell_tools_smart_tool_list | while IFS= read -r tool; do
    tool_path="$(_shell_tools_dependency_path "$tool" 2>/dev/null || true)"
    if [ -n "$tool_path" ]; then
      printf "%-16s %sOK%s %s\n" "$tool" "$ST_GREEN" "$ST_RESET" "$tool_path"
    else
      printf "%-16s %smissing%s\n" "$tool" "$ST_RED" "$ST_RESET"
    fi
  done
}

_shell_tools_smart_tool_summary() {
  local total=0
  local installed=0
  local tool
  local tool_path

  while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    total=$((total + 1))
    tool_path="$(_shell_tools_dependency_path "$tool" 2>/dev/null || true)"
    [ -n "$tool_path" ] && installed=$((installed + 1))
  done <<EOF
$(_shell_tools_smart_tool_list)
EOF

  printf "%s/%s" "$installed" "$total"
}

_shell_tools_remove_profile_hook() {
  local profile="$1"
  local tmp

  [ -f "$profile" ] || return 0
  tmp="${profile}.tmp.$$"
  awk '
    /# >>> shell-alias-tools >>>/ { skip = 1; next }
    /# <<< shell-alias-tools <<</ { skip = 0; next }
    !skip { print }
  ' "$profile" > "$tmp"
  mv "$tmp" "$profile"
  printf "%sRemoved profile hook:%s %s\n" "$ST_GREEN" "$ST_RESET" "$profile"
}

shelluninstall() {
  printf "\n%sShell Alias Tools uninstall%s\n" "$ST_CYAN" "$ST_RESET"

  if ! _shell_tools_yes_no "Remove Shell Alias Tools from your shell profiles?" "yes"; then
    return 0
  fi

  _shell_tools_remove_profile_hook "$HOME/.bashrc"
  _shell_tools_remove_profile_hook "$HOME/.zshrc"
  _shell_tools_remove_profile_hook "$HOME/.profile"

  if _shell_tools_yes_no "Delete $SHELL_ALIAS_TOOLS_HOME including aliases and infra config?" "no"; then
    rm -rf "$SHELL_ALIAS_TOOLS_HOME"
    printf "%sDeleted:%s %s\n" "$ST_GREEN" "$ST_RESET" "$SHELL_ALIAS_TOOLS_HOME"
  else
    printf "%sKept:%s %s. SSH config is left untouched.\n" "$ST_YELLOW" "$ST_RESET" "$SHELL_ALIAS_TOOLS_HOME"
  fi

  echo "Restart the terminal to finish unloading the current session."
}

myhelp() {
  printf "\n%sCOMMANDS%s\n\n" "$ST_CYAN" "$ST_RESET"
  printf "init          Infra dashboard\n"
  printf "shellsetup    Interactive first-run setup\n"
  printf "infra-add     Add a server to infra config\n"
  printf "infra-edit    Modify an infra server\n"
  printf "infra-list    List configured servers\n"
  printf "sshhosts      Pick an SSH host and connect\n"
  printf "check-tools   Check local CLI dependencies\n"
  printf "shelluninstall Remove profile hook and optional data\n"
  printf "ll/la/l/lt    Smart listing via eza when available\n"
  printf "cat/catp      Pretty file reading via bat when available\n"
  printf "z/zi          Smart directory jumping via zoxide when available\n"
  printf "cdf           Fuzzy cd into a directory with fzf\n"
  printf "ff            Fuzzy find a file with preview\n"
  printf "fe            Fuzzy find a file and open it in editor\n"
  printf "mkcd          Create a directory and cd into it\n"
  printf "please        Re-run the previous command with sudo\n"
  printf "extract       Extract common archive formats\n"
  printf "serve         Start a quick HTTP file server\n"
  printf "ports         Show listening TCP/UDP ports\n"
  printf "dps/dcu/dcd/dcl Docker ps, compose up/down/logs\n"
  printf "duh           Show first-level disk usage sorted by size\n"
  printf "pathlist      Print PATH one entry per line\n"
  printf "sysupdate     Update the VM with the detected package manager\n"
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
  local tool_summary

  ip="$(_shell_tools_primary_ip)"
  [ -n "$ip" ] || ip="unknown"
  uptime_text="$(_shell_tools_uptime)"
  disk_text="$(_shell_tools_disk)"
  host_count="$(tail -n +2 "$INFRA_HOSTS_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  shell_name="$(basename "${SHELL:-shell}")"
  tool_summary="$(_shell_tools_smart_tool_summary)"

  printf "\n%s==========================================================%s\n" "$ST_DIM" "$ST_RESET"
  printf "%sENV READY - %s@%s%s\n" "$ST_CYAN" "$(id -un 2>/dev/null || whoami)" "$(hostname -s 2>/dev/null || hostname)" "$ST_RESET"
  printf "%sIP: %s | OS: %s | Shell: %s%s\n" "$ST_MAGENTA" "$ip" "$(uname -s)" "$shell_name" "$ST_RESET"
  printf "%sDisk: %s | Uptime: %s | Infra hosts: %s%s\n" "$ST_CYAN" "$disk_text" "$uptime_text" "$host_count" "$ST_RESET"
  printf "%sSmart tools: %s | Try: ll, ff, fe, cdf, ports, sysupdate%s\n" "$ST_MAGENTA" "$tool_summary" "$ST_RESET"
  printf "%s==========================================================%s\n" "$ST_DIM" "$ST_RESET"
  printf "init       -> infra dashboard\n"
  printf "sshhosts   -> connect to SSH host\n"
  printf "ff         -> fuzzy file finder\n"
  printf "infra-add  -> add server\n"
  printf "infra-edit -> modify server\n"
  printf "check-tools-> dependency check\n"
  printf "myhelp     -> all commands\n\n"
}

alias aa='add-alias-last'
alias laa='list-alias'
alias rma='rm-alias'

alias-tools-load

case "$-" in
  *i*)
    _shell_tools_configure_smart_shell
    alias-tools-load
    shell-tools-dashboard
    ;;
esac
