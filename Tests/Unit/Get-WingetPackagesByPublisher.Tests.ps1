#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests specifically for Get-WingetPackagesByPublisher function
.DESCRIPTION
    Detailed unit tests covering publisher search scenarios and edge cases
#>

BeforeAll {
    # Load test helper to properly import the module
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'TestHelper.ps1')
}

Describe 'Get-WingetPackagesByPublisher - Advanced Scenarios' {
    Context 'Publisher Name Matching' {
        BeforeEach {
            Mock -CommandName Write-Verbose -ModuleName WinGetManifestFetcher
            Mock -CommandName Write-Warning -ModuleName WinGetManifestFetcher
        }
        
        It 'Should prioritize exact matches over partial matches' {
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                
                if ($Path -eq 'manifests/m/Microsoft') {
                    return @{ type = 'dir' }
                }
                elseif ($Path -eq 'manifests/m') {
                    return @{
                        entries = @(
                            @{ name = 'Microsoft'; type = 'dir'; path = 'manifests/m/Microsoft' }
                            @{ name = 'MicrosoftEdge'; type = 'dir'; path = 'manifests/m/MicrosoftEdge' }
                            @{ name = 'Microchip'; type = 'dir'; path = 'manifests/m/Microchip' }
                        )
                    }
                }
                elseif ($Path -eq 'manifests/m/Microsoft') {
                    return @{
                        entries = @(
                            @{ name = 'PowerToys'; type = 'dir'; path = 'manifests/m/Microsoft/PowerToys' }
                            @{ name = 'VisualStudioCode'; type = 'dir'; path = 'manifests/m/Microsoft/VisualStudioCode' }
                        )
                    }
                }
                return @{ entries = @() }
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-WingetPackagesByPublisher -Publisher 'Microsoft'
            
            # Should only return Microsoft packages, not MicrosoftEdge or Microchip
            $result | Should -Not -BeNullOrEmpty
            $result.Publisher | Should -All { $_ -eq 'Microsoft' }
            
            # Verify exact match was used (should call Get-GitHubContent with exact path first)
            Assert-MockCalled -CommandName Get-GitHubContent -Times 1 -Exactly -Scope It -ModuleName WinGetManifestFetcher -ParameterFilter {
                $Path -eq 'manifests/m/Microsoft'
            }
        }
        
        It 'Should handle case-insensitive publisher names' {
            $publisherVariations = @('microsoft', 'MICROSOFT', 'MiCrOsOfT')
            
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                
                # GitHub paths are case-sensitive, but we should handle this
                if ($Path -match 'manifests/m/[Mm]icrosoft$') {
                    return @{
                        entries = @(
                            @{ name = 'PowerToys'; type = 'dir' }
                        )
                    }
                }
                return $null
            } -ModuleName WinGetManifestFetcher
            
            $publisherVariations | ForEach-Object {
                { Get-WingetPackagesByPublisher -Publisher $_ -ErrorAction Stop } | Should -Not -Throw
            }
        }
        
        It 'Should search all letter directories for short publisher names' {
            $mockCallCount = 0
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                
                if ($Path -match '^manifests/[a-z]$') {
                    $script:mockCallCount++
                    return @{
                        entries = @(
                            @{ name = 'ABC'; type = 'dir' }
                            @{ name = 'ABCompany'; type = 'dir' }
                        )
                    }
                }
                return @{ entries = @() }
            } -ModuleName WinGetManifestFetcher
            
            $null = Get-WingetPackagesByPublisher -Publisher 'AB'
            
            # For a 2-letter search, it should check all letter directories
            $script:mockCallCount | Should -BeGreaterThan 20
        }
    }
    
    Context 'Complex Publisher Structures' {
        It 'Should handle publishers with nested organization structures' {
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                
                if ($Path -match 'JetBrains$') {
                    return @{
                        entries = @(
                            @{ name = 'IntelliJIDEA'; type = 'dir' }
                            @{ name = 'IntelliJIDEA.Ultimate'; type = 'dir' }
                            @{ name = 'IntelliJIDEA.Community'; type = 'dir' }
                            @{ name = 'PyCharm'; type = 'dir' }
                            @{ name = 'PyCharm.Professional'; type = 'dir' }
                            @{ name = 'PyCharm.Community'; type = 'dir' }
                        )
                    }
                }
                return @{ entries = @() }
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-WingetPackagesByPublisher -Publisher 'JetBrains'
            
            $result | Should -HaveCount 6
            $result.PackageIdentifier | Should -Contain 'JetBrains.IntelliJIDEA.Ultimate'
            $result.PackageIdentifier | Should -Contain 'JetBrains.PyCharm.Professional'
        }
        
        It 'Should filter out non-directory entries' {
            Mock -CommandName Get-GitHubContent -MockWith {
                @{
                    entries = @(
                        @{ name = 'PowerToys'; type = 'dir' }
                        @{ name = 'README.md'; type = 'file' }
                        @{ name = '.validation'; type = 'dir' }
                        @{ name = 'VisualStudioCode'; type = 'dir' }
                    )
                }
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-WingetPackagesByPublisher -Publisher 'Microsoft'
            
            # Should only include actual package directories
            $result | Should -HaveCount 2
            $result.PackageName | Should -Not -Contain 'README.md'
            $result.PackageName | Should -Not -Contain '.validation'
        }
    }
    
    Context 'Version Information Integration' {
        It 'Should handle version retrieval failures gracefully' {
            Mock -CommandName Get-GitHubContent -MockWith {
                @{
                    entries = @(
                        @{ name = 'Package1'; type = 'dir'; path = 'manifests/t/Test/Package1' }
                        @{ name = 'Package2'; type = 'dir'; path = 'manifests/t/Test/Package2' }
                        @{ name = 'Package3'; type = 'dir'; path = 'manifests/t/Test/Package3' }
                    )
                }
            } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName Get-LatestWingetVersion -MockWith {
                param($App)
                
                if ($App -eq 'Test.Package2') {
                    throw "Failed to get version"
                }
                
                return @{
                    PackageIdentifier = $App
                    PackageVersion = '1.0.0'
                }
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-WingetPackagesByPublisher -Publisher 'Test' -IncludeVersions
            
            # Should still return all packages
            $result | Should -HaveCount 3
            
            # Package1 and Package3 should have versions
            ($result | Where-Object { $_.PackageName -eq 'Package1' }).LatestVersion | Should -Be '1.0.0'
            ($result | Where-Object { $_.PackageName -eq 'Package3' }).LatestVersion | Should -Be '1.0.0'
            
            # Package2 should have null version due to error
            ($result | Where-Object { $_.PackageName -eq 'Package2' }).LatestVersion | Should -BeNullOrEmpty
        }
        
        It 'Should not call Get-LatestWingetVersion when IncludeVersions is false' {
            Mock -CommandName Get-GitHubContent -MockWith {
                @{
                    entries = @(
                        @{ name = 'Package1'; type = 'dir' }
                    )
                }
            } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName Get-LatestWingetVersion -MockWith {
                throw "Should not be called"
            } -ModuleName WinGetManifestFetcher
            
            { Get-WingetPackagesByPublisher -Publisher 'Test' } | Should -Not -Throw
            
            # Verify Get-LatestWingetVersion was not called
            Assert-MockCalled -CommandName Get-LatestWingetVersion -Times 0 -Exactly -Scope It -ModuleName WinGetManifestFetcher
        }
    }
    
    Context 'Performance and Limits' {
        It 'Should stop searching when MaxResults is reached during publisher search' {
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                
                if ($Path -match '^manifests/[a-z]$') {
                    return @{
                        entries = @(
                            @{ name = 'TestPublisher1'; type = 'dir' }
                            @{ name = 'TestPublisher2'; type = 'dir' }
                            @{ name = 'TestPublisher3'; type = 'dir' }
                        )
                    }
                }
                return @{ entries = @() }
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-WingetPackagesByPublisher -Publisher 'Test' -MaxResults 2
            
            # Even though there might be more matching publishers, it should stop at 2
            $result.Publisher | Select-Object -Unique | Should -HaveCount 2
        }
        
        It 'Should stop package enumeration when MaxResults is reached' {
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                
                if ($Path -eq 'manifests/m/Microsoft') {
                    return @{ type = 'dir' }
                }
                elseif ($Path -like '*/Microsoft') {
                    return @{
                        entries = 1..20 | ForEach-Object {
                            @{ name = "Package$_"; type = 'dir' }
                        }
                    }
                }
                return $null
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-WingetPackagesByPublisher -Publisher 'Microsoft' -MaxResults 5
            
            $result | Should -HaveCount 5
        }
    }
    
    Context 'Special Characters and Edge Cases' {
        It 'Should handle publishers with special characters' {
            $specialPublishers = @(
                @{ Name = 'Notepad++'; Expected = 'Notepad%2B%2B' }
                @{ Name = 'C++ Team'; Expected = 'C%2B%2B Team' }
            )
            
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                
                # Verify URL encoding is applied
                if ($Path -match '%2B') {
                    return @{
                        entries = @(
                            @{ name = 'Notepad++'; type = 'dir' }
                        )
                    }
                }
                return $null
            } -ModuleName WinGetManifestFetcher
            
            $specialPublishers | ForEach-Object {
                { Get-WingetPackagesByPublisher -Publisher $_.Name -ErrorAction Stop } | Should -Not -Throw
            }
        }
        
        It 'Should handle empty publisher directories' {
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                
                if ($Path -eq 'manifests/e/EmptyPublisher') {
                    return @{ type = 'dir' }
                }
                elseif ($Path -like '*/EmptyPublisher') {
                    return @{ entries = @() }  # No packages
                }
                return $null
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-WingetPackagesByPublisher -Publisher 'EmptyPublisher'
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-WingetPackagesByPublisher - Output Validation' {
    Context 'Object Structure' {
        It 'Should return consistent object structure for all packages' {
            Mock -CommandName Get-GitHubContent -MockWith {
                @{
                    entries = @(
                        @{ name = 'Package1'; type = 'dir'; path = 'manifests/t/Test/Package1' }
                        @{ name = 'Package2'; type = 'dir'; path = 'manifests/t/Test/Package2' }
                    )
                }
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-WingetPackagesByPublisher -Publisher 'Test'
            
            $result | ForEach-Object {
                $_.PSObject.Properties.Name | Should -Contain 'Publisher'
                $_.PSObject.Properties.Name | Should -Contain 'PackageName'
                $_.PSObject.Properties.Name | Should -Contain 'PackageIdentifier'
                $_.PSObject.Properties.Name | Should -Contain 'ManifestPath'
                $_.PSObject.Properties.Name | Should -Contain 'LatestVersion'
                
                # Types should be consistent
                $_.Publisher | Should -BeOfType [string]
                $_.PackageName | Should -BeOfType [string]
                $_.PackageIdentifier | Should -BeOfType [string]
                $_.ManifestPath | Should -BeOfType [string]
            }
        }
        
        It 'Should construct correct package identifiers' {
            Mock -CommandName Get-GitHubContent -MockWith {
                @{
                    entries = @(
                        @{ name = 'PowerToys'; type = 'dir'; path = 'manifests/m/Microsoft/PowerToys' }
                        @{ name = 'VisualStudioCode'; type = 'dir'; path = 'manifests/m/Microsoft/VisualStudioCode' }
                    )
                }
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-WingetPackagesByPublisher -Publisher 'Microsoft'
            
            $result | ForEach-Object {
                # PackageIdentifier should be Publisher.PackageName
                $_.PackageIdentifier | Should -Be "$($_.Publisher).$($_.PackageName)"
                
                # ManifestPath should match the structure
                $_.ManifestPath | Should -Match "manifests/[a-z]/$($_.Publisher)/$($_.PackageName)"
            }
        }
    }
}

AfterAll {
    Remove-Module -Name WinGetManifestFetcher -Force -ErrorAction SilentlyContinue
}