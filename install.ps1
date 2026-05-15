[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$SkipDeps,
    [switch]$SkipInfra,
    [switch]$DryRun,
    [string]$Mode = "",
    [Alias("Role")]
    [string]$MachineProfile = "",
    [string]$Ui = $(if ($env:SHELLDECK_INSTALL_UI) { $env:SHELLDECK_INSTALL_UI } else { "auto" }),
    [switch]$ClassicUi,
    [switch]$GumUi,
    [string]$InstallDir = $(if ($env:SHELL_ALIAS_TOOLS_HOME) { $env:SHELL_ALIAS_TOOLS_HOME } else { Join-Path $HOME ".shell-alias-tools" })
)

$ErrorActionPreference = "Stop"
$ShellToolsVersion = if ($env:SHELL_TOOLS_VERSION) { $env:SHELL_TOOLS_VERSION } else { "0.1.4" }
$ShellAliasToolsRef = if ($env:SHELL_ALIAS_TOOLS_REF) { $env:SHELL_ALIAS_TOOLS_REF } else { "v$ShellToolsVersion" }
$RawBase = if ($env:SHELL_ALIAS_TOOLS_RAW_BASE) {
    $env:SHELL_ALIAS_TOOLS_RAW_BASE
}
else {
    "https://raw.githubusercontent.com/adrienclaire/ShellDeck/$ShellAliasToolsRef"
}

if ($ClassicUi) { $Ui = "classic" }
if ($GumUi) { $Ui = "gum" }
$script:UseGum = $false

function Test-GumUi {
    return ($script:UseGum -and (Get-Command gum -ErrorAction SilentlyContinue))
}

function Write-Step {
    param([string]$Message)
    if (Test-GumUi) {
        & gum style --foreground 39 --bold $Message
    }
    else {
        Write-Host $Message -ForegroundColor Cyan
    }
}

function Write-Ok {
    param([string]$Message)
    if (Test-GumUi) {
        & gum style --foreground 42 --bold $Message
    }
    else {
        Write-Host $Message -ForegroundColor Green
    }
}

function Write-Warn {
    param([string]$Message)
    if (Test-GumUi) {
        & gum style --foreground 214 --bold $Message
    }
    else {
        Write-Host $Message -ForegroundColor Yellow
    }
}

function Write-DryRun {
    param([string]$Message)
    if ($DryRun) {
        Write-Host "[dry-run] $Message" -ForegroundColor Magenta
    }
}

function Confirm-InstallChoice {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [bool]$Default = $true
    )

    if ($Yes) {
        return $Default
    }

    if (Test-GumUi) {
        $gumDefault = if ($Default) { "true" } else { "false" }
        & gum confirm "--default=$gumDefault" $Prompt
        return ($LASTEXITCODE -eq 0)
    }

    $suffix = if ($Default) { "Y/n" } else { "y/N" }
    while ($true) {
        $answer = (Read-Host "$Prompt [$suffix]").Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }

        switch ($answer) {
            "y" { return $true }
            "yes" { return $true }
            "o" { return $true }
            "oui" { return $true }
            "n" { return $false }
            "no" { return $false }
            "non" { return $false }
            default { Write-Warn "Please answer yes or no." }
        }
    }
}

function Show-InstallerBanner {
    if (Test-GumUi) {
        "ShellDeck`nSmart shell bootstrap and infra-aware installer`n`nProfile-aware setup for control nodes and workstations." |
            gum style --border rounded --border-foreground 39 --padding "1 2" --margin "1 0" --foreground 255 --bold
    }
    else {
        Write-Step "ShellDeck installer"
    }
}

function Normalize-InstallMode {
    param([string]$Value)

    switch ($Value.Trim().ToLowerInvariant()) {
        { $_ -in @("1", "b", "basic") } { return "basic" }
        { $_ -in @("2", "c", "complete", "complet", "full") } { return "complete" }
        { $_ -in @("3", "m", "manual") } { return "manual" }
        default { return "" }
    }
}

function Read-InstallMode {
    if (-not [string]::IsNullOrWhiteSpace($Mode)) {
        $normalized = Normalize-InstallMode $Mode
        if ($normalized) {
            return $normalized
        }
        Write-Warn "Unknown install mode '$Mode'. Use basic, complete, or manual."
    }

    if ($Yes) {
        return "basic"
    }

    if (Test-GumUi) {
        $choice = & gum choose --header "Choose dependency setup mode" --height 8 `
            "Basic - install required smart-shell dependencies automatically" `
            "Complete - required dependencies plus Docker, Multipass, and GitHub CLI" `
            "Manual - ask before installing every dependency"
        if ($choice -like "Basic*") { return "basic" }
        if ($choice -like "Complete*") { return "complete" }
        if ($choice -like "Manual*") { return "manual" }
    }

    Write-Step "Setup mode"
    Write-Host "  1) Basic    - install required smart-shell dependencies automatically"
    Write-Host "  2) Complete - install required dependencies plus Docker, Multipass, and GitHub CLI"
    Write-Host "  3) Manual   - ask before installing every dependency"

    while ($true) {
        $choice = Read-Host "Choose setup mode [1]"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            $choice = "1"
        }

        $normalized = Normalize-InstallMode $choice
        if ($normalized) {
            return $normalized
        }

        Write-Warn "Choose 1 for Basic, 2 for Complete, or 3 for Manual."
    }
}

function Normalize-MachineProfile {
    param([string]$Value)

    switch ($Value.Trim().ToLowerInvariant()) {
        { $_ -in @("1", "control", "control-node", "controlnode", "management", "manager", "management-host", "management-computer", "admin", "infra") } { return "control" }
        { $_ -in @("2", "workstation", "desktop", "laptop", "dev", "developer", "personal") } { return "workstation" }
        default { return "" }
    }
}

function Read-MachineProfile {
    if (-not [string]::IsNullOrWhiteSpace($MachineProfile)) {
        $normalized = Normalize-MachineProfile $MachineProfile
        if ($normalized) {
            return $normalized
        }
        Write-Warn "Unknown machine profile '$MachineProfile'. Use control or workstation."
    }

    if ($Yes) {
        return "control"
    }

    if (Test-GumUi) {
        $choice = & gum choose --header "Choose machine profile" --height 6 `
            "Control node - smart shell plus infra dashboard, SSH shortcuts, host/service checks" `
            "Workstation - smart shell plus optional local SSH/security hardening"
        if ($choice -like "Control*") { return "control" }
        if ($choice -like "Workstation*") { return "workstation" }
    }

    Write-Step "Machine profile"
    Write-Host "  1) Control node - smart shell plus infra dashboard, SSH shortcuts, host/service checks"
    Write-Host "  2) Workstation  - smart shell only, no infra dashboard or SSH host management"

    while ($true) {
        $choice = Read-Host "Choose machine profile [1]"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            $choice = "1"
        }

        $normalized = Normalize-MachineProfile $choice
        if ($normalized) {
            return $normalized
        }

        Write-Warn "Choose 1 for Control node or 2 for Workstation."
    }
}

function Get-InstallToolPath {
    param([string]$Tool)

    switch ($Tool) {
        "bash-completion" { return "PowerShell completion" }
        "bat" {
            $cmd = Get-Command bat -ErrorAction SilentlyContinue
            if (-not $cmd) { $cmd = Get-Command batcat -ErrorAction SilentlyContinue }
            if ($cmd) { return $cmd.Source }
            return ""
        }
        "fd" {
            $cmd = Get-Command fd -ErrorAction SilentlyContinue
            if (-not $cmd) { $cmd = Get-Command fdfind -ErrorAction SilentlyContinue }
            if ($cmd) { return $cmd.Source }
            return ""
        }
        "ripgrep" {
            $cmd = Get-Command rg -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Source }
            return ""
        }
        "neovim" {
            $cmd = Get-Command nvim -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Source }
            return ""
        }
        "nc" {
            $cmd = Get-Command nc -ErrorAction SilentlyContinue
            if (-not $cmd) { $cmd = Get-Command ncat -ErrorAction SilentlyContinue }
            if ($cmd) { return $cmd.Source }
            return ""
        }
        "tree" {
            $cmd = Get-Command tree.com -ErrorAction SilentlyContinue
            if (-not $cmd) { $cmd = Get-Command tree -ErrorAction SilentlyContinue }
            if ($cmd) { return $cmd.Source }
            return ""
        }
        "unzip" {
            $cmd = Get-Command Expand-Archive -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Name }
            return ""
        }
        "zip" {
            $cmd = Get-Command Compress-Archive -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Name }
            return ""
        }
        default {
            $cmd = Get-Command $Tool -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Source }
            return ""
        }
    }
}

function Write-RuntimeConfig {
    param([Parameter(Mandatory = $true)][string]$SelectedMachineProfile)

    $configPath = Join-Path $InstallDir "config"
    if ($DryRun) {
        Write-DryRun "would write $configPath with SHELLDECK_MACHINE_PROFILE=$SelectedMachineProfile"
        return
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($configPath, "SHELLDECK_MACHINE_PROFILE=$SelectedMachineProfile`n", $utf8NoBom)
}

function Ensure-InstallFiles {
    param([Parameter(Mandatory = $true)][string]$SelectedMachineProfile)

    if ($DryRun) {
        Write-DryRun "would create $InstallDir and install shell-tools.ps1, aliases.ps1, and profile config"
        if ($SelectedMachineProfile -eq "control") {
            Write-DryRun "would create infra-hosts.csv for the control node profile"
        }
        Write-RuntimeConfig -SelectedMachineProfile $SelectedMachineProfile
        return (Join-Path $InstallDir "shell-tools.ps1")
    }

    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    }

    $runtimePath = Join-Path $InstallDir "shell-tools.ps1"
    $localRuntime = if ($PSScriptRoot) { Join-Path $PSScriptRoot "alias-tools.ps1" } else { "" }

    if ($localRuntime -and (Test-Path $localRuntime)) {
        Copy-Item -Path $localRuntime -Destination $runtimePath -Force
    }
    else {
        Write-Step "Downloading PowerShell runtime..."
        Invoke-WebRequest -Uri "$RawBase/alias-tools.ps1" -OutFile $runtimePath
    }

    $aliasesPath = Join-Path $InstallDir "aliases.ps1"
    if (-not (Test-Path $aliasesPath)) {
        New-Item -ItemType File -Force -Path $aliasesPath | Out-Null
    }

    Write-RuntimeConfig -SelectedMachineProfile $SelectedMachineProfile

    $hostsPath = Join-Path $InstallDir "infra-hosts.csv"
    if ($SelectedMachineProfile -eq "control" -and -not (Test-Path $hostsPath)) {
        "Name,HostName,SshEnabled,User,Port,InSshConfig,Docker,Services" |
            Set-Content -Path $hostsPath -Encoding UTF8
    }

    return $runtimePath
}

function Add-ProfileHook {
    param([Parameter(Mandatory = $true)][string]$RuntimePath)

    if ($DryRun) {
        Write-DryRun "would add ShellDeck profile hook to $PROFILE"
        return
    }

    $profilePath = $PROFILE
    $profileDir = Split-Path $profilePath

    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }

    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Force -Path $profilePath | Out-Null
    }

    if (Select-String -Path $profilePath -Pattern "shell-alias-tools" -Quiet -ErrorAction SilentlyContinue) {
        Write-Warn "Profile already contains Shell Alias Tools hook: $profilePath"
        return
    }

    $escapedRuntime = $RuntimePath.Replace("'", "''")
    $block = @"

# >>> shell-alias-tools >>>
. '$escapedRuntime'
# <<< shell-alias-tools <<<
"@

    Add-Content -Path $profilePath -Value $block
    Write-Ok "Profile hook added: $profilePath"
}

function Install-WindowsDependency {
    param(
        [string]$Tool,
        [bool]$Auto = $false
    )

    $wingetPackages = @{
        git       = "Git.Git"
        wget      = "GNU.Wget2"
        gum       = "Charmbracelet.gum"
        fzf       = "junegunn.fzf"
        bat       = "sharkdp.bat"
        eza       = "eza-community.eza"
        zoxide    = "ajeetdsouza.zoxide"
        starship  = "Starship.Starship"
        ripgrep   = "BurntSushi.ripgrep.MSVC"
        fd        = "sharkdp.fd"
        jq        = "jqlang.jq"
        yq        = "MikeFarah.yq"
        btop      = "aristocratos.btop4win"
        duf       = "muesli.duf"
        neovim    = "Neovim.Neovim"
        gh        = "GitHub.cli"
        docker    = "Docker.DockerDesktop"
        multipass = "Canonical.Multipass"
    }

    if ($Tool -eq "ssh") {
        if ($DryRun) {
            Write-DryRun "would install Windows OpenSSH Client capability"
            return
        }

        if ($Auto -or (Confirm-InstallChoice "Install the Windows OpenSSH Client capability?" $true)) {
            try {
                Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 | Out-Null
            }
            catch {
                Write-Warn "OpenSSH Client install failed. You may need an elevated PowerShell session."
            }
        }
        return
    }

    if ($Tool -in @("curl", "bash-completion", "tree", "unzip", "zip")) {
        Write-Warn "$Tool is usually built into modern Windows or PowerShell. No extra package was installed."
        return
    }

    if ($Tool -in @("rsync", "tmux", "htop", "nc")) {
        Write-Warn "No reliable native Windows package mapping is configured for $Tool yet."
        return
    }

    if (-not $wingetPackages.ContainsKey($Tool)) {
        Write-Warn "No winget package mapping is configured for $Tool."
        return
    }

    if ($DryRun) {
        Write-DryRun "would run: winget install --id $($wingetPackages[$Tool]) --exact --accept-source-agreements --accept-package-agreements"
        return
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warn "winget is not available. Please install $Tool manually."
        return
    }

    try {
        winget install --id $wingetPackages[$Tool] --exact --accept-source-agreements --accept-package-agreements
    }
    catch {
        Write-Warn "winget install failed for $Tool."
    }
}

function Install-Dependencies {
    param([string]$SetupMode)

    $requiredTools = @(
        "git", "ssh", "curl", "wget", "gum", "fzf", "bash-completion", "bat", "eza", "zoxide",
        "starship", "ripgrep", "fd", "jq", "yq", "nc", "tree", "unzip", "zip", "rsync", "tmux",
        "btop", "htop", "duf", "neovim"
    )
    $optionalTools = @("gh", "docker", "multipass")

    Write-Step "Dependency setup"
    switch ($SetupMode) {
        "basic" { Write-Step "Basic mode: installing required smart-shell dependencies automatically." }
        "complete" { Write-Step "Complete mode: installing required dependencies plus Docker, Multipass, and GitHub CLI." }
        "manual" { Write-Step "Manual mode: you will be asked about every dependency." }
    }

    foreach ($tool in $requiredTools) {
        $path = Get-InstallToolPath $tool
        $status = if ($path) { "installed at $path" } else { "missing" }

        if ($SetupMode -eq "manual") {
            $default = -not [bool]$path
            if (-not (Confirm-InstallChoice "Install/update smart-shell dependency '$tool'? ($status)" $default)) {
                Write-Warn "$tool is useful for the best Shell Alias Tools experience. Some commands may fall back or fail."
                continue
            }
        }
        elseif ($path) {
            Write-Ok "$tool already installed ($path)"
            continue
        }
        else {
            Write-Step "Installing required dependency: $tool"
        }

        Install-WindowsDependency -Tool $tool -Auto ($SetupMode -ne "manual")
    }

    if ($SetupMode -eq "basic") {
        Write-Step "Basic mode skips optional dependencies: $($optionalTools -join ', ')"
        return
    }

    foreach ($tool in $optionalTools) {
        $path = Get-InstallToolPath $tool
        $status = if ($path) { "installed at $path" } else { "missing" }

        if ($SetupMode -eq "manual") {
            $default = ($tool -eq "gh" -and -not [bool]$path)
            if (-not (Confirm-InstallChoice "Install/update optional dependency '$tool'? ($status)" $default)) {
                continue
            }
        }
        elseif ($path) {
            Write-Ok "$tool already installed ($path)"
            continue
        }
        else {
            Write-Step "Installing optional dependency: $tool"
        }

        Install-WindowsDependency -Tool $tool -Auto ($SetupMode -ne "manual")
    }
}

function Enable-LocalSshServer {
    if (-not (Confirm-InstallChoice "Enable inbound SSH server on this Windows machine/VM?" $false)) {
        return
    }

    if ($DryRun) {
        Write-DryRun "would install OpenSSH.Server capability, start sshd, set automatic startup, and allow TCP/22 through Windows Firewall"
        return
    }

    try {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
        Start-Service sshd
        Set-Service -Name sshd -StartupType Automatic

        if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
        }

        Write-Ok "OpenSSH Server is enabled."
    }
    catch {
        Write-Warn "Could not enable OpenSSH Server. Try again from an elevated PowerShell session."
    }
}

function Configure-Infra {
    param([string]$RuntimePath)

    if ($DryRun) {
        Write-DryRun "would load $RuntimePath and offer interactive infra host setup"
        return
    }

    $previousNoDashboard = $env:SHELL_TOOLS_NO_DASHBOARD
    $env:SHELL_TOOLS_NO_DASHBOARD = "1"
    . $RuntimePath
    $env:SHELL_TOOLS_NO_DASHBOARD = $previousNoDashboard

    if (Get-Command shellsetup -ErrorAction SilentlyContinue) {
        shellsetup
    }
}

function Initialize-InstallerUi {
    $normalizedUi = $Ui.Trim().ToLowerInvariant()

    if ($normalizedUi -in @("classic", "none", "off")) {
        $script:UseGum = $false
        return
    }

    if ($normalizedUi -notin @("auto", "gum")) {
        Write-Warn "Unknown -Ui value '$Ui'. Use auto, gum, or classic."
        $normalizedUi = "auto"
    }

    if (Get-Command gum -ErrorAction SilentlyContinue) {
        $script:UseGum = $true
        return
    }

    if ($Yes) {
        return
    }

    if ($normalizedUi -eq "auto" -and -not (Confirm-InstallChoice "Install Gum now for a richer installer interface?" $true)) {
        return
    }

    if ($DryRun) {
        Write-DryRun "would install gum with winget for the rich installer UI"
        return
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warn "winget is not available. Continuing with the classic installer UI."
        return
    }

    try {
        winget install --id Charmbracelet.gum -e --accept-package-agreements --accept-source-agreements | Out-Host
    }
    catch {
        Write-Warn "Gum install failed. Continuing with the classic installer UI."
    }

    if (Get-Command gum -ErrorAction SilentlyContinue) {
        $script:UseGum = $true
    }
    else {
        Write-Warn "Gum is not available after install attempt. Continuing with the classic installer UI."
    }
}

function Main {
    Initialize-InstallerUi
    Show-InstallerBanner
    $selectedMachineProfile = Read-MachineProfile
    Write-Step "Installing ShellDeck for Windows as $selectedMachineProfile profile..."
    if ($DryRun) {
        Write-Warn "Dry run enabled: no files, packages, profiles, services, or firewall rules will be changed."
    }

    $runtimePath = Ensure-InstallFiles -SelectedMachineProfile $selectedMachineProfile
    Add-ProfileHook -RuntimePath $runtimePath

    if (-not $SkipDeps) {
        $setupMode = Read-InstallMode
        Install-Dependencies -SetupMode $setupMode
        if ($selectedMachineProfile -eq "control") {
            Enable-LocalSshServer
        }
        else {
            Write-Step "Workstation profile: skipping inbound SSH server and infra host setup."
        }
    }

    if ($selectedMachineProfile -eq "control" -and -not $SkipInfra) {
        Configure-Infra -RuntimePath $runtimePath
    }

    if ($DryRun) {
        Write-Ok "Dry run complete."
        return
    }

    Write-Ok "Install complete."
    Write-Host ""
    Write-Host "IMPORTANT: restart PowerShell to apply the effect." -ForegroundColor Cyan
    Write-Host "Run this now to reload your current PowerShell profile:"
    Write-Host ". '$runtimePath'"
    Write-Host ""
    Write-Host "Then try:" -ForegroundColor Cyan
    Write-Host "ll"
    Write-Host "ff"
    Write-Host "check-tools"
    if ($selectedMachineProfile -eq "control") {
        Write-Host "init"
        Write-Host "sshhosts"
        Write-Host "infra-add"
    }
}

Main
