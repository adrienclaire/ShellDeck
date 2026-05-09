[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$SkipDeps,
    [switch]$SkipInfra,
    [string]$Mode = "",
    [string]$InstallDir = $(if ($env:SHELL_ALIAS_TOOLS_HOME) { $env:SHELL_ALIAS_TOOLS_HOME } else { Join-Path $HOME ".shell-alias-tools" })
)

$ErrorActionPreference = "Stop"
$RawBase = if ($env:SHELL_ALIAS_TOOLS_RAW_BASE) {
    $env:SHELL_ALIAS_TOOLS_RAW_BASE
}
else {
    "https://raw.githubusercontent.com/adrienclaire/Shell-Alias-Tools/main"
}

function Write-Step {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
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

function Ensure-InstallFiles {
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

    $hostsPath = Join-Path $InstallDir "infra-hosts.csv"
    if (-not (Test-Path $hostsPath)) {
        "Name,HostName,SshEnabled,User,Port,InSshConfig,Docker,Services" |
            Set-Content -Path $hostsPath -Encoding UTF8
    }

    return $runtimePath
}

function Add-ProfileHook {
    param([Parameter(Mandatory = $true)][string]$RuntimePath)

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

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warn "winget is not available. Please install $Tool manually."
        return
    }

    if (-not $wingetPackages.ContainsKey($Tool)) {
        Write-Warn "No winget package mapping is configured for $Tool."
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
        "git", "ssh", "curl", "wget", "fzf", "bash-completion", "bat", "eza", "zoxide",
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

    $previousNoDashboard = $env:SHELL_TOOLS_NO_DASHBOARD
    $env:SHELL_TOOLS_NO_DASHBOARD = "1"
    . $RuntimePath
    $env:SHELL_TOOLS_NO_DASHBOARD = $previousNoDashboard

    if (Get-Command shellsetup -ErrorAction SilentlyContinue) {
        shellsetup
    }
}

function Main {
    Write-Step "Installing Shell Alias Tools for Windows..."

    $runtimePath = Ensure-InstallFiles
    Add-ProfileHook -RuntimePath $runtimePath

    if (-not $SkipDeps) {
        $setupMode = Read-InstallMode
        Install-Dependencies -SetupMode $setupMode
        Enable-LocalSshServer
    }

    if (-not $SkipInfra) {
        Configure-Infra -RuntimePath $runtimePath
    }

    Write-Ok "Install complete."
    Write-Host ""
    Write-Host "IMPORTANT: restart PowerShell to apply the effect." -ForegroundColor Cyan
    Write-Host "Run this now to reload your current PowerShell profile:"
    Write-Host ". '$runtimePath'"
    Write-Host ""
    Write-Host "Then try:" -ForegroundColor Cyan
    Write-Host "init"
    Write-Host "ll"
    Write-Host "ff"
    Write-Host "sshhosts"
    Write-Host "check-tools"
}

Main
