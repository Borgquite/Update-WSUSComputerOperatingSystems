# Update-WSUSComputerOperatingSystems
Update OS Description field in Windows Server Update Services with additional edition and release information

Do you still need to use WSUS in a location with low bandwidth / unreliable Internet connections, or in an airgapped environment, even once it is [deprecated](https://techcommunity.microsoft.com/t5/windows-it-pro-blog/windows-server-update-services-wsus-deprecation/ba-p/4250436)?

Do you think that preventing someone from [exercising rights you previously granted them](https://community.spiceworks.com/t/maybe-wam-wsus-is-not-longer-free/655421/37) is not behaviour that should be financially rewarded?

This script can be run against a WSUS server to add additional edition and release information to the OS Description field, e.g. 'Windows 11 Enterprise 23H2' and 'Windows Server 2022 Enterprise'.

The script was designed from scratch with publicly available documentation only, and is released to the community in perpetuity under the GNU GENERAL PUBLIC LICENSE 3.0.

Make sure to schedule the script to run regularly (e.g. daily) to ensure that new devices receive the latest updated operating system descriptions.

Legal notice: This script is provided without any warranty; without even the implied warranty of merchantability or fitness for a particular purpose. In no event shall the author or contributors be liable for any damages arising from its use. This script is provided “as is”.
