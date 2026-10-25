#Requires -Version 5.1
<#
.SYNOPSIS
    Offline tests for the OS catalog and change-processing logic.
.DESCRIPTION
    Parses the source file and evaluates ONLY four catalog assignments and
    three selected functions. The main program is never executed: there is
    no SQL connection, WSUS modification, task creation or logging to disk.
    Run only against your trusted copy of the source script.
.EXAMPLE
    .\tests\Test-WSUSCatalog.ps1
.EXAMPLE
    .\tests\Test-WSUSCatalog.ps1 -Path 'C:\Work\Update-WSUSComputerOperatingSystems.ps1'
#>
[CmdletBinding()]
param(
    [string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Update-WSUSComputerOperatingSystems.ps1')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Source file not found: $Path"
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $Path, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw "PowerShell parse error: $($parseErrors[0].Message)"
}

# Extract only trusted, data-only declarations; do not run main script.
$wantedVariables = @(
    'ClientProductVersions',
    'ServerProductVersions',
    'AzureStackHCIProductVersions',
    'OSDescriptions'
)
$wantedFunctions = @('Get-OsKey', 'New-NameCatalog', 'Process-Changes')
$fragments = New-Object 'System.Collections.Generic.List[string]'

foreach ($name in $wantedVariables) {
    $found = @($ast.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $_.Left.VariablePath.UserPath -eq $name
    })
    if ($found.Count -ne 1) { throw "Missing or duplicate catalog variable: $name" }
    [void]$fragments.Add($found[0].Extent.Text)
}
foreach ($name in $wantedFunctions) {
    $found = @($ast.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $_.Name -eq $name
    })
    if ($found.Count -ne 1) { throw "Missing or duplicate function: $name" }
    [void]$fragments.Add($found[0].Extent.Text)
}

# Dot-source only these extracted declarations into this test's scope.
. ([scriptblock]::Create(($fragments -join "`r`n")))
$catalog = New-NameCatalog
if ($null -eq $catalog -or $catalog.Count -eq 0) {
    throw 'Catalog is missing or empty.'
}

# Representative mappings are intentionally tested independently of total
# catalog size, which may grow when upstream OS definitions are updated.
$checks = @{
    '10|0|19045|48'  = 'Windows 10 Pro 22H2'
    '10|0|26200|4'   = 'Windows 11 Enterprise 25H2'
    '10|0|26300|48'  = 'Windows 11 Pro 26H2'
    '10|0|17763|7'   = 'Windows Server 2019 Standard'
    '10|0|26100|406' = 'Microsoft Azure Stack HCI, version 24H2'
}
foreach ($key in $checks.Keys) {
    if (-not $catalog.ContainsKey($key)) {
        throw "Missing representative mapping: $key"
    }
    if ($catalog[$key] -cne $checks[$key]) {
        throw "Wrong mapping ${key}: expected '$($checks[$key])'; actual '$($catalog[$key])'"
    }
}
Write-Host ("PASS: syntax; catalog contains {0} combinations; {1} representative mappings." -f $catalog.Count, $checks.Count)

# Isolate changes processor from SQL and file logging with test doubles.
$script:TestWrites = New-Object 'System.Collections.Generic.List[object]'
$script:TestLog = New-Object 'System.Collections.Generic.List[string]'
$script:MockUpdateResult = 1
$script:NameLookups = 0

function Write-Log([string]$Message) {
    [void]$script:TestLog.Add($Message)
}
function Get-ComputerNames {
    $script:NameLookups++
    return @{ '11' = 'coder1-pc.bs.loc'; '12' = 'already-correct.bs.loc' }
}
function Set-DescriptionById($Row, [string]$DesiredDescription) {
    [void]$script:TestWrites.Add([pscustomobject]@{
        Id = [string]$Row.Id
        Desired = $DesiredDescription
    })
    return $script:MockUpdateResult
}
function New-TestRow([string]$Id, [string]$Description, [int]$Build, [int]$Type = 48) {
    return [pscustomobject]@{
        Id = $Id
        Description = $Description
        Major = 10
        Minor = 0
        Build = $Build
        Type = $Type
    }
}
function Assert-Test([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

$initial = @{
    '11' = New-TestRow '11' 'Windows 10 Pro' 26300
    '12' = New-TestRow '12' 'Windows 11 Pro 26H2' 26300
    '13' = New-TestRow '13' 'Unknown OS' 999999
}
Process-Changes -Before @{} -After $initial -Lookup $catalog -InitialReason 'INITIAL'
Assert-Test ($script:TestWrites.Count -eq 1) 'initial reconciliation must update only wrong known entry'
Assert-Test ($script:TestWrites[0].Id -eq '11') 'initial update must target ID 11'
Assert-Test ($script:TestWrites[0].Desired -ceq 'Windows 11 Pro 26H2') 'initial update name'
Assert-Test ($script:NameLookups -eq 1) 'one name lookup for a non-empty update set'
Write-Host 'PASS: initial reconciliation; correct and unknown OS entries untouched.'

$script:TestWrites.Clear()
$script:TestLog.Clear()
Process-Changes -Before $initial -After $initial -Lookup $catalog
Assert-Test ($script:TestWrites.Count -eq 0) 'unchanged notification must not update SQL'
Assert-Test ($script:NameLookups -eq 1) 'unchanged notification must not load names'
Write-Host 'PASS: unchanged notification is a no-op.'

$before = @{
    '11' = New-TestRow '11' 'Windows 11 Pro 26H2' 26300
}
$after = @{
    '11' = New-TestRow '11' 'Windows 10 Pro' 26300
}
Process-Changes -Before $before -After $after -Lookup $catalog
Assert-Test ($script:TestWrites.Count -eq 1) 'changed description must be corrected'
Assert-Test ($script:TestLog -match 'UPDATED CHANGED coder1-pc') 'correction must be logged as changed'
Write-Host 'PASS: changed description is corrected.'

$script:TestWrites.Clear()
$script:TestLog.Clear()
$script:MockUpdateResult = 0
$before = @{ '11' = New-TestRow '11' 'Windows 10 Pro 25H2' 26200 }
$after = @{ '11' = New-TestRow '11' 'Windows 10 Pro' 26300 }
Process-Changes -Before $before -After $after -Lookup $catalog
Assert-Test ($script:TestWrites.Count -eq 1) 'build change should request update'
Assert-Test ($script:TestLog -match 'SKIPPED \(row changed concurrently\)') 'concurrent row change must be logged as skipped'
Write-Host 'PASS: build change and concurrent UPDATE skip.'

# Static safety checks: validate we still have numeric TargetID and guarded UPDATE.
# This is not a substitute for SQL integration tests on a real SUSDB.
$source = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).ProviderPath)
foreach ($piece in @(
    'SqlDbType]::Int',
    'WHERE [TargetID] = @TargetID',
    'AND [OSBuildNumber] = @Build',
    'AND [NewProductType] = @Type',
    '([OSDescription] IS NULL OR [OSDescription] <> @Description)'
)) {
    if (-not $source.Contains($piece)) { throw "Missing SQL safety guard: $piece" }
}
Write-Host 'PASS: numeric TargetID and SQL UPDATE guards present.'
Write-Host 'PASS: offline checks completed; no SQL connections or writes were made.'
