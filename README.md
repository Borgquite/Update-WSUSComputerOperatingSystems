# Update-WSUSComputerOperatingSystems

Update the **OS Description** field in Windows Server Update Services (WSUS) with additional Windows edition and release information, such as `Windows 11 Enterprise 23H2` or `Windows Server 2022 Datacenter`.

Do you still need to use WSUS in a location with low bandwidth / unreliable Internet connections, or in an airgapped environment, even once it is [deprecated](https://techcommunity.microsoft.com/t5/windows-it-pro-blog/windows-server-update-services-wsus-deprecation/ba-p/4250436)?

Do you think that preventing someone from [exercising rights you previously granted them](https://community.spiceworks.com/t/maybe-wam-wsus-is-not-longer-free/655421/37) is not behaviour that should be financially rewarded?

The original script was designed from scratch using publicly available documentation and released to the community under the GNU General Public License version 3. The existing OS/build/edition catalog is retained and used by the additional modes described below.

**Important:** This tool updates `OSDescription` directly in the WSUS `SUSDB` database. Direct changes to SUSDB are not an officially supported WSUS management API. **Back up SUSDB and verify the backup before use**, preferably test on a noncritical server first.

## Features

- **One-time correction:** scan WSUS computer records, identify known OS editions/builds and update incorrect `OSDescription` values, then exit.
- **Event-driven correction:** `-AsService` performs an initial reconciliation and then uses SQL Query Notifications (`SqlDependency`) to detect new or changed WSUS computer records. This avoids repeated full scans on a fixed schedule.
- **Safe update conditions:** check the computer's OS version, build, edition and current description before updating; avoid redundant writes and skip records changed concurrently.
- **Automatic reconnection:** retry SQL listener failures and reconcile records after reconnecting.
- **Scheduled-task installer:** optionally register a startup task running as `SYSTEM`, without copying scripts into a fixed system directory.
- **Local log:** append timestamped `INFO`, `WARNING` and `ERROR` messages to `Update-WSUSComputerOperatingSystems.log` alongside the main script.
- **No external PowerShell modules:** uses `System.Data.SqlClient` included with .NET Framework; the `SqlServer` PowerShell module and PowerShell Gallery packages are not required.

## Requirements

- Windows PowerShell **5.1 (Desktop edition)** on the WSUS server. Tested with Windows Server 2019 Core; other server versions should be validated in your environment.
- WSUS using Windows Internal Database (WID) or an accessible Microsoft SQL Server instance.
- An account allowed to read `dbo.tbComputerTarget` and `dbo.tbComputerTargetDetail` and update `OSDescription` in `SUSDB`.
- For `-AsService`, **Service Broker enabled in `SUSDB`** and permissions sufficient to establish SQL Query Notifications. The installation process does not enable Service Broker automatically.
- Administrator privileges for installing or changing a scheduled task running as `SYSTEM`.

## Run manually

Open an elevated Windows PowerShell 5.1 session **on the WSUS server** and run the main script:

```powershell
# Correct existing descriptions once and exit.
.\Update-WSUSComputerOperatingSystems.ps1

# Correct existing descriptions, then monitor subsequent changes indefinitely.
.\Update-WSUSComputerOperatingSystems.ps1 -AsService

# Test the event listener for 60 minutes, then exit.
.\Update-WSUSComputerOperatingSystems.ps1 -AsService -DurationMinutes 60
```

The default database connection is local WID (`\\.\pipe\MICROSOFT##WID\tsql\query`). To use an external SQL Server instance:

```powershell
.\Update-WSUSComputerOperatingSystems.ps1 -SQLServerInstance 'SQLSERVER\INSTANCE' -AsService
```

`-Encrypt Optional` is the default (`Encrypt=False` in the .NET connection string). `-Encrypt Mandatory` uses `Encrypt=True` and requires a trusted SQL Server certificate; `True` and `False` are also accepted. `-DurationMinutes` requires `-AsService`; zero means unlimited duration. Unrecognized builds and editions are left unchanged.

You can run the one-time mode from your own scheduling system. For continuous monitoring, the installer below provides a dedicated Task Scheduler configuration.

## Install a scheduled task

`Install-WSUSComputerOperatingSystems.ps1` creates or updates a scheduled task named **`Update-WSUSComputerOperatingSystems`**, under the Task Scheduler folder you select. It runs the main script **from the chosen installation directory**; the installer itself is not copied there.

The registered task runs as `SYSTEM` with `-AsService`, starts **one minute after system startup**, has no execution time limit, and is also **started immediately after installation**. Task Scheduler uses `MultipleInstances=IgnoreNew` to prevent parallel instances of this task.

The installer uses the main script already present in the chosen folder or downloads it from the project's `main` branch. If a local copy exists, it asks whether to download the latest version (default **Yes**); answering **No** keeps the local file. The installer validates the downloaded PowerShell syntax and `-AsService` support before replacing an existing file.

**Download source:** The commands below use this repository's `main` branch (`Borgquite/Update-WSUSComputerOperatingSystems`). For development branches, use the corresponding branch or commit URLs instead. Inspect downloaded scripts before executing them.

### Quick installation: one PowerShell command

Run one of the following in an elevated Windows PowerShell 5.1 session. Each command downloads **only the installer** to a uniquely named temporary file, runs it, and removes that temporary copy. The installer obtains the main script separately and registers the task.

**A. Install in the current directory.** First switch to the desired **permanent** directory (for example, `Set-Location 'C:\Scripts\WSUS'`):

```powershell
$f=Join-Path $env:TEMP ("WSUS-Install-$([guid]::NewGuid().ToString('N')).ps1"); try { Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/Borgquite/Update-WSUSComputerOperatingSystems/main/Install-WSUSComputerOperatingSystems.ps1' -OutFile $f -ErrorAction Stop; & $f -InstallPath (Get-Location).ProviderPath } finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
```

**B. Install in a specified directory.** Replace `C:\Scripts\WSUS` with your preferred permanent path:

```powershell
$f=Join-Path $env:TEMP ("WSUS-Install-$([guid]::NewGuid().ToString('N')).ps1"); try { Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/Borgquite/Update-WSUSComputerOperatingSystems/main/Install-WSUSComputerOperatingSystems.ps1' -OutFile $f -ErrorAction Stop; & $f -InstallPath 'C:\Scripts\WSUS' } finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
```

The commands track the current `main` branch, not a pinned release. For repeatable deployments, substitute URLs pinned to a specific commit or release tag. Internet access is required for the quick-install commands and for automatic main-script updates.

### Manual installation: two alternatives

Download `Install-WSUSComputerOperatingSystems.ps1` from this repository or download and extract the repository ZIP. You can also use a previously obtained copy of `Update-WSUSComputerOperatingSystems.ps1` to install without downloading the main script again.

**A. Install alongside the installer:**

```powershell
& 'C:\Scripts\WSUS\Install-WSUSComputerOperatingSystems.ps1'
```

By default the installer checks **its own directory** (`$PSScriptRoot`), not the PowerShell working directory (`$PWD`). If the main script is already there, the installer skips the installation-directory question and offers to update the script. If the main script is absent, it asks for a destination and proposes the installer's directory, unless that location is temporary.

**B. Install into a different directory:**

```powershell
& 'C:\Temp\WSUS\Install-WSUSComputerOperatingSystems.ps1' -InstallPath 'D:\Scripts\WSUS'
```

This is useful when the installer was downloaded to a temporary directory. The destination is always `-InstallPath`; the installer's own location is irrelevant when that parameter is supplied.

### Installer options and prompts

- **Installation directory:** prompt only if needed and `-InstallPath` was not supplied. Temporary destinations (`%TEMP%`, `%TMP%`, `C:\Temp` and similar paths) are rejected; a permanent path must be specified.
- **Task Scheduler folder:** `Task Scheduler folder (leave empty for root)`; blank means `\`, while `MP` means `\MP\`. Pass `-TaskPath '\MP'` to choose a folder without prompting. Missing Scheduler folders are created.
- **Confirmation:** the installer shows the full configuration and asks before creating or updating a task. It will not silently replace an unrelated task with the same name.
- **Existing tasks:** if this task is already running, the installer stops it before applying changes and starts it again afterward. Other tasks with the same name in different Task Scheduler folders are reported but not modified.
- **Script files:** the main script is downloaded only when missing or when its update is accepted. The installer itself is not copied to the target folder. Missing permanent installation directories are created as necessary.

Example with custom installation and Scheduler folders:

```powershell
.\Install-WSUSComputerOperatingSystems.ps1 -InstallPath 'C:\Scripts\WSUS' -TaskPath '\MP'
```

Example for an external SQL Server:

```powershell
.\Install-WSUSComputerOperatingSystems.ps1 -InstallPath 'C:\Scripts\WSUS' -TaskPath '\MP' -SQLServerInstance 'SQLSERVER\INSTANCE' -Encrypt Mandatory
```

To check or manually start the task after installation:

```powershell
Get-ScheduledTask -TaskPath '\MP\' -TaskName 'Update-WSUSComputerOperatingSystems'
Get-ScheduledTaskInfo -TaskPath '\MP\' -TaskName 'Update-WSUSComputerOperatingSystems'
Start-ScheduledTask -TaskPath '\MP\' -TaskName 'Update-WSUSComputerOperatingSystems'
```

To remove **only the scheduled task**, leaving the script and its log in place:

```powershell
.\Install-WSUSComputerOperatingSystems.ps1 -Uninstall -TaskPath '\MP'
```

**Note for existing installations:** This installer does not alter the previous task named `WSUS Update Operating Systems`. If you already run that original daily task, review and disable it separately if switching to continuous monitoring.

## Logging

The main script appends logs to **`Update-WSUSComputerOperatingSystems.log` alongside its own `.ps1` file**. For an installation in `C:\Scripts\WSUS`, the log path is `C:\Scripts\WSUS\Update-WSUSComputerOperatingSystems.log`.

Log lines use local server time with millisecond precision and the format `dd.MM.yyyy HH:mm:ss.fff [LEVEL] Message`:

```text
25.10.2026 16:23:34.075 [INFO] Catalog loaded: 1094 combinations. Mode=SERVICE.
25.10.2026 16:23:34.278 [INFO] UPDATED INITIAL example-pc.contoso.com [14] Build=26200; OS=Windows 10 Pro -> Windows 11 Pro 25H2
25.10.2026 16:23:34.325 [INFO] Affected=97; wrong=12; updated=12
```

Levels are `INFO`, `WARNING`, and `ERROR`. Only actual fixes and relevant listener/SQL conditions are logged; routine no-op notifications do not produce an entry. The log is created when the main script runs, not by the installer. **No internal log rotation or truncation** is performed; configure retention or rotation externally if necessary. Ensure the task account can write to the installation directory.

Follow the log in PowerShell:

```powershell
Get-Content 'C:\Scripts\WSUS\Update-WSUSComputerOperatingSystems.log' -Tail 30 -Wait
```

## How event-driven monitoring works

1. Generate the name catalog using the script's OS version and SKU mappings.
2. Register SQL Query Notifications before the initial database reconciliation to avoid missing concurrent changes.
3. Read the current computer details and repair incorrect names where the build/SKU matches a known catalog entry.
4. When an event arrives, re-register the next notification and compare the new snapshot with the previous one. Check that the database row still matches before issuing an `UPDATE`.
5. Ignore already-correct descriptions and redundant notifications, including notifications caused by the script's own updates.
6. If the listener or SQL connection fails, log the error, wait 15 seconds, reconnect and perform a full reconciliation.

No database triggers are installed. The listener relies on Service Broker / `SqlDependency`; it does not install or clean up Service Broker infrastructure itself.

## Tests and production validation

The offline test is located at `tests/Test-WSUSCatalog.ps1`:

```powershell
.\tests\Test-WSUSCatalog.ps1
```

It validates the OS catalog and representative mappings as well as the correction logic using mocked SQL and logging operations. It **does not connect to SUSDB or modify WSUS**. The test does not require a WSUS installation.

Before putting the event-driven task into production, also verify:

1. A one-time run completes successfully and a second run does not repeat successful updates.
2. `-AsService -DurationMinutes 60` works on your server and corrects at least one **newly changed** description, not only the initial scan.
3. The installed scheduled task can connect to `SUSDB` as `SYSTEM` and starts after reboot.
4. The listener reconnects after a planned WID/SQL Server service restart.
5. The installed folder's write permissions are limited to trusted administrators: modification of the `.ps1` file allows code to execute as `SYSTEM`.

## License

The project is distributed under the **GNU General Public License version 3**. See [LICENSE](LICENSE).

Legal notice: This script is provided without any warranty; without even the implied warranty of merchantability or fitness for a particular purpose. In no event shall the author or contributors be liable for any damages arising from its use. This script is provided "as is".
