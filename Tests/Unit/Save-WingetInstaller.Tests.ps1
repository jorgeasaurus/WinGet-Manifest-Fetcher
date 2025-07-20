#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    # Load test helper to properly import the module
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'TestHelper.ps1')
    
    # Disable caching for tests
    InModuleScope WinGetManifestFetcher {
        $script:CacheEnabled = $false
    }
    
    # Mock functions
    Mock -ModuleName WinGetManifestFetcher Get-LatestWingetVersion {
        return [PSCustomObject]@{
            PackageIdentifier = '7zip.7zip'
            PackageName = '7-Zip'
            PackageVersion = '23.01'
            Publisher = '7-Zip'
            Installers = @(
                [PSCustomObject]@{
                    Architecture = 'x64'
                    InstallerType = 'exe'
                    InstallerUrl = 'https://www.7-zip.org/a/7z2301-x64.exe'
                    InstallerSha256 = 'A7803233EEDB6A4B59B3024CCF9292A6FFFB94507DC998AA67C5B745D197A5DC'
                },
                [PSCustomObject]@{
                    Architecture = 'x86'
                    InstallerType = 'exe'
                    InstallerUrl = 'https://www.7-zip.org/a/7z2301.exe'
                    InstallerSha256 = '87C09C4B9E76B4F3C8EE1A95AE96DBDE45DFE968BB6759F91F6F2F0E12345678'
                },
                [PSCustomObject]@{
                    Architecture = 'arm64'
                    InstallerType = 'exe'
                    InstallerUrl = 'https://www.7-zip.org/a/7z2301-arm64.exe'
                    InstallerSha256 = 'FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00'
                }
            )
        }
    }
    
    Mock -ModuleName WinGetManifestFetcher Test-Path {
        param($Path)
        if ($Path -like "*\Downloads" -or $Path -like "*/Downloads") {
            return $true
        }
        if ($Path -like "*.exe") {
            return $false
        }
        return $true
    }
    
    Mock -ModuleName WinGetManifestFetcher New-Item {}
    Mock -ModuleName WinGetManifestFetcher Resolve-Path {
        param($Path)
        return [PSCustomObject]@{ Path = [System.IO.Path]::GetFullPath($Path) }
    }
    
    # Mock download functions based on platform
    if (Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Mock -ModuleName WinGetManifestFetcher Start-BitsTransfer {}
    }
    Mock -ModuleName WinGetManifestFetcher New-Object {
        param($TypeName)
        if ($TypeName -eq 'System.Net.WebClient') {
            $mockWebClient = [PSCustomObject]@{}
            Add-Member -InputObject $mockWebClient -MemberType ScriptMethod -Name 'DownloadFile' -Value {}
            return $mockWebClient
        }
    }
    
    Mock -ModuleName WinGetManifestFetcher Get-FileHash {
        return [PSCustomObject]@{
            Hash = 'A7803233EEDB6A4B59B3024CCF9292A6FFFB94507DC998AA67C5B745D197A5DC'
        }
    }
    Mock -ModuleName WinGetManifestFetcher Remove-Item {}
    Mock -ModuleName WinGetManifestFetcher Get-Item {
        param($Path)
        $mockFile = [PSCustomObject]@{
            Name = [System.IO.Path]::GetFileName($Path)
            FullName = $Path
            Length = 12345678
            LastWriteTime = Get-Date
        }
        Add-Member -InputObject $mockFile -MemberType ScriptMethod -Name 'Add-Member' -Value {
            param($MemberType, $Name, $Value, [switch]$PassThru)
            Add-Member -InputObject $this -MemberType $MemberType -Name $Name -Value $Value -Force
            if ($PassThru) { return $this }
        }
        return $mockFile
    }
    Mock -ModuleName WinGetManifestFetcher Write-Host {}
    Mock -ModuleName WinGetManifestFetcher Write-Warning {}
}

Describe 'Save-WingetInstaller' {
    Context 'Parameter Validation' {
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
        
        It 'Validates Architecture parameter' {
            $cmd = Get-Command Save-WingetInstaller
            $validateSet = $cmd.Parameters['Architecture'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'x86'
            $validateSet.ValidValues | Should -Contain 'arm64'
            $validateSet.ValidValues | Should -Contain 'arm'
            $validateSet.ValidValues | Should -Contain 'neutral'
        }
        
        It 'Supports WhatIf' {
            $cmd = Get-Command Save-WingetInstaller
            $cmd.Parameters.ContainsKey('WhatIf') | Should -Be $true
        }
    }
    
    Context 'Basic Functionality' {
        BeforeEach {
            Mock -ModuleName WinGetManifestFetcher Test-Path {
                param($Path)
                if ($Path -like "*.exe") {
                    return $false
                }
                return $true
            } -Verifiable
        }
        
        It 'Downloads installer to specified path' {
            Save-WingetInstaller -App '7zip.7zip' -Path './Downloads'
            
            Should -Invoke -CommandName Get-LatestWingetVersion -ModuleName WinGetManifestFetcher -Times 1
            if (Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue) {
                Should -Invoke -CommandName Start-BitsTransfer -ModuleName WinGetManifestFetcher -Times 1
            } else {
                Should -Invoke -CommandName New-Object -ModuleName WinGetManifestFetcher -Times 1 -ParameterFilter {
                    $TypeName -eq 'System.Net.WebClient'
                }
            }
        }
        
        It 'Creates directory if it does not exist' {
            Mock -ModuleName WinGetManifestFetcher Test-Path {
                param($Path)
                if ($Path -eq './NewFolder' -or $Path -like '*/NewFolder') {
                    return $false
                }
                if ($Path -like "*.exe") {
                    return $false
                }
                return $true
            }
            
            Mock -ModuleName WinGetManifestFetcher Resolve-Path {
                param($Path)
                return [PSCustomObject]@{ Path = './NewFolder' }
            }
            
            Save-WingetInstaller -App '7zip.7zip' -Path './NewFolder'
            
            Should -Invoke -CommandName New-Item -ModuleName WinGetManifestFetcher -Times 1 -ParameterFilter {
                $ItemType -eq 'Directory' -and $Path -eq './NewFolder'
            }
        }
        
        It 'Returns file info with PassThru' {
            $result = Save-WingetInstaller -App '7zip.7zip' -PassThru
            
            $result | Should -Not -BeNullOrEmpty
            $result.PackageId | Should -Be '7zip.7zip'
            $result.PackageVersion | Should -Be '23.01'
            $result.Architecture | Should -Be 'x64'
            $result.InstallerType | Should -Be 'exe'
            $result.HashVerified | Should -Be $true
        }
    }
    
    Context 'Architecture Selection' {
        It 'Downloads x64 by default' {
            Save-WingetInstaller -App '7zip.7zip'
            
            if (Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue) {
                Should -Invoke -CommandName Start-BitsTransfer -ModuleName WinGetManifestFetcher -Times 1 -ParameterFilter {
                    $Source -like '*7z2301-x64.exe'
                }
            } else {
                Should -Invoke -CommandName New-Object -ModuleName WinGetManifestFetcher -Times 1
            }
        }
        
        It 'Downloads specified architecture' {
            # Mock Get-FileHash to return the correct hash for x86
            Mock -ModuleName WinGetManifestFetcher Get-FileHash {
                return [PSCustomObject]@{
                    Hash = '87C09C4B9E76B4F3C8EE1A95AE96DBDE45DFE968BB6759F91F6F2F0E12345678'
                }
            }
            
            Save-WingetInstaller -App '7zip.7zip' -Architecture 'x86'
            
            if (Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue) {
                Should -Invoke -CommandName Start-BitsTransfer -ModuleName WinGetManifestFetcher -Times 1 -ParameterFilter {
                    $Source -like '*7z2301.exe'
                }
            } else {
                Should -Invoke -CommandName New-Object -ModuleName WinGetManifestFetcher -Times 1
            }
        }
        
        It 'Errors when architecture not available' {
            Mock -ModuleName WinGetManifestFetcher Get-LatestWingetVersion {
                return [PSCustomObject]@{
                    PackageIdentifier = 'Test.Package'
                    Installers = @(
                        [PSCustomObject]@{
                            Architecture = 'x64'
                            InstallerUrl = 'https://example.com/test.exe'
                        }
                    )
                }
            }
            
            { Save-WingetInstaller -App 'Test.Package' -Architecture 'arm64' -ErrorAction Stop } | Should -Throw "*No installer found for architecture 'arm64'*"
        }
    }
    
    Context 'Installer Type Filtering' {
        BeforeEach {
            Mock -ModuleName WinGetManifestFetcher Get-LatestWingetVersion {
                return [PSCustomObject]@{
                    PackageIdentifier = 'Test.Package'
                    PackageName = 'Test Package'
                    PackageVersion = '1.0.0'
                    Installers = @(
                        [PSCustomObject]@{
                            Architecture = 'x64'
                            InstallerType = 'msi'
                            InstallerUrl = 'https://example.com/test.msi'
                            InstallerSha256 = 'AAAA'
                        },
                        [PSCustomObject]@{
                            Architecture = 'x64'
                            InstallerType = 'exe'
                            InstallerUrl = 'https://example.com/test.exe'
                            InstallerSha256 = 'BBBB'
                        }
                    )
                }
            }
        }
        
        It 'Downloads specified installer type' {
            Mock -ModuleName WinGetManifestFetcher Test-Path {
                param($Path)
                if ($Path -like "*.msi") {
                    return $false
                }
                return $true
            }
            
            Mock -ModuleName WinGetManifestFetcher Get-FileHash {
                return [PSCustomObject]@{
                    Hash = 'AAAA'
                }
            }
            
            Save-WingetInstaller -App 'Test.Package' -InstallerType 'msi'
            
            if (Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue) {
                Should -Invoke -CommandName Start-BitsTransfer -ModuleName WinGetManifestFetcher -Times 1 -ParameterFilter {
                    $Source -like '*.msi'
                }
            } else {
                Should -Invoke -CommandName New-Object -ModuleName WinGetManifestFetcher -Times 1
            }
        }
        
        It 'Errors when installer type not available' {
            { Save-WingetInstaller -App 'Test.Package' -InstallerType 'zip' -ErrorAction Stop } | Should -Throw "*No installer found for type 'zip'*"
        }
    }
    
    Context 'Hash Validation' {
        It 'Validates hash by default' {
            Save-WingetInstaller -App '7zip.7zip'
            
            Should -Invoke -CommandName Get-FileHash -ModuleName WinGetManifestFetcher -Times 1
        }
        
        It 'Skips hash validation when requested' {
            Save-WingetInstaller -App '7zip.7zip' -SkipHashValidation
            
            Should -Invoke -CommandName Get-FileHash -ModuleName WinGetManifestFetcher -Times 0
            Should -Invoke -CommandName Write-Warning -ModuleName WinGetManifestFetcher -Times 1 -ParameterFilter {
                $Message -like '*Hash validation skipped*'
            }
        }
        
        It 'Removes file on hash mismatch' {
            # Temporarily override the Get-FileHash mock for this test only
            Mock -ModuleName WinGetManifestFetcher Get-FileHash {
                return [PSCustomObject]@{
                    Hash = 'WRONGHASH'
                }
            } -Verifiable
            
            Mock -ModuleName WinGetManifestFetcher Test-Path {
                param($Path)
                if ($Path -like "*.exe") {
                    return $false  # File doesn't exist before download
                }
                return $true
            }
            
            Mock -ModuleName WinGetManifestFetcher Write-Error {}
            
            Save-WingetInstaller -App '7zip.7zip' -ErrorAction SilentlyContinue
            
            Should -Invoke -CommandName Write-Error -ModuleName WinGetManifestFetcher -Times 3 -ParameterFilter {
                $Message -like "*Hash verification failed*" -or 
                $Message -like "Expected:*" -or 
                $Message -like "Actual:*"
            }
            Should -Invoke -CommandName Remove-Item -ModuleName WinGetManifestFetcher -Times 1
        }
        
        It 'Warns when no hash in manifest' {
            Mock -ModuleName WinGetManifestFetcher Get-LatestWingetVersion {
                return [PSCustomObject]@{
                    PackageIdentifier = 'Test.Package'
                    Installers = @(
                        [PSCustomObject]@{
                            Architecture = 'x64'
                            InstallerType = 'exe'
                            InstallerUrl = 'https://example.com/test.exe'
                            InstallerSha256 = $null
                        }
                    )
                }
            }
            
            Save-WingetInstaller -App 'Test.Package'
            
            Should -Invoke -CommandName Write-Warning -ModuleName WinGetManifestFetcher -Times 1 -ParameterFilter {
                $Message -like '*No hash available in manifest*'
            }
        }
    }
    
    Context 'Error Handling' {
        It 'Handles package not found' {
            Mock -ModuleName WinGetManifestFetcher Get-LatestWingetVersion {
                return $null
            }
            
            { Save-WingetInstaller -App 'NonExistent.Package' -ErrorAction Stop } | Should -Throw "*Package 'NonExistent.Package' not found*"
        }
        
        It 'Handles no installers in package' {
            Mock -ModuleName WinGetManifestFetcher Get-LatestWingetVersion {
                return [PSCustomObject]@{
                    PackageIdentifier = 'Test.Package'
                    Installers = @()
                }
            }
            
            { Save-WingetInstaller -App 'Test.Package' -ErrorAction Stop } | Should -Throw "*No installers found for package*"
        }
        
        It 'Handles download failure' {
            if (Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue) {
                Mock -ModuleName WinGetManifestFetcher Start-BitsTransfer { throw "Network error" }
            } else {
                Mock -ModuleName WinGetManifestFetcher New-Object {
                    param($TypeName)
                    if ($TypeName -eq 'System.Net.WebClient') {
                        throw "Network error"
                    }
                }
            }
            
            { Save-WingetInstaller -App '7zip.7zip' -ErrorAction Stop } | Should -Throw "*Failed to download installer*"
        }
        
        It 'Does not overwrite existing file without Force' {
            Mock -ModuleName WinGetManifestFetcher Test-Path {
                param($Path)
                if ($Path -like "*.exe") {
                    return $true
                }
                return $true
            }
            
            { Save-WingetInstaller -App '7zip.7zip' -ErrorAction Stop } | Should -Throw "*File already exists*"
        }
    }
    
    Context 'WhatIf Support' {
        It 'Does not download when using WhatIf' {
            Save-WingetInstaller -App '7zip.7zip' -WhatIf
            
            if (Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue) {
                Should -Invoke -CommandName Start-BitsTransfer -ModuleName WinGetManifestFetcher -Times 0
            }
            Should -Invoke -CommandName Get-FileHash -ModuleName WinGetManifestFetcher -Times 0
        }
    }
    
    Context 'WebClient Fallback' {
        BeforeEach {
            Mock -ModuleName WinGetManifestFetcher Get-Command {
                param($Name)
                if ($Name -eq 'Start-BitsTransfer') {
                    return $null
                }
                return $true
            }
            
            Mock -ModuleName WinGetManifestFetcher New-Object {
                param($TypeName)
                if ($TypeName -eq 'System.Net.WebClient') {
                    $mockWebClient = [PSCustomObject]@{}
                    Add-Member -InputObject $mockWebClient -MemberType ScriptMethod -Name 'DownloadFile' -Value {}
                    return $mockWebClient
                }
            }
        }
        
        It 'Uses WebClient when BITS is not available' {
            Save-WingetInstaller -App '7zip.7zip'
            
            Should -Invoke -CommandName New-Object -ModuleName WinGetManifestFetcher -Times 1 -ParameterFilter {
                $TypeName -eq 'System.Net.WebClient'
            }
        }
    }
}

AfterAll {
    Remove-Module -Name WinGetManifestFetcher -Force -ErrorAction SilentlyContinue
}