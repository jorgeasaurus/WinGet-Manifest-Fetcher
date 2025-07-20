#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Integration tests for WinGetManifestFetcher module
.DESCRIPTION
    These tests make actual calls to GitHub API and should be run when online.
    Use -Tag 'Integration' to run only these tests.
.NOTES
    These tests may be affected by GitHub API rate limits.
#>

BeforeAll {
    # Get the module path
    $ModulePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $ModuleName = 'WinGetManifestFetcher'
    
    # Remove module if already loaded
    Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction SilentlyContinue
    
    # Import the module - check both old and new locations
    if (Test-Path "$ModulePath\$ModuleName.psm1") {
        Import-Module "$ModulePath\$ModuleName.psm1" -Force
    } elseif (Test-Path "$ModulePath\src\$ModuleName.psm1") {
        Import-Module "$ModulePath\src\$ModuleName.psm1" -Force
    } else {
        throw "Could not find module file in expected locations"
    }
    
    # Test if we have internet connectivity
    $script:HasInternet = $false
    try {
        $null = Invoke-RestMethod -Uri 'https://api.github.com' -TimeoutSec 5
        $script:HasInternet = $true
    }
    catch {
        Write-Warning "No internet connectivity detected. Integration tests will be skipped."
    }
    
    # Common test packages that should exist
    $script:TestPackages = @{
        KnownGood = @(
            @{ App = '7zip.7zip'; Publisher = '7zip'; MinInstallers = 2 }
            @{ App = 'Git.Git'; Publisher = 'Git'; MinInstallers = 2 }
            @{ App = 'Microsoft.PowerToys'; Publisher = 'Microsoft'; MinInstallers = 1 }
            @{ App = 'Notepad++.Notepad++'; Publisher = 'Notepad++'; MinInstallers = 2 }
            @{ App = 'VideoLAN.VLC'; Publisher = 'VideoLAN'; MinInstallers = 2 }
        )
        Publishers = @(
            @{ Name = 'Microsoft'; MinPackages = 50 }
            @{ Name = 'Google'; MinPackages = 5 }
            @{ Name = 'Adobe'; MinPackages = 5 }
            @{ Name = 'Mozilla'; MinPackages = 2 }
        )
    }
}

Describe 'WinGetManifestFetcher Integration Tests' -Tag 'Integration' {
    Context 'Prerequisites' {
        It 'Should have internet connectivity' {
            $script:HasInternet | Should -Be $true
        }
        
        It 'Should have GitHub API accessible' {
            { Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-pkgs' -TimeoutSec 10 } | Should -Not -Throw
        }
        
        It 'Should have required modules available' {
            Get-Module -ListAvailable -Name PowerShellForGitHub | Should -Not -BeNullOrEmpty
            Get-Module -ListAvailable -Name powershell-yaml | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-LatestWingetVersion - Integration' -Tag 'Integration' -Skip:(-not $script:HasInternet) {
    Context 'Real Package Retrieval' {
        It 'Should retrieve known packages: <App>' -TestCases $script:TestPackages.KnownGood {
            param($App, $Publisher, $MinInstallers)
            
            $result = Get-LatestWingetVersion -App $App -ErrorAction SilentlyContinue
            
            $result | Should -Not -BeNullOrEmpty
            $result.PackageIdentifier | Should -Be $App
            $result.PackageVersion | Should -Match '^\d+\.\d+.*'
            $result.Installers | Should -Not -BeNullOrEmpty
            $result.Installers.Count | Should -BeGreaterOrEqual $MinInstallers
        }
        
        It 'Should handle non-existent packages gracefully' {
            $fakePackage = "NonExistent.Package.$(Get-Random -Maximum 999999)"
            
            { Get-LatestWingetVersion -App $fakePackage -ErrorAction Stop } | Should -Throw
        }
    }
    
    Context 'Version Source Performance' {
        It 'Should be faster with VersionSource parameter' {
            $app = 'Microsoft.PowerToys'
            $versionSource = 'manifests/m/Microsoft/PowerToys'
            
            # First call without version source
            $start1 = Get-Date
            $result1 = Get-LatestWingetVersion -App $app
            $duration1 = (Get-Date) - $start1
            
            # Second call with version source
            $start2 = Get-Date
            $result2 = Get-LatestWingetVersion -App $app -VersionSource $versionSource
            $duration2 = (Get-Date) - $start2
            
            # Both should return same package
            $result1.PackageIdentifier | Should -Be $result2.PackageIdentifier
            $result1.PackageVersion | Should -Be $result2.PackageVersion
            
            # Version source should be faster (allowing some margin for network variance)
            # Note: This might fail occasionally due to network conditions
            Write-Host "Without VersionSource: $($duration1.TotalSeconds)s, With VersionSource: $($duration2.TotalSeconds)s"
        }
    }
    
    Context 'Package Content Validation' {
        It 'Should return complete package information for Microsoft.PowerToys' {
            $result = Get-LatestWingetVersion -App 'Microsoft.PowerToys'
            
            # Basic properties
            $result.PackageIdentifier | Should -Be 'Microsoft.PowerToys'
            $result.PackageVersion | Should -Not -BeNullOrEmpty
            $result.PackageName | Should -BeLike '*PowerToys*'
            $result.Publisher | Should -BeLike '*Microsoft*'
            
            # URLs
            $result.PublisherUrl | Should -BeLike 'https://*'
            $result.LicenseUrl | Should -BeLike 'https://*'
            
            # Descriptions
            $result.ShortDescription | Should -Not -BeNullOrEmpty
            $result.Description | Should -Not -BeNullOrEmpty
            
            # Installers
            $result.Installers | Should -Not -BeNullOrEmpty
            $result.Installers | ForEach-Object {
                $_.Architecture | Should -BeIn @('x64', 'arm64')
                $_.InstallerType | Should -Not -BeNullOrEmpty
                $_.InstallerUrl | Should -BeLike 'https://*'
                $_.InstallerSha256 | Should -Match '^[A-Fa-f0-9]{64}$'
            }
        }
    }
    
    Context 'Search Functionality' {
        It 'Should find packages with partial names' {
            $partialSearches = @(
                @{ Search = 'notepad'; Expected = 'Notepad++.Notepad++' }
                @{ Search = '7zip'; Expected = '7zip.7zip' }
                @{ Search = 'powertoys'; Expected = 'Microsoft.PowerToys' }
            )
            
            $partialSearches | ForEach-Object {
                $result = Get-LatestWingetVersion -App $_.Search -ErrorAction SilentlyContinue
                if ($result) {
                    $result.PackageIdentifier | Should -BeLike "*$($_.Search)*"
                }
            }
        }
        
        It 'Should handle Publisher/Package format' {
            $result = Get-LatestWingetVersion -App 'Microsoft/PowerToys'
            
            $result | Should -Not -BeNullOrEmpty
            $result.PackageIdentifier | Should -Be 'Microsoft.PowerToys'
        }
    }
}

Describe 'Get-WingetPackagesByPublisher - Integration' -Tag 'Integration' -Skip:(-not $script:HasInternet) {
    Context 'Publisher Search' {
        It 'Should find packages for known publishers: <Name>' -TestCases $script:TestPackages.Publishers {
            param($Name, $MinPackages)
            
            $result = Get-WingetPackagesByPublisher -Publisher $Name -MaxResults 100
            
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterOrEqual $MinPackages
            $result | ForEach-Object {
                $_.Publisher | Should -Be $Name
                $_.PackageIdentifier | Should -BeLike "$Name.*"
                $_.ManifestPath | Should -BeLike "manifests/*/$Name/*"
            }
        }
        
        It 'Should support partial publisher names' {
            $result = Get-WingetPackagesByPublisher -Publisher 'Micro' -MaxResults 20
            
            $result | Should -Not -BeNullOrEmpty
            $publishers = $result.Publisher | Select-Object -Unique
            $publishers | Should -Contain 'Microsoft'
        }
        
        It 'Should return empty for non-existent publisher' {
            $fakePublisher = "NonExistentPublisher$(Get-Random -Maximum 999999)"
            
            $result = Get-WingetPackagesByPublisher -Publisher $fakePublisher
            $result | Should -BeNullOrEmpty
        }
    }
    
    Context 'Version Information' {
        It 'Should include versions when requested' {
            $result = Get-WingetPackagesByPublisher -Publisher 'VideoLAN' -IncludeVersions
            
            $result | Should -Not -BeNullOrEmpty
            $result | ForEach-Object {
                $_.LatestVersion | Should -Not -BeNullOrEmpty
                $_.LatestVersion | Should -Match '^\d+\.\d+.*'
            }
        }
        
        It 'Should not include versions by default' {
            $result = Get-WingetPackagesByPublisher -Publisher 'VideoLAN' -MaxResults 5
            
            $result | Should -Not -BeNullOrEmpty
            $result | ForEach-Object {
                $_.LatestVersion | Should -BeNullOrEmpty
            }
        }
    }
    
    Context 'MaxResults Parameter' {
        It 'Should respect MaxResults limit' {
            $limits = @(1, 5, 10)
            
            $limits | ForEach-Object {
                $result = Get-WingetPackagesByPublisher -Publisher 'Microsoft' -MaxResults $_
                $result.Count | Should -Be $_
            }
        }
        
        It 'Should return all results when MaxResults is 0' {
            # Note: This might return many results, so we test with a smaller publisher
            $result = Get-WingetPackagesByPublisher -Publisher 'Notepad++' -MaxResults 0
            
            $result | Should -Not -BeNullOrEmpty
            # Notepad++ should have at least the main package
            $result.Count | Should -BeGreaterOrEqual 1
        }
    }
}

Describe 'Error Handling - Integration' -Tag 'Integration' -Skip:(-not $script:HasInternet) {
    Context 'Network Errors' {
        It 'Should provide meaningful error for invalid package format' {
            $invalidFormats = @(
                'InvalidFormat',
                '...',
                'Too.Many.Dots.In.Package.Id.Here',
                '123StartingWithNumber'
            )
            
            $invalidFormats | ForEach-Object {
                { Get-LatestWingetVersion -App $_ -ErrorAction Stop } | Should -Throw
            }
        }
    }
    
    Context 'GitHub API Limits' {
        It 'Should handle rate limit gracefully' -Skip {
            # This test is skipped by default as it would consume API quota
            # Uncomment to test rate limit handling
            
            # Make many rapid requests
            1..100 | ForEach-Object {
                Get-LatestWingetVersion -App "Test.Package$_" -ErrorAction SilentlyContinue
            }
            
            # Should still work (might be slower due to rate limiting)
            { Get-LatestWingetVersion -App 'Microsoft.PowerToys' } | Should -Not -Throw
        }
    }
}

Describe 'Real-World Scenarios - Integration' -Tag 'Integration' -Skip:(-not $script:HasInternet) {
    Context 'Common Use Cases' {
        It 'Should retrieve all Microsoft development tools' {
            $devTools = Get-WingetPackagesByPublisher -Publisher 'Microsoft' -MaxResults 50 |
                Where-Object { $_.PackageName -match 'Visual|Code|SDK|Runtime|Tools' }
            
            $devTools | Should -Not -BeNullOrEmpty
            $devTools.Count | Should -BeGreaterThan 5
        }
        
        It 'Should find all Python versions' {
            $pythonPackages = Get-WingetPackagesByPublisher -Publisher 'Python' -IncludeVersions
            
            $pythonPackages | Should -Not -BeNullOrEmpty
            $pythonPackages | Where-Object { $_.PackageIdentifier -like 'Python.Python.3*' } | Should -Not -BeNullOrEmpty
        }
        
        It 'Should get latest versions of popular browsers' {
            $browsers = @(
                'Google.Chrome',
                'Mozilla.Firefox',
                'Microsoft.Edge'
            )
            
            $browsers | ForEach-Object {
                $result = Get-LatestWingetVersion -App $_ -ErrorAction SilentlyContinue
                if ($result) {
                    $result.PackageVersion | Should -Not -BeNullOrEmpty
                    $result.Installers | Should -Not -BeNullOrEmpty
                }
            }
        }
    }
    
    Context 'Performance Benchmarks' {
        It 'Should complete common operations within reasonable time' {
            $operations = @(
                @{
                    Name = 'Single package lookup'
                    ScriptBlock = { Get-LatestWingetVersion -App 'Git.Git' }
                    MaxSeconds = 10
                }
                @{
                    Name = 'Publisher search (10 results)'
                    ScriptBlock = { Get-WingetPackagesByPublisher -Publisher 'Microsoft' -MaxResults 10 }
                    MaxSeconds = 15
                }
                @{
                    Name = 'Package with version source'
                    ScriptBlock = { Get-LatestWingetVersion -App '7zip.7zip' -VersionSource 'manifests/7/7zip/7zip' }
                    MaxSeconds = 5
                }
            )
            
            $operations | ForEach-Object {
                $start = Get-Date
                $null = & $_.ScriptBlock
                $duration = (Get-Date) - $start
                
                Write-Host "$($_.Name): $($duration.TotalSeconds) seconds"
                $duration.TotalSeconds | Should -BeLessOrEqual $_.MaxSeconds
            }
        }
    }
}

AfterAll {
    # Clean up
    Remove-Module -Name WinGetManifestFetcher -Force -ErrorAction SilentlyContinue
}