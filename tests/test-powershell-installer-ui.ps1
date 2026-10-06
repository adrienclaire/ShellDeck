$ErrorActionPreference = "Stop"

function Assert-Ui {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$tokens = $null
$parseErrors = $null
$installerAst = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $repoRoot "install.ps1"), [ref]$tokens, [ref]$parseErrors)
Assert-Ui (-not $parseErrors) "installer does not parse"
foreach ($functionName in @("Initialize-InstallerUi", "Test-GumUi", "Read-MachineProfile", "Read-InstallMode", "Normalize-MachineProfile", "Normalize-InstallMode")) {
    $functionAst = $installerAst.Find({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
    }, $true)
    . ([scriptblock]::Create($functionAst.Extent.Text))
}

# Model native winget exit codes without installing packages or changing PATH.
function Get-Command {
    param($Name, $ErrorAction)
    if ($Name -eq "gum" -and $script:testGumAvailable) { return [PSCustomObject]@{ Name = "gum" } }
    if ($Name -eq "winget" -and $script:testWingetAvailable) { return [PSCustomObject]@{ Name = "winget" } }
    return $null
}
function winget {
    $script:testCalls += ,@($args)
    if ($args[0] -eq "source") {
        $global:LASTEXITCODE = $script:testSourceExit
    }
    else {
        $script:testInstalls++
        $global:LASTEXITCODE = $script:testInstallExits[$script:testInstalls - 1]
        if ($LASTEXITCODE -eq 0 -and $script:testExposeGum) { $script:testGumAvailable = $true }
    }
}
function Refresh-InstallerSessionPath { $script:testRefreshes++ }
function Restart-InstallerWithGumIfPossible { $script:testRestarts++ }
function Confirm-InstallChoice { param($Prompt, $Default); $script:testConfirmations++; return $script:testConsent }
function Write-Warn { param($Message); $script:testWarnings += $Message }
function Write-Step { param($Message) }
function Write-DryRun { param($Message); $script:testDryMessages += $Message }
function Read-Host {
    param($Prompt)
    if ($Prompt -like "Choose machine profile*") { return "2" }
    if ($Prompt -like "Choose setup mode*") { return "3" }
    throw "Unexpected prompt: $Prompt"
}
function Reset-UiTest {
    $script:UseGum = $false
    $script:testGumAvailable = $false
    $script:testWingetAvailable = $true
    $script:testExposeGum = $true
    $script:testConsent = $true
    $script:testCalls = @()
    $script:testWarnings = @()
    $script:testDryMessages = @()
    $script:testConfirmations = 0
    $script:testInstalls = 0
    $script:testRefreshes = 0
    $script:testRestarts = 0
    $script:testSourceExit = 0
    $script:testInstallExits = @(0, 0)
}

$Ui = "auto"
$Yes = $false
$DryRun = $false
$MachineProfile = ""
$Mode = ""
$InstallDir = Join-Path ([IO.Path]::GetTempPath()) ("shelldeck-ui-test-" + [guid]::NewGuid())

Reset-UiTest
$script:testInstallExits = @(-1978335212, -1978335212)
Initialize-InstallerUi
Assert-Ui (-not $script:UseGum) "failed Gum install enabled the rich UI"
Assert-Ui ($script:testCalls.Count -eq 3) "failed install must retry only once after source refresh"
Assert-Ui ($script:testRestarts -eq 0) "failed install restarted the installer"
Assert-Ui ((Read-MachineProfile) -eq "workstation") "machine profile cannot be selected after Gum failure"
Assert-Ui ((Read-InstallMode) -eq "manual") "dependency mode cannot be selected after Gum failure"
Assert-Ui ($script:testCalls[0][2] -ceq "charmbracelet.gum") "incorrect case-sensitive package ID"
Assert-Ui ($script:testCalls[0] -contains "--source") "Gum install must use the winget source"

Reset-UiTest
$script:testInstallExits = @(-1978335212, 0)
Initialize-InstallerUi
Assert-Ui ($script:UseGum -and $script:testRestarts -eq 1) "successful retry did not enable Gum"
Assert-Ui ($script:testRefreshes -eq 2) "session PATH was not refreshed after successful install"

Reset-UiTest
$script:testInstallExits = @(1, 0)
$script:testSourceExit = 1
Initialize-InstallerUi
Assert-Ui ($script:testCalls.Count -eq 2 -and -not $script:UseGum) "source failure must stop retries and keep classic UI"

Reset-UiTest
$script:testExposeGum = $false
Initialize-InstallerUi
Assert-Ui (-not $script:UseGum -and $script:testRestarts -eq 0) "missing executable after install must keep classic UI"

Reset-UiTest
$script:testWingetAvailable = $false
Initialize-InstallerUi
Assert-Ui ($script:testCalls.Count -eq 0 -and -not $script:UseGum) "missing winget must keep classic UI"

Reset-UiTest
$script:testConsent = $false
Initialize-InstallerUi
Assert-Ui ($script:testCalls.Count -eq 0) "declined Gum install invoked winget"

Reset-UiTest
$DryRun = $true
Initialize-InstallerUi
Assert-Ui ($script:testCalls.Count -eq 0 -and $script:testDryMessages.Count -eq 1) "dry-run invoked winget"
$DryRun = $false

Reset-UiTest
$script:testGumAvailable = $true
Initialize-InstallerUi
Assert-Ui ($script:UseGum -and $script:testCalls.Count -eq 0 -and $script:testConfirmations -eq 0) "installed Gum was bootstrapped again"

Reset-UiTest
$Ui = "classic"
Initialize-InstallerUi
Assert-Ui ($script:testCalls.Count -eq 0 -and $script:testRefreshes -eq 0) "classic UI triggered Gum bootstrap"

Write-Host "PowerShell installer UI bootstrap checks passed"
