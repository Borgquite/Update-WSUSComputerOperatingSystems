#Requires -Version 5.1
<#
.SYNOPSIS
    Install, update or uninstall the WSUS OS descriptions event task.
.DESCRIPTION
    Uses an existing script from the chosen folder, or downloads the fork's latest
    main script into that folder. Never moves or copies its own installer file.
    By default downloads the main script from avmaksimov/Update-WSUSComputerOperatingSystems.
.EXAMPLE
    .\Install-WSUSComputerOperatingSystems.ps1
.EXAMPLE
    .\Install-WSUSComputerOperatingSystems.ps1 -InstallPath 'D:\Scripts\WSUS'
.EXAMPLE
    .\Install-WSUSComputerOperatingSystems.ps1 -InstallPath 'D:\Scripts\WSUS' -TaskPath '\MP\'
.EXAMPLE
    .\Install-WSUSComputerOperatingSystems.ps1 -Uninstall -TaskPath '\MP\'
#>
[CmdletBinding()]
param(
    [Parameter()][string]$InstallPath,
    [Parameter()][string]$TaskPath,
    [Parameter()][switch]$Uninstall,
    [Parameter()][string]$SQLServerInstance = '\\.\pipe\MICROSOFT##WID\tsql\query',
    [Parameter()][ValidateSet('Optional','Mandatory','True','False')][string]$Encrypt = 'Optional',
    [Parameter()][string]$MainScriptUrl
)

$ErrorActionPreference = 'Stop'
$MainScriptName = 'Update-WSUSComputerOperatingSystems.ps1'
$TaskName = 'Update-WSUSComputerOperatingSystems'
# Source repository (default branch: main).
$DefaultMainScriptUrl = 'https://raw.githubusercontent.com/Borgquite/Update-WSUSComputerOperatingSystems/main/Update-WSUSComputerOperatingSystems.ps1'
if ([string]::IsNullOrWhiteSpace($MainScriptUrl)) { $MainScriptUrl = $DefaultMainScriptUrl }

function Read-YesNo {
    param([string]$Question, [bool]$DefaultYes = $false)
    $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = (Read-Host "$Question $suffix").Trim()
        if (-not $answer) { return $DefaultYes }
        if ($answer -match '^(?i:y|yes)$') { return $true }
        if ($answer -match '^(?i:n|no)$') { return $false }
        Write-Warning 'Please enter Y or N.'
    }
}

function Get-FullInstallPath {
    param([string]$Path)
    $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'An installation directory is required.' }
    return [IO.Path]::GetFullPath($Path)
}

function Test-TemporaryDirectory {
    param([string]$Path)
    $full = (Get-FullInstallPath $Path) -replace '[\\/]+$', ''
    foreach ($temp in @($env:TEMP, $env:TMP, (Join-Path $env:SystemRoot 'Temp'))) {
        if ([string]::IsNullOrWhiteSpace($temp)) { continue }
        $tempFull = (Get-FullInstallPath $temp) -replace '[\\/]+$', ''
        if ($full.Equals($tempFull, [StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith($tempFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    # Also catch conventional custom temporary directories (e.g. C:\Temp, D:\Work\tmp).
    return ($full -match '(?i)[\\/](temp|tmp)([\\/]|$)')
}

function Get-InstallationDirectory {
    param([string]$ExplicitPath)
    # Resolve the default installation directory from this installer, not the caller's $PWD.
    $installerDirectory = $PSScriptRoot
    $mainNextToInstaller = Join-Path $installerDirectory $MainScriptName
    if (-not $PSBoundParameters.ContainsKey('ExplicitPath')) { $ExplicitPath = '' }
    $needPrompt = [string]::IsNullOrWhiteSpace($ExplicitPath) -and
        (-not (Test-Path -LiteralPath $mainNextToInstaller -PathType Leaf) -or (Test-TemporaryDirectory $installerDirectory))
    if (-not $needPrompt) {
        $chosen = if ($ExplicitPath) { Get-FullInstallPath $ExplicitPath } else { Get-FullInstallPath $installerDirectory }
        if (-not (Test-TemporaryDirectory $chosen)) { return $chosen }
        Write-Warning "Temporary directories cannot be used as permanent install locations: $chosen"
    }
    $default = if (Test-TemporaryDirectory $installerDirectory) { $null } else { $installerDirectory }
    while ($true) {
        if ($default) {
            $answer = Read-Host "Installation directory [$default]"
            if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $default }
        } else {
            $answer = Read-Host 'Installation directory (required; temporary folders are not allowed)'
            if ([string]::IsNullOrWhiteSpace($answer)) {
                Write-Warning 'Please specify a permanent installation directory.'
                continue
            }
        }
        try { $chosen = Get-FullInstallPath $answer }
        catch { Write-Warning $_.Exception.Message; continue }
        if (Test-TemporaryDirectory $chosen) {
            Write-Warning 'That directory is temporary. Please choose another location.'
            continue
        }
        return $chosen
    }
}

function Normalize-TaskPath {
    param([string]$Folder)
    $Folder = $Folder.Trim().Replace('/', '\')
    if ($Folder -match '[<>:"|?*]') { throw 'Invalid Task Scheduler folder.' }
    if ($Folder -eq '' -or $Folder -eq '\') { return '\' }
    $parts = @($Folder.Trim('\') -split '\\' | Where-Object { $_ -ne '' })
    if ($parts.Count -eq 0) { return '\' }
    return '\' + ($parts -join '\') + '\'
}

function Ensure-TaskFolder {
    param([string]$Path)
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $folder = $service.GetFolder('\')
    foreach ($part in ($Path.Trim('\') -split '\\')) {
        if (-not $part) { continue }
        try { $folder = $folder.GetFolder($part) }
        catch { $folder = $folder.CreateFolder($part) }
    }
}

function Test-ScriptSyntax {
    param([string]$Path)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "Script parse error: $($parseErrors[0].Message)" }
    $parameters = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    if ($parameters -notcontains 'AsService') {
        throw 'The selected main script does not support -AsService; refusing to schedule it.'
    }
}

function Test-OurScheduledTask {
    param($Task)
    if ($null -eq $Task) { return $false }
    $actions = @($Task.Actions)
    return ($actions.Count -eq 1 -and
        $actions[0].Execute -match '(?i)(^|[\\/])powershell\.exe$' -and
        ($actions[0].Arguments -match '(?i)Update-WSUSComputerOperatingSystems(-Event)?\.ps1'))
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run the installer from an elevated Windows PowerShell 5.1 session.'
}
if ($SQLServerInstance -match '["\r\n]' -or $Encrypt -match '["\r\n]') { throw 'Invalid SQL connection parameter.' }

if ($Uninstall) {
    if (-not $PSBoundParameters.ContainsKey('TaskPath')) {
        $TaskPath = Read-Host 'Task Scheduler folder (leave empty for root)'
    }
    $TaskPath = Normalize-TaskPath $TaskPath
    $existing = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "Task not found: $TaskPath$TaskName"
        return
    }
    if (-not (Test-OurScheduledTask $existing)) {
        throw "Task $TaskPath$TaskName does not appear to belong to this project. Refusing to remove it."
    }
    if (Read-YesNo "Remove task $TaskPath$TaskName?" -DefaultYes $false) {
        Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Confirm:$false
        Write-Host 'Task removed. Script files were left untouched.'
    } else { Write-Host 'Cancelled.' }
    return
}

$directory = Get-InstallationDirectory -ExplicitPath $InstallPath
$destination = Join-Path $directory $MainScriptName
$localExists = Test-Path -LiteralPath $destination -PathType Leaf
$download = -not $localExists
if ($localExists) {
    Write-Host "Main script found: $destination"
    $download = Read-YesNo 'Download the latest version?' -DefaultYes $true
} else {
    Write-Host "Main script not found: $destination"
}

if (-not $PSBoundParameters.ContainsKey('TaskPath')) {
    $TaskPath = Read-Host 'Task Scheduler folder (leave empty for root)'
}
$TaskPath = Normalize-TaskPath $TaskPath
$existing = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue

# Only modify a previously installed task if its action points to this project.
if ($existing -and -not (Test-OurScheduledTask $existing)) {
    throw "Task $TaskPath$TaskName exists but is not recognized as this project's task."
}

# Warn about the same task name in other Scheduler folders; leave them unchanged.
$elsewhere = @(Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskPath -ne $TaskPath })
foreach ($item in $elsewhere) {
    Write-Warning "A task with the same name also exists at $($item.TaskPath). It will not be modified."
}

$work = Join-Path $env:TEMP ('WSUS-OS-Install-' + [guid]::NewGuid().ToString('N'))
$staged = Join-Path $work $MainScriptName
try {
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    if ($download) {
        try {
            if ($MainScriptUrl -notmatch '^https://') {
                throw 'The main script download URL must use HTTPS.'
            }
            Write-Host "Downloading main script from: $MainScriptUrl"
            Invoke-WebRequest -UseBasicParsing -Uri $MainScriptUrl -OutFile $staged -ErrorAction Stop
            Test-ScriptSyntax $staged
            Write-Host 'Download and syntax check: OK.'
        } catch {
            Write-Warning ('Download failed: ' + $_.Exception.Message)
            if (-not $localExists -or -not (Read-YesNo 'Continue using the existing script?' -DefaultYes $false)) {
                throw 'Installation cancelled: no usable download.'
            }
            $download = $false
        }
    }
    if (-not $download) { Test-ScriptSyntax $destination }
    $fileChanged = $download
    if ($download -and $localExists) {
        $fileChanged = (Get-FileHash -Algorithm SHA256 -LiteralPath $staged).Hash -ne
                       (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
        if (-not $fileChanged) { Write-Host 'The installed script is already up to date.' }
    }

    Write-Host ''
    Write-Host 'Installation summary:'
    Write-Host "  Installation directory: $directory"
    Write-Host "  Main script: $destination"
    Write-Host "  Task: $TaskPath$TaskName"
    Write-Host '  Account: SYSTEM'
    Write-Host '  Trigger: System startup + 1 minute'
    Write-Host '  Mode: -AsService (unlimited runtime)'
    Write-Host "  Script action: $(if ($fileChanged) { 'Download / update' } else { 'Keep existing' })"
    if ($existing) {
        Write-Host '  Existing task: update'
        if (-not (Read-YesNo 'Update the existing scheduled task?' -DefaultYes $false)) {
            Write-Host 'Cancelled.'
            return
        }
    } elseif (-not (Read-YesNo 'Proceed with installation?' -DefaultYes $false)) {
        Write-Host 'Cancelled.'
        return
    }

    $wasRunning = ($null -ne $existing -and $existing.State -eq 'Running')
    if ($wasRunning) {
        Write-Host 'Stopping the existing task...'
        Stop-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
        $until = (Get-Date).AddSeconds(30)
        do {
            Start-Sleep -Milliseconds 500
            $state = (Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName).State
        } while ($state -eq 'Running' -and (Get-Date) -lt $until)
        if ($state -eq 'Running') { throw 'The previous task instance did not stop. No files were replaced.' }
    }

    $backup = Join-Path $work 'previous-main.ps1'
    $replaced = $false
    try {
        if ($fileChanged) {
            if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }
            if ($localExists) { Copy-Item -LiteralPath $destination -Destination $backup -Force }
            $newFile = Join-Path $directory ('.' + $MainScriptName + '.' + [guid]::NewGuid().ToString('N') + '.new')
            try {
                Copy-Item -LiteralPath $staged -Destination $newFile -Force
                if ($localExists) {
                    # Source and destination are in the same directory for an atomic NTFS replacement.
                    [System.IO.File]::Replace($newFile, $destination, $null)
                } else {
                    [System.IO.File]::Move($newFile, $destination)
                }
                $replaced = $true
            } finally {
                if (Test-Path -LiteralPath $newFile) { Remove-Item -LiteralPath $newFile -Force }
            }
        }

        Ensure-TaskFolder $TaskPath
        $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -AsService -SQLServerInstance "{1}" -Encrypt {2}' -f $destination, $SQLServerInstance, $Encrypt
        $action = New-ScheduledTaskAction -Execute $powershellExe -Argument $arguments -WorkingDirectory $directory
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $trigger.Delay = 'PT1M'
        $runAs = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
            -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $runAs -Settings $settings
        Register-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -InputObject $task -Force | Out-Null
    } catch {
        # Task registration failed: restore previous script if it was replaced.
        if ($replaced) {
            if ($localExists) { Copy-Item -LiteralPath $backup -Destination $destination -Force }
            else { Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue }
        }
        if ($wasRunning) {
            try { Start-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop }
            catch { Write-Warning 'Could not restart the previous task after installation failure.' }
        }
        throw
    }
    Write-Host ''
    Write-Host "Installed task: $TaskPath$TaskName"
    Write-Host "Main script: $destination"
    Write-Host 'Task runs as SYSTEM on startup with a 1-minute delay and no execution time limit.'
    # Start the task immediately, not just at the next system boot.
    # If it is already running, Task Scheduler's IgnoreNew setting prevents a second instance.
    try {
        Start-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop
        if ($wasRunning) {
            Write-Host 'Previously running task restarted with the updated configuration.'
        } else {
            Write-Host 'Task start requested. Check the log to verify SQL access under SYSTEM.'
        }
    } catch {
        Write-Warning ('Task installed, but failed to start: ' + $_.Exception.Message)
    }
    Write-Host ('Log file: ' + (Join-Path $directory 'Update-WSUSComputerOperatingSystems.log'))
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
