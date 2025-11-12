# Update-WSUSComputerOperatingSystems
Update OS Description field in Windows Server Update Services with additional edition and release information

Do you still need to use WSUS in a location with low bandwidth / unreliable Internet connections, or in an airgapped environment, even once it is [deprecated](https://techcommunity.microsoft.com/t5/windows-it-pro-blog/windows-server-update-services-wsus-deprecation/ba-p/4250436)?

Do you think that preventing someone from [exercising rights you previously granted them](https://community.spiceworks.com/t/maybe-wam-wsus-is-not-longer-free/655421/37) is not behaviour that should be financially rewarded?

This script can be run against a WSUS server to add additional edition and release information to the OS Description field, e.g. 'Windows 11 Enterprise 23H2' and 'Windows Server 2022 Enterprise'.

The script was designed from scratch with publicly available documentation only, and is released to the community in perpetuity under the GNU GENERAL PUBLIC LICENSE 3.0.

Make sure to schedule the script to run regularly (e.g. daily) to ensure that new devices receive the latest updated operating system descriptions.

Legal notice: This script is provided without any warranty; without even the implied warranty of merchantability or fitness for a particular purpose. In no event shall the author or contributors be liable for any damages arising from its use. This script is provided “as is”.

# Installation Instructions

Open 'Windows PowerShell' as Administrator on your WSUS server, then run these commands:

    # Update PowerShellGet for Windows PowerShell 5.1 - https://learn.microsoft.com/en-us/powershell/gallery/powershellget/update-powershell-51?view=powershellget-3.x
    Install-Module -Name PowerShellGet -AllowClobber -Force
    # (When prompted if you want PowerShellGet to install and import the NuGet provider, respond with 'Y')

    # Install latest version of SQLServer module - https://learn.microsoft.com/en-us/powershell/sql-server/download-sql-server-ps-module?view=sqlserver-ps
    Install-Module -Name SqlServer
    # (When prompted if you want to install the modules from 'PSGallery', respond with 'Y')

    # Change to Update Services installation directory
    Set-Location "$env:ProgramFiles\Update Services"

    # Download latest version of the script to "%ProgramFiles%\Update Services\Update-WSUSComputerOperatingSystems.ps1"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Borgquite/Update-WSUSComputerOperatingSystems/refs/heads/main/Update-WSUSComputerOperatingSystems.ps1" -OutFile Update-WSUSComputerOperatingSystems.ps1

    # Create a new scheduled task to run at midnight daily for up to 2 hours on a local Windows Internal Database instance
    Register-ScheduledTask -TaskName "WSUS Update Operating Systems" `
      -User 'SYSTEM' `
      -Action (New-ScheduledTaskAction -Execute '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' `
        -Argument '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ProgramFiles%\Update Services\Update-WSUSComputerOperatingSystems.ps1" -SQLServerInstance "\\.\pipe\MICROSOFT##WID\tsql\query" -Encrypt Optional' `
        -WorkingDirectory '%ProgramFiles%\Update Services') `
      -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2)) `
      -Trigger (New-ScheduledTaskTrigger -At "00:00:00" -Daily)
    # Update \\.\pipe\MICROSOFT##WID\tsql\query in the above command to SQLSERVERNAME\INSTANCENAME when using an external SQL Server instance

    # Run the scheduled task immediately
    Start-ScheduledTask -TaskName "WSUS Update Operating Systems"
