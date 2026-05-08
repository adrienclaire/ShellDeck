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
- Installs or offers common CLI dependencies: `git`, `ssh`, `curl`, `fzf`, `jq`, `gh`, and `nc` where supported.
- Shows a dependency checklist every install and asks directly about `git`, `ssh`, `curl`, `fzf`, `jq`, `nc`, `gh`, `docker`, and `multipass`.
- Asks whether to enable inbound SSH on the new VM or machine.
- Asks whether to generate an ed25519 SSH key.
- Shows the public key and tells you how to copy it to the remote host.
- Adds SSH hosts to `~/.ssh/config`.
- Stores infra hosts in `~/.shell-alias-tools/infra-hosts.csv`.
- Tracks one host with many exposed service addresses.

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
aa            Save the previous command as an alias/function
laa           List aliases on Bash/Zsh
rma           Remove alias on Bash/Zsh
lf            List saved PowerShell functions
ep            Edit PowerShell profile
reloadp       Reload the profile runtime
```

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
Host alias
Host IPv4
SSH access? yes/no
  SSH user
  SSH port
  Add to ~/.ssh/config? yes/no
Docker on this host? yes/no
Service address? yes/no
  http://paperless.home.arpa
  192.168.1.187:8000
```

Hosts are stored as CSV:

```csv
Name,HostName,SshEnabled,User,Port,InSshConfig,Docker,Services
proxmox,192.168.1.185,true,root,22,true,true,http://paperless.home.arpa;http://192.168.1.187:8000
```

If Docker is enabled and the host has SSH access, `init` will run `docker ps` over SSH and print exposed container URLs. It uses the SSH config alias when available, otherwise it connects with `ssh -p <port> <user>@<ip>`.

Service addresses can be URLs or host:port values. Host:port values are normalized with `http://` before saving.

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
