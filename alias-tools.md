# Alias Tools Example

This project started from a small Bash alias helper. The production Bash/Zsh version now lives in [`shell-tools.sh`](shell-tools.sh), and the PowerShell version lives in [`alias-tools.ps1`](alias-tools.ps1).

Core idea:

```bash
export ALIAS_TOOLS_FILE="${HOME}/.aliases"

alias-tools-load() {
  [ -f "$ALIAS_TOOLS_FILE" ] && source "$ALIAS_TOOLS_FILE"
}

alias-tools-save() {
  local name="$1"
  local cmd="$2"

  if [ -z "$name" ] || [ -z "$cmd" ]; then
    echo 'Usage: alias-tools-save alias_name "command"'
    return 1
  fi

  touch "$ALIAS_TOOLS_FILE"
  grep -vE "^alias ${name}=" "$ALIAS_TOOLS_FILE" > "${ALIAS_TOOLS_FILE}.tmp" 2>/dev/null || true
  mv "${ALIAS_TOOLS_FILE}.tmp" "$ALIAS_TOOLS_FILE"

  echo "alias $name='$cmd'" >> "$ALIAS_TOOLS_FILE"
  source "$ALIAS_TOOLS_FILE"
}

alias aa='add-alias-last'
alias laa='list-alias'
alias rma='rm-alias'
```

The current runtime extends this with:

- startup dashboard
- dependency checks
- SSH key and host onboarding
- infra host storage
- Proxmox and Docker service checks
