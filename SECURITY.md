# Security Policy

ShellDeck changes shell startup files, installs packages, and can optionally configure SSH, UFW, fail2ban, and PAM MFA. Treat it like infrastructure automation, not a cosmetic shell theme.

## Supported Versions

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |

## Safe Install Guidance

Prefer tagged release URLs over `main`:

```bash
curl -fsSLO https://raw.githubusercontent.com/adrienclaire/Shell-Alias-Tools/v0.1.0/install.sh
curl -fsSLO https://raw.githubusercontent.com/adrienclaire/Shell-Alias-Tools/v0.1.0/checksums.txt
sha256sum -c --ignore-missing checksums.txt
bash install.sh
```

On Windows:

```powershell
irm https://raw.githubusercontent.com/adrienclaire/Shell-Alias-Tools/v0.1.0/install.ps1 -OutFile install.ps1
irm https://raw.githubusercontent.com/adrienclaire/Shell-Alias-Tools/v0.1.0/checksums.txt -OutFile checksums.txt
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

These features are disabled or guarded by default:

- `please` re-runs the previous command with elevated privileges. Enable it with `SHELL_TOOLS_ENABLE_PLEASE=1`.
- PowerShell `add-func` stores executable function bodies. Enable it with `SHELL_TOOLS_ENABLE_CUSTOM_FUNCTIONS=1`.
- The Starship remote installer fallback is disabled by default. Enable it with `SHELL_TOOLS_ALLOW_REMOTE_INSTALLERS=1` or answer yes when prompted.

## Linux Hardening Notes

- UFW defaults are deny incoming and allow outgoing.
- Always allow your active SSH port before enabling UFW on a remote VM.
- If an active SSH session is detected, UFW enablement defaults to no after a lockout warning.
- TOTP MFA keeps `nullok` by default so unenrolled users are not locked out during rollout.
- SSH MFA changes validate `sshd -t` before reloading SSH and restore the installer backup if validation fails.
- Passkey/PAM U2F is not automated yet because it needs per-user hardware key enrollment and mapping.

## Reporting a Vulnerability

Open a private security advisory on GitHub if available, or contact the repository owner directly. Do not open a public issue for live secrets, lockout risks, or exploitable command injection paths.
