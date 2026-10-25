# Update tbComputerTargetDetail for WSUS to add more details in OSDescription field (based on https://www.wsus.de/windows-editionen-anzeigen/)
# See also https://server-essentials.com/support/windows-10-vista-wsus-not-updating
# See also https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wusp/5f216289-0876-4dc3-ad85-e1d61a9e7ce1#Appendix_A_13

#Requires -Version 5.1
<#
.SYNOPSIS
    Fix WSUS OS descriptions once, or continuously using SQL Query Notifications.
.DESCRIPTION
    Based on Borgquite/Update-WSUSComputerOperatingSystems (GPL-3.0).
    Event-driven implementation adapted from Watch-WSUSOS-AutoFix-v1.1.ps1.
    No SqlServer module or other external PowerShell dependency is needed.
.EXAMPLE
    .\Update-WSUSComputerOperatingSystems.ps1
.EXAMPLE
    .\Update-WSUSComputerOperatingSystems.ps1 -AsService
.EXAMPLE
    .\Update-WSUSComputerOperatingSystems.ps1 -AsService -DurationMinutes 60
#>
[CmdletBinding()]
param(
    [Parameter()][string]$SQLServerInstance = '\\.\pipe\MICROSOFT##WID\tsql\query',
    [Parameter()][ValidateSet('Optional','Mandatory','True','False')][string]$Encrypt = 'Optional',
    [Parameter()][switch]$AsService,
    [Parameter()][ValidateRange(0,43200)][int]$DurationMinutes = 0
)

$ErrorActionPreference = 'Stop'
if (-not $AsService -and $PSBoundParameters.ContainsKey('DurationMinutes')) {
    throw '-DurationMinutes requires -AsService.'
}
Add-Type -AssemblyName System.Data

# OS catalog from Borgquite/Update-WSUSComputerOperatingSystems (GPL-3.0).
# Original structured PowerShell data, retained to simplify upstream updates.
# https://github.com/Borgquite/Update-WSUSComputerOperatingSystems

$ClientProductVersions = @(
    # Based on https://learn.microsoft.com/en-us/windows/release-health/release-information
    @{
        ProductVersion = ' 8'
        OSMajorVersion = 6
        OSMinorVersion = 2
        OSBuildNumber = 9200
    }
    @{
        ProductVersion = ' 8.1'
        OSMajorVersion = 6
        OSMinorVersion = 3
        OSBuildNumber = 9600
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 1507'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 10240
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 1511'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 10586
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 1607'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 14393
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 1703'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 15063
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 1709'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 16299
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 1803'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 17134
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 1809'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 17763
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 1903'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 18362
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 1909'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 18363
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 2004'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 19041
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 20H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 19042
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 21H1'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 19043
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 21H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 19044
    }
    @{
        ProductVersion = ' 10'
        ProductRelease = ' 22H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 19045
    }
    @{
        ProductVersion = ' 11'
        ProductRelease = ' 21H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 22000
    }
    @{
        ProductVersion = ' 11'
        ProductRelease = ' 22H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 22621
    }
    @{
        ProductVersion = ' 11'
        ProductRelease = ' 23H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 22631
    }
    @{
        ProductVersion = ' 11'
        ProductRelease = ' 24H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 26100
    }
    @{
        ProductVersion = ' 11'
        ProductRelease = ' 25H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 26200
    }
    @{
        ProductVersion = ' 11'
        ProductRelease = ' 26H1'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 28000
    }
    @{
        ProductVersion = ' 11'
        ProductRelease = ' 26H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 26300
    }
)

$ServerProductVersions = @(
    # Based on https://learn.microsoft.com/en-us/windows/release-health/windows-server-release-info
    @{
        ProductVersion = ' 2012'
        OSMajorVersion = 6
        OSMinorVersion = 2
        OSBuildNumber = 9200
    }
    @{
        ProductVersion = ' 2012 R2'
        OSMajorVersion = 6
        OSMinorVersion = 3
        OSBuildNumber = 9600
    }
    @{
        ProductVersion = ' 2016'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 14393
    }
    @{
        ProductVersion = ', version 1709'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 16299
    }
    @{
        ProductVersion = ', version 1803'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 17134
    }
    @{
        ProductVersion = ' 2019'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 17763
    }
    @{
        ProductVersion = ', version 1903'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 18362
    }
    @{
        ProductVersion = ', version 1909'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 18363
    }
    @{
        ProductVersion = ', version 2004'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 19041
    }
    @{
        ProductVersion = ', version 20H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 19042
    }
    @{
        ProductVersion = ' 2022'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 20348
    }
    @{
        ProductVersion = ', version 23H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 25398
    }
    @{
        ProductVersion = ' 2025'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 26100
    }
)

$AzureStackHCIProductVersions = @(
    # Based on https://betawiki.net/wiki/Azure_Stack_HCI
    @{
        ProductVersion = ', version 20H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 17784
    }
    @{
        ProductVersion = ', version 21H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 20348
    }
    @{
        ProductVersion = ', version 22H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 20349
    }
    @{
        ProductVersion = ', version 23H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 25398
    }
    @{
        ProductVersion = ', version 24H2'
        OSMajorVersion = 10
        OSMinorVersion = 0
        OSBuildNumber = 26100
    }
)

$OSDescriptions = @(
    @{
        ProductName = 'Windows'
        ProductVersions = $ClientProductVersions
        ProductTypes = @(
            # Based on https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem
            # Based on https://learn.microsoft.com/en-us/mem/intune/fundamentals/filters-device-properties
            # Based on https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-getproductinfo
            # Based on https://betawiki.net/wiki/List_of_Windows_product_types
            @{
                ProductEdition = ' S'
                NewProductTypes = @(178)
            }
            @{
                ProductEdition = ' S N'
                NewProductTypes = @(179)
            }
            @{
                ProductEdition = ' Pro N'
                NewProductTypes = @(49)
            }
            @{
                ProductEdition = ' SE'
                NewProductTypes = @(203)
            }
            @{
                ProductEdition = ' SE N'
                NewProductTypes = @(202)
            }
            @{
                ProductEdition = ' Home'
                NewProductTypes = @(101, 111)
            }
            @{
                ProductEdition = ' Home China'
                NewProductTypes = @(99)
            }
            @{
                ProductEdition = ' Home N'
                NewProductTypes = @(98)
            }
            @{
                ProductEdition = ' Home Single Language'
                NewProductTypes = @(100)
            }
            @{
                ProductEdition = ' Education'
                NewProductTypes = @(121)
            }
            @{
                ProductEdition = ' Education N'
                NewProductTypes = @(122)
            }
            @{
                ProductEdition = ' Enterprise'
                NewProductTypes = @(4)
            }
            @{
                ProductEdition = ' Enterprise Evaluation'
                NewProductTypes = @(72)
            }
            @{
                ProductEdition = ' Enterprise G'
                NewProductTypes = @(171)
            }
            @{
                ProductEdition = ' Enterprise G N'
                NewProductTypes = @(172)
            }
            @{
                ProductEdition = ' Enterprise N'
                NewProductTypes = @(27)
            }
            @{
                ProductEdition = ' Enterprise N Evaluation'
                NewProductTypes = @(84)
            }
            @{
                ProductEdition = ' Enterprise LTSC'
                NewProductTypes = @(125)
            }
            @{
                ProductEdition = ' Enterprise LTSC Evaluation'
                NewProductTypes = @(129)
            }
            @{
                ProductEdition = ' Enterprise LTSC N'
                NewProductTypes = @(126)
            }
            @{
                ProductEdition = ' Enterprise LTSC N Evaluation'
                NewProductTypes = @(130)
            }
            @{
                ProductEdition = ' Holographic'
                NewProductTypes = @(135)
            }
            @{
                ProductEdition = ' Holographic for Business'
                NewProductTypes = @(136)
            }
            @{
                ProductEdition = ' IoT Core'
                NewProductTypes = @(123)
            }
            @{
                ProductEdition = ' IoT Core Commercial'
                NewProductTypes = @(131)
            }
            @{
                ProductEdition = ' IoT Enterprise'
                NewProductTypes = @(188)
            }
            @{
                ProductEdition = ' IoT Enterprise LTSC'
                NewProductTypes = @(191)
            }
            @{
                ProductEdition = ' Mobile'
                NewProductTypes = @(104)
            }
            @{
                ProductEdition = ' Mobile Enterprise'
                NewProductTypes = @(133)
            }
            @{
                ProductEdition = ' Team'
                NewProductTypes = @(119)
            }
            @{
                ProductEdition = ' Pro'
                NewProductTypes = @(48)
            }
            @{
                ProductEdition = ' Pro Education'
                NewProductTypes = @(164)
            }
            @{
                ProductEdition = ' Pro Education N'
                NewProductTypes = @(165)
            }
            @{
                ProductEdition = ' Pro for Workstations'
                NewProductTypes = @(161)
            }
            @{
                ProductEdition = ' Pro for Workstations N'
                NewProductTypes = @(162)
            }
            @{
                ProductEdition = ' Pro China'
                NewProductTypes = @(139)
            }
            @{
                ProductEdition = ' Pro Single Language'
                NewProductTypes = @(138)
            }
            @{
                ProductEdition = ' Enterprise multi-session'
                NewProductTypes = @(175)
            }
        )
    }
    @{
        ProductName = 'Windows RT'
        ProductVersions = $ClientProductVersions
        ProductTypes = @(
            @{
                ProductEdition = ''
                NewProductTypes = @(97)
            }
        )
    }
    @{
        ProductName = 'Windows Server'
        ProductVersions = $ServerProductVersions
        ProductTypes = @(
            # Based on https://learn.microsoft.com/en-us/dotnet/api/microsoft.powershell.commands.operatingsystemsku
            @{
                ProductEdition = ' Standard'
                NewProductTypes = @(7, 13)
            }
            @{
                ProductEdition = ' Standard Evaluation'
                NewProductTypes = @(79, 160)
            }
            @{
                ProductEdition = ' Datacenter'
                NewProductTypes = @(8, 12)
            }
            @{
                ProductEdition = ' Datacenter Evaluation'
                NewProductTypes = @(80, 159)
            }
            @{
                ProductEdition = ' Datacenter: Azure Edition'
                NewProductTypes = @(407)
            }
            @{
                ProductEdition = ' Datacenter: Azure Edition Core'
                NewProductTypes = @(408)
            }
            @{
                ProductEdition = ' Foundation'
                NewProductTypes = @(33)
            }
            @{
                ProductEdition = ' Essentials'
                NewProductTypes = @(50)
            }
        )
    }
    @{
        ProductName = 'Microsoft Hyper-V Server'
        ProductVersions = $ServerProductVersions
        ProductTypes = @(
            @{
                ProductEdition = ''
                NewProductTypes = @(42)
            }
        )
    }
    @{
        ProductName = 'Microsoft Azure Stack HCI'
        ProductVersions = $AzureStackHCIProductVersions
        ProductTypes = @(
            @{
                ProductEdition = ''
                NewProductTypes = @(406)
            }
        )
    }
)

function Get-OsKey($Major, $Minor, $Build, $ProductType) {
    return (@([string]$Major, [string]$Minor, [string]$Build, [string]$ProductType) -join '|')
}

function New-NameCatalog {
    $lookup = @{}
    foreach ($OSDescription in $OSDescriptions) {
        foreach ($ProductVersion in $OSDescription.ProductVersions) {
            foreach ($ProductType in $OSDescription.ProductTypes) {
                foreach ($NewProductType in $ProductType.NewProductTypes) {
                    $key = Get-OsKey $ProductVersion.OSMajorVersion $ProductVersion.OSMinorVersion $ProductVersion.OSBuildNumber $NewProductType
                    $description = "$($OSDescription.ProductName)$($ProductVersion.ProductVersion)$($ProductType.ProductEdition)$($ProductVersion.ProductRelease)"
                    if ($lookup.ContainsKey($key) -and $lookup[$key] -cne $description) {
                        throw "Conflicting OS catalog entry: $key"
                    }
                    $lookup[$key] = $description
                }
            }
        }
    }
    if ($lookup.Count -eq 0) { throw 'OS name catalog is empty.' }
    return $lookup
}

$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
if ($SQLServerInstance.StartsWith('\\.\pipe\', [StringComparison]::OrdinalIgnoreCase)) {
    $builder['Data Source'] = 'np:' + $SQLServerInstance
} else {
    $builder['Data Source'] = $SQLServerInstance
}
$builder['Initial Catalog'] = 'SUSDB'
$builder['Integrated Security'] = $true
$builder['Application Name'] = 'WSUS-OS-EventFix'
# System.Data.SqlClient expects a boolean. Mandatory requires a trusted SQL TLS certificate.
$builder['Encrypt'] = ($Encrypt -eq 'Mandatory' -or $Encrypt -eq 'True')
$connectionString = $builder.ConnectionString
$eventName = 'WSUS.OS.EventFix.Change'
$logFile = Join-Path $PSScriptRoot 'Update-WSUSComputerOperatingSystems.log'
$endTime = if ($AsService -and $DurationMinutes -gt 0) { (Get-Date).AddMinutes($DurationMinutes) } else { $null }
$listenerStarted = $false

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR')][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'dd.MM.yyyy HH:mm:ss.fff'), $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

function Set-SqlNotificationOptions([System.Data.SqlClient.SqlConnection]$Connection) {
    $cmd = $Connection.CreateCommand()
    try {
        $cmd.CommandText = 'SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET CONCAT_NULL_YIELDS_NULL ON; SET QUOTED_IDENTIFIER ON; SET ARITHABORT ON; SET NUMERIC_ROUNDABORT OFF;'
        [void]$cmd.ExecuteNonQuery()
    } finally { $cmd.Dispose() }
}

function Get-Snapshot([bool]$Subscribe = $false) {
    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
    $command = $null
    $reader = $null
    try {
        $connection.Open()
        if ($Subscribe) { Set-SqlNotificationOptions $connection }
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 30
        $command.CommandText = 'SELECT [TargetID], [OSDescription], [OSBuildNumber], [OSMajorVersion], [OSMinorVersion], [NewProductType] FROM [dbo].[tbComputerTargetDetail]'
        if ($Subscribe) {
            $dependency = [System.Data.SqlClient.SqlDependency]::new($command)
            [void](Register-ObjectEvent -InputObject $dependency -EventName OnChange -SourceIdentifier $eventName)
        }
        $rows = @{}
        $reader = $command.ExecuteReader()
        while ($reader.Read()) {
            $id = [string]$reader.GetValue(0)
            $rows[$id] = [pscustomobject]@{
                Id          = $id
                Description = if ($reader.IsDBNull(1)) { $null } else { [string]$reader.GetValue(1) }
                Build       = if ($reader.IsDBNull(2)) { $null } else { $reader.GetValue(2) }
                Major       = if ($reader.IsDBNull(3)) { $null } else { $reader.GetValue(3) }
                Minor       = if ($reader.IsDBNull(4)) { $null } else { $reader.GetValue(4) }
                Type        = if ($reader.IsDBNull(5)) { $null } else { $reader.GetValue(5) }
            }
        }
        return $rows
    }
    catch {
        if ($Subscribe) { Clear-Notifications }
        throw
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $command) { $command.Dispose() }
        $connection.Dispose()
    }
}

function Get-ComputerNames {
    $names = @{}
    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
    $command = $null
    $reader = $null
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = 'SELECT [TargetID], [FullDomainName] FROM [dbo].[tbComputerTarget]'
        $reader = $command.ExecuteReader()
        while ($reader.Read()) {
            $id = [string]$reader.GetValue(0)
            $names[$id] = if ($reader.IsDBNull(1)) { $id } else { [string]$reader.GetValue(1) }
        }
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $command) { $command.Dispose() }
        $connection.Dispose()
    }
    return $names
}

function Set-DescriptionById($Row, [string]$DesiredDescription) {
    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
    $cmd = $null
    try {
        $connection.Open()
        $cmd = $connection.CreateCommand()
        $cmd.CommandTimeout = 30
        $cmd.CommandText = @'
UPDATE [dbo].[tbComputerTargetDetail]
SET [OSDescription] = @Description
WHERE [TargetID] = @TargetID
  AND [OSMajorVersion] = @Major
  AND [OSMinorVersion] = @Minor
  AND [OSBuildNumber] = @Build
  AND [NewProductType] = @Type
  AND ([OSDescription] IS NULL OR [OSDescription] <> @Description)
'@
        [void]$cmd.Parameters.Add('@Description', [System.Data.SqlDbType]::NVarChar, 256)
        $cmd.Parameters['@Description'].Value = $DesiredDescription
        [void]$cmd.Parameters.Add('@TargetID', [System.Data.SqlDbType]::Int)
        $cmd.Parameters['@TargetID'].Value = [int]$Row.Id
        foreach ($part in @(@('Major',$Row.Major), @('Minor',$Row.Minor),
                           @('Build',$Row.Build), @('Type',$Row.Type))) {
            $parameterName = '@' + $part[0]
            [void]$cmd.Parameters.Add($parameterName, [System.Data.SqlDbType]::Int)
            $cmd.Parameters[$parameterName].Value = [int]$part[1]
        }
        return [int]$cmd.ExecuteNonQuery()
    }
    finally {
        if ($null -ne $cmd) { $cmd.Dispose() }
        $connection.Dispose()
    }
}

function Process-Changes([hashtable]$Before, [hashtable]$After, [hashtable]$Lookup, [string]$InitialReason = 'ADDED') {
    $affected = [System.Collections.Generic.List[object]]::new()
    foreach ($id in $After.Keys) {
        $row = $After[$id]
        if (-not $Before.ContainsKey($id)) {
            $affected.Add([pscustomobject]@{ Row = $row; Reason = $InitialReason })
            continue
        }
        $old = $Before[$id]
        if ($old.Description -cne $row.Description -or $old.Build -ne $row.Build -or
            $old.Major -ne $row.Major -or $old.Minor -ne $row.Minor -or $old.Type -ne $row.Type) {
            $affected.Add([pscustomobject]@{ Row = $row; Reason = 'CHANGED' })
        }
    }

    $wrong = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $affected) {
        $row = $entry.Row
        if ($null -in @($row.Major, $row.Minor, $row.Build, $row.Type)) { continue }
        $key = Get-OsKey $row.Major $row.Minor $row.Build $row.Type
        if (-not $Lookup.ContainsKey($key)) { continue }
        $desired = [string]$Lookup[$key]
        if ($row.Description -ceq $desired) { continue }
        $wrong.Add([pscustomobject]@{ Row = $row; Reason = $entry.Reason; Desired = $desired })
    }

    $updated = 0
    if ($wrong.Count -gt 0) {
        $names = Get-ComputerNames
        foreach ($entry in $wrong) {
            $row = $entry.Row
            $count = Set-DescriptionById -Row $row -DesiredDescription $entry.Desired
            $computer = if ($names.ContainsKey($row.Id)) { $names[$row.Id] } else { $row.Id }
            $msg = '{0} {1} [{2}] Build={3}; OS={4} -> {5}' -f $entry.Reason,
                $computer, $row.Id, $row.Build, $row.Description, $entry.Desired
            if ($count -eq 1) {
                $updated++
                Write-Log "UPDATED $msg"
            } else {
                Write-Log "SKIPPED (row changed concurrently): $msg" -Level WARNING
            }
        }
    }
    if ($InitialReason -eq 'INITIAL' -or $wrong.Count -gt 0) {
        Write-Log ('Affected={0}; wrong={1}; updated={2}' -f $affected.Count, $wrong.Count, $updated)
    }
}

function Clear-Notifications {
    Unregister-Event -SourceIdentifier $eventName -ErrorAction SilentlyContinue
    Get-Event -SourceIdentifier $eventName -ErrorAction SilentlyContinue |
        Remove-Event -ErrorAction SilentlyContinue
}

function Stop-Listener {
    Clear-Notifications
    if ($script:listenerStarted) {
        try { [void][System.Data.SqlClient.SqlDependency]::Stop($connectionString) }
        catch { Write-Log ('SqlDependency.Stop failed: ' + $_.Exception.Message) -Level WARNING }
        finally { $script:listenerStarted = $false }
    }
}

function Start-Listener {
    $script:listenerStarted = [System.Data.SqlClient.SqlDependency]::Start($connectionString)
    if (-not $script:listenerStarted) { throw 'SqlDependency.Start returned False.' }
}

try {
    $lookup = New-NameCatalog
    Write-Log "Catalog loaded: $($lookup.Count) combinations. Mode=$(if ($AsService) { 'SERVICE' } else { 'ONCE' })."

    if (-not $AsService) {
        $initial = Get-Snapshot
        Process-Changes -Before @{} -After $initial -Lookup $lookup -InitialReason 'INITIAL'
    } else {
        $hadConnection = $false
        while ($null -eq $endTime -or (Get-Date) -lt $endTime) {
            try {
                Start-Listener
                # Subscribe before initial reconciliation; own updates generate harmless notifications.
                $previous = Get-Snapshot -Subscribe $true
                if ($hadConnection) { Write-Log 'SQL connection restored; full reconciliation.' }
                $hadConnection = $true
                Process-Changes -Before @{} -After $previous -Lookup $lookup -InitialReason 'INITIAL'
                while ($null -eq $endTime -or (Get-Date) -lt $endTime) {
                    $notification = Wait-Event -SourceIdentifier $eventName -Timeout 10
                    if ($null -eq $notification) { continue }
                    $args = $notification.SourceEventArgs
                    Clear-Notifications
                    if ($args.Type.ToString() -eq 'Subscribe' -or $args.Info.ToString() -eq 'Invalid') {
                        throw ('SqlDependency notification rejected: Type={0}, Source={1}, Info={2}' -f $args.Type, $args.Source, $args.Info)
                    }
                    # Always re-arm before doing any updates; filter self-notifications via comparison.
                    $current = Get-Snapshot -Subscribe $true
                    Process-Changes -Before $previous -After $current -Lookup $lookup
                    $previous = $current
                }
            }
            catch {
                Write-Log ('SQL/listener error: ' + $_.Exception.Message + '; reconnecting in 15 seconds.') -Level ERROR
                $hadConnection = $true
                Stop-Listener
                if ($null -ne $endTime -and (Get-Date) -ge $endTime) { break }
                Start-Sleep -Seconds 15
            }
            finally { Stop-Listener }
        }
    }
    Write-Log 'Finished.'
}
catch {
    Write-Log $_.Exception.Message -Level ERROR
    throw
}
finally {
    Stop-Listener
}
