# Changelog

## Unreleased

- Added optional Gum-powered installer UI for richer choices, confirmations, inputs, and styled installer sections.
- Added `--ui auto|gum|classic`, `--gum-ui`, and `--classic-ui` for Bash/macOS/Linux installs, plus `-Ui`, `-GumUi`, and `-ClassicUi` for PowerShell.
- Added Gum bootstrap relaunch behavior for downloaded installers, with PATH refresh and same-process fallback for streamed installs.
- Added Charmbracelet's official apt repository fallback when `apt-get install gum` cannot locate the package.

## 0.1.4 - 2026-05-13

- Added Linux workstation SSH onboarding with authorized_keys setup, optional password-login disablement, SSH port detection, UFW/fail2ban/MFA hardening, and guarded SSH restart prompts.
- Kept workstation infra dashboard commands disabled while still allowing local security configuration.

## 0.1.3 - 2026-05-13

- Added Control node vs Workstation machine profile selection at installer startup.
- Workstation profile now skips infra dashboard commands, SSH host onboarding, inbound SSH setup, and Linux security prompts.
- Added Apache License 2.0 with non-commercial and Commons Clause source-available licensing terms.
- Documented personal, educational, and commercial-use license boundaries in the README.

## 0.1.2 - 2026-05-09

- Updated release links and installer defaults for the renamed `adrienclaire/ShellDeck` repository.
- Updated GitHub repository metadata for the new ShellDeck project identity.

## 0.1.1 - 2026-05-09

- Fixed CI workflow issues found by the first production-readiness run.
- Kept ShellCheck advisory non-blocking while preserving parser and security checks as blocking gates.

## 0.1.0 - 2026-05-09

- First production-readiness baseline for ShellDeck.
- Added cross-platform install modes: Basic, Complete, and Manual.
- Added Linux UFW, fail2ban, and optional TOTP MFA setup prompts.
- Added smart Bash and PowerShell runtime dashboards, aliases, infra host setup, and dependency checks.
- Added CI validation, security policy, dry-run mode, and safer opt-in gates for risky helpers.
