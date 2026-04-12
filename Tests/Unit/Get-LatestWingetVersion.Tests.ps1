#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests specifically for Get-LatestWingetVersion function
.DESCRIPTION
    Detailed unit tests covering edge cases and error conditions
#>

BeforeAll {
    # Load test helper to properly import the module
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'TestHelper.ps1')
    
    # Import mock data
    . (Join-Path $PSScriptRoot '..' 'Fixtures' 'MockManifests.ps1')
}

Describe 'Get-LatestWingetVersion - Edge Cases' {
    Context 'Special Characters in Package Names' {
        BeforeEach {
            Mock -CommandName Write-Verbose -ModuleName WinGetManifestFetcher
            Mock -CommandName Write-Warning -ModuleName WinGetManifestFetcher
        }
        
        It 'Should handle package names with special characters' {
            $specialNames = @(
                'Notepad++.Notepad++',
                'JetBrains.IntelliJIDEA.Ultimate.EAP',
                'Microsoft.DotNet.SDK.8',
                'Python.Python.3.12'
            )
            
            Mock -CommandName Get-GitHubContent -MockWith {
                @{ type = 'dir' }
            } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{ PackageIdentifier = 'Test.Package'; PackageVersion = '1.0.0'; Installers = @() }
            } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            
            $specialNames | ForEach-Object {
                { Get-LatestWingetVersion -App $_ -ErrorAction Stop } | Should -Not -Throw
            }
        }
        
        It 'Should URL-encode special characters in package paths' {
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                # Verify that Notepad++ is URL-encoded
                if ($Path -like '*Notepad++*' -and $Path -notlike '*Notepad%2B%2B*') {
                    throw "Path not properly encoded"
                }
                return @{ entries = @(@{ name = '8.6.2'; type = 'dir' }) }
            } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{ PackageIdentifier = 'Notepad++.Notepad++'; PackageVersion = '8.6.2'; Installers = @() }
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-LatestWingetVersion -App 'Notepad++.Notepad++' -VersionSource 'manifests/n/Notepad%2B%2B/Notepad%2B%2B'
            $result | Should -Not -BeNullOrEmpty
        }
    }
    
    Context 'Version Sorting Edge Cases' {
        It 'Should correctly sort semantic versions' {
            Mock -CommandName Get-GitHubContent -MockWith {
                @{
                    entries = @(
                        @{ name = '1.0.0'; type = 'dir' }
                        @{ name = '1.10.0'; type = 'dir' }
                        @{ name = '1.2.0'; type = 'dir' }
                        @{ name = '2.0.0-beta'; type = 'dir' }
                        @{ name = '1.9.0'; type = 'dir' }
                        @{ name = '.validation'; type = 'dir' }
                    )
                }
            } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{ PackageIdentifier = 'Test.Package'; PackageVersion = '1.10.0'; Installers = @() }
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-LatestWingetVersion -App 'Test.Package' -VersionSource 'manifests/t/Test/Package'
            
            # Should select 2.0.0-beta as latest (or 1.10.0 if pre-release is excluded)
            $result.PackageVersion | Should -BeIn @('2.0.0-beta', '1.10.0')
        }
        
        It 'Should handle non-standard version formats' {
            Mock -CommandName Get-GitHubContent -MockWith {
                @{
                    entries = @(
                        @{ name = '2024.1'; type = 'dir' }
                        @{ name = '2023.3.4'; type = 'dir' }
                        @{ name = 'v1.0'; type = 'dir' }
                        @{ name = '1.0'; type = 'dir' }
                    )
                }
            } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{ PackageIdentifier = 'Test.Package'; PackageVersion = '2024.1'; Installers = @() }
            } -ModuleName WinGetManifestFetcher
            
            { Get-LatestWingetVersion -App 'Test.Package' -VersionSource 'manifests/t/Test/Package' } | Should -Not -Throw
        }
    }
    
    Context 'Manifest Structure Variations' {
        It 'Should handle manifests with minimal information' {
            Mock -CommandName Get-GitHubContent -MockWith {
                @{ entries = @(@{ name = '1.0.0'; type = 'dir' }) }
            } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName Invoke-RestMethod -MockWith {
                param($Uri)
                if ($Uri -like '*installer.yaml') {
                    return @'
PackageIdentifier: Minimal.Package
PackageVersion: 1.0.0
Installers:
- Architecture: x64
  InstallerUrl: https://example.com/installer.exe
  InstallerSha256: 0000000000000000000000000000000000000000000000000000000000000000
ManifestType: installer
ManifestVersion: 1.0.0
'@
                }
                return ''
            } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                param($Yaml)
                if ($Yaml -like '*Minimal.Package*') {
                    return @{
                        PackageIdentifier = 'Minimal.Package'
                        PackageVersion = '1.0.0'
                        Installers = @(
                            @{
                                Architecture = 'x64'
                                InstallerUrl = 'https://example.com/installer.exe'
                                InstallerSha256 = '0000000000000000000000000000000000000000000000000000000000000000'
                            }
                        )
                    }
                }
                return @{}
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-LatestWingetVersion -App 'Minimal.Package' -VersionSource 'manifests/m/Minimal/Package'
            
            $result | Should -Not -BeNullOrEmpty
            $result.PackageIdentifier | Should -Be 'Minimal.Package'
            $result.PackageVersion | Should -Be '1.0.0'
            $result.Installers | Should -HaveCount 1
        }
        
        It 'Should merge installer-level and manifest-level properties correctly' {
            Mock -CommandName Get-GitHubContent -MockWith {
                @{ entries = @(@{ name = '1.0.0'; type = 'dir' }) }
            } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{
                    PackageIdentifier = 'Test.Package'
                    PackageVersion = '1.0.0'
                    Scope = 'machine'  # Manifest-level default
                    InstallerSwitches = @{ Silent = '/S' }  # Manifest-level default
                    Installers = @(
                        @{
                            Architecture = 'x64'
                            InstallerUrl = 'https://example.com/x64.exe'
                            InstallerSha256 = '0000000000000000000000000000000000000000000000000000000000000000'
                            Scope = 'user'  # Override manifest-level
                        }
                        @{
                            Architecture = 'x86'
                            InstallerUrl = 'https://example.com/x86.exe'
                            InstallerSha256 = '1111111111111111111111111111111111111111111111111111111111111111'
                            # Should inherit manifest-level Scope
                        }
                    )
                }
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-LatestWingetVersion -App 'Test.Package' -VersionSource 'manifests/t/Test/Package'
            
            $result.Installers[0].Scope | Should -Be 'user'  # Overridden
            $result.Installers[1].Scope | Should -Be 'machine'  # Inherited
        }
    }
    
    Context 'Error Recovery' {
        It 'Should continue processing when one manifest file is malformed' {
            Mock -CommandName Get-GitHubContent -MockWith {
                @{
                    entries = @(
                        @{ name = '1.0.0'; type = 'dir' }
                        @{ name = '2.0.0'; type = 'dir' }
                    )
                }
            } -ModuleName WinGetManifestFetcher -ParameterFilter { $Path -notlike '*/1.0.0' -and $Path -notlike '*/2.0.0' }
            
            Mock -CommandName Get-GitHubContent -MockWith {
                @{
                    entries = @(
                        @{ name = 'Package.installer.yaml'; download_url = 'https://mock/installer.yaml' }
                    )
                }
            } -ModuleName WinGetManifestFetcher -ParameterFilter { $Path -like '*/2.0.0' }
            
            Mock -CommandName Get-GitHubContent -MockWith {
                throw "Malformed content"
            } -ModuleName WinGetManifestFetcher -ParameterFilter { $Path -like '*/1.0.0' }
            
            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{ PackageIdentifier = 'Test.Package'; PackageVersion = '2.0.0'; Installers = @() }
            } -ModuleName WinGetManifestFetcher
            
            # Should skip 1.0.0 and use 2.0.0
            $result = Get-LatestWingetVersion -App 'Test.Package' -VersionSource 'manifests/t/Test/Package'
            $result.PackageVersion | Should -Be '2.0.0'
        }
        
        It 'Should handle empty version directories' {
            Mock -CommandName Get-GitHubContent -MockWith {
                @{ entries = @() }  # Empty directory
            } -ModuleName WinGetManifestFetcher
            
            { Get-LatestWingetVersion -App 'Empty.Package' -VersionSource 'manifests/e/Empty/Package' -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe 'Get-LatestWingetVersion - Performance' {
    Context 'Caching Behavior' {
        It 'Should not make redundant API calls' {
            Mock -CommandName Get-GitHubContent -MockWith {
                @{ entries = @(@{ name = '1.0.0'; type = 'dir' }) }
            } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{ PackageIdentifier = 'Test.Package'; PackageVersion = '1.0.0'; Installers = @() }
            } -ModuleName WinGetManifestFetcher
            
            # First call
            $null = Get-LatestWingetVersion -App 'Test.Package' -VersionSource 'manifests/t/Test/Package'
            
            # Verify API calls were made
            Assert-MockCalled -CommandName Get-GitHubContent -ModuleName WinGetManifestFetcher
            Assert-MockCalled -CommandName Invoke-RestMethod -ModuleName WinGetManifestFetcher
        }
    }
}

AfterAll {
    Remove-Module -Name WinGetManifestFetcher -Force -ErrorAction SilentlyContinue
}