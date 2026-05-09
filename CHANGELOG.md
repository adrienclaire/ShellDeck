# Changelog

## 0.1.1 - 2026-05-09

- Fixed CI workflow issues found by the first production-readiness run.
- Kept ShellCheck advisory non-blocking while preserving parser and security checks as blocking gates.

## 0.1.0 - 2026-05-09

- First production-readiness baseline for ShellDeck.
- Added cross-platform install modes: Basic, Complete, and Manual.
- Added Linux UFW, fail2ban, and optional TOTP MFA setup prompts.
- Added smart Bash and PowerShell runtime dashboards, aliases, infra host setup, and dependency checks.
- Added CI validation, security policy, dry-run mode, and safer opt-in gates for risky helpers.
