$ErrorActionPreference = "Stop"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimePath = Join-Path $repoRoot "alias-tools.ps1"
$runtimeText = Get-Content -Path $runtimePath -Raw
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("shelldeck-cache-test-" + [guid]::NewGuid())

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $env:SHELL_ALIAS_TOOLS_HOME = $tempRoot
    $env:SHELLDECK_DASHBOARD_CACHE_FILE = Join-Path $tempRoot "dashboard-cache.json"
    $env:SHELL_TOOLS_NO_DASHBOARD = "1"
    $env:SHELL_TOOLS_NO_PROMPT = "1"

    . $runtimePath

    Assert-True ($runtimeText -notmatch "Get-NetIPConfiguration") "fast IP lookup must not load Get-NetIPConfiguration"
    Assert-True ($null -ne (Get-Command shelldeck-refresh -ErrorAction SilentlyContinue)) "shelldeck-refresh command must exist"
    Assert-True ($null -ne (Get-Command shelldeck-update -ErrorAction SilentlyContinue)) "shelldeck-update command must exist"
    Assert-True ($null -ne (Get-Command shelldeckinfo-enabled -ErrorAction SilentlyContinue)) "shelldeckinfo-enabled command must exist"
    Assert-True ($null -ne (Get-Command shelldeckinfo-disabled -ErrorAction SilentlyContinue)) "shelldeckinfo-disabled command must exist"
    Assert-True ($null -ne (Get-Command shelldeckinfo-status -ErrorAction SilentlyContinue)) "shelldeckinfo-status command must exist"
    Assert-True ($runtimeText -match "infra-hosts\.csv") "runtime update must keep infra data outside the replaced runtime file"

    $script:refreshCount = 0
    function script:New-ShellDeckDashboardSnapshot {
        $script:refreshCount++
        return [PSCustomObject]@{
            CacheVersion = 1
            RefreshedDate = (Get-Date).ToString("yyyy-MM-dd")
            RefreshedAt = (Get-Date).ToString("o")
            IP = "192.0.2.$script:refreshCount"
            Uptime = "1h 0m"
            Disk = "10 GB free / 20 GB"
            InfraHosts = 2
            SmartTools = "5/10"
        }
    }

    $first = Get-ShellDeckDashboardSnapshot
    $second = Get-ShellDeckDashboardSnapshot
    Assert-True ($script:refreshCount -eq 1) "same-day dashboard reads must reuse the cache"
    Assert-True ($first.IP -eq $second.IP) "cached dashboard data must remain stable"

    $forced = Get-ShellDeckDashboardSnapshot -ForceRefresh
    Assert-True ($script:refreshCount -eq 2) "forced refresh must rebuild the cache"
    Assert-True ($forced.IP -ne $first.IP) "forced refresh must return new dashboard data"

    Set-Content -Path $env:SHELLDECK_DASHBOARD_CACHE_FILE -Value "{invalid json" -Encoding UTF8
    $recovered = Get-ShellDeckDashboardSnapshot
    Assert-True ($script:refreshCount -eq 3) "invalid cache data must trigger a refresh"
    Assert-True ($recovered.IP -eq "192.0.2.3") "invalid cache recovery must return refreshed data"


    Remove-Item Env:SHELL_TOOLS_NO_DASHBOARD -ErrorAction SilentlyContinue
    shelldeckinfo-disabled | Out-Null
    Assert-True (-not (Test-ShellDeckDashboardEnabled)) "disabled startup banner config must suppress the dashboard"
    Assert-True ((Get-Content -Path (Join-Path $tempRoot "config") -Raw) -match "SHELLDECK_SHOW_DASHBOARD=false") "disabled startup banner setting must persist to config"

    $disabledRoot = Join-Path $tempRoot "disabled-load"
    New-Item -ItemType Directory -Force -Path $disabledRoot | Out-Null
    Set-Content -Path (Join-Path $disabledRoot "config") -Value "SHELLDECK_SHOW_DASHBOARD=false" -Encoding UTF8
    $loadScript = Join-Path $tempRoot "load-disabled.ps1"
    @"
`$env:SHELL_ALIAS_TOOLS_HOME = '$disabledRoot'
`$env:SHELLDECK_DASHBOARD_CACHE_FILE = '$(Join-Path $disabledRoot "dashboard-cache.json")'
`$env:SHELL_TOOLS_NO_PROMPT = '1'
. '$runtimePath'
"@ | Set-Content -Path $loadScript -Encoding UTF8
    $loadOutput = & pwsh -NoProfile -File $loadScript | Out-String
    Assert-True ($loadOutput -notmatch "ShellDeck ready") "disabled startup banner must not print during profile load"

    shelldeckinfo-enabled | Out-Null
    Assert-True (Test-ShellDeckDashboardEnabled) "enabled startup banner config must allow the dashboard"
    Assert-True ((Get-Content -Path (Join-Path $tempRoot "config") -Raw) -match "SHELLDECK_SHOW_DASHBOARD=true") "enabled startup banner setting must persist to config"

    Write-Host "PowerShell dashboard cache regression checks passed"
}
finally {
    Remove-Item Env:SHELL_ALIAS_TOOLS_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:SHELLDECK_DASHBOARD_CACHE_FILE -ErrorAction SilentlyContinue
    Remove-Item Env:SHELL_TOOLS_NO_DASHBOARD -ErrorAction SilentlyContinue
    Remove-Item Env:SHELL_TOOLS_NO_PROMPT -ErrorAction SilentlyContinue
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
