#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

BeforeAll {
    $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $manifestPath = Join-Path (Join-Path (Join-Path $projectRoot 'output') 'WinGetManifestFetcher') 'WinGetManifestFetcher.psd1'
    Import-Module $manifestPath -Force -ErrorAction Stop
}

Describe 'WinGetManifestFetcher live GitHub boundary' -Tag 'Integration' {
    It 'retrieves a known package through a direct manifest path' {
        $result = Get-LatestWingetVersion -App '7zip.7zip' -VersionSource 'manifests/7/7zip/7zip' -ErrorAction Stop

        $result.PackageIdentifier | Should -Be '7zip.7zip'
        $result.PackageVersion | Should -Match '^\d+\.\d+$'
        $result.Installers | Should -Not -BeNullOrEmpty
        $result.Installers.InstallerUrl | Should -Not -Contain $null
        $result.Installers.InstallerSha256 | Should -Match '^[A-Fa-f0-9]{64}$'
    }

    It 'returns a bounded nested publisher listing' {
        $result = @(Get-WingetPackagesByPublisher -Publisher 'Python' -MaxResults 2 -ErrorAction Stop)

        $result | Should -HaveCount 2
        $result.PackageIdentifier | Should -Match '^Python\.'
        $result.ManifestPath | Should -Match '^manifests/p/Python/'
    }
}

AfterAll {
    Remove-Module -Name WinGetManifestFetcher -Force -ErrorAction SilentlyContinue
}
