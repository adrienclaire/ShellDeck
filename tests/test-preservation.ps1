$ErrorActionPreference = "Stop"

function Assert-Preserved {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("shelldeck-preservation-" + [guid]::NewGuid())
$originalProfile = $PROFILE
$originalPath = $env:PATH
$originalCatAlias = Get-Alias cat -ErrorAction SilentlyContinue
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $env:SHELL_ALIAS_TOOLS_HOME = Join-Path $testRoot "data"
    $env:SHELL_TOOLS_NO_DASHBOARD = "1"
    $env:SHELL_TOOLS_NO_PROMPT = "1"
    $PROFILE = Join-Path $testRoot "profile.ps1"

    # Dry-run must not create even the install directory or profile.
    & (Join-Path $repoRoot "install.ps1") -DryRun -Yes -ClassicUi -MachineProfile workstation -Mode complete -InstallDir $env:SHELL_ALIAS_TOOLS_HOME
    Assert-Preserved (-not (Test-Path $env:SHELL_ALIAS_TOOLS_HOME)) "dry-run created an install directory"
    Assert-Preserved (-not (Test-Path $PROFILE)) "dry-run created a profile"
    Assert-Preserved ($env:PATH -eq $originalPath) "dry-run changed process PATH"

    New-Item -ItemType Directory -Path $env:SHELL_ALIAS_TOOLS_HOME | Out-Null
    $configFile = Join-Path $env:SHELL_ALIAS_TOOLS_HOME "config"
    $aliasFile = Join-Path $env:SHELL_ALIAS_TOOLS_HOME "aliases.ps1"
    $hostFile = Join-Path $env:SHELL_ALIAS_TOOLS_HOME "infra-hosts.csv"
    Set-Content $configFile "# keep comment`nSHELLDECK_MACHINE_PROFILE=workstation`nSHELLDECK_SHOW_DASHBOARD=false`nCUSTOM_SETTING=keep"
    Set-Content $aliasFile 'function ll { "user-ll" }; function ep { "user-ep" }; function infra-list { "user-infra" }; Set-Alias gs Get-Location'
    Set-Content $hostFile "Name,HostName`nserver1,192.0.2.1"
    Set-Content $PROFILE '# personal profile mentions shell-alias-tools but has no hook'
    $aliasHash = (Get-FileHash $aliasFile).Hash
    $hostHash = (Get-FileHash $hostFile).Hash
    & (Join-Path $repoRoot "install.ps1") -Yes -ClassicUi -SkipDeps -SkipInfra -InstallDir $env:SHELL_ALIAS_TOOLS_HOME
    & (Join-Path $repoRoot "install.ps1") -Yes -ClassicUi -SkipDeps -SkipInfra -InstallDir $env:SHELL_ALIAS_TOOLS_HOME
    Assert-Preserved ((Get-Content $configFile -Raw) -match 'CUSTOM_SETTING=keep') "reinstall lost settings"
    Assert-Preserved ((Get-Content $configFile -Raw) -match 'SHELLDECK_MACHINE_PROFILE=workstation') "reinstall changed saved profile"
    Assert-Preserved ((Get-Content $configFile -Raw) -match 'SHELLDECK_SHOW_DASHBOARD=false') "reinstall reset banner choice"
    Assert-Preserved ((Get-FileHash $aliasFile).Hash -eq $aliasHash) "reinstall changed user code"
    Assert-Preserved ((Get-FileHash $hostFile).Hash -eq $hostHash) "reinstall changed hosts"
    Assert-Preserved (@(Select-String $PROFILE -Pattern '^# >>> shell-alias-tools >>>$').Count -eq 1) "hook missing or duplicated"
    Assert-Preserved (@(Get-ChildItem $env:SHELL_ALIAS_TOOLS_HOME -Filter 'shell-tools.ps1.bak.*').Count -gt 0) "reinstall did not back up runtime"

    function ff { "caller-ff" }
    Set-Alias gp Get-Location -Option AllScope -Force
    $runtime = Join-Path $env:SHELL_ALIAS_TOOLS_HOME "shell-tools.ps1"
    . $runtime
    . $runtime
    Assert-Preserved ((ll) -eq "user-ll") "user file function lost on reload"
    Assert-Preserved ((ff) -eq "caller-ff") "caller function lost on reload"
    Assert-Preserved ((ep) -eq "user-ep") "default alias hid user function"
    Assert-Preserved ((infra-list) -eq "user-infra") "workstation removed user infra command"
    Assert-Preserved ((Get-Alias gp).Definition -eq "Get-Location") "caller alias removed"
    Assert-Preserved ((Get-Alias gs).Definition -eq "Get-Location") "user file alias removed"
    $loadedCatAlias = Get-Alias cat -ErrorAction SilentlyContinue
    if ($originalCatAlias) {
        Assert-Preserved ($loadedCatAlias.Definition -eq $originalCatAlias.Definition) "existing cat alias changed"
    }
    else {
        Assert-Preserved ($null -eq $loadedCatAlias) "runtime imposed a cat alias"
    }

    $beforeUpdate = (Get-FileHash $configFile).Hash
    $script:testUpdateContent = (Get-Content $runtime -Raw).Replace('docker ps', 'docker ps --all')
    function Invoke-WebRequest { param($Uri, $OutFile, $ErrorAction); [IO.File]::WriteAllText($OutFile, $script:testUpdateContent) }
    shelldeck-update
    . $runtime
    Assert-Preserved ((Get-Command dps).Definition -match 'docker ps --all') "owned default did not update"
    Assert-Preserved ((ll) -eq "user-ll" -and (ff) -eq "caller-ff") "update lost overrides"
    Assert-Preserved ((Get-FileHash $configFile).Hash -eq $beforeUpdate) "update changed config"
    Assert-Preserved ((Get-FileHash $aliasFile).Hash -eq $aliasHash) "update changed user code"
    Assert-Preserved ((Get-FileHash $hostFile).Hash -eq $hostHash) "update changed hosts"
    $runtimeHash = (Get-FileHash $runtime).Hash
    $script:testUpdateContent = 'function broken {'
    shelldeck-update
    Assert-Preserved ((Get-FileHash $runtime).Hash -eq $runtimeHash) "invalid update replaced runtime"

    Set-ShellDeckConfigValue -Key SHELLDECK_MACHINE_PROFILE -Value control
    . $runtime
    Assert-Preserved ($null -ne (Get-Command init -ErrorAction SilentlyContinue)) "control profile lacks init"
    Set-ShellDeckConfigValue -Key SHELLDECK_MACHINE_PROFILE -Value workstation
    . $runtime
    Assert-Preserved ($null -eq (Get-Command init -ErrorAction SilentlyContinue)) "workstation kept owned init"
    Assert-Preserved ((infra-list) -eq "user-infra") "profile change removed a user function"

    function Read-ShellToolsYesNo { param($Prompt, $Default); return $Default }
    shelluninstall
    Assert-Preserved (-not (Select-String $PROFILE -Pattern '^# >>> shell-alias-tools >>>$' -Quiet)) "uninstall kept hook"
    Assert-Preserved ((Get-Content $PROFILE -Raw) -match 'personal profile') "uninstall removed personal content"
    Assert-Preserved ((Get-FileHash $aliasFile).Hash -eq $aliasHash) "default uninstall deleted user data"

    Set-Content $hostFile "Name,HostName,User,Port,Role,CheckPorts,Url,SshEnabled`nserver1,192.0.2.1,admin,22,docker,22;80,http://192.0.2.1,true"
    $legacyHash = (Get-FileHash $hostFile).Hash
    Convert-ShellToolsInfraSchema
    $legacyBackup = Get-ChildItem $env:SHELL_ALIAS_TOOLS_HOME -Filter 'infra-hosts.csv.bak.*' | Select-Object -First 1
    Assert-Preserved ($null -ne $legacyBackup -and (Get-FileHash $legacyBackup.FullName).Hash -eq $legacyHash) "legacy migration lost original CSV"

    # Exercise only the installer PATH helper, not Main or a package manager.
    $installerAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'install.ps1'), [ref]$null, [ref]$null)
    $refreshAst = $installerAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Refresh-InstallerSessionPath' }, $true)
    . ([scriptblock]::Create($refreshAst.Extent.Text))
    $DryRun = $false
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    Refresh-InstallerSessionPath
    $refreshedPath = $env:PATH
    Refresh-InstallerSessionPath
    Assert-Preserved ($env:PATH.StartsWith($originalPath)) "refresh reordered process PATH"
    Assert-Preserved ($env:PATH -eq $refreshedPath) "repeated refresh duplicated paths"
    Assert-Preserved ([Environment]::GetEnvironmentVariable('Path', 'User') -eq $userPath) "refresh wrote User PATH"
    Assert-Preserved ([Environment]::GetEnvironmentVariable('Path', 'Machine') -eq $machinePath) "refresh wrote Machine PATH"
    Write-Host "PowerShell preservation checks passed"
}
finally {
    $env:PATH = $originalPath
    $PROFILE = $originalProfile
    if (Test-Path $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
