# Shell Alias Tools - PowerShell profile runtime
# Loaded from the user profile by install.ps1.

$script:ShellToolsRoot = if ($env:SHELL_ALIAS_TOOLS_HOME) {
    $env:SHELL_ALIAS_TOOLS_HOME
}
else {
    Join-Path $HOME ".shell-alias-tools"
}

$script:AliasToolsPath = Join-Path $script:ShellToolsRoot "aliases.ps1"
$script:InfraHostsPath = Join-Path $script:ShellToolsRoot "infra-hosts.csv"
$script:ShellDeckConfigPath = Join-Path $script:ShellToolsRoot "config"

function ConvertTo-ShellDeckMachineProfile {
    param([string]$Value)

    switch ($Value.Trim().ToLowerInvariant()) {
        { $_ -in @("control", "control-node", "controlnode", "management", "manager", "management-host", "management-computer", "admin", "infra") } { return "control" }
        { $_ -in @("workstation", "desktop", "laptop", "dev", "developer", "personal") } { return "workstation" }
        default { return "" }
    }
}

function Get-ShellDeckMachineProfile {
    if ($env:SHELLDECK_MACHINE_PROFILE) {
        $fromEnv = ConvertTo-ShellDeckMachineProfile $env:SHELLDECK_MACHINE_PROFILE
        if ($fromEnv) {
            return $fromEnv
        }
    }

    if (Test-Path $script:ShellDeckConfigPath) {
        foreach ($line in Get-Content -Path $script:ShellDeckConfigPath -ErrorAction SilentlyContinue) {
            if ($line -match '^\s*SHELLDECK_MACHINE_PROFILE\s*=\s*"?([^"\r\n]+)"?\s*$') {
                $fromConfig = ConvertTo-ShellDeckMachineProfile $matches[1]
                if ($fromConfig) {
                    return $fromConfig
                }
            }
        }
    }

    return "control"
}

$script:ShellDeckMachineProfile = Get-ShellDeckMachineProfile

function Test-ShellDeckControlProfile {
    return ($script:ShellDeckMachineProfile -eq "control")
}

function Get-ShellDeckMachineProfileLabel {
    if (Test-ShellDeckControlProfile) {
        return "Control node"
    }
    return "Workstation"
}

function Convert-ShellToolsInfraSchema {
    if (-not (Test-Path $script:InfraHostsPath)) {
        return
    }

    $header = Get-Content -Path $script:InfraHostsPath -First 1 -ErrorAction SilentlyContinue
    $normalizedHeader = ($header -replace '"', "")
    if ($normalizedHeader -ne "Name,HostName,User,Port,Role,CheckPorts,Url,SshEnabled") {
        return
    }

    $records = @(Import-Csv -Path $script:InfraHostsPath | ForEach-Object {
        $services = if ($_.Url) { $_.Url } else { "" }
        [PSCustomObject]@{
            Name        = $_.Name
            HostName    = $_.HostName
            SshEnabled  = $_.SshEnabled
            User        = $_.User
            Port        = $_.Port
            InSshConfig = $_.SshEnabled
            Docker      = if ($_.Role -match "docker") { "true" } else { "false" }
            Services    = $services
        }
    })

    $records | Export-Csv -Path $script:InfraHostsPath -NoTypeInformation -Encoding UTF8
}

function Ensure-ShellToolsHome {
    if (-not (Test-Path $script:ShellToolsRoot)) {
        New-Item -ItemType Directory -Force -Path $script:ShellToolsRoot | Out-Null
    }

    if (-not (Test-Path $script:AliasToolsPath)) {
        New-Item -ItemType File -Force -Path $script:AliasToolsPath | Out-Null
    }

    if (-not (Test-ShellDeckControlProfile)) {
        return
    }

    if (-not (Test-Path $script:InfraHostsPath)) {
        "Name,HostName,SshEnabled,User,Port,InSshConfig,Docker,Services" |
            Set-Content -Path $script:InfraHostsPath -Encoding UTF8
    }

    Convert-ShellToolsInfraSchema
}

Ensure-ShellToolsHome

if (Test-Path $script:AliasToolsPath) {
    . $script:AliasToolsPath
}

function Read-ShellToolsDefault {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [string]$Default = ""
    )

    if ($Default) {
        $value = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $Default
        }
        return $value.Trim()
    }

    return (Read-Host $Prompt).Trim()
}

function Read-ShellToolsYesNo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [bool]$Default = $true
    )

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
            default { Write-Host "Please answer yes or no." -ForegroundColor Yellow }
        }
    }
}

function Test-ShellToolsInfraName {
    param([string]$Value)
    return ($Value -match '^[A-Za-z][A-Za-z0-9._-]*$')
}

function Test-ShellToolsIPv4 {
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

function Test-ShellToolsUser {
    param([string]$Value)
    return ($Value -match '^[A-Za-z0-9._-]+[$]?$')
}

function Test-ShellToolsPortValue {
    param([string]$Value)

    if ($Value -notmatch '^\d+$') {
        return $false
    }

    $port = [int]$Value
    return ($port -ge 1 -and $port -le 65535)
}

function Test-ShellToolsProtocol {
    param([string]$Value)
    return ($Value.ToLowerInvariant() -in @("http", "https"))
}

function Read-ShellToolsValidatedDefault {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [string]$Default = "",

        [Parameter(Mandatory = $true)]
        [scriptblock]$Validator,

        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )

    while ($true) {
        $value = Read-ShellToolsDefault $Prompt $Default
        if (& $Validator $value) {
            return $value
        }

        Write-Host $ErrorMessage -ForegroundColor Yellow
    }
}

function Resolve-ShellToolsValidatedValue {
    param(
        [string]$Value,
        [string]$Prompt,
        [string]$Default,
        [scriptblock]$Validator,
        [string]$ErrorMessage
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        if (& $Validator $Value) {
            return $Value
        }

        Write-Host "'$Value' is invalid. $ErrorMessage" -ForegroundColor Yellow
    }

    return Read-ShellToolsValidatedDefault -Prompt $Prompt -Default $Default -Validator $Validator -ErrorMessage $ErrorMessage
}

function Resolve-ShellToolsPortValue {
    param(
        [int]$Value,
        [string]$Prompt,
        [int]$Default
    )

    if ($Value -ge 1 -and $Value -le 65535) {
        return $Value
    }

    $portText = Read-ShellToolsValidatedDefault -Prompt $Prompt -Default ([string]$Default) -Validator ${function:Test-ShellToolsPortValue} -ErrorMessage "This is not a valid TCP port. Use a number from 1 to 65535."
    return [int]$portText
}

function Read-ShellToolsServices {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [string]$Existing = ""
    )

    $services = New-Object System.Collections.Generic.List[string]

    if ($Existing) {
        Write-Host ""
        Write-Host "Existing service endpoints:" -ForegroundColor Cyan
        $Existing -split ";" | Where-Object { $_ } | ForEach-Object {
            Write-Host "  - $_"
        }

        if (Read-ShellToolsYesNo "Keep these service endpoints?" $true) {
            return $Existing
        }
    }

    if (-not (Read-ShellToolsYesNo "Do you want to add a service endpoint?" $true)) {
        return ""
    }

    while ($true) {
        $protocol = Read-ShellToolsValidatedDefault -Prompt "Service protocol, http or https" -Default "http" -Validator ${function:Test-ShellToolsProtocol} -ErrorMessage "Use http or https."
        $port = Read-ShellToolsValidatedDefault -Prompt "Service port, example 8000, 80, 8222" -Default "" -Validator ${function:Test-ShellToolsPortValue} -ErrorMessage "This is not a valid service port. Use a number from 1 to 65535."
        $services.Add(("{0}://{1}:{2}" -f $protocol.ToLowerInvariant(), $HostName, $port))

        if (-not (Read-ShellToolsYesNo "Add another service endpoint?" $false)) {
            break
        }
    }

    return ($services -join ";")
}

function Get-PrimaryIPv4 {
    try {
        $ip = Get-NetIPConfiguration |
            Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.IPv4Address.IPAddress -notlike "169.254.*" } |
            Select-Object -First 1 |
            ForEach-Object { $_.IPv4Address.IPAddress }

        if ($ip) {
            return $ip
        }
    }
    catch {
        return "unknown"
    }

    return "unknown"
}

function Get-ShortUptime {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $uptime = (Get-Date) - $os.LastBootUpTime

        if ($uptime.Days -gt 0) {
            return ("{0}d {1}h" -f $uptime.Days, $uptime.Hours)
        }

        return ("{0}h {1}m" -f $uptime.Hours, $uptime.Minutes)
    }
    catch {
        return "unknown"
    }
}

function Get-ShellToolsDiskSummary {
    try {
        $driveName = (Split-Path $HOME -Qualifier).TrimEnd(":")
        $drive = Get-PSDrive -Name $driveName -ErrorAction Stop
        $freeGb = [math]::Round($drive.Free / 1GB, 1)
        $totalGb = [math]::Round(($drive.Free + $drive.Used) / 1GB, 1)
        return ("{0} GB free / {1} GB" -f $freeGb, $totalGb)
    }
    catch {
        return "unknown"
    }
}

function Get-ShellToolsToolPath {
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

function Get-ShellToolsSmartToolList {
    return @(
        "git", "ssh", "curl", "wget", "fzf", "bash-completion", "bat", "eza", "zoxide",
        "starship", "ripgrep", "fd", "jq", "yq", "nc", "tree", "unzip", "zip", "rsync", "tmux",
        "btop", "htop", "duf", "neovim", "gh", "docker", "multipass"
    )
}

function Get-InfraHosts {
    if (-not (Test-ShellDeckControlProfile)) {
        return @()
    }

    Ensure-ShellToolsHome

    if (-not (Test-Path $script:InfraHostsPath)) {
        return @()
    }

    return @(Import-Csv -Path $script:InfraHostsPath | Where-Object { $_.Name -and $_.HostName })
}

function Add-InfraHostRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [bool]$SshEnabled = $false,

        [string]$User = "",

        [int]$Port = 22,

        [bool]$InSshConfig = $false,

        [bool]$Docker = $false,

        [string]$Services = "",

        [string]$PreviousName = ""
    )

    Ensure-ShellToolsHome

    $records = @(Get-InfraHosts | Where-Object { $_.Name -ne $Name -and $_.Name -ne $PreviousName })
    $records += [PSCustomObject]@{
        Name        = $Name
        HostName    = $HostName
        SshEnabled  = $SshEnabled.ToString().ToLowerInvariant()
        User        = $User
        Port        = if ($SshEnabled) { $Port } else { "" }
        InSshConfig = $InSshConfig.ToString().ToLowerInvariant()
        Docker      = $Docker.ToString().ToLowerInvariant()
        Services    = $Services
    }

    $records | Sort-Object Name | Export-Csv -Path $script:InfraHostsPath -NoTypeInformation -Encoding UTF8
}

function Ensure-SshKey {
    $sshDir = Join-Path $HOME ".ssh"
    $keyPath = Join-Path $sshDir "id_ed25519"
    $publicKeyPath = "$keyPath.pub"

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
    }

    if (-not (Test-Path $publicKeyPath)) {
        if (Read-ShellToolsYesNo "No ed25519 SSH key found. Generate one now?" $true) {
            $comment = "{0}@{1}-shell-alias-tools" -f $env:USERNAME, $env:COMPUTERNAME
            & ssh-keygen -t ed25519 -C $comment -f $keyPath
        }
    }

    if (Test-Path $publicKeyPath) {
        Write-Host ""
        Write-Host "Public key ready:" -ForegroundColor Cyan
        Write-Host $publicKeyPath -ForegroundColor DarkGray
        Get-Content $publicKeyPath
        Write-Host ""
        Write-Host "Copy that key into the remote host's ~/.ssh/authorized_keys." -ForegroundColor Yellow
    }
}

function Remove-SshConfigHost {
    param([string]$Name)

    $configPath = Join-Path $HOME ".ssh\config"
    if (-not (Test-Path $configPath)) {
        return
    }

    $lines = @(Get-Content $configPath -ErrorAction SilentlyContinue)
    $kept = New-Object System.Collections.Generic.List[string]
    $skip = $false

    foreach ($line in $lines) {
        if ($line -match '^\s*Host\s+(.+)$') {
            $hostNames = $matches[1] -split '\s+'
            $skip = [bool]($hostNames | Where-Object { $_ -eq $Name })
            if ($skip) {
                continue
            }
        }

        if (-not $skip) {
            $kept.Add($line)
        }
    }

    Set-Content -Path $configPath -Value $kept -Encoding UTF8
}

function Set-SshConfigHost {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [string]$User,

        [int]$Port = 22,

        [string]$PreviousName = ""
    )

    $sshDir = Join-Path $HOME ".ssh"
    $configPath = Join-Path $sshDir "config"

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
    }

    if (-not (Test-Path $configPath)) {
        New-Item -ItemType File -Force -Path $configPath | Out-Null
    }

    if ($PreviousName) {
        Remove-SshConfigHost $PreviousName
    }
    Remove-SshConfigHost $Name

    $entry = @"

Host $Name
    HostName $HostName
    User $User
    Port $Port
    ServerAliveInterval 30
    ServerAliveCountMax 3
"@

    Add-Content -Path $configPath -Value $entry
    Write-Host "SSH config updated: ssh $Name" -ForegroundColor Green
}

function Add-InfraHost {
    param(
        [string]$Name,
        [string]$HostName
    )

    Write-Host ""
    Write-Host "Infra host onboarding" -ForegroundColor Cyan

    $Name = Resolve-ShellToolsValidatedValue -Value $Name -Prompt "Host alias" -Default "server1" -Validator ${function:Test-ShellToolsInfraName} -ErrorMessage "Use a host alias like server1, docker-vm, or app01. Letters, numbers, dot, dash, underscore; start with a letter."
    $HostName = Resolve-ShellToolsValidatedValue -Value $HostName -Prompt "Host IPv4, example 192.168.1.X" -Default "" -Validator ${function:Test-ShellToolsIPv4} -ErrorMessage "This is not an IPv4 address. Example: 192.168.1.187."

    $sshEnabled = Read-ShellToolsYesNo "SSH access to this host?" $true
    $user = ""
    $port = 22
    $inSshConfig = $false

    if ($sshEnabled) {
        $user = Read-ShellToolsValidatedDefault -Prompt "SSH user" -Default "admin" -Validator ${function:Test-ShellToolsUser} -ErrorMessage "Use a simple SSH user, like admin, ubuntu, or deploy."
        $port = Resolve-ShellToolsPortValue -Value 0 -Prompt "SSH port" -Default 22

        if (Read-ShellToolsYesNo "Add this host to ~/.ssh/config?" $true) {
            $inSshConfig = $true
            Ensure-SshKey
            Set-SshConfigHost -Name $Name -HostName $HostName -User $user -Port $port
            Write-Host ""
            Write-Host "Copy the public key above to the host, then type:" -ForegroundColor Cyan
            Write-Host "  ssh $Name"
            Write-Host "To list all SSH shortcuts, type:"
            Write-Host "  sshhosts"
            Write-Host ""
        }
    }

    $docker = Read-ShellToolsYesNo "Does this host use Docker?" $false
    if ($docker -and -not $sshEnabled) {
        Write-Host "Docker discovery needs SSH later. You can still save the host now." -ForegroundColor Yellow
    }

    $services = Read-ShellToolsServices -HostName $HostName

    Add-InfraHostRecord -Name $Name -HostName $HostName -SshEnabled:$sshEnabled -User $user -Port $port -InSshConfig:$inSshConfig -Docker:$docker -Services $services
    Write-Host "Infra host saved: $Name ($HostName)" -ForegroundColor Green
}

function Select-InfraHostName {
    param([string]$Name)

    $hosts = @(Get-InfraHosts)
    if ($hosts.Count -eq 0) {
        Write-Host "No infra hosts configured." -ForegroundColor Yellow
        return $null
    }

    if ($Name) {
        if ($hosts.Name -contains $Name) {
            return $Name
        }

        Write-Host "Infra host '$Name' was not found." -ForegroundColor Yellow
    }

    $names = @($hosts.Name | Sort-Object)
    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        return ($names | fzf --height 40% --layout reverse --border --prompt "Infra host > ")
    }

    for ($i = 0; $i -lt $names.Count; $i++) {
        Write-Host ("{0,2}) {1}" -f ($i + 1), $names[$i])
    }

    while ($true) {
        $choice = Read-ShellToolsDefault "Host number" "1"
        if ($choice -match '^\d+$') {
            $index = [int]$choice - 1
            if ($index -ge 0 -and $index -lt $names.Count) {
                return $names[$index]
            }
        }

        Write-Host "Choose a valid host number." -ForegroundColor Yellow
    }
}

function Edit-InfraHost {
    param([string]$Name)

    $selectedName = Select-InfraHostName $Name
    if (-not $selectedName) {
        return
    }

    $current = @(Get-InfraHosts | Where-Object { $_.Name -eq $selectedName } | Select-Object -First 1)[0]
    if (-not $current) {
        Write-Host "Infra host '$selectedName' was not found." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Editing infra host: $selectedName" -ForegroundColor Cyan

    $newName = Read-ShellToolsValidatedDefault -Prompt "Host alias" -Default $current.Name -Validator ${function:Test-ShellToolsInfraName} -ErrorMessage "Use a host alias like server1, docker-vm, or app01."
    $newHostName = Read-ShellToolsValidatedDefault -Prompt "Host IPv4, example 192.168.1.X" -Default $current.HostName -Validator ${function:Test-ShellToolsIPv4} -ErrorMessage "This is not an IPv4 address. Example: 192.168.1.187."

    $sshEnabled = Read-ShellToolsYesNo "SSH access to this host?" ($current.SshEnabled -eq "true")
    $user = ""
    $port = 22
    $inSshConfig = $false

    if ($sshEnabled) {
        $user = Read-ShellToolsValidatedDefault -Prompt "SSH user" -Default $(if ($current.User) { $current.User } else { "admin" }) -Validator ${function:Test-ShellToolsUser} -ErrorMessage "Use a simple SSH user, like admin, ubuntu, or deploy."
        $defaultPort = if ($current.Port -match '^\d+$') { [int]$current.Port } else { 22 }
        $port = Resolve-ShellToolsPortValue -Value 0 -Prompt "SSH port" -Default $defaultPort

        if (Read-ShellToolsYesNo "Update/add this host in ~/.ssh/config?" ($current.InSshConfig -eq "true")) {
            $inSshConfig = $true
            Ensure-SshKey
            Set-SshConfigHost -Name $newName -HostName $newHostName -User $user -Port $port -PreviousName $current.Name
            Write-Host ""
            Write-Host "Copy the public key above to the host, then type:" -ForegroundColor Cyan
            Write-Host "  ssh $newName"
            Write-Host "To list all SSH shortcuts, type:"
            Write-Host "  sshhosts"
            Write-Host ""
        }
    }

    $docker = Read-ShellToolsYesNo "Does this host use Docker?" ($current.Docker -eq "true")
    $services = Read-ShellToolsServices -HostName $newHostName -Existing $current.Services

    Add-InfraHostRecord -Name $newName -HostName $newHostName -SshEnabled:$sshEnabled -User $user -Port $port -InSshConfig:$inSshConfig -Docker:$docker -Services $services -PreviousName $current.Name
    Write-Host "Infra host updated." -ForegroundColor Green
}

function Initialize-ShellTools {
    if (-not (Test-ShellDeckControlProfile)) {
        Write-Host "Workstation profile is active. Infra setup is disabled." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Shell Alias Tools setup" -ForegroundColor Cyan

    $hosts = @(Get-InfraHosts)
    if ($hosts.Count -eq 0) {
        if (Read-ShellToolsYesNo "Configure your first infra host now?" $true) {
            Add-InfraHost
        }
    }

    while (Read-ShellToolsYesNo "Add another infra server?" $false) {
        Add-InfraHost
    }

    Write-Host ""
    Write-Host "Setup complete. Run init to open the infra dashboard." -ForegroundColor Green
}

function Test-ShellToolsTcpPort {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    if (Get-Command Test-NetConnection -ErrorAction SilentlyContinue) {
        return (Test-NetConnection -ComputerName $HostName -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue)
    }

    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        $success = $async.AsyncWaitHandle.WaitOne(2000, $false)
        $client.Close()
        return $success
    }
    catch {
        return $false
    }
}

function Get-ShellToolsServicePort {
    param([string]$Service)

    try {
        $uri = [Uri]$Service
        if ($uri.Port -gt 0) {
            return $uri.Port
        }

        if ($uri.Scheme -eq "https") {
            return 443
        }
        return 80
    }
    catch {
        return $null
    }
}

function Get-ShellToolsServiceHost {
    param([string]$Service)

    try {
        return ([Uri]$Service).Host
    }
    catch {
        return ""
    }
}

function Show-ShellToolsServices {
    param([string]$Services)

    if (-not $Services) {
        return
    }

    foreach ($service in ($Services -split ";" | Where-Object { $_ })) {
        $serviceHost = Get-ShellToolsServiceHost $service
        $servicePort = Get-ShellToolsServicePort $service
        if (-not $serviceHost -or -not $servicePort) {
            Write-Host ("  service   {0,-34} INVALID" -f $service) -ForegroundColor Yellow
            continue
        }

        $open = Test-ShellToolsTcpPort -HostName $serviceHost -Port $servicePort
        $state = if ($open) { "OPEN" } else { "CLOSED" }
        $color = if ($open) { "Green" } else { "Red" }
        Write-Host ("  service   {0,-34} {1,-6} {2}:{3}" -f $service, $state, $serviceHost, $servicePort) -ForegroundColor $color
    }
}

function Show-DockerServicesForHost {
    param(
        [Parameter(Mandatory = $true)]
        $HostRecord
    )

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        return
    }

    if ($HostRecord.SshEnabled -ne "true" -or $HostRecord.Docker -ne "true") {
        return
    }

    try {
        if ($HostRecord.InSshConfig -eq "true") {
            $containers = & ssh -o BatchMode=yes -o ConnectTimeout=3 $HostRecord.Name "docker ps --format '{{.Names}}|{{.Ports}}'" 2>$null
        }
        else {
            $target = "{0}@{1}" -f $HostRecord.User, $HostRecord.HostName
            $containers = & ssh -o BatchMode=yes -o ConnectTimeout=3 -p $HostRecord.Port $target "docker ps --format '{{.Names}}|{{.Ports}}'" 2>$null
        }

        if (-not $containers) {
            return
        }

        Write-Host ""
        Write-Host ("  Docker containers on {0}" -f $HostRecord.Name) -ForegroundColor Yellow
        foreach ($line in $containers) {
            $parts = $line -split "\|", 2
            $containerName = $parts[0]
            $ports = if ($parts.Count -gt 1) { $parts[1] } else { "" }

            if ($ports -match ":(\d+)->") {
                $url = "http://{0}:{1}" -f $HostRecord.HostName, $matches[1]
                Write-Host ("  docker    {0,-34} OPEN   {1}" -f $containerName, $url) -ForegroundColor Green
            }
            else {
                Write-Host ("  docker    {0,-34} INT    internal" -f $containerName) -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host ("  Docker scan failed on {0}" -f $HostRecord.Name) -ForegroundColor Red
    }
}

function init {
    if (-not (Test-ShellDeckControlProfile)) {
        Write-Host "Workstation profile is active. Infra dashboard is disabled." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "+------------------------------------------------------------+" -ForegroundColor Blue
    Write-Host "| SHELL INFRA DASHBOARD                                      |" -ForegroundColor Blue
    Write-Host "+------------------------------------------------------------+" -ForegroundColor Blue
    Write-Host ""

    $hosts = @(Get-InfraHosts)
    if ($hosts.Count -eq 0) {
        Write-Host "No infra hosts configured yet." -ForegroundColor Yellow
        if (Read-ShellToolsYesNo "Run interactive setup now?" $true) {
            Initialize-ShellTools
            $hosts = @(Get-InfraHosts)
        }
    }

    foreach ($hostRecord in $hosts) {
        $pingOk = $false
        try {
            $pingOk = Test-Connection -ComputerName $hostRecord.HostName -Count 1 -Quiet -ErrorAction SilentlyContinue
        }
        catch {
            $pingOk = $false
        }

        $pingStatus = if ($pingOk) { "UP" } else { "DOWN" }
        $pingColor = if ($pingOk) { "Green" } else { "Red" }
        Write-Host ("{0,-14} {1,-15} {2,-8} ssh:{3,-5} docker:{4,-5}" -f $hostRecord.Name, $hostRecord.HostName, $pingStatus, $hostRecord.SshEnabled, $hostRecord.Docker) -ForegroundColor $pingColor

        if ($hostRecord.SshEnabled -eq "true" -and $hostRecord.Port -match '^\d+$') {
            $open = Test-ShellToolsTcpPort -HostName $hostRecord.HostName -Port ([int]$hostRecord.Port)
            $state = if ($open) { "OPEN" } else { "CLOSED" }
            $color = if ($open) { "Green" } else { "Red" }
            Write-Host ("  ssh       {0,-34} {1,-6} {2}:{3}" -f "ssh $($hostRecord.Name)", $state, $hostRecord.HostName, $hostRecord.Port) -ForegroundColor $color
        }

        Show-ShellToolsServices $hostRecord.Services
        Show-DockerServicesForHost -HostRecord $hostRecord
    }

    Write-Host ""
}

function infra-add {
    Add-InfraHost
}

function infra-edit {
    param([string]$Name)
    Edit-InfraHost -Name $Name
}

function infra-list {
    $hosts = @(Get-InfraHosts)
    if ($hosts.Count -eq 0) {
        Write-Host "No infra hosts configured." -ForegroundColor Yellow
        return
    }

    $hosts | Format-Table Name, HostName, SshEnabled, User, Port, InSshConfig, Docker, Services -AutoSize
}

function sshhosts {
    $configPath = Join-Path $HOME ".ssh\config"

    if (-not (Test-Path $configPath)) {
        Write-Host "No SSH config found." -ForegroundColor Red
        return
    }

    $hosts = Get-Content $configPath |
        Where-Object { $_ -match '^\s*Host\s+(.+)$' } |
        ForEach-Object { ($_ -replace '^\s*Host\s+', '').Trim() } |
        Where-Object { $_ -notmatch '\*|\?' } |
        Sort-Object -Unique

    if (-not $hosts) {
        Write-Host "No concrete SSH hosts found." -ForegroundColor Yellow
        return
    }

    $selected = $null
    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        $selected = $hosts | fzf --height 40% --layout reverse --border --prompt "SSH > "
    }
    else {
        for ($i = 0; $i -lt $hosts.Count; $i++) {
            Write-Host ("{0,2}) {1}" -f ($i + 1), $hosts[$i])
        }

        $choice = Read-ShellToolsDefault "Connect to host number" "1"
        $index = [int]$choice - 1
        if ($index -ge 0 -and $index -lt $hosts.Count) {
            $selected = $hosts[$index]
        }
    }

    if ($selected) {
        Clear-Host
        Write-Host ""
        Write-Host "Connecting to $selected ..." -ForegroundColor Cyan
        Write-Host ""
        ssh $selected
    }
}

function check-tools {
    $results = Get-ShellToolsSmartToolList | ForEach-Object {
        $path = Get-ShellToolsToolPath $_
        [PSCustomObject]@{
            Tool   = $_
            Status = if ($path) { "OK" } else { "missing" }
            Path   = $path
        }
    }

    $results | Format-Table -AutoSize
}

function Get-ShellToolsSmartToolSummary {
    $tools = @(Get-ShellToolsSmartToolList)
    $installed = @($tools | Where-Object { Get-ShellToolsToolPath $_ }).Count
    return ("{0}/{1}" -f $installed, $tools.Count)
}

function Edit-Profile {
    if (Get-Command cursor -ErrorAction SilentlyContinue) {
        cursor $PROFILE
    }
    elseif (Get-Command code -ErrorAction SilentlyContinue) {
        code $PROFILE
    }
    else {
        notepad $PROFILE
    }
}

function Reload-Profile {
    . $PROFILE
    Write-Host "Profile reloaded." -ForegroundColor Green
}

function add-func {
    param(
        [Parameter(Mandatory = $true)]
        [string]$name,

        [Parameter(Mandatory = $true)]
        [string]$body
    )

    if ($env:SHELL_TOOLS_ENABLE_CUSTOM_FUNCTIONS -ne "1") {
        Write-Host "add-func is disabled by default because it stores executable PowerShell code." -ForegroundColor Yellow
        Write-Host "Enable it with: `$env:SHELL_TOOLS_ENABLE_CUSTOM_FUNCTIONS='1'" -ForegroundColor Yellow
        return
    }

    Ensure-ShellToolsHome

    if (Get-Command $name -ErrorAction SilentlyContinue) {
        Write-Host "'$name' already exists in this session." -ForegroundColor Yellow
        return
    }

    $funcText = @"

function $name {
    $body
}

"@

    Add-Content -Path $script:AliasToolsPath -Value $funcText
    Invoke-Expression "function $name { $body }"

    Write-Host "Function '$name' created and loaded." -ForegroundColor Green
}

function list-funcs {
    Ensure-ShellToolsHome

    $matches = Select-String -Path $script:AliasToolsPath -Pattern '^\s*function\s+([a-zA-Z0-9\-_]+)' -AllMatches -ErrorAction SilentlyContinue
    if (-not $matches) {
        Write-Host "No custom functions found." -ForegroundColor Yellow
        return
    }

    $names = foreach ($match in $matches) {
        foreach ($item in $match.Matches) {
            $item.Groups[1].Value
        }
    }

    $names | Sort-Object -Unique
}

function add-last-func {
    param([Parameter(Mandatory = $true)][string]$name)

    $last = (Get-History -Count 1).CommandLine
    if (-not $last) {
        Write-Host "No previous command found." -ForegroundColor Yellow
        return
    }

    add-func $name $last
}

function ll {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza -lah --git --icons=auto --group-directories-first @args
    }
    else {
        Get-ChildItem -Force @args
    }
}

function la {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza -a --icons=auto --group-directories-first @args
    }
    else {
        Get-ChildItem -Force @args
    }
}

function l {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --icons=auto --group-directories-first @args
    }
    else {
        Get-ChildItem @args
    }
}

function lt {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --tree --level=2 --icons=auto --git @args
    }
    else {
        tree @args
    }
}

function catp {
    if (Get-Command bat -ErrorAction SilentlyContinue) {
        bat --paging=always @args
    }
    else {
        Get-Content @args
    }
}

function cat {
    if (Get-Command bat -ErrorAction SilentlyContinue) {
        bat @args
    }
    else {
        Get-Content @args
    }
}

function mkcd {
    param([Parameter(Mandatory = $true)][string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    Set-Location $Path
}

function cdf {
    param([string]$Root = ".")

    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "fzf is missing. Run check-tools, then install dependencies if needed." -ForegroundColor Yellow
        return
    }

    if (Get-Command fd -ErrorAction SilentlyContinue) {
        $selected = fd --type d --hidden --exclude .git . $Root | fzf --height 40% --layout reverse --border --prompt "cd > "
    }
    else {
        $selected = Get-ChildItem -Path $Root -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\.git(\\|$)' } |
            ForEach-Object { $_.FullName } |
            fzf --height 40% --layout reverse --border --prompt "cd > "
    }

    if ($selected) {
        Set-Location $selected
    }
}

function ff {
    param([string]$Root = ".")

    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "fzf is missing. Run check-tools, then install dependencies if needed." -ForegroundColor Yellow
        return
    }

    $preview = if (Get-Command bat -ErrorAction SilentlyContinue) {
        "bat --style=numbers --color=always --line-range=:200 {}"
    }
    else {
        "powershell -NoProfile -Command `"Get-Content -TotalCount 200 -LiteralPath '{}'`""
    }

    if (Get-Command fd -ErrorAction SilentlyContinue) {
        return (fd --type f --hidden --exclude .git . $Root | fzf --height 70% --layout reverse --border --preview $preview --prompt "file > ")
    }

    if (Get-Command rg -ErrorAction SilentlyContinue) {
        return (rg --files $Root | fzf --height 70% --layout reverse --border --preview $preview --prompt "file > ")
    }

    return (Get-ChildItem -Path $Root -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\.git(\\|$)' } |
        ForEach-Object { $_.FullName } |
        fzf --height 70% --layout reverse --border --preview $preview --prompt "file > ")
}

function fe {
    param([string]$Root = ".")

    $file = ff $Root
    if (-not $file) {
        return
    }

    if ($env:EDITOR -and (Get-Command $env:EDITOR -ErrorAction SilentlyContinue)) {
        & $env:EDITOR $file
    }
    elseif (Get-Command nvim -ErrorAction SilentlyContinue) {
        nvim $file
    }
    elseif (Get-Command code -ErrorAction SilentlyContinue) {
        code $file
    }
    else {
        notepad $file
    }
}

function extract {
    param([Parameter(Mandatory = $true)][string]$Archive)

    if (-not (Test-Path $Archive)) {
        Write-Host "Archive not found: $Archive" -ForegroundColor Yellow
        return
    }

    if ($Archive -match '\.zip$') {
        Expand-Archive -LiteralPath $Archive -DestinationPath .
        return
    }

    if (Get-Command tar -ErrorAction SilentlyContinue) {
        tar -xf $Archive
        return
    }

    Write-Host "Unsupported archive or missing tar: $Archive" -ForegroundColor Yellow
}

function serve {
    param([int]$Port = 8000)

    if (Get-Command python -ErrorAction SilentlyContinue) {
        python -m http.server $Port
    }
    elseif (Get-Command py -ErrorAction SilentlyContinue) {
        py -m http.server $Port
    }
    else {
        Write-Host "Python is missing, cannot start a quick file server." -ForegroundColor Yellow
    }
}

function ports {
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        Get-NetTCPConnection -State Listen | Sort-Object LocalPort | Format-Table LocalAddress, LocalPort, OwningProcess -AutoSize
    }
    else {
        netstat -ano
    }
}

function dps {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        docker ps @args
    }
    else {
        Write-Host "Docker is missing. Run check-tools, then install Docker if this machine should use it." -ForegroundColor Yellow
    }
}

function dcu {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        docker compose up -d @args
    }
    else {
        Write-Host "Docker is missing. Run check-tools, then install Docker if this machine should use it." -ForegroundColor Yellow
    }
}

function dcd {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        docker compose down @args
    }
    else {
        Write-Host "Docker is missing. Run check-tools, then install Docker if this machine should use it." -ForegroundColor Yellow
    }
}

function dcl {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        docker compose logs -f @args
    }
    else {
        Write-Host "Docker is missing. Run check-tools, then install Docker if this machine should use it." -ForegroundColor Yellow
    }
}

function pathlist {
    $env:PATH -split ';'
}

function sysupdate {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget upgrade --all
    }
    else {
        Write-Host "winget is not available." -ForegroundColor Yellow
    }
}

function please {
    if ($env:SHELL_TOOLS_ENABLE_PLEASE -ne "1") {
        Write-Host "please is disabled by default because it re-runs history elevated." -ForegroundColor Yellow
        Write-Host "Enable it with: `$env:SHELL_TOOLS_ENABLE_PLEASE='1'" -ForegroundColor Yellow
        return
    }

    $last = (Get-History -Count 1).CommandLine
    if (-not $last) {
        Write-Host "No previous command found." -ForegroundColor Yellow
        return
    }

    if (Get-Command sudo -ErrorAction SilentlyContinue) {
        sudo pwsh -NoProfile -Command $last
        return
    }

    Start-Process powershell.exe -Verb RunAs -ArgumentList @("-NoExit", "-Command", $last)
}

function myip {
    try {
        Invoke-RestMethod -Uri "https://ifconfig.me/ip"
    }
    catch {
        Get-PrimaryIPv4
    }
}

function g {
    git @args
}

function gs {
    git status
}

function ga {
    if ($args.Count -gt 0) {
        git add @args
    }
    else {
        git add .
    }
}

function gc {
    git commit -m @args
}

function gp {
    git push @args
}

function gl {
    git log --oneline --graph --decorate --all -20
}

function gd {
    git diff @args
}

function Show-ShellDashboard {
    if ($env:SHELL_TOOLS_NO_DASHBOARD -eq "1") {
        return
    }

    $ip = Get-PrimaryIPv4
    $profileLabel = Get-ShellDeckMachineProfileLabel
    $hostCount = if (Test-ShellDeckControlProfile) { @(Get-InfraHosts).Count } else { 0 }
    $uptime = Get-ShortUptime
    $disk = Get-ShellToolsDiskSummary
    $toolSummary = Get-ShellToolsSmartToolSummary

    Write-Host ""
    Write-Host ("=" * 58) -ForegroundColor DarkGray
    Write-Host ("ShellDeck ready - {0}@{1}" -f (whoami), $env:COMPUTERNAME) -ForegroundColor Cyan
    Write-Host ("IP: {0} | Uptime: {1}" -f $ip, $uptime) -ForegroundColor Magenta
    if (Test-ShellDeckControlProfile) {
        Write-Host ("Disk: {0} | Profile: {1} | Infra hosts: {2}" -f $disk, $profileLabel, $hostCount) -ForegroundColor DarkCyan
    }
    else {
        Write-Host ("Disk: {0} | Profile: {1}" -f $disk, $profileLabel) -ForegroundColor DarkCyan
    }
    Write-Host ("Smart tools: {0} | Try: ll, ff, fe, cdf, ports, sysupdate" -f $toolSummary) -ForegroundColor Magenta
    Write-Host ("=" * 58) -ForegroundColor DarkGray
    Write-Host "ff         -> fuzzy file finder"
    if (Test-ShellDeckControlProfile) {
        Write-Host "init       -> infra dashboard"
        Write-Host "sshhosts   -> connect to SSH host"
        Write-Host "infra-add  -> add server"
        Write-Host "infra-edit -> modify server"
    }
    Write-Host "check-tools-> dependency check"
    Write-Host "myhelp     -> all commands"
    Write-Host ""
}

function myhelp {
    Write-Host ""
    Write-Host "COMMANDS" -ForegroundColor Cyan
    Write-Host ""
    if (Test-ShellDeckControlProfile) {
        Write-Host "init          Infra dashboard"
        Write-Host "shellsetup    Interactive first-run setup"
        Write-Host "infra-add     Add a server to infra config"
        Write-Host "infra-edit    Modify an infra server"
        Write-Host "infra-list    List configured servers"
        Write-Host "sshhosts      Pick an SSH host and connect"
    }
    Write-Host "check-tools   Check local CLI dependencies"
    Write-Host "shelluninstall Remove profile hook and optional data"
    Write-Host "ll/la/l/lt    Smart listing via eza when available"
    Write-Host "cat/catp      Pretty file reading via bat when available"
    Write-Host "cdf           Fuzzy cd into a directory with fzf"
    Write-Host "ff            Fuzzy find a file with preview"
    Write-Host "fe            Fuzzy find a file and open it in editor"
    Write-Host "mkcd          Create a directory and cd into it"
    Write-Host "please        Re-run the previous command elevated (opt-in)"
    Write-Host "extract       Extract common archive formats"
    Write-Host "serve         Start a quick HTTP file server"
    Write-Host "ports         Show listening TCP ports"
    Write-Host "dps/dcu/dcd/dcl Docker ps, compose up/down/logs"
    Write-Host "pathlist      Print PATH one entry per line"
    Write-Host "sysupdate     Update with winget"
    Write-Host "ep            Edit PowerShell profile"
    Write-Host "reloadp       Reload profile"
    Write-Host "add-func      Save a custom function"
    Write-Host "aa            Save the previous command as a function"
    Write-Host "lf            List saved functions"
    Write-Host ""
}

function Remove-ShellToolsProfileHook {
    param([string]$ProfilePath)

    if (-not (Test-Path $ProfilePath)) {
        return
    }

    $content = Get-Content -Raw -Path $ProfilePath
    $pattern = '(?s)\r?\n?# >>> shell-alias-tools >>>.*?# <<< shell-alias-tools <<<\r?\n?'
    $updated = [regex]::Replace($content, $pattern, [Environment]::NewLine)

    if ($updated -ne $content) {
        Set-Content -Path $ProfilePath -Value $updated.TrimEnd() -Encoding UTF8
        Write-Host "Removed profile hook: $ProfilePath" -ForegroundColor Green
    }
}

function Uninstall-ShellTools {
    Write-Host ""
    Write-Host "Shell Alias Tools uninstall" -ForegroundColor Cyan

    if (-not (Read-ShellToolsYesNo "Remove Shell Alias Tools from your PowerShell profile?" $true)) {
        return
    }

    Remove-ShellToolsProfileHook -ProfilePath $PROFILE

    if (Read-ShellToolsYesNo "Delete $script:ShellToolsRoot including aliases, config, and any infra data?" $false) {
        if (Test-Path $script:ShellToolsRoot) {
            Remove-Item -LiteralPath $script:ShellToolsRoot -Recurse -Force
            Write-Host "Deleted $script:ShellToolsRoot" -ForegroundColor Green
        }
    }
    else {
        Write-Host "Kept $script:ShellToolsRoot. SSH config is left untouched." -ForegroundColor Yellow
    }

    Write-Host "Restart PowerShell to finish unloading the current session." -ForegroundColor Cyan
}

function shelluninstall {
    Uninstall-ShellTools
}

function Get-ShellToolsGitBranch {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return ""
    }

    try {
        $branch = git branch --show-current 2>$null
        if (-not $branch) {
            $branch = git rev-parse --short HEAD 2>$null
        }
        if ($branch) {
            return " ($branch)"
        }
    }
    catch {
        return ""
    }

    return ""
}

function Enable-ShellToolsStarship {
    if ($env:SHELL_TOOLS_NO_PROMPT -eq "1") {
        return $false
    }

    if (-not (Get-Command starship -ErrorAction SilentlyContinue)) {
        return $false
    }

    try {
        Invoke-Expression (&starship init powershell)
        return $true
    }
    catch {
        return $false
    }
}

$script:ShellToolsStarshipReady = Enable-ShellToolsStarship

if ($env:SHELL_TOOLS_NO_PROMPT -ne "1" -and -not $script:ShellToolsStarshipReady) {
    function global:prompt {
        $branch = Get-ShellToolsGitBranch
        Write-Host ("{0}@{1} " -f $env:USERNAME, $env:COMPUTERNAME) -NoNewline -ForegroundColor Cyan
        Write-Host (Get-Location) -NoNewline -ForegroundColor Blue
        if ($branch) {
            Write-Host $branch -NoNewline -ForegroundColor Yellow
        }
        Write-Host ""
        return "PS> "
    }
}

foreach ($shellToolsAlias in @("cat", "g", "gs", "ga", "gc", "gp", "gl", "gd", "ll", "la", "l", "lt", "dps", "dcu", "dcd", "dcl")) {
    if (Test-Path "Alias:$shellToolsAlias") {
        Remove-Item "Alias:$shellToolsAlias" -Force -ErrorAction SilentlyContinue
    }
}

Set-Alias ep Edit-Profile -Scope Global -Force
Set-Alias reloadp Reload-Profile -Scope Global -Force
Set-Alias aa add-last-func -Scope Global -Force
Set-Alias lf list-funcs -Scope Global -Force
if (Test-ShellDeckControlProfile) {
    Set-Alias shellsetup Initialize-ShellTools -Scope Global -Force
}
else {
    foreach ($infraCommand in @("init", "infra-add", "infra-edit", "infra-list", "sshhosts", "Initialize-ShellTools", "Add-InfraHost", "Edit-InfraHost", "Select-InfraHostName")) {
        if (Test-Path "Function:$infraCommand") {
            Remove-Item "Function:$infraCommand" -Force -ErrorAction SilentlyContinue
        }
    }

    if (Test-Path "Alias:shellsetup") {
        Remove-Item "Alias:shellsetup" -Force -ErrorAction SilentlyContinue
    }
}
Set-Alias myh myhelp -Scope Global -Force

Show-ShellDashboard
