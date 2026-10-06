# Security Policy

ShellDeck changes shell startup files, installs packages, and can optionally configure SSH, UFW, fail2ban, and PAM MFA. Treat it like infrastructure automation, not a cosmetic shell theme.

## Supported Versions

| Version | Supported |
| --- | --- |
| 0.2.x | Yes |
| 0.1.x | Upgrade to 0.2.x |

## Safe Install Guidance

Before enabling SSH, firewall, fail2ban, or MFA automation on a production machine, test the full flow in a lab VM and take a snapshot or backup. Keep an active recovery session open while changing SSH/PAM/firewall settings. ShellDeck validates what it can, but you are responsible for confirming access works in your environment; the project cannot be responsible for lockouts, broken access, firewall mistakes, or production outages caused by local configuration choices.

Prefer tagged release URLs over `main`:

```bash
curl -fsSLO https://raw.githubusercontent.com/adrienclaire/ShellDeck/v0.2.6/install.sh
curl -fsSLO https://raw.githubusercontent.com/adrienclaire/ShellDeck/v0.2.6/checksums.txt
sha256sum -c --ignore-missing checksums.txt
bash install.sh
```

On Windows:

```powershell
irm https://raw.githubusercontent.com/adrienclaire/ShellDeck/v0.2.6/install.ps1 -OutFile install.ps1
irm https://raw.githubusercontent.com/adrienclaire/ShellDeck/v0.2.6/checksums.txt -OutFile checksums.txt
Get-FileHash .\install.ps1 -Algorithm SHA256
.\install.ps1
```

For a preview without changes, run:

```bash
bash install.sh --dry-run
```

```powershell
.\install.ps1 -DryRun
```

## Risky Features

Dry-run previews selected actions without writing files, installing packages, changing the process PATH, or loading the runtime. For a non-interactive preview, use `--dry-run --yes --classic-ui --profile workstation --mode basic` or `-DryRun -Yes -ClassicUi -MachineProfile workstation -Mode basic`.

The installer only appends missing directories to the process PATH. It does not write persistent User/Machine PATH; third-party package installers may change it themselves. Runtime updates replace only the runtime after syntax validation and a backup. Syntax validation is not signature verification or a sandbox.

`shelluninstall` removes marked profile hooks and keeps local user data by default. It does not remove CLI packages or undo SSH, UFW, fail2ban, or PAM configuration. Local alias/function files are executable code and must be treated as trusted user input.

These features are disabled or guarded by default:

- `please` re-runs the previous command with elevated privileges. Enable it with `SHELL_TOOLS_ENABLE_PLEASE=1`.
- PowerShell `add-func` stores executable function bodies. Enable it with `SHELL_TOOLS_ENABLE_CUSTOM_FUNCTIONS=1`.
- The Starship remote installer fallback is disabled by default. Enable it with `SHELL_TOOLS_ALLOW_REMOTE_INSTALLERS=1` or answer yes when prompted.

## Linux Hardening Notes

- UFW defaults are deny incoming and allow outgoing.
- Always allow your active SSH port before enabling UFW on a remote VM.
- If an active SSH session is detected, UFW enablement defaults to no after a lockout warning.
- TOTP MFA keeps `nullok` by default so unenrolled users are not locked out during rollout.
- SSH MFA can set `AuthenticationMethods publickey,keyboard-interactive` globally or in a `Match User` block for the current user.
- SSH MFA comments `@include common-auth` in `/etc/pam.d/sshd` so PAM does not request the account password after TOTP.
- SSH MFA changes validate `sshd -t` before offering to restart SSH and restore the installer backup if validation fails.
- Passkey/PAM U2F is not automated yet because it needs per-user hardware key enrollment and mapping.

## Reporting a Vulnerability

Open a private security advisory on GitHub if available, or contact the repository owner directly. Do not open a public issue for live secrets, lockout risks, or exploitable command injection paths.
