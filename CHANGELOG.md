# Changelog

## Unreleased

## 0.2.2 - 2026-06-26

- Added persistent PowerShell startup banner controls: `shelldeckinfo-enabled`, `shelldeckinfo-disabled`, and `shelldeckinfo-status`.
- Disabled startup banners are saved in ShellDeck config so future PowerShell profile loads remain quiet while commands stay available.
- Kept `SHELL_TOOLS_NO_DASHBOARD=1` as an environment override for one-off automated sessions.
- Added regression coverage for disabled banner profile loads.

## 0.2.1 - 2026-06-06

- Added `shelldeck-update` for Bash/Zsh and PowerShell so ShellDeck can update the runtime in place without deleting infra hosts, aliases, config, or SSH data.
- Added a timestamped runtime backup during in-place updates plus syntax validation before replacement.
- Added a daily PowerShell dashboard cache and `shelldeck-refresh` to reduce repeated startup cost across sessions.
- Replaced the slow PowerShell IP lookup path with a faster .NET network-interface query.
- Fixed `init` skipping hosts that appear after a Docker-enabled host by preventing SSH-based Docker scans from consuming the infra CSV loop input.
- Added regression coverage for PowerShell dashboard caching, updater safety, and the Docker-scan stdin bug.

## 0.2.0 - 2026-05-20

- Added optional Gum-powered installer UI for richer choices, confirmations, inputs, and styled installer sections.
- Added `--ui auto|gum|classic`, `--gum-ui`, and `--classic-ui` for Bash/macOS/Linux installs, plus `-Ui`, `-GumUi`, and `-ClassicUi` for PowerShell.
- Added Gum bootstrap relaunch behavior for downloaded installers, with PATH refresh and same-process fallback for streamed installs.
- Added Charmbracelet's official apt repository fallback when `apt-get install gum` cannot locate the package.
- Added ShellDeck logo assets, a terminal wordmark banner, and refreshed README screenshots for a more polished project presentation.
- Fixed Gum choice prompts on older Gum builds by avoiding the incompatible `--header` flag.
- Fixed early machine profile and setup mode prompts falling back to numbered input when a Gum build does not support `gum choose --height`.
- Fixed Gum detection inside captured selection prompts by checking `/dev/tty` instead of stdout.
- Fixed leaked terminal cursor-position responses before Gum choice prompts by avoiding `gum style` immediately before `gum choose`.
- Fixed editor launches during workstation SSH onboarding so `nano` receives `/dev/tty` when the installer is run through `curl | bash`.
- Added a pseudo-terminal workstation onboarding integration test that covers the authorized_keys editor flow.
- Added SSH MFA `AuthenticationMethods publickey,keyboard-interactive` configuration with global or current-user `Match User` scope.
- SSH MFA now comments `/etc/pam.d/sshd` `@include common-auth` so public-key plus TOTP does not ask for the account password.
- Added production lockout warnings for SSH, firewall, PAM, and MFA changes.

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
