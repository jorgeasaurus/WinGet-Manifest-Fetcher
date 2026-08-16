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
    
}

Describe 'Get-LatestWingetVersion - Parameters' {
    It 'Requires a non-empty App value' {
        $command = Get-Command Get-LatestWingetVersion
        $command.Parameters.App.Attributes.Mandatory | Should -BeTrue
        { Get-LatestWingetVersion -App $null } | Should -Throw
        { Get-LatestWingetVersion -App '' } | Should -Throw
    }
}

Describe 'Get-LatestWingetVersion - Edge Cases' {
    BeforeEach {
        Mock -CommandName Get-CacheItem -MockWith { $null } -ModuleName WinGetManifestFetcher
        Mock -CommandName Set-CacheItem -ModuleName WinGetManifestFetcher
        Mock -CommandName Write-Verbose -ModuleName WinGetManifestFetcher
        Mock -CommandName Write-Warning -ModuleName WinGetManifestFetcher
        Mock -CommandName Get-WingetPackageVersionEntry -MockWith {
            param($Path)
            & (Get-Module WinGetManifestFetcher) {
                param($RequestedPath)
                $content = Get-GitHubContent -OwnerName microsoft -RepositoryName winget-pkgs -Path $RequestedPath
                @($content.Entries)
            } $Path
        } -ModuleName WinGetManifestFetcher
    }

    Context 'Special Characters in Package Names' {
        It 'Should query GitHub contents through the native REST boundary' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                param($Uri)

                if ($Uri -eq 'https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/n/Notepad%2B%2B/Notepad%2B%2B') {
                    return @([PSCustomObject]@{ name = '8.6.2'; type = 'dir' })
                }
                if ($Uri -eq 'https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/n/Notepad%2B%2B/Notepad%2B%2B/8.6.2') {
                    return @([PSCustomObject]@{
                        name = 'Notepad++.Notepad++.installer.yaml'
                        type = 'file'
                        download_url = 'https://mock/installer.yaml'
                    })
                }
                if ($Uri -eq 'https://mock/installer.yaml') {
                    return 'installer manifest'
                }
                throw "Unexpected REST URI: $Uri"
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{
                    PackageIdentifier = 'Notepad++.Notepad++'
                    PackageVersion = '8.6.2'
                    Installers = @(@{ Architecture = 'x64' })
                }
            } -ModuleName WinGetManifestFetcher

            $result = Get-LatestWingetVersion -App 'Notepad++.Notepad++' -VersionSource 'manifests/n/Notepad++/Notepad++'

            $result.PackageIdentifier | Should -Be 'Notepad++.Notepad++'
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName WinGetManifestFetcher -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/n/Notepad%2B%2B/Notepad%2B%2B'
            }
        }
        
        It 'Should handle package names with special characters' {
            $specialNames = @(
                'Notepad++.Notepad++',
                'JetBrains.IntelliJIDEA.Ultimate.EAP',
                'Microsoft.DotNet.SDK.8',
                'Python.Python.3.12'
            )
            
            Mock -CommandName Get-WingetPackageVersionEntry -MockWith {
                @([PSCustomObject]@{ name = '1.0.0'; type = 'dir'; sha = 'version-sha' })
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Get-GitHubContent -MockWith {
                @{ Entries = @(
                    @{ name = 'Test.Package.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                ) }
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
                if ($Path -like '*/8.6.2') {
                    return @{
                        entries = @(
                            @{ name = 'Notepad++.Notepad++.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                        )
                    }
                }
                return @{ entries = @(
                    @{ name = '8.6.2'; type = 'dir' }
                    @{ name = '8.6.1'; type = 'dir' }
                ) }
            } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{ PackageIdentifier = 'Notepad++.Notepad++'; PackageVersion = '8.6.2'; Installers = @(@{ Architecture = 'x64' }) }
            } -ModuleName WinGetManifestFetcher
            
            $result = Get-LatestWingetVersion -App 'Notepad++.Notepad++' -VersionSource 'manifests/n/Notepad++/Notepad++'
            $result | Should -Not -BeNullOrEmpty
        }
    }
    
    Context 'Version Sorting Edge Cases' {
        It 'Should correctly sort semantic versions' {
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                # Return manifest files for version-specific paths
                if ($Path -like '*/[0-9]*') {
                    return @{
                        entries = @(
                            @{ name = 'Test.Package.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                        )
                    }
                }
                return @{
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
            
            # 2.0.0-beta is filtered by ignoreFolders (contains 'Beta'); 1.10.0 is the highest remaining
            $result.PackageVersion | Should -Be '1.10.0'
        }
        
        It 'Should handle non-standard version formats' {
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                if ($Path -like '*/2024.1') {
                    return @{ entries = @(
                        @{ name = 'Test.Package.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                    ) }
                }

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

        It 'Should sort versions with more than four numeric components numerically' {
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                if ($Path -like '*/10.0.0.0.1') {
                    return @{ entries = @(
                        @{ name = 'Test.Package.installer.yaml'; type = 'file'; download_url = 'https://mock/10.0.0.0.1/installer.yaml' }
                    ) }
                }
                if ($Path -like '*/9.0.0.0.1') {
                    return @{ entries = @(
                        @{ name = 'Test.Package.installer.yaml'; type = 'file'; download_url = 'https://mock/9.0.0.0.1/installer.yaml' }
                    ) }
                }

                return @{ entries = @(
                    @{ name = '9.0.0.0.1'; type = 'dir' }
                    @{ name = '10.0.0.0.1'; type = 'dir' }
                ) }
            } -ModuleName WinGetManifestFetcher

            Mock -CommandName Invoke-RestMethod -MockWith {
                param($Uri)
                $Uri
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                param($Yaml)
                $version = if ($Yaml -like '*10.0.0.0.1*') { '10.0.0.0.1' } else { '9.0.0.0.1' }
                @{ PackageIdentifier = 'Test.Package'; PackageVersion = $version; Installers = @() }
            } -ModuleName WinGetManifestFetcher

            $result = Get-LatestWingetVersion -App 'Test.Package' -VersionSource 'manifests/t/Test/Package'

            $result.PackageVersion | Should -Be '10.0.0.0.1'
        }
    }

    Context 'Package Name Search' {
        BeforeEach {
            $script:originalGitHubToken = $env:GITHUB_TOKEN
            $env:GITHUB_TOKEN = 'test-token'
        }

        AfterEach {
            if ($null -eq $script:originalGitHubToken) {
                Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
            } else {
                $env:GITHUB_TOKEN = $script:originalGitHubToken
            }
        }

        It 'Should find a package when its publisher is in a different manifest shard' {
            Mock -CommandName Invoke-WingetGitHubRequest -MockWith {
                @{
                    total_count = 1
                    items       = @(
                        @{ path = 'manifests/m/Microsoft/PowerToys/0.94.1/Microsoft.PowerToys.installer.yaml' }
                    )
                }
            } -ModuleName WinGetManifestFetcher

            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                if ($Path -eq 'manifests/m/Microsoft/PowerToys') {
                    return @{ entries = @(@{ name = '0.94.1'; type = 'dir' }) }
                }

                return @{
                    entries = @(
                        @{ name = 'Microsoft.PowerToys.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                    )
                }
            } -ModuleName WinGetManifestFetcher

            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{
                    PackageIdentifier = 'Microsoft.PowerToys'
                    PackageVersion    = '0.94.1'
                    Installers        = @()
                }
            } -ModuleName WinGetManifestFetcher

            $result = Get-LatestWingetVersion -App 'PowerToys'

            $result.PackageIdentifier | Should -Be 'Microsoft.PowerToys'
            Should -Invoke -CommandName Invoke-WingetGitHubRequest -ModuleName WinGetManifestFetcher -Times 1 -Exactly
        }

        It 'Should hydrate broad-search candidates lazily until one succeeds' {
            Mock -CommandName Invoke-WingetGitHubRequest -MockWith {
                @{
                    total_count = 3
                    items = @(
                        @{ path = 'manifests/a/Acme/EditorOne/1.0.0/Acme.EditorOne.installer.yaml' }
                        @{ path = 'manifests/a/Acme/EditorTwo/1.0.0/Acme.EditorTwo.installer.yaml' }
                        @{ path = 'manifests/a/Acme/EditorThree/1.0.0/Acme.EditorThree.installer.yaml' }
                    )
                }
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Get-WingetPackageVersionEntry -MockWith {
                @([PSCustomObject]@{ name = '1.0.0'; type = 'dir'; sha = 'version-sha' })
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Get-GitHubContent -MockWith {
                @{ Entries = @(
                    @{ name = 'Acme.EditorOne.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                ) }
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{ PackageIdentifier = 'Acme.EditorOne'; PackageVersion = '1.0.0'; Installers = @() }
            } -ModuleName WinGetManifestFetcher

            $result = Get-LatestWingetVersion -App 'Editor'

            $result.PackageIdentifier | Should -Be 'Acme.EditorOne'
            Should -Invoke -CommandName Invoke-WingetGitHubRequest -ModuleName WinGetManifestFetcher -Times 1 -Exactly
            Should -Invoke -CommandName Get-WingetPackageVersionEntry -ModuleName WinGetManifestFetcher -Times 1 -Exactly
        }

        It 'Should derive the package from a locale manifest display-name search result' {
            Mock -CommandName Invoke-WingetGitHubRequest -MockWith {
                @{
                    total_count = 1
                    items       = @(
                        @{ path = 'manifests/m/Microsoft/VisualStudioCode/1.98.0/Microsoft.VisualStudioCode.locale.en-US.yaml' }
                    )
                }
            } -ModuleName WinGetManifestFetcher

            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                if ($Path -eq 'manifests/m/Microsoft/VisualStudioCode') {
                    return @{ entries = @(@{ name = '1.98.0'; type = 'dir' }) }
                }

                return @{ entries = @(
                    @{ name = 'Microsoft.VisualStudioCode.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                ) }
            } -ModuleName WinGetManifestFetcher

            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{
                    PackageIdentifier = 'Microsoft.VisualStudioCode'
                    PackageVersion    = '1.98.0'
                    Installers        = @()
                }
            } -ModuleName WinGetManifestFetcher

            $result = Get-LatestWingetVersion -App 'Visual Studio Code'

            $result.PackageIdentifier | Should -Be 'Microsoft.VisualStudioCode'
            Should -Invoke -CommandName Get-GitHubContent -ModuleName WinGetManifestFetcher -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'manifests/m/Microsoft/VisualStudioCode'
            }
        }
        It 'Should require authentication for broad package-name search' {
            Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
            Mock -CommandName Invoke-WingetGitHubRequest -ModuleName WinGetManifestFetcher

            { Get-LatestWingetVersion -App 'Power Toys' -ErrorAction Stop } |
                Should -Throw '*requires GITHUB_TOKEN*'
            Should -Invoke -CommandName Invoke-WingetGitHubRequest -ModuleName WinGetManifestFetcher -Times 0 -Exactly
            Should -Invoke -CommandName Set-CacheItem -ModuleName WinGetManifestFetcher -Times 0 -Exactly
        }

        It 'Should resolve an exact identifier without authentication' {
            Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
            Mock -CommandName Invoke-WingetGitHubRequest -ModuleName WinGetManifestFetcher
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                if ($Path -eq 'manifests/m/Microsoft/PowerToys') {
                    return @{ Entries = @(@{ name = '0.94.1'; type = 'dir' }) }
                }
                return @{ Entries = @(
                    @{ name = 'Microsoft.PowerToys.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                ) }
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{ PackageIdentifier = 'Microsoft.PowerToys'; PackageVersion = '0.94.1'; Installers = @() }
            } -ModuleName WinGetManifestFetcher

            $result = Get-LatestWingetVersion -App 'Microsoft.PowerToys'

            $result.PackageIdentifier | Should -Be 'Microsoft.PowerToys'
            Should -Invoke -CommandName Invoke-WingetGitHubRequest -ModuleName WinGetManifestFetcher -Times 0 -Exactly
            Should -Invoke -CommandName Get-WingetPackageVersionEntry -ModuleName WinGetManifestFetcher -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'manifests/m/Microsoft/PowerToys' -and $PackageIdentifier -eq 'Microsoft.PowerToys'
            }
            Should -Invoke -CommandName Get-GitHubContent -ModuleName WinGetManifestFetcher -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'manifests/m/Microsoft/PowerToys'
            }
        }

        It 'Should report PackageNotFound when exact fallback finds no authenticated candidates' {
            Mock -CommandName Get-WingetPackageVersionEntry -MockWith {
                throw [System.Management.Automation.ItemNotFoundException]::new('Exact package path was not found')
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Search-WingetPackage -ModuleName WinGetManifestFetcher

            $failure = try {
                Get-LatestWingetVersion -App 'Missing.Package' -ErrorAction Stop
            } catch {
                $_
            }

            $failure | Should -Not -BeNullOrEmpty
            $failure.Exception | Should -BeOfType [System.Management.Automation.ItemNotFoundException]
            $failure.Exception.InnerException.Message | Should -Be 'Exact package path was not found'
            $failure.FullyQualifiedErrorId | Should -BeLike 'PackageNotFound*'
            Should -Invoke -CommandName Search-WingetPackage -ModuleName WinGetManifestFetcher -Times 1 -Exactly
            Should -Invoke -CommandName Set-CacheItem -ModuleName WinGetManifestFetcher -Times 0 -Exactly
        }

        It 'Should report PackageNotFound for an unauthenticated exact miss' {
            Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
            Mock -CommandName Get-WingetPackageVersionEntry -MockWith {
                throw [System.Management.Automation.ItemNotFoundException]::new('Exact package path was not found')
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Search-WingetPackage -ModuleName WinGetManifestFetcher

            $failure = try {
                Get-LatestWingetVersion -App 'Missing.Package' -ErrorAction Stop
            } catch {
                $_
            }

            $failure | Should -Not -BeNullOrEmpty
            $failure.Exception | Should -BeOfType [System.Management.Automation.ItemNotFoundException]
            $failure.Exception.InnerException.Message | Should -Be 'Exact package path was not found'
            $failure.FullyQualifiedErrorId | Should -BeLike 'PackageNotFound*'
            Should -Invoke -CommandName Search-WingetPackage -ModuleName WinGetManifestFetcher -Times 0 -Exactly
            Should -Invoke -CommandName Set-CacheItem -ModuleName WinGetManifestFetcher -Times 0 -Exactly
        }

        It 'Should fall back from a dotted display name to authenticated search' {
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                if ($Path -eq 'manifests/n/Node/js') {
                    throw [System.Management.Automation.ItemNotFoundException]::new('GitHub path not found')
                }
                if ($Path -eq 'manifests/o/OpenJS/NodeJS') {
                    return @{ Entries = @(@{ name = '22.0.0'; type = 'dir' }) }
                }
                return @{ Entries = @(
                    @{ name = 'OpenJS.NodeJS.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                ) }
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Invoke-WingetGitHubRequest -MockWith {
                @{
                    total_count = 1
                    items = @(
                        @{ path = 'manifests/o/OpenJS/NodeJS/22.0.0/OpenJS.NodeJS.installer.yaml' }
                    )
                }
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{ PackageIdentifier = 'OpenJS.NodeJS'; PackageVersion = '22.0.0'; Installers = @() }
            } -ModuleName WinGetManifestFetcher

            $result = Get-LatestWingetVersion -App 'Node.js'

            $result.PackageIdentifier | Should -Be 'OpenJS.NodeJS'
            Should -Invoke -CommandName Get-WingetPackageVersionEntry -ModuleName WinGetManifestFetcher -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'manifests/n/Node/js' -and $PackageIdentifier -eq 'Node.js'
            }
            Should -Invoke -CommandName Get-WingetPackageVersionEntry -ModuleName WinGetManifestFetcher -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'manifests/o/OpenJS/NodeJS' -and $PackageIdentifier -eq 'OpenJS.NodeJS'
            }
            Should -Invoke -CommandName Get-GitHubContent -ModuleName WinGetManifestFetcher -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'manifests/n/Node/js'
            }
            Should -Invoke -CommandName Invoke-WingetGitHubRequest -ModuleName WinGetManifestFetcher -Times 1 -Exactly
        }

        It 'Should not broad-search after an exact package hydrates successfully' {
            Mock -CommandName Get-WingetPackageVersionEntry -MockWith {
                @([PSCustomObject]@{ name = '1.0.0'; type = 'dir'; sha = 'version-sha' })
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Get-GitHubContent -MockWith {
                $exception = [System.Management.Automation.ItemNotFoundException]::new('Selected version contents were not found')
                throw [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'SelectedVersionNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    'manifests/t/Test/Package/1.0.0'
                )
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Search-WingetPackage -ModuleName WinGetManifestFetcher

            $caughtError = $null
            try {
                Get-LatestWingetVersion -App 'Test.Package' -ErrorAction Stop
            } catch {
                $caughtError = $_
            }

            $caughtError.Exception | Should -BeOfType [System.Management.Automation.ItemNotFoundException]
            $caughtError.FullyQualifiedErrorId | Should -Match '^SelectedVersionNotFound'
            Should -Invoke -CommandName Get-WingetPackageVersionEntry -ModuleName WinGetManifestFetcher -Times 1 -Exactly
            Should -Invoke -CommandName Search-WingetPackage -ModuleName WinGetManifestFetcher -Times 0 -Exactly
            Should -Invoke -CommandName Set-CacheItem -ModuleName WinGetManifestFetcher -Times 0 -Exactly
        }

        It 'Should fall back when an exact identifier guess is an organizational prefix' {
            Mock -CommandName Get-WingetPackageVersionEntry -MockWith {
                param($Path)
                if ($Path -eq 'manifests/p/Python/Python') {
                    throw [System.IO.InvalidDataException]::new('Not a package leaf')
                }
                @([PSCustomObject]@{ path = '3.12.0'; name = '3.12.0'; type = 'dir'; sha = 'version-sha' })
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Invoke-WingetGitHubRequest -MockWith {
                @{
                    total_count = 1
                    items = @(
                        @{ path = 'manifests/p/Python/Python/3/12/3.12.0/Python.Python.3.12.installer.yaml' }
                    )
                }
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Get-GitHubContent -MockWith {
                @{ Entries = @(
                    @{ name = 'Python.Python.3.12.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                ) }
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{ PackageIdentifier = 'Python.Python.3.12'; PackageVersion = '3.12.0'; Installers = @() }
            } -ModuleName WinGetManifestFetcher

            $result = Get-LatestWingetVersion -App 'Python.Python'

            $result.PackageIdentifier | Should -Be 'Python.Python.3.12'
            Should -Invoke -CommandName Get-WingetPackageVersionEntry -ModuleName WinGetManifestFetcher -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'manifests/p/Python/Python'
            }
            Should -Invoke -CommandName Invoke-WingetGitHubRequest -ModuleName WinGetManifestFetcher -Times 1 -Exactly
        }

        It 'Should reject incomplete code-search responses without caching' {
            Mock -CommandName Invoke-WingetGitHubRequest -MockWith {
                @{
                    incomplete_results = $true
                    total_count = 1
                    items = @(
                        @{ path = 'manifests/m/Microsoft/PowerToys/0.94.1/Microsoft.PowerToys.installer.yaml' }
                    )
                }
            } -ModuleName WinGetManifestFetcher

            { Get-LatestWingetVersion -App 'PowerToys' -ErrorAction Stop } | Should -Throw '*incomplete*'
            Should -Invoke -CommandName Set-CacheItem -ModuleName WinGetManifestFetcher -Times 0 -Exactly
        }

        It 'Should reject code-search totals above the API result cap without caching' {
            Mock -CommandName Invoke-WingetGitHubRequest -MockWith {
                @{
                    incomplete_results = $false
                    total_count = 1001
                    items = @(
                        @{ path = 'manifests/m/Microsoft/PowerToys/0.94.1/Microsoft.PowerToys.installer.yaml' }
                    )
                }
            } -ModuleName WinGetManifestFetcher

            { Get-LatestWingetVersion -App 'PowerToys' -ErrorAction Stop } | Should -Throw '*1,000*'
            Should -Invoke -CommandName Set-CacheItem -ModuleName WinGetManifestFetcher -Times 0 -Exactly
        }

        It 'Should propagate non-authentication code-search failures without caching' {
            Mock -CommandName Invoke-WingetGitHubRequest -MockWith {
                throw 'Response status code does not indicate success: 503 (Service Unavailable).'
            } -ModuleName WinGetManifestFetcher

            { Get-LatestWingetVersion -App 'PowerToys' -ErrorAction Stop } | Should -Throw '*503*'
            Should -Invoke -CommandName Set-CacheItem -ModuleName WinGetManifestFetcher -Times 0 -Exactly
        }

        It 'Should propagate later-page failures without caching partial search results' {
            Mock -CommandName Invoke-WingetGitHubRequest -MockWith {
                param($UriFragment)
                if ($UriFragment -match '&page=1$') {
                    $items = @(1..100 | ForEach-Object {
                        @{ path = 'manifests/m/Microsoft/PowerToys/0.94.1/Microsoft.PowerToys.installer.yaml' }
                    })
                    return @{ total_count = 101; items = $items }
                }

                throw 'Response status code does not indicate success: 401 (Unauthorized).'
            } -ModuleName WinGetManifestFetcher

            { Get-LatestWingetVersion -App 'PowerToys' -ErrorAction Stop } | Should -Throw '*401*'
            Should -Invoke -CommandName Invoke-WingetGitHubRequest -ModuleName WinGetManifestFetcher -Times 2 -Exactly
            Should -Invoke -CommandName Set-CacheItem -ModuleName WinGetManifestFetcher -Times 0 -Exactly
        }
    }
    
    Context 'Manifest Structure Variations' {
        It 'Should handle manifests with minimal information' {
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                if ($Path -like '*/1.0.0') {
                    return @{
                        entries = @(
                            @{ name = 'Minimal.Package.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                        )
                    }
                }
                return @{ entries = @(
                    @{ name = '1.0.0'; type = 'dir' }
                    @{ name = '0.9.0'; type = 'dir' }
                ) }
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
                param($Path)
                if ($Path -like '*/1.0.0') {
                    return @{
                        entries = @(
                            @{ name = 'Test.Package.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                        )
                    }
                }
                return @{ entries = @(
                    @{ name = '1.0.0'; type = 'dir' }
                    @{ name = '0.9.0'; type = 'dir' }
                ) }
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
        It 'Should surface the underlying error when every package candidate fails' {
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                if ($Path -like '*/1.0.0') {
                    return @{ entries = @(
                        @{ name = 'Test.Package.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                    ) }
                }

                return @{ entries = @(@{ name = '1.0.0'; type = 'dir' }) }
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Invoke-RestMethod -MockWith {
                $exception = [System.Net.WebException]::new('Manifest API returned 502 Bad Gateway')
                throw [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'ManifestDownloadFailed',
                    [System.Management.Automation.ErrorCategory]::ConnectionError,
                    'https://mock/installer.yaml'
                )
            } -ModuleName WinGetManifestFetcher

            $caughtError = $null
            try {
                Get-LatestWingetVersion -App 'Test.Package' -VersionSource 'manifests/t/Test/Package' -ErrorAction Stop
            } catch {
                $caughtError = $_
            }

            $caughtError.Exception.Message | Should -Be 'Manifest API returned 502 Bad Gateway'
            $caughtError.FullyQualifiedErrorId | Should -Match '^ManifestDownloadFailed'
            Should -Invoke -CommandName Set-CacheItem -ModuleName WinGetManifestFetcher -Times 0 -Exactly
        }

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
            
            $failure = try {
                Get-LatestWingetVersion -App 'Empty.Package' -VersionSource 'manifests/e/Empty/Package' -ErrorAction Stop
            } catch {
                $_
            }

            $failure | Should -Not -BeNullOrEmpty
            $failure.FullyQualifiedErrorId | Should -BeLike 'PackageNotFound*'
        }
    }
}

Describe 'Package candidate resolution' {
    It 'Should resolve an ordinary exact package with one Contents request and one leaf-proof tree request' {
        Mock -CommandName Get-GitHubContent -MockWith {
            [PSCustomObject]@{
                Entries = @(
                    [PSCustomObject]@{ name = '1.0.0'; type = 'dir'; sha = 'version-1' }
                    [PSCustomObject]@{ name = '2.0.0'; type = 'dir'; sha = 'version-2' }
                )
            }
        } -ModuleName WinGetManifestFetcher
        Mock -CommandName Get-WingetGitHubTree -MockWith {
            [PSCustomObject]@{
                Entries = @([PSCustomObject]@{
                    path = 'Test.Package.installer.yaml'
                    type = 'blob'
                    sha = 'manifest-sha'
                })
            }
        } -ModuleName WinGetManifestFetcher
        Mock -CommandName Get-WingetGitHubTreeSha -ModuleName WinGetManifestFetcher

        InModuleScope WinGetManifestFetcher {
            $entries = @(Get-WingetPackageVersionEntry -Path 'manifests/t/Test/Package' -PackageIdentifier 'Test.Package')
            $entries.name | Should -Be @('1.0.0', '2.0.0')
        }

        Should -Invoke -CommandName Get-GitHubContent -ModuleName WinGetManifestFetcher -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'manifests/t/Test/Package'
        }
        Should -Invoke -CommandName Get-WingetGitHubTree -ModuleName WinGetManifestFetcher -Times 1 -Exactly -ParameterFilter {
            $TreeReference -eq 'version-1'
        }
        Should -Invoke -CommandName Get-WingetGitHubTreeSha -ModuleName WinGetManifestFetcher -Times 0 -Exactly
    }

    It 'Should hydrate more than 1000 immediate versions through uncapped Git trees' {
        Mock -CommandName Get-GitHubContent -MockWith {
            [PSCustomObject]@{
                Entries = @(1..1000 | ForEach-Object {
                    [PSCustomObject]@{ name = [string]$_; type = 'dir'; sha = "content-version-$_" }
                })
            }
        } -ModuleName WinGetManifestFetcher
        Mock -CommandName Get-WingetGitHubTreeSha -MockWith { 'package-sha' } -ModuleName WinGetManifestFetcher
        Mock -CommandName Get-WingetGitHubTree -MockWith {
            param($TreeReference)
            if ($TreeReference -eq 'package-sha') {
                return [PSCustomObject]@{
                    Entries = @(1..1001 | ForEach-Object {
                        [PSCustomObject]@{ path = [string]$_; type = 'tree'; sha = "version-$_" }
                    })
                }
            }

            [PSCustomObject]@{
                Entries = @([PSCustomObject]@{
                    path = 'Test.Package.installer.yaml'
                    type = 'blob'
                    sha = 'manifest-sha'
                })
            }
        } -ModuleName WinGetManifestFetcher

        InModuleScope WinGetManifestFetcher {
            $entries = @(Get-WingetPackageVersionEntry -Path 'manifests/t/Test/Package' -PackageIdentifier 'Test.Package')
            $entries | Should -HaveCount 1001
        }

        Should -Invoke -CommandName Get-WingetGitHubTree -ModuleName WinGetManifestFetcher -Times 2 -Exactly
        Should -Invoke -CommandName Get-GitHubContent -ModuleName WinGetManifestFetcher -Times 1 -Exactly
    }

    It 'Should reject a child package manifest as proof of an organizational prefix' {
        Mock -CommandName Get-WingetGitHubTreeSha -MockWith { 'prefix-sha' } -ModuleName WinGetManifestFetcher
        Mock -CommandName Get-WingetGitHubTree -MockWith {
            param($TreeReference)
            if ($TreeReference -eq 'prefix-sha') {
                return [PSCustomObject]@{
                    Entries = @([PSCustomObject]@{ path = '2'; type = 'tree'; sha = 'child-sha' })
                }
            }

            [PSCustomObject]@{
                Entries = @([PSCustomObject]@{ path = 'Python.Python.2.installer.yaml'; type = 'blob'; sha = 'manifest-sha' })
            }
        } -ModuleName WinGetManifestFetcher

        InModuleScope WinGetManifestFetcher {
            { Get-WingetPackageVersionEntry -Path 'manifests/p/Python/Python' -PackageIdentifier 'Python.Python' } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException])
        }
    }

    It 'Should return lightweight identity candidates' {
        Mock -CommandName Get-WingetPackageVersionEntry -ModuleName WinGetManifestFetcher

        InModuleScope WinGetManifestFetcher {
            $candidate = Resolve-WingetPackage -App 'Test.Package' -VersionSource 'manifests/t/Test/Package'

            $candidate.PackageId | Should -Be 'Test.Package'
            $candidate.Path | Should -Be 'manifests/t/Test/Package'
            $candidate.PSObject.Properties.Name | Should -Not -Contain 'VersionEntries'
        }

        Should -Invoke -CommandName Get-WingetPackageVersionEntry -ModuleName WinGetManifestFetcher -Times 0 -Exactly
    }
}

Describe 'Get-LatestWingetVersion - Performance' {
    BeforeEach {
        Mock -CommandName Get-WingetPackageVersionEntry -MockWith {
            param($Path)
            & (Get-Module WinGetManifestFetcher) {
                param($RequestedPath)
                $content = Get-GitHubContent -OwnerName microsoft -RepositoryName winget-pkgs -Path $RequestedPath
                @($content.Entries)
            } $Path
        } -ModuleName WinGetManifestFetcher
    }

    Context 'Caching Behavior' {
        It 'Should use distinct cache keys for application names that sanitize identically' {
            $keys = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName Get-CacheItem -MockWith {
                param($Key)
                $keys.Add($Key)
                [PSCustomObject]@{ PackageIdentifier = 'Cached.Package'; PackageVersion = '1.0.0'; Installers = @() }
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Set-CacheItem -ModuleName WinGetManifestFetcher

            $null = Get-LatestWingetVersion -App 'Foo/Bar'
            $null = Get-LatestWingetVersion -App 'Foo_Bar'

            $keys | Should -HaveCount 2
            $keys[0] | Should -Not -Be $keys[1]
        }

        It 'Should use distinct cache keys for version sources that sanitize identically' {
            $keys = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName Get-CacheItem -MockWith {
                param($Key)
                $keys.Add($Key)
                [PSCustomObject]@{ PackageIdentifier = 'Cached.Package'; PackageVersion = '1.0.0'; Installers = @() }
            } -ModuleName WinGetManifestFetcher
            Mock -CommandName Set-CacheItem -ModuleName WinGetManifestFetcher

            $null = Get-LatestWingetVersion -App 'Test.Package' -VersionSource 'manifests/f/Foo/Bar'
            $null = Get-LatestWingetVersion -App 'Test.Package' -VersionSource 'manifests/f/Foo_Bar'

            $keys | Should -HaveCount 2
            $keys[0] | Should -Not -Be $keys[1]
        }

        It 'Should not make redundant API calls' {
            Mock -CommandName Get-CacheItem -MockWith { $null } -ModuleName WinGetManifestFetcher
            Mock -CommandName Set-CacheItem -ModuleName WinGetManifestFetcher
            Mock -CommandName Write-Verbose -ModuleName WinGetManifestFetcher
            Mock -CommandName Write-Warning -ModuleName WinGetManifestFetcher
            
            Mock -CommandName Get-GitHubContent -MockWith {
                param($Path)
                if ($Path -like '*/1.0.0') {
                    return @{
                        entries = @(
                            @{ name = 'Test.Package.installer.yaml'; type = 'file'; download_url = 'https://mock/installer.yaml' }
                        )
                    }
                }
                return @{ entries = @(
                    @{ name = '1.0.0'; type = 'dir' }
                    @{ name = '0.9.0'; type = 'dir' }
                ) }
            } -ModuleName WinGetManifestFetcher
            
            Mock -CommandName Invoke-RestMethod -MockWith { '' } -ModuleName WinGetManifestFetcher
            Mock -CommandName ConvertFrom-Yaml -MockWith {
                @{ PackageIdentifier = 'Test.Package'; PackageVersion = '1.0.0'; Installers = @(@{ Architecture = 'x64' }) }
            } -ModuleName WinGetManifestFetcher
            
            # First call
            $null = Get-LatestWingetVersion -App 'Test.Package' -VersionSource 'manifests/t/Test/Package'
            
            # Verify API calls were made
            Should -Invoke -CommandName Get-GitHubContent -ModuleName WinGetManifestFetcher -Times 2 -Exactly
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName WinGetManifestFetcher -Times 1 -Exactly
        }
    }
}

AfterAll {
    Remove-Module -Name WinGetManifestFetcher -Force -ErrorAction SilentlyContinue
}
