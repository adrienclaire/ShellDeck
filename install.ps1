[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$SkipDeps,
    [switch]$SkipInfra,
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

function Read-InstallDefault {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [string]$Default = ""
    )

    if ($Yes) {
        return $Default
    }

    if ($Default) {
        $value = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $Default
        }
        return $value.Trim()
    }

    return (Read-Host $Prompt).Trim()
}

function Test-InstallInfraName {
    param([string]$Value)
    return ($Value -match '^[A-Za-z][A-Za-z0-9._-]*$')
}

function Test-InstallIPv4 {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $parts = $Value.Trim() -split '\.'
    if ($parts.Count -ne 4) {
        return $false
    }

    foreach ($part in $parts) {
        if ($part -notmatch '^\d{1,3}$') {
            return $false
        }

        $number = [int]$part
        if ($number -lt 0 -or $number -gt 255) {
            return $false
        }
    }

    return $true
}

function Test-InstallUser {
    param([string]$Value)
    return ($Value -match '^[A-Za-z0-9._-]+[$]?$')
}

function Test-InstallRole {
    param([string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -notmatch '[,\r\n]')
}

function Test-InstallUrl {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    $uri = $null
    return [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in @("http", "https")
}

function Test-InstallPort {
    param([string]$Value)

    if ($Value -notmatch '^\d+$') {
        return $false
    }

    $port = [int]$Value
    return ($port -ge 1 -and $port -le 65535)
}

function Convert-InstallPortList {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $ports = @()
    $items = $Value.Trim() -split '[;,\s]+' | Where-Object { $_ }
    foreach ($item in $items) {
        if (-not (Test-InstallPort $item)) {
            return $null
        }
        $ports += ([int]$item).ToString()
    }

    if ($ports.Count -eq 0) {
        return $null
    }

    return (($ports | Select-Object -Unique) -join ";")
}

function Read-InstallValidated {
    param(
        [string]$Prompt,
        [string]$Default,
        [scriptblock]$Validator,
        [string]$ErrorMessage
    )

    while ($true) {
        $value = Read-InstallDefault $Prompt $Default
        if (& $Validator $value) {
            return $value
        }

        Write-Warn $ErrorMessage
    }
}

function Read-InstallPorts {
    param(
        [string]$Prompt,
        [string]$Default
    )

    while ($true) {
        $value = Read-InstallDefault $Prompt $Default
        $normalized = Convert-InstallPortList $value
        if ($normalized) {
            return $normalized
        }

        Write-Warn "This is not a valid port list. Use values like 22;8006 or 22, 8006."
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
        "Name,HostName,User,Port,Role,CheckPorts,Url,SshEnabled" |
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

function Install-Dependencies {
    $wingetPackages = @{
        git       = "Git.Git"
        fzf       = "junegunn.fzf"
        gh        = "GitHub.cli"
        jq        = "jqlang.jq"
        docker    = "Docker.DockerDesktop"
        multipass = "Canonical.Multipass"
    }

    foreach ($tool in @("git", "ssh", "curl", "fzf", "jq", "gh", "docker", "multipass")) {
        if (Get-Command $tool -ErrorAction SilentlyContinue) {
            Write-Ok "$tool already installed."
            continue
        }

        $default = $true
        if ($tool -in @("docker", "multipass")) {
            $default = $false
        }

        if (-not (Confirm-InstallChoice "Install missing dependency '$tool'?" $default)) {
            continue
        }

        if ($tool -eq "ssh") {
            if (Confirm-InstallChoice "Install the Windows OpenSSH Client capability?" $true) {
                try {
                    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 | Out-Null
                }
                catch {
                    Write-Warn "OpenSSH Client install failed. You may need an elevated PowerShell session."
                }
            }
            continue
        }

        if ($tool -eq "curl") {
            Write-Warn "curl is normally included with modern Windows. Please install it manually if this machine does not have it."
            continue
        }

        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Warn "winget is not available. Please install $tool manually."
            continue
        }

        if ($wingetPackages.ContainsKey($tool)) {
            try {
                winget install --id $wingetPackages[$tool] --exact --accept-source-agreements --accept-package-agreements
            }
            catch {
                Write-Warn "winget install failed for $tool."
            }
        }
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

function Ensure-SshKey {
    $sshDir = Join-Path $HOME ".ssh"
    $keyPath = Join-Path $sshDir "id_ed25519"
    $publicKeyPath = "$keyPath.pub"

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
    }

    if (-not (Test-Path $publicKeyPath)) {
        if (Confirm-InstallChoice "Generate an ed25519 SSH key?" $true) {
            $comment = "{0}@{1}-shell-alias-tools" -f $env:USERNAME, $env:COMPUTERNAME
            ssh-keygen -t ed25519 -C $comment -f $keyPath
        }
    }

    if (Test-Path $publicKeyPath) {
        Write-Host ""
        Write-Host "Public key:" -ForegroundColor Cyan
        Get-Content $publicKeyPath
        Write-Host ""
        Write-Host "Copy it to the remote host's ~/.ssh/authorized_keys." -ForegroundColor Yellow
    }
}

function Add-SshConfigHost {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [string]$User,

        [int]$Port = 22
    )

    $sshDir = Join-Path $HOME ".ssh"
    $configPath = Join-Path $sshDir "config"

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
    }

    if (-not (Test-Path $configPath)) {
        New-Item -ItemType File -Force -Path $configPath | Out-Null
    }

    $escaped = [regex]::Escape($Name)
    if (Select-String -Path $configPath -Pattern "^\s*Host\s+$escaped\s*$" -Quiet -ErrorAction SilentlyContinue) {
        Write-Warn "SSH config already contains Host $Name."
        return
    }

    $entry = @"

Host $Name
    HostName $HostName
    User $User
    Port $Port
    ServerAliveInterval 30
    ServerAliveCountMax 3
"@

    Add-Content -Path $configPath -Value $entry
    Write-Ok "SSH config added: ssh $Name"
}

function Get-InfraHostsPath {
    return (Join-Path $InstallDir "infra-hosts.csv")
}

function Get-InfraHosts {
    $hostsPath = Get-InfraHostsPath
    if (-not (Test-Path $hostsPath)) {
        return @()
    }

    return @(Import-Csv -Path $hostsPath | Where-Object { $_.Name -and $_.HostName })
}

function Add-InfraHost {
    param(
        [string]$Name = "proxmox",
        [string]$HostName = "192.168.1.185",
        [string]$User = "root",
        [int]$Port = 22,
        [string]$Role = "proxmox",
        [string]$CheckPorts = "22;8006",
        [string]$Url = "https://192.168.1.185:8006"
    )

    Write-Host ""
    Write-Step "Infra host onboarding"

    $Name = Read-InstallValidated -Prompt "Host alias" -Default $Name -Validator ${function:Test-InstallInfraName} -ErrorMessage "Use a host alias like proxmox, docker-vm, or app01. Letters, numbers, dot, dash, underscore; start with a letter."
    $HostName = Read-InstallValidated -Prompt "Host IPv4" -Default $HostName -Validator ${function:Test-InstallIPv4} -ErrorMessage "This is not an IPv4 address. Example: 192.168.1.185."
    $User = Read-InstallValidated -Prompt "SSH user" -Default $User -Validator ${function:Test-InstallUser} -ErrorMessage "Use a simple SSH user, like root, ubuntu, admin, or adrien."
    $Port = [int](Read-InstallValidated -Prompt "SSH port" -Default ([string]$Port) -Validator ${function:Test-InstallPort} -ErrorMessage "This is not a valid TCP port. Use a number from 1 to 65535.")
    $Role = Read-InstallValidated -Prompt "Role" -Default $Role -Validator ${function:Test-InstallRole} -ErrorMessage "Role cannot be empty and cannot contain commas."
    $CheckPorts = Read-InstallPorts -Prompt "Ports to check, separated by semicolon" -Default $CheckPorts
    $Url = Read-InstallValidated -Prompt "Web URL, optional" -Default $Url -Validator ${function:Test-InstallUrl} -ErrorMessage "Use a full URL like https://192.168.1.185:8006, or leave it empty."

    $sshEnabled = $false
    if (Confirm-InstallChoice "Add this host to ~/.ssh/config?" $true) {
        $sshEnabled = $true
        Ensure-SshKey
        Add-SshConfigHost -Name $Name -HostName $HostName -User $User -Port $Port
        Write-Host "When the key is installed on the host, connect with: ssh $Name" -ForegroundColor Cyan
    }

    $records = @(Get-InfraHosts | Where-Object { $_.Name -ne $Name })
    $records += [PSCustomObject]@{
        Name       = $Name
        HostName   = $HostName
        User       = $User
        Port       = $Port
        Role       = $Role
        CheckPorts = $CheckPorts
        Url        = $Url
        SshEnabled = $sshEnabled.ToString().ToLowerInvariant()
    }

    $records | Sort-Object Name | Export-Csv -Path (Get-InfraHostsPath) -NoTypeInformation -Encoding UTF8
    Write-Ok "Infra host saved: $Name ($HostName)"
}

function Configure-Infra {
    $hosts = @(Get-InfraHosts)

    if ($hosts.Count -eq 0) {
        if (Confirm-InstallChoice "Add your default Proxmox host at 192.168.1.185?" $true) {
            Add-InfraHost
        }
    }

    while (Confirm-InstallChoice "Add another infra server?" $false) {
        Add-InfraHost -Name "server" -HostName "192.168.1.10" -User $env:USERNAME -Port 22 -Role "server" -CheckPorts "22" -Url ""
    }
}

function Main {
    Write-Step "Installing Shell Alias Tools for Windows..."

    $runtimePath = Ensure-InstallFiles
    Add-ProfileHook -RuntimePath $runtimePath

    if (-not $SkipDeps) {
        Install-Dependencies
        Enable-LocalSshServer
    }

    if (-not $SkipInfra) {
        Configure-Infra
    }

    Write-Ok "Install complete."
    Write-Host ""
    Write-Host "Restart PowerShell or run:" -ForegroundColor Cyan
    Write-Host ". '$runtimePath'"
    Write-Host ""
    Write-Host "Then try:" -ForegroundColor Cyan
    Write-Host "init"
    Write-Host "sshhosts"
    Write-Host "check-tools"
}

Main
