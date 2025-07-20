#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    # Load test helper to properly import the module
    . (Join-Path $PSScriptRoot 'TestHelper.ps1')
    
    # Disable caching for tests
    InModuleScope WinGetManifestFetcher {
        $script:CacheEnabled = $false
    }
}

Describe 'Module Tests' {
    It 'Module imports successfully' {
        Get-Module -Name WinGetManifestFetcher | Should -Not -BeNullOrEmpty
    }
    
    It 'Exports expected functions' {
        $module = Get-Module -Name WinGetManifestFetcher
        $module.ExportedFunctions.Keys | Should -Contain 'Get-LatestWingetVersion'
        $module.ExportedFunctions.Keys | Should -Contain 'Get-WingetPackagesByPublisher'
        $module.ExportedFunctions.Keys | Should -Contain 'Save-WingetInstaller'
        $module.ExportedFunctions.Keys | Should -Contain 'Clear-WingetManifestCache'
        $module.ExportedFunctions.Keys | Should -Contain 'Get-WingetManifestCacheInfo'
        $module.ExportedFunctions.Keys | Should -Contain 'Set-WingetManifestCacheEnabled'
    }
}

Describe 'Get-LatestWingetVersion Parameter Tests' {
    It 'Requires App parameter' {
        $cmd = Get-Command Get-LatestWingetVersion
        $cmd.Parameters['App'].Attributes.Mandatory | Should -Be $true
    }
    
    It 'Rejects null App parameter' {
        { Get-LatestWingetVersion -App $null } | Should -Throw
    }
    
    It 'Rejects empty App parameter' {
        { Get-LatestWingetVersion -App '' } | Should -Throw
    }
}

Describe 'Get-WingetPackagesByPublisher Parameter Tests' {
    It 'Requires Publisher parameter' {
        $cmd = Get-Command Get-WingetPackagesByPublisher
        $cmd.Parameters['Publisher'].Attributes.Mandatory | Should -Be $true
    }
    
    It 'Rejects null Publisher parameter' {
        { Get-WingetPackagesByPublisher -Publisher $null } | Should -Throw
    }
    
    It 'Rejects empty Publisher parameter' {
        { Get-WingetPackagesByPublisher -Publisher '' } | Should -Throw
    }
}

Describe 'Save-WingetInstaller Parameter Tests' {
    It 'Requires App parameter' {
        $cmd = Get-Command Save-WingetInstaller
        $cmd.Parameters['App'].Attributes.Mandatory | Should -Be $true
    }
    
    It 'Rejects null App parameter' {
        { Save-WingetInstaller -App $null } | Should -Throw
    }
    
    It 'Rejects empty App parameter' {
        { Save-WingetInstaller -App '' } | Should -Throw
    }
}

Describe 'Cache Functions Tests' {
    It 'Set-WingetManifestCacheEnabled enables cache' {
        { Set-WingetManifestCacheEnabled -Enabled $true } | Should -Not -Throw
    }
    
    It 'Set-WingetManifestCacheEnabled disables cache' {
        { Set-WingetManifestCacheEnabled -Enabled $false } | Should -Not -Throw
    }
    
    It 'Clear-WingetManifestCache runs without error' {
        { Clear-WingetManifestCache } | Should -Not -Throw
    }
    
    It 'Get-WingetManifestCacheInfo returns proper structure when cache enabled' {
        Set-WingetManifestCacheEnabled -Enabled $true
        $info = Get-WingetManifestCacheInfo
        $info | Should -Not -BeNullOrEmpty
        $info.Enabled | Should -BeOfType [bool]
        $info.Directory | Should -Not -BeNullOrEmpty
        $info.ExpirationMinutes | Should -Be 60
    }
}

AfterAll {
    Remove-Module -Name WinGetManifestFetcher -Force -ErrorAction SilentlyContinue
}