#Requires -Version 5.1
#Requires -Module Pester

BeforeAll {
    # Import the module
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\WinGetManifestFetcher.psm1" | Resolve-Path
    Import-Module $modulePath -Force
    
    # Store original cache settings
    $script:originalCacheEnabled = $script:CacheEnabled
    $script:originalCacheDirectory = $script:CacheDirectory
    $script:originalCacheExpirationMinutes = $script:CacheExpirationMinutes
    
    # Set up test cache directory
    $script:testCacheDirectory = Join-Path -Path $TestDrive -ChildPath "TestCache"
    New-Item -ItemType Directory -Path $script:testCacheDirectory -Force | Out-Null
    
    # Override cache directory for tests
    $script:CacheDirectory = $script:testCacheDirectory
    $script:CacheEnabled = $true
}

AfterAll {
    # Restore original cache settings
    $script:CacheEnabled = $script:originalCacheEnabled
    $script:CacheDirectory = $script:originalCacheDirectory
    $script:CacheExpirationMinutes = $script:originalCacheExpirationMinutes
    
    # Clean up test cache directory
    if (Test-Path -Path $script:testCacheDirectory) {
        Remove-Item -Path $script:testCacheDirectory -Recurse -Force
    }
}

Describe "Get-CacheItem" {
    BeforeEach {
        # Clear test cache
        Get-ChildItem -Path $script:testCacheDirectory -Filter "*.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    
    Context "When cache is disabled" {
        It "Should return null when cache is disabled" {
            $script:CacheEnabled = $false
            $result = Get-CacheItem -Key "test_key"
            $result | Should -BeNullOrEmpty
            $script:CacheEnabled = $true
        }
    }
    
    Context "When cache item does not exist" {
        It "Should return null for non-existent cache key" {
            $result = Get-CacheItem -Key "non_existent_key"
            $result | Should -BeNullOrEmpty
        }
    }
    
    Context "When cache item exists" {
        It "Should return cached data for valid unexpired item" {
            # Create test cache item
            $testData = @{ Name = "Test"; Value = 123 }
            $cacheEntry = @{
                Version = $script:CacheVersion
                Timestamp = (Get-Date).ToString('o')
                Data = $testData
            }
            $cacheFile = Join-Path -Path $script:testCacheDirectory -ChildPath "test_key.json"
            $cacheEntry | ConvertTo-Json -Depth 10 | Out-File -FilePath $cacheFile -Force
            
            # Retrieve cache item
            $result = Get-CacheItem -Key "test_key"
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be "Test"
            $result.Value | Should -Be 123
        }
        
        It "Should return null for expired cache item" {
            # Create expired cache item
            $testData = @{ Name = "Test"; Value = 123 }
            $cacheEntry = @{
                Version = $script:CacheVersion
                Timestamp = (Get-Date).AddMinutes(-120).ToString('o')  # 2 hours old
                Data = $testData
            }
            $cacheFile = Join-Path -Path $script:testCacheDirectory -ChildPath "expired_key.json"
            $cacheEntry | ConvertTo-Json -Depth 10 | Out-File -FilePath $cacheFile -Force
            
            # Retrieve cache item (should be null due to expiration)
            $result = Get-CacheItem -Key "expired_key" -ExpirationMinutes 60
            $result | Should -BeNullOrEmpty
            
            # File should be deleted
            Test-Path -Path $cacheFile | Should -BeFalse
        }
        
        It "Should return null for cache item with wrong version" {
            # Create cache item with wrong version
            $testData = @{ Name = "Test"; Value = 123 }
            $cacheEntry = @{
                Version = "0.1"  # Wrong version
                Timestamp = (Get-Date).ToString('o')
                Data = $testData
            }
            $cacheFile = Join-Path -Path $script:testCacheDirectory -ChildPath "wrong_version_key.json"
            $cacheEntry | ConvertTo-Json -Depth 10 | Out-File -FilePath $cacheFile -Force
            
            # Retrieve cache item
            $result = Get-CacheItem -Key "wrong_version_key"
            $result | Should -BeNullOrEmpty
            
            # File should be deleted
            Test-Path -Path $cacheFile | Should -BeFalse
        }
    }
}

Describe "Set-CacheItem" {
    BeforeEach {
        # Clear test cache
        Get-ChildItem -Path $script:testCacheDirectory -Filter "*.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    
    Context "When cache is disabled" {
        It "Should not create cache file when cache is disabled" {
            $script:CacheEnabled = $false
            $testData = @{ Name = "Test"; Value = 123 }
            Set-CacheItem -Key "test_key" -Data $testData
            
            $cacheFile = Join-Path -Path $script:testCacheDirectory -ChildPath "test_key.json"
            Test-Path -Path $cacheFile | Should -BeFalse
            
            $script:CacheEnabled = $true
        }
    }
    
    Context "When cache is enabled" {
        It "Should create cache file with correct structure" {
            $testData = @{ Name = "Test"; Value = 123 }
            Set-CacheItem -Key "test_key" -Data $testData
            
            $cacheFile = Join-Path -Path $script:testCacheDirectory -ChildPath "test_key.json"
            Test-Path -Path $cacheFile | Should -BeTrue
            
            $content = Get-Content -Path $cacheFile -Raw | ConvertFrom-Json
            $content.Version | Should -Be $script:CacheVersion
            $content.Timestamp | Should -Not -BeNullOrEmpty
            $content.Data.Name | Should -Be "Test"
            $content.Data.Value | Should -Be 123
        }
        
        It "Should overwrite existing cache file" {
            # Create initial cache item
            $testData1 = @{ Name = "Test1"; Value = 123 }
            Set-CacheItem -Key "test_key" -Data $testData1
            
            # Overwrite with new data
            $testData2 = @{ Name = "Test2"; Value = 456 }
            Set-CacheItem -Key "test_key" -Data $testData2
            
            # Verify new data
            $cacheFile = Join-Path -Path $script:testCacheDirectory -ChildPath "test_key.json"
            $content = Get-Content -Path $cacheFile -Raw | ConvertFrom-Json
            $content.Data.Name | Should -Be "Test2"
            $content.Data.Value | Should -Be 456
        }
    }
}

Describe "Clear-WingetManifestCache" {
    BeforeEach {
        # Create some test cache files
        1..5 | ForEach-Object {
            $testData = @{ Item = $_; Value = "Test$_" }
            Set-CacheItem -Key "test_key_$_" -Data $testData
        }
    }
    
    Context "When cache has items" {
        It "Should clear all cache files with -Force" {
            # Verify files exist
            $files = Get-ChildItem -Path $script:testCacheDirectory -Filter "*.json"
            $files.Count | Should -Be 5
            
            # Clear cache
            Clear-WingetManifestCache -Force
            
            # Verify files are gone
            $files = Get-ChildItem -Path $script:testCacheDirectory -Filter "*.json" -ErrorAction SilentlyContinue
            $files.Count | Should -Be 0
        }
    }
    
    Context "When cache is empty" {
        It "Should handle empty cache gracefully" {
            # Clear cache first
            Clear-WingetManifestCache -Force
            
            # Try to clear again
            { Clear-WingetManifestCache -Force } | Should -Not -Throw
        }
    }
}

Describe "Get-WingetManifestCacheInfo" {
    BeforeEach {
        # Clear test cache
        Get-ChildItem -Path $script:testCacheDirectory -Filter "*.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    
    Context "When cache is empty" {
        It "Should return info object with zero counts" {
            $info = Get-WingetManifestCacheInfo
            
            $info.Enabled | Should -Be $true
            $info.Directory | Should -Be $script:testCacheDirectory
            $info.ItemCount | Should -Be 0
            $info.TotalSizeMB | Should -Be 0
            $info.OldestItemAge | Should -BeNullOrEmpty
            $info.NewestItemAge | Should -BeNullOrEmpty
            $info.ExpirationMinutes | Should -Be $script:CacheExpirationMinutes
        }
    }
    
    Context "When cache has items" {
        It "Should return correct cache statistics" {
            # Create cache items with different ages
            $testData1 = @{ Name = "Test1"; Value = "Large" * 1000 }
            Set-CacheItem -Key "test_key_1" -Data $testData1
            
            Start-Sleep -Seconds 2
            
            $testData2 = @{ Name = "Test2"; Value = "Small" }
            Set-CacheItem -Key "test_key_2" -Data $testData2
            
            $info = Get-WingetManifestCacheInfo
            
            $info.ItemCount | Should -Be 2
            $info.TotalSizeMB | Should -BeGreaterThan 0
            $info.OldestItemAge | Should -Not -BeNullOrEmpty
            $info.NewestItemAge | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Set-WingetManifestCacheEnabled" {
    It "Should disable cache when set to false" {
        Set-WingetManifestCacheEnabled -Enabled $false
        $script:CacheEnabled | Should -BeFalse
    }
    
    It "Should enable cache when set to true" {
        Set-WingetManifestCacheEnabled -Enabled $true
        $script:CacheEnabled | Should -BeTrue
    }
    
    It "Should create cache directory when enabling if it doesn't exist" {
        # Remove cache directory
        if (Test-Path -Path $script:testCacheDirectory) {
            Remove-Item -Path $script:testCacheDirectory -Recurse -Force
        }
        
        # Enable cache
        Set-WingetManifestCacheEnabled -Enabled $true
        
        # Directory should be created
        Test-Path -Path $script:testCacheDirectory | Should -BeTrue
    }
}

Describe "Integration: Caching with Get-LatestWingetVersion" -Tag "Integration" {
    BeforeAll {
        # Mock Get-GitHubContent to avoid actual API calls
        Mock Get-GitHubContent {
            # Return mock data based on the path
            if ($Path -like "*manifests/7/7zip/7zip") {
                return @{
                    entries = @(
                        @{ name = "23.01"; type = "dir" }
                    )
                }
            }
            elseif ($Path -like "*manifests/7/7zip/7zip/23.01") {
                return @{
                    entries = @(
                        @{ name = "7zip.7zip.installer.yaml"; download_url = "mock_url" }
                    )
                }
            }
            else {
                throw "Not found"
            }
        }
        
        Mock Invoke-RestMethod {
            # Return mock YAML content
            return @"
PackageIdentifier: 7zip.7zip
PackageVersion: 23.01
Installers:
- Architecture: x64
  InstallerType: msi
  InstallerUrl: https://www.7-zip.org/a/7z2301-x64.msi
  InstallerSha256: MOCKHASH123
"@
        }
        
        Mock ConvertFrom-Yaml {
            return @{
                PackageIdentifier = "7zip.7zip"
                PackageVersion = "23.01"
                Installers = @(
                    @{
                        Architecture = "x64"
                        InstallerType = "msi"
                        InstallerUrl = "https://www.7-zip.org/a/7z2301-x64.msi"
                        InstallerSha256 = "MOCKHASH123"
                    }
                )
            }
        }
    }
    
    BeforeEach {
        # Clear test cache
        Get-ChildItem -Path $script:testCacheDirectory -Filter "*.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    
    It "Should cache results from Get-LatestWingetVersion" {
        # First call should hit the API
        $result1 = Get-LatestWingetVersion -App "7zip.7zip"
        $result1 | Should -Not -BeNullOrEmpty
        
        # Verify cache file was created
        $cacheKey = "package_7zip.7zip"
        $cacheFile = Join-Path -Path $script:testCacheDirectory -ChildPath "$cacheKey.json"
        Test-Path -Path $cacheFile | Should -BeTrue
        
        # Second call should use cache (mock should not be called again)
        $result2 = Get-LatestWingetVersion -App "7zip.7zip"
        $result2 | Should -Not -BeNullOrEmpty
        $result2.PackageIdentifier | Should -Be $result1.PackageIdentifier
    }
}