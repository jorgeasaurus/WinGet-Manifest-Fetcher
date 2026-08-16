@{
    RootModule = 'WinGetManifestFetcher.psm1'
    ModuleVersion = '1.6.0'
    GUID = 'a7d2e4f8-9b3c-4d5e-8f1a-2c3b4a5d6e7f'
    Author = 'WinGet Manifest Fetcher Contributors'
    CompanyName = 'Jorgeasaurus'
    Copyright = '(c) 2026 WinGet Manifest Fetcher Contributors. All rights reserved.'
    Description = 'Retrieves installer information from the microsoft/winget-pkgs repository without requiring the WinGet client.'
    PowerShellVersion = '5.1'

    RequiredModules = @(
        @{ ModuleName = 'powershell-yaml'; ModuleVersion = '0.4.0' }
    )

    FunctionsToExport = @(
        'Get-LatestWingetVersion'
        'Get-WingetPackagesByPublisher'
        'Save-WingetInstaller'
        'Clear-WingetManifestCache'
        'Get-WingetManifestCacheInfo'
        'Set-WingetManifestCacheEnabled'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @(
                'WinGet'
                'PackageManager'
                'Manifest'
                'GitHub'
                'Installer'
                'Windows'
                'PSEdition_Desktop'
                'PSEdition_Core'
            )
            LicenseUri = 'https://github.com/jorgeasaurus/WinGet-Manifest-Fetcher/blob/main/LICENSE'
            ProjectUri = 'https://github.com/jorgeasaurus/WinGet-Manifest-Fetcher'
            ReleaseNotes = @'
## Version 1.6.0
- Native GitHub REST requests with token-based authentication
- Reliable package search, version ordering, and nested publisher traversal
- Staged HTTPS installer downloads with fail-closed SHA256 validation
- Hardened build, test, coverage, and publishing gates
'@
        }
    }
}
