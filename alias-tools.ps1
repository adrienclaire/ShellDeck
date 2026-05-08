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

function Ensure-ShellToolsHome {
    if (-not (Test-Path $script:ShellToolsRoot)) {
        New-Item -ItemType Directory -Force -Path $script:ShellToolsRoot | Out-Null
    }

    if (-not (Test-Path $script:AliasToolsPath)) {
        New-Item -ItemType File -Force -Path $script:AliasToolsPath | Out-Null
    }

    if (-not (Test-Path $script:InfraHostsPath)) {
        "Name,HostName,User,Port,Role,CheckPorts,Url,SshEnabled" |
            Set-Content -Path $script:InfraHostsPath -Encoding UTF8
    }
}

Ensure-ShellToolsHome

if (Test-Path $script:AliasToolsPath) {
    . $script:AliasToolsPath
}

function Write-ShellToolsLine {
    param(
        [string]$Text = "",
        [string]$Color = "White"
    )

    Write-Host $Text -ForegroundColor $Color
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

function Test-ShellToolsRole {
    param([string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -notmatch '[,\r\n]')
}

function Test-ShellToolsUrl {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    $uri = $null
    return [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in @("http", "https")
}

function Test-ShellToolsPortValue {
    param([string]$Value)

    if ($Value -notmatch '^\d+$') {
        return $false
    }

    $port = [int]$Value
    return ($port -ge 1 -and $port -le 65535)
}

function Convert-ShellToolsPortList {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $ports = @()
    $items = $Value.Trim() -split '[;,\s]+' | Where-Object { $_ }
    foreach ($item in $items) {
        if (-not (Test-ShellToolsPortValue $item)) {
            return $null
        }

        $ports += ([int]$item).ToString()
    }

    if ($ports.Count -eq 0) {
        return $null
    }

    return (($ports | Select-Object -Unique) -join ";")
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

function Resolve-ShellToolsPortList {
    param(
        [string]$Value,
        [string]$Prompt,
        [string]$Default
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $normalized = Convert-ShellToolsPortList $Value
        if ($normalized) {
            return $normalized
        }

        Write-Host "'$Value' is not a valid port list. Use values like 22;8006 or 22, 8006." -ForegroundColor Yellow
    }

    while ($true) {
        $answer = Read-ShellToolsDefault $Prompt $Default
        $normalized = Convert-ShellToolsPortList $answer
        if ($normalized) {
            return $normalized
        }

        Write-Host "This is not a valid port list. Use values like 22;8006 or 22, 8006." -ForegroundColor Yellow
    }
}

function Get-PrimaryIPv4 {
    try {
        if (Get-Command Get-NetIPConfiguration -ErrorAction SilentlyContinue) {
            $ip = Get-NetIPConfiguration |
                Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.IPv4Address.IPAddress -notlike "169.254.*" } |
                Select-Object -First 1 |
                ForEach-Object { $_.IPv4Address.IPAddress }

            if ($ip) {
                return $ip
            }
        }
    }
    catch {
        # Fall through to the .NET network adapter fallback.
    }

    try {
        $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object {
                $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up -and
                $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback
            }

        foreach ($interface in $interfaces) {
            foreach ($address in $interface.GetIPProperties().UnicastAddresses) {
                if ($address.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                    $candidate = $address.Address.IPAddressToString
                    if ($candidate -and $candidate -notlike "169.254.*") {
                        return $candidate
                    }
                }
            }
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
        $drive = Get-PSDrive -Name (Split-Path $HOME -Qualifier).TrimEnd(":") -ErrorAction Stop
        $freeGb = [math]::Round($drive.Free / 1GB, 1)
        $totalGb = [math]::Round(($drive.Free + $drive.Used) / 1GB, 1)
        return ("{0} GB free / {1} GB" -f $freeGb, $totalGb)
    }
    catch {
        return "unknown"
    }
}

function Get-InfraHosts {
    Ensure-ShellToolsHome

    if (-not (Test-Path $script:InfraHostsPath)) {
        return @()
    }

    $hosts = @(Import-Csv -Path $script:InfraHostsPath)
    return $hosts | Where-Object { $_.Name -and $_.HostName }
}

function Add-InfraHostRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [string]$User,

        [int]$Port = 22,

        [string]$Role = "server",

        [string]$CheckPorts = "22",

        [string]$Url = "",

        [bool]$SshEnabled = $true,

        [string]$PreviousName = ""
    )

    Ensure-ShellToolsHome

    $records = @(Get-InfraHosts | Where-Object { $_.Name -ne $Name -and $_.Name -ne $PreviousName })
    $records += [PSCustomObject]@{
        Name       = $Name
        HostName   = $HostName
        User       = $User
        Port       = $Port
        Role       = $Role
        CheckPorts = $CheckPorts
        Url        = $Url
        SshEnabled = $SshEnabled.ToString().ToLowerInvariant()
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
    $exists = Select-String -Path $configPath -Pattern "^\s*Host\s+$escaped\s*$" -Quiet -ErrorAction SilentlyContinue
    if ($exists) {
        Write-Host "SSH config already has Host $Name. Keeping it." -ForegroundColor Yellow
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
    Write-Host "SSH host added: ssh $Name" -ForegroundColor Green
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

    $lines = @(Get-Content $configPath -ErrorAction SilentlyContinue)
    $kept = New-Object System.Collections.Generic.List[string]
    $skip = $false
    $namesToRemove = @($Name)
    if ($PreviousName) {
        $namesToRemove += $PreviousName
    }

    foreach ($line in $lines) {
        if ($line -match '^\s*Host\s+(.+)$') {
            $hostNames = $matches[1] -split '\s+'
            if ($hostNames | Where-Object { $_ -in $namesToRemove }) {
                $skip = $true
                continue
            }

            $skip = $false
        }

        if (-not $skip) {
            $kept.Add($line)
        }
    }

    Set-Content -Path $configPath -Value $kept -Encoding UTF8

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
        [string]$HostName,
        [string]$User,
        [int]$Port = 0,
        [string]$Role = "",
        [string]$CheckPorts = "",
        [string]$Url = ""
    )

    Write-Host ""
    Write-Host "Infra host onboarding" -ForegroundColor Cyan

    $Name = Resolve-ShellToolsValidatedValue -Value $Name -Prompt "Host alias" -Default "proxmox" -Validator ${function:Test-ShellToolsInfraName} -ErrorMessage "Use a host alias like proxmox, docker-vm, or app01. Letters, numbers, dot, dash, underscore; start with a letter."
    $HostName = Resolve-ShellToolsValidatedValue -Value $HostName -Prompt "Host IPv4" -Default "192.168.1.185" -Validator ${function:Test-ShellToolsIPv4} -ErrorMessage "This is not an IPv4 address. Example: 192.168.1.185."
    $User = Resolve-ShellToolsValidatedValue -Value $User -Prompt "SSH user" -Default "root" -Validator ${function:Test-ShellToolsUser} -ErrorMessage "Use a simple SSH user, like root, ubuntu, admin, or adrien."
    $Port = Resolve-ShellToolsPortValue -Value $Port -Prompt "SSH port" -Default 22
    $Role = Resolve-ShellToolsValidatedValue -Value $Role -Prompt "Role" -Default "proxmox" -Validator ${function:Test-ShellToolsRole} -ErrorMessage "Role cannot be empty and cannot contain commas."

    $defaultCheckPorts = if ($Role -match "proxmox") { "22;8006" } else { "22" }
    $CheckPorts = Resolve-ShellToolsPortList -Value $CheckPorts -Prompt "Ports to check, separated by semicolon" -Default $defaultCheckPorts

    if (-not $Url -and $Role -match "proxmox") {
        $Url = "https://{0}:8006" -f $HostName
    }

    $Url = Resolve-ShellToolsValidatedValue -Value $Url -Prompt "Web URL (optional)" -Default $Url -Validator ${function:Test-ShellToolsUrl} -ErrorMessage "Use a full URL like https://192.168.1.185:8006, or leave it empty."

    $sshEnabled = Read-ShellToolsYesNo "Add this host to ~/.ssh/config?" $true
    if ($sshEnabled) {
        Ensure-SshKey
        Add-SshConfigHost -Name $Name -HostName $HostName -User $User -Port $Port
        Write-Host "When the key is installed on the host, connect with: ssh $Name" -ForegroundColor Cyan
    }

    Add-InfraHostRecord -Name $Name -HostName $HostName -User $User -Port $Port -Role $Role -CheckPorts $CheckPorts -Url $Url -SshEnabled:$sshEnabled
    Write-Host "Infra host saved to $script:InfraHostsPath" -ForegroundColor Green
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

    $newName = Read-ShellToolsValidatedDefault -Prompt "Host alias" -Default $current.Name -Validator ${function:Test-ShellToolsInfraName} -ErrorMessage "Use a host alias like proxmox, docker-vm, or app01."
    $newHostName = Read-ShellToolsValidatedDefault -Prompt "Host IPv4" -Default $current.HostName -Validator ${function:Test-ShellToolsIPv4} -ErrorMessage "This is not an IPv4 address. Example: 192.168.1.185."
    $newUser = Read-ShellToolsValidatedDefault -Prompt "SSH user" -Default $current.User -Validator ${function:Test-ShellToolsUser} -ErrorMessage "Use a simple SSH user, like root, ubuntu, admin, or adrien."
    $newPort = Resolve-ShellToolsPortValue -Value 0 -Prompt "SSH port" -Default ([int]$current.Port)
    $newRole = Read-ShellToolsValidatedDefault -Prompt "Role" -Default $current.Role -Validator ${function:Test-ShellToolsRole} -ErrorMessage "Role cannot be empty and cannot contain commas."
    $newCheckPorts = Resolve-ShellToolsPortList -Value "" -Prompt "Ports to check, separated by semicolon" -Default $current.CheckPorts
    $newUrl = Read-ShellToolsValidatedDefault -Prompt "Web URL (optional)" -Default $current.Url -Validator ${function:Test-ShellToolsUrl} -ErrorMessage "Use a full URL like https://192.168.1.185:8006, or leave it empty."

    $defaultSsh = ($current.SshEnabled -eq "true")
    $sshEnabled = Read-ShellToolsYesNo "Update/add this host in ~/.ssh/config?" $defaultSsh
    if ($sshEnabled) {
        Ensure-SshKey
        Set-SshConfigHost -Name $newName -HostName $newHostName -User $newUser -Port $newPort -PreviousName $current.Name
    }

    Add-InfraHostRecord -Name $newName -HostName $newHostName -User $newUser -Port $newPort -Role $newRole -CheckPorts $newCheckPorts -Url $newUrl -SshEnabled:$sshEnabled -PreviousName $current.Name
    Write-Host "Infra host updated." -ForegroundColor Green
}

function Initialize-ShellTools {
    Write-Host ""
    Write-Host "Shell Alias Tools setup" -ForegroundColor Cyan

    $hosts = @(Get-InfraHosts)
    if ($hosts.Count -eq 0) {
        if (Read-ShellToolsYesNo "Add your default Proxmox host at 192.168.1.185?" $true) {
            Add-InfraHost -Name "proxmox" -HostName "192.168.1.185" -User "root" -Port 22 -Role "proxmox" -CheckPorts "22;8006" -Url "https://192.168.1.185:8006"
        }
    }

    while (Read-ShellToolsYesNo "Add another infra server?" $false) {
        Add-InfraHost
    }

    Write-Host ""
    Write-Host "Setup complete. Run init to open the infra dashboard." -ForegroundColor Green
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

Set-Alias ep Edit-Profile -Scope Global -Force

function Reload-Profile {
    . $PROFILE
    Write-Host "Profile reloaded." -ForegroundColor Green
}

Set-Alias reloadp Reload-Profile -Scope Global -Force

function add-func {
    param(
        [Parameter(Mandatory = $true)]
        [string]$name,

        [Parameter(Mandatory = $true)]
        [string]$body
    )

    Ensure-ShellToolsHome

    if (Get-Command $name -ErrorAction SilentlyContinue) {
        Write-Host "'$name' already exists in this session." -ForegroundColor Yellow
        return
    }

    if (Select-String -Path $script:AliasToolsPath -Pattern "function\s+$([regex]::Escape($name))\b" -Quiet -ErrorAction SilentlyContinue) {
        Write-Host "'$name' already exists in $script:AliasToolsPath." -ForegroundColor Yellow
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

function add-alias-cmd {
    param(
        [Parameter(Mandatory = $true)]
        [string]$name,

        [Parameter(Mandatory = $true)]
        [string]$command
    )

    add-func $name $command
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

Set-Alias lf list-funcs -Scope Global -Force

function add-last-func {
    param(
        [Parameter(Mandatory = $true)]
        [string]$name
    )

    $last = (Get-History -Count 1).CommandLine
    if (-not $last) {
        Write-Host "No previous command found." -ForegroundColor Yellow
        return
    }

    add-func $name $last
}

Set-Alias aa add-last-func -Scope Global -Force

function vms {
    if (Get-Command multipass -ErrorAction SilentlyContinue) {
        Write-Host "Multipass VMs:" -ForegroundColor Cyan
        multipass list
    }
    else {
        Write-Host "Multipass is not installed." -ForegroundColor Yellow
    }
}

function portforwarding {
    netsh interface portproxy show all
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

function Show-DockerServicesForHost {
    param(
        [Parameter(Mandatory = $true)]
        $HostRecord
    )

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        return
    }

    if ($HostRecord.SshEnabled -ne "true") {
        return
    }

    if ($HostRecord.Role -notmatch "docker") {
        return
    }

    try {
        $containers = & ssh -o BatchMode=yes -o ConnectTimeout=3 $HostRecord.Name "docker ps --format '{{.Names}}|{{.Ports}}'" 2>$null
        if (-not $containers) {
            return
        }

        Write-Host ""
        Write-Host ("Docker services on {0}" -f $HostRecord.Name) -ForegroundColor Yellow
        foreach ($line in $containers) {
            $parts = $line -split "\|", 2
            $containerName = $parts[0]
            $ports = if ($parts.Count -gt 1) { $parts[1] } else { "" }

            if ($ports -match ":(\d+)->") {
                $url = "http://{0}:{1}" -f $HostRecord.HostName, $matches[1]
                Write-Host ("  OK   {0,-22} {1}" -f $containerName, $url) -ForegroundColor Green
            }
            else {
                Write-Host ("  INT  {0,-22} internal" -f $containerName) -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host ("Docker scan failed on {0}" -f $HostRecord.Name) -ForegroundColor Red
    }
}

function init {
    Write-Host ""
    Write-Host "HOMELAB COMMAND CENTER" -ForegroundColor Cyan
    Write-Host ""

    $hosts = @(Get-InfraHosts)
    if ($hosts.Count -eq 0) {
        Write-Host "No infra hosts configured yet." -ForegroundColor Yellow
        if (Read-ShellToolsYesNo "Run interactive setup now?" $true) {
            Initialize-ShellTools
            $hosts = @(Get-InfraHosts)
        }
    }

    if ($hosts.Count -eq 0) {
        return
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
        Write-Host ("{0,-14} {1,-15} {2,-10} {3}" -f $hostRecord.Name, $hostRecord.HostName, $pingStatus, $hostRecord.Role) -ForegroundColor $pingColor

        $normalizedPorts = Convert-ShellToolsPortList $hostRecord.CheckPorts
        if (-not $normalizedPorts) {
            Write-Host ("  invalid port list: {0}" -f $hostRecord.CheckPorts) -ForegroundColor Yellow
            continue
        }

        $ports = @($normalizedPorts -split ";" | Where-Object { $_ })
        foreach ($portText in $ports) {
            $port = 0
            if ([int]::TryParse($portText, [ref]$port)) {
                $open = Test-ShellToolsTcpPort -HostName $hostRecord.HostName -Port $port
                $state = if ($open) { "OPEN" } else { "CLOSED" }
                $color = if ($open) { "Green" } else { "Red" }
                Write-Host ("  port {0,-6} {1}" -f $port, $state) -ForegroundColor $color
            }
        }

        if ($hostRecord.Url) {
            Write-Host ("  url        {0}" -f $hostRecord.Url) -ForegroundColor Cyan
        }

        Show-DockerServicesForHost -HostRecord $hostRecord
    }

    Write-Host ""
}

function init2 {
    init
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

    $hosts | Format-Table Name, HostName, User, Port, Role, CheckPorts, Url -AutoSize
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

    if (Read-ShellToolsYesNo "Delete $script:ShellToolsRoot including aliases and infra config?" $false) {
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
    $tools = @("git", "ssh", "curl", "fzf", "jq", "nc", "gh", "docker", "multipass")
    $results = $tools | ForEach-Object {
        $cmd = Get-Command $_ -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Tool   = $_
            Status = if ($cmd) { "OK" } else { "missing" }
            Path   = if ($cmd) { $cmd.Source } else { "" }
        }
    }

    $results | Format-Table -AutoSize
}

function myhelp {
    Write-Host ""
    Write-Host "COMMANDS" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "init          Infra dashboard"
    Write-Host "shellsetup    Interactive first-run setup"
    Write-Host "infra-add     Add a server to infra config"
    Write-Host "infra-edit    Modify an infra server"
    Write-Host "infra-list    List configured servers"
    Write-Host "sshhosts      Pick an SSH host and connect"
    Write-Host "check-tools   Check local CLI dependencies"
    Write-Host "shelluninstall Remove profile hook and optional data"
    Write-Host "ep            Edit PowerShell profile"
    Write-Host "reloadp       Reload profile"
    Write-Host "add-func      Save a custom function"
    Write-Host "aa            Save the previous command as a function"
    Write-Host "lf            List saved functions"
    Write-Host "vms           List Multipass VMs"
    Write-Host "portforwarding Show Windows portproxy rules"
    Write-Host ""
}

Set-Alias shellsetup Initialize-ShellTools -Scope Global -Force
Set-Alias myh myhelp -Scope Global -Force

function Show-ShellDashboard {
    if ($env:SHELL_TOOLS_NO_DASHBOARD -eq "1") {
        return
    }

    $ip = Get-PrimaryIPv4
    $hostCount = @(Get-InfraHosts).Count
    $uptime = Get-ShortUptime
    $disk = Get-ShellToolsDiskSummary

    Write-Host ""
    Write-Host ("=" * 58) -ForegroundColor DarkGray
    Write-Host ("ENV READY - {0}@{1}" -f (whoami), $env:COMPUTERNAME) -ForegroundColor Cyan
    Write-Host ("IP: {0} | Uptime: {1}" -f $ip, $uptime) -ForegroundColor Magenta
    Write-Host ("Disk: {0} | Infra hosts: {1}" -f $disk, $hostCount) -ForegroundColor DarkCyan
    Write-Host ("=" * 58) -ForegroundColor DarkGray
    Write-Host "init       -> infra dashboard"
    Write-Host "sshhosts   -> connect to SSH host"
    Write-Host "infra-add  -> add server"
    Write-Host "infra-edit -> modify server"
    Write-Host "check-tools-> dependency check"
    Write-Host "myhelp     -> all commands"
    Write-Host ""
}

Show-ShellDashboard
