$ErrorActionPreference = "Stop"

function Assert-Relaunch {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$tokens = $null
$parseErrors = $null
$installerAst = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $repoRoot "install.ps1"), [ref]$tokens, [ref]$parseErrors)
Assert-Relaunch (-not $parseErrors) "installer does not parse"
$relaunchFunctions = foreach ($functionName in @("Get-InstallerReinvokeParameters", "Restart-InstallerWithGumIfPossible")) {
    $functionAst = $installerAst.Find({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
    }, $true)
    Assert-Relaunch ($null -ne $functionAst) "missing relaunch function $functionName"
    $functionAst.Extent.Text
}
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("shelldeck relaunch " + [guid]::NewGuid())
$originalReexec = $env:SHELLDECK_GUM_REEXECED
$originalCapture = $env:SHELLDECK_TEST_RELAUNCH_CAPTURE
$originalReady = $env:SHELLDECK_TEST_GUM_READY
$originalFlowRoot = $env:SHELLDECK_TEST_RELAUNCH_ROOT
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $fixturePath = Join-Path $testRoot "installer fixture.ps1"
    $capturePath = Join-Path $testRoot "received.json"
    $fixture = $installerAst.ParamBlock.Extent.Text + @'

$ErrorActionPreference = "Stop"
if ($env:SHELLDECK_GUM_REEXECED -eq "1") {
    [PSCustomObject]@{
        Yes = [bool]$Yes
        SkipDeps = [bool]$SkipDeps
        SkipInfra = [bool]$SkipInfra
        DryRun = [bool]$DryRun
        Mode = $Mode
        MachineProfile = $MachineProfile
        Ui = $Ui
        InstallDir = $InstallDir
    } | ConvertTo-Json | Set-Content -LiteralPath $env:SHELLDECK_TEST_RELAUNCH_CAPTURE -Encoding UTF8
    exit 0
}
function gum { }
function Refresh-InstallerSessionPath { }
function Write-Step { param($Message); Write-Host $Message }

'@ + ($relaunchFunctions -join "`n") + @'

$global:LASTEXITCODE = 123
Restart-InstallerWithGumIfPossible
throw "Installer did not exit after relaunch."
'@
    [IO.File]::WriteAllText($fixturePath, $fixture, [Text.UTF8Encoding]::new($false))
    $enginePath = (Get-Process -Id $PID).Path
    $env:SHELLDECK_TEST_RELAUNCH_CAPTURE = $capturePath
    $customDir = Join-Path $testRoot "install data's folder"
    foreach ($explicitOptions in @($false, $true)) {
        Remove-Item Env:SHELLDECK_GUM_REEXECED -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $capturePath -ErrorAction SilentlyContinue
        if ($explicitOptions) {
            & $enginePath -NoProfile -File $fixturePath -InstallDir $customDir -Role workstation -Mode manual -Yes -SkipDeps -SkipInfra -DryRun
        }
        else {
            & $enginePath -NoProfile -File $fixturePath -InstallDir $customDir
        }
        Assert-Relaunch ($LASTEXITCODE -eq 0) "successful relaunch inherited a stale native exit code"
        Assert-Relaunch (Test-Path -LiteralPath $capturePath) "relaunched script did not run"
        $received = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
        Assert-Relaunch ($received.Ui -eq "gum") "Ui was bound positionally"
        Assert-Relaunch ($received.InstallDir -ceq $customDir) "install path was shifted or split"
        Assert-Relaunch ($received.Yes -eq $explicitOptions -and $received.SkipDeps -eq $explicitOptions -and
            $received.SkipInfra -eq $explicitOptions -and $received.DryRun -eq $explicitOptions) "switch values were lost"
        $expectedProfile = if ($explicitOptions) { "workstation" } else { "" }
        $expectedMode = if ($explicitOptions) { "manual" } else { "" }
        Assert-Relaunch ($received.MachineProfile -ceq $expectedProfile) "machine profile changed during relaunch"
        Assert-Relaunch ($received.Mode -ceq $expectedMode) "setup mode changed during relaunch"
    }

    # Run the actual installer entry point and relaunch into a temporary profile.
    # Only winget, Gum interaction, and dependency installation are simulated.
    $mainCall = $installerAst.EndBlock.Statements[-1]
    $flowMocks = @'

$PROFILE = Join-Path $env:SHELLDECK_TEST_RELAUNCH_ROOT "profile.ps1"
function Get-Command {
    param($Name, $ErrorAction)
    if ($Name -eq "gum") {
        if ($env:SHELLDECK_TEST_GUM_READY -eq "1") { return [PSCustomObject]@{ Name = "gum" } }
        return $null
    }
    if ($Name -eq "winget") { return [PSCustomObject]@{ Name = "winget" } }
    Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction SilentlyContinue
}
function winget {
    if ($args[0] -ne "install" -or $args[2] -cne "charmbracelet.gum") { throw "Unexpected winget bootstrap" }
    $env:SHELLDECK_TEST_GUM_READY = "1"
    $global:LASTEXITCODE = 0
}
function gum {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq "style") { "Gum display text"; return }
    if ($args[0] -eq "choose") {
        if ($args[1] -like "Control*") { return "Workstation - smart shell" }
        return "Manual - ask before installing every dependency"
    }
    throw "Unexpected Gum interaction"
}
function Read-Host {
    param($Prompt)
    if ($Prompt -like "Install Gum now*") { return "y" }
    throw "Unexpected classic prompt: $Prompt"
}
function Install-Dependencies {
    param([string]$SetupMode)
    if ($SetupMode -ne "manual") { throw "Incorrect dependency mode after relaunch" }
    [IO.File]::WriteAllText((Join-Path $env:SHELLDECK_TEST_RELAUNCH_ROOT "mode.txt"), $SetupMode)
}

'@
    $flowPath = Join-Path $testRoot "full installer.ps1"
    $installerSource = Get-Content -LiteralPath (Join-Path $repoRoot "install.ps1") -Raw
    [IO.File]::WriteAllText($flowPath, $installerSource.Insert($mainCall.Extent.StartOffset, $flowMocks), [Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $repoRoot "alias-tools.ps1") -Destination (Join-Path $testRoot "alias-tools.ps1")
    $env:SHELLDECK_TEST_RELAUNCH_ROOT = $testRoot
    Remove-Item Env:SHELLDECK_GUM_REEXECED -ErrorAction SilentlyContinue
    Remove-Item Env:SHELLDECK_TEST_GUM_READY -ErrorAction SilentlyContinue
    & $enginePath -NoProfile -File $flowPath -InstallDir $customDir -SkipInfra
    Assert-Relaunch ($LASTEXITCODE -eq 0) "full installer failed after Gum bootstrap/relaunch"
    Assert-Relaunch ((Get-Content -LiteralPath (Join-Path $customDir "config") -Raw).Trim() -eq
        "SHELLDECK_MACHINE_PROFILE=workstation") "full install selected the wrong machine profile"
    Assert-Relaunch ((Get-Content -LiteralPath (Join-Path $testRoot "mode.txt") -Raw) -eq "manual") "full install lost dependency selection"
    Assert-Relaunch (Test-Path -LiteralPath (Join-Path $customDir "shell-tools.ps1")) "full install did not write the runtime"
    Assert-Relaunch (Select-String -LiteralPath (Join-Path $testRoot "profile.ps1") -Pattern '^# >>> shell-alias-tools >>>$' -Quiet) "full install did not add the profile hook"
}
finally {
    $env:SHELLDECK_GUM_REEXECED = $originalReexec
    $env:SHELLDECK_TEST_RELAUNCH_CAPTURE = $originalCapture
    $env:SHELLDECK_TEST_GUM_READY = $originalReady
    $env:SHELLDECK_TEST_RELAUNCH_ROOT = $originalFlowRoot
    if (Test-Path $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

# Run real display/selection helpers with Gum stdout, without a TUI or package installs.
foreach ($functionName in @("Write-Step", "Write-Ok", "Write-Warn", "Show-InstallerBanner", "Read-MachineProfile", "Read-InstallMode", "Normalize-MachineProfile", "Normalize-InstallMode")) {
    $functionAst = $installerAst.Find({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
    }, $true)
    . ([scriptblock]::Create($functionAst.Extent.Text))
}
function Test-GumUi { return $true }
function gum {
    if ($args[0] -eq "style") { "display-only diagnostic"; return }
    if ($args[0] -eq "choose") {
        if ($args[1] -like "Control*") { return "Workstation - test" }
        return "Manual - test"
    }
    throw "Unexpected Gum command"
}
$script:ShellDeckLogo = "ShellDeck"
$InstallDir = Join-Path ([IO.Path]::GetTempPath()) ("shelldeck-empty-" + [guid]::NewGuid())
$Yes = $false
$MachineProfile = "invalid-profile"
$Mode = "invalid-mode"
Assert-Relaunch (@(Write-Step "step").Count -eq 0) "step output leaked into return values"
Assert-Relaunch (@(Write-Ok "ok").Count -eq 0) "success output leaked into return values"
Assert-Relaunch (@(Write-Warn "warning").Count -eq 0) "warning output leaked into return values"
Assert-Relaunch (@(Show-InstallerBanner).Count -eq 0) "banner output leaked into return values"
$selectedProfile = Read-MachineProfile
$selectedMode = Read-InstallMode
Assert-Relaunch ($selectedProfile -is [string] -and $selectedProfile -eq "workstation") "profile includes diagnostic output"
Assert-Relaunch ($selectedMode -is [string] -and $selectedMode -eq "manual") "setup mode includes diagnostic output"
Write-Host "PowerShell installer relaunch and output isolation checks passed"
