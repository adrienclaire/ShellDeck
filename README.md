# Shell Alias Tools

Cross-platform shell bootstrap for fresh VMs, workstations, and homelab nodes.

It installs a profile runtime that turns your terminal startup into a small infra dashboard, keeps personal aliases/functions in one place, and helps onboard SSH hosts such as Proxmox, Docker VMs, and app servers.

## One-command install

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/adrienclaire/Shell-Alias-Tools/main/install.ps1 | iex
```

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/adrienclaire/Shell-Alias-Tools/main/install.sh | bash
```

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/adrienclaire/Shell-Alias-Tools/main/install.sh | bash
```

The Linux/macOS installer also has explicit local wrappers:

```bash
bash install-linux.sh
bash install-macos.sh
```

## What It Does

- Installs the shell runtime into `~/.shell-alias-tools`.
- Hooks the runtime into your PowerShell, Bash, or Zsh profile.
- Prints an `ENV READY` dashboard on shell startup with user, host, IP, disk, uptime, and infra host count.
- Turns Bash into a smarter daily shell with clean shared history, Bash completion, fzf key bindings, modern file listing, pretty file reading, smart directory jumping, and safe fallbacks.
- Installs or offers common CLI dependencies: `git`, `ssh`, `curl`, `fzf`, `bash-completion`, `bat`, `eza`, `zoxide`, `jq`, `gh`, and `nc` where supported.
- Shows a dependency checklist every install and asks directly about `git`, `ssh`, `curl`, `fzf`, `bash-completion`, `bat`, `eza`, `zoxide`, `jq`, `nc`, `gh`, `docker`, and `multipass`.
- Asks whether to enable inbound SSH on the new VM or machine.
- Asks whether to generate an ed25519 SSH key.
- Shows the public key and tells you how to copy it to the remote host.
- Adds SSH hosts to `~/.ssh/config`.
- Stores infra hosts in `~/.shell-alias-tools/infra-hosts.csv`.
- Tracks one host with many exposed service ports.

## Main Commands

```text
init          Infra dashboard and live host checks
shellsetup    Interactive first-run setup
infra-add     Add a server to infra config
infra-edit    Modify an existing server
infra-list    List configured servers
sshhosts      Pick an SSH host and connect
check-tools   Check local CLI dependencies
shelluninstall Remove profile hook and optionally delete local data
myhelp        Show all commands
```

Alias helpers:

```text
ll/la/l/lt    Modern directory listing with eza when available
cat/catp      Pretty file reading with bat or batcat when available
z/zi          Smart directory jumping with zoxide when available
cdf           Fuzzy cd into a directory with fzf
mkcd          Create a directory and cd into it
please        Re-run the previous command with sudo
aa            Save the previous command as an alias/function
laa           List aliases on Bash/Zsh
rma           Remove alias on Bash/Zsh
lf            List saved PowerShell functions
ep            Edit PowerShell profile
reloadp       Reload the profile runtime
```

## Smart Bash Layer

On interactive Bash shells, the runtime applies a Bash-compatible quality-of-life layer:

```bash
HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend cmdhist checkwinsize
PROMPT_COMMAND='history -a; history -c; history -r'
```

It sources `bash-completion` when installed, loads fzf key bindings and completion from common Linux and Homebrew paths, initializes zoxide, and defines modern aliases only when they do not already exist. Existing custom aliases saved with `aa` still win.

## Install Options

Windows:

```powershell
.\install.ps1 -Yes
.\install.ps1 -SkipDeps
.\install.ps1 -SkipInfra
```

Linux/macOS:

```bash
bash install.sh --yes
bash install.sh --skip-deps
bash install.sh --skip-infra
```

## Infra Config

The host setup flow is:

```text
Host alias (default: server1)
Host IPv4 (example: 192.168.1.X)
SSH access? yes/no
  SSH user (default: admin)
  SSH port
  Add to ~/.ssh/config? yes/no
Docker on this host? yes/no
Service endpoint? yes/no
  Protocol: http or https
  Port: 8000
  Port: 8222
```

Hosts are stored as CSV:

```csv
Name,HostName,SshEnabled,User,Port,InSshConfig,Docker,Services
server1,192.168.1.187,true,admin,22,true,true,http://192.168.1.187:8000;https://192.168.1.187:8222
```

If Docker is enabled and the host has SSH access, `init` will run `docker ps` over SSH and print exposed container URLs. It uses the SSH config alias when available, otherwise it connects with `ssh -p <port> <user>@<ip>`.

When adding a service to a host, enter the protocol and the port. For host `192.168.1.187`, protocol `https` with port `8222` saves `https://192.168.1.187:8222`.

## macOS Notes

Yes, `fzf` works on macOS. The installer treats it as a required dependency for the best experience and can install it with Homebrew. Shell Alias Tools uses `fzf` directly for `sshhosts` and `infra-edit`.

Docker and Multipass are heavier desktop tools on macOS, so the installer asks before installing each one.

## Files

```text
install.ps1        Windows installer
install.sh         Linux/macOS installer
install-linux.sh   Linux wrapper
install-macos.sh   macOS wrapper
alias-tools.ps1    PowerShell runtime
shell-tools.sh     Bash/Zsh runtime
alias-tools.md     Original Bash alias-tool example
```
