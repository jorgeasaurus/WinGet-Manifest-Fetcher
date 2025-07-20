# Mock manifest data for offline testing

$script:MockManifests = @{
    'Microsoft.PowerToys' = @{
        InstallerYaml = @'
PackageIdentifier: Microsoft.PowerToys
PackageVersion: 0.75.1
InstallerType: exe
Scope: user
InstallModes:
- interactive
- silent
InstallerSwitches:
  Silent: /silent /norestart
  SilentWithProgress: /silent /norestart
UpgradeBehavior: install
Commands:
- PowerToys
Installers:
- Architecture: x64
  InstallerUrl: https://github.com/microsoft/PowerToys/releases/download/v0.75.1/PowerToysSetup-0.75.1-x64.exe
  InstallerSha256: 1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF
- Architecture: arm64
  InstallerUrl: https://github.com/microsoft/PowerToys/releases/download/v0.75.1/PowerToysSetup-0.75.1-arm64.exe
  InstallerSha256: FEDCBA0987654321FEDCBA0987654321FEDCBA0987654321FEDCBA0987654321
ManifestType: installer
ManifestVersion: 1.5.0
'@
        DefaultYaml = @'
PackageIdentifier: Microsoft.PowerToys
PackageVersion: 0.75.1
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.5.0
'@
        LocaleYaml = @'
PackageIdentifier: Microsoft.PowerToys
PackageVersion: 0.75.1
PackageLocale: en-US
Publisher: Microsoft Corporation
PublisherUrl: https://microsoft.com
PublisherSupportUrl: https://github.com/microsoft/PowerToys/issues
PrivacyUrl: https://privacy.microsoft.com/privacystatement
Author: Microsoft Corporation
PackageName: PowerToys (Preview)
PackageUrl: https://github.com/microsoft/PowerToys
License: MIT
LicenseUrl: https://github.com/microsoft/PowerToys/blob/master/LICENSE
Copyright: Copyright (c) Microsoft Corporation. All rights reserved.
CopyrightUrl: https://github.com/microsoft/PowerToys/blob/main/LICENSE
ShortDescription: Microsoft PowerToys is a set of utilities for power users to tune and streamline their Windows experience for greater productivity.
Description: |
  Microsoft PowerToys is a set of utilities for power users to tune and streamline their Windows experience for greater productivity.
  Inspired by the Windows 95 era PowerToys project, this reboot provides power users with ways to squeeze more efficiency out of the Windows shell and customize it for individual workflows.
Moniker: powertoys
Tags:
- colorpicker
- fancyzones
- fileexplorer
- imageresizer
- keyboardmanager
- power
- powerrename
- powertoys
- productivity
- shortcutguide
- utility
- windows
ManifestType: defaultLocale
ManifestVersion: 1.5.0
'@
    }
    
    '7zip.7zip' = @{
        InstallerYaml = @'
PackageIdentifier: 7zip.7zip
PackageVersion: 23.01
InstallerType: msi
Scope: machine
UpgradeBehavior: install
Commands:
- 7z
FileExtensions:
- 7z
- bz2
- gz
- rar
- tar
- zip
Installers:
- Architecture: x64
  InstallerUrl: https://www.7-zip.org/a/7z2301-x64.msi
  InstallerSha256: A1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF
  ProductCode: '{23170F69-40C1-2702-2301-000001000000}'
- Architecture: x86
  InstallerUrl: https://www.7-zip.org/a/7z2301.msi
  InstallerSha256: B1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF
  ProductCode: '{23170F69-40C1-2701-2301-000001000000}'
- Architecture: arm64
  InstallerUrl: https://www.7-zip.org/a/7z2301-arm64.exe
  InstallerSha256: C1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF
  InstallerType: exe
  InstallerSwitches:
    Silent: /S
    SilentWithProgress: /S
ManifestType: installer
ManifestVersion: 1.5.0
'@
        LocaleYaml = @'
PackageIdentifier: 7zip.7zip
PackageVersion: 23.01
PackageLocale: en-US
Publisher: Igor Pavlov
PublisherUrl: https://www.7-zip.org
PublisherSupportUrl: https://www.7-zip.org/support.html
Author: Igor Pavlov
PackageName: 7-Zip
PackageUrl: https://www.7-zip.org
License: GNU LGPL
LicenseUrl: https://www.7-zip.org/license.txt
Copyright: Copyright (C) 1999-2023 Igor Pavlov.
CopyrightUrl: https://www.7-zip.org/license.txt
ShortDescription: 7-Zip is a file archiver with a high compression ratio.
Description: |
  7-Zip is a file archiver with a high compression ratio. The program supports various archive formats and provides a powerful command line version.
Moniker: 7zip
Tags:
- archiver
- compression
- file-compression
- utility
ManifestType: defaultLocale
ManifestVersion: 1.5.0
'@
    }
    
    'Git.Git' = @{
        InstallerYaml = @'
PackageIdentifier: Git.Git
PackageVersion: 2.44.0
InstallerType: inno
Scope: machine
UpgradeBehavior: install
Commands:
- git
Installers:
- Architecture: x64
  InstallerUrl: https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/Git-2.44.0-64-bit.exe
  InstallerSha256: D1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF
- Architecture: x86
  InstallerUrl: https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/Git-2.44.0-32-bit.exe
  InstallerSha256: E1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF
ManifestType: installer
ManifestVersion: 1.5.0
'@
        LocaleYaml = @'
PackageIdentifier: Git.Git
PackageVersion: 2.44.0
PackageLocale: en-US
Publisher: Johannes Schindelin
PublisherUrl: https://gitforwindows.org
PublisherSupportUrl: https://github.com/git-for-windows/git/issues
Author: Johannes Schindelin
PackageName: Git
PackageUrl: https://gitforwindows.org
License: GNU General Public License version 2
LicenseUrl: https://raw.githubusercontent.com/git-for-windows/git/main/COPYING
Copyright: Copyright Johannes Schindelin
ShortDescription: Git for Windows focuses on offering a lightweight, native set of tools that bring the full feature set of the Git SCM to Windows.
Description: |
  Git for Windows provides a BASH emulation used to run Git from the command line. *NIX users should feel right at home, as the BASH emulation behaves just like the "git" command in LINUX and UNIX environments.
Moniker: git
Tags:
- cli
- command-line
- cross-platform
- development
- dvcs
- foss
- open-source
- tool
- utility
- vcs
ManifestType: defaultLocale
ManifestVersion: 1.5.0
'@
    }
}

# Function to get mock manifest content
function Get-MockManifest {
    param(
        [string]$PackageId,
        [string]$ManifestType
    )
    
    if ($script:MockManifests.ContainsKey($PackageId)) {
        return $script:MockManifests[$PackageId][$ManifestType]
    }
    
    return $null
}

# Function and variable are now available in the current scope