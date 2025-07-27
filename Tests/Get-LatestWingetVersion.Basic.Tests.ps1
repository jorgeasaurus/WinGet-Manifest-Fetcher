BeforeAll {
    # Import the module with explicit path resolution
    $moduleName = 'WinGetManifestFetcher'
    
    # Remove if already loaded
    if (Get-Module -Name $moduleName) {
        Remove-Module -Name $moduleName -Force
    }
    
    # Build the path
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path -Path $moduleRoot -ChildPath 'src' -AdditionalChildPath "$moduleName.psd1"
    
    if (-not (Test-Path $modulePath)) {
        throw "Module not found at: $modulePath"
    }
    
    # Import with verbose output for debugging
    Import-Module $modulePath -Force -ErrorAction Stop -Global
    
    # Verify module loaded
    $loadedModule = Get-Module -Name $moduleName
    if (-not $loadedModule) {
        throw "Module $moduleName failed to load"
    }
    
    Write-Host "Module loaded: $($loadedModule.Name) v$($loadedModule.Version) from $($loadedModule.ModuleBase)" -ForegroundColor Green
}

Describe 'Get-LatestWingetVersion - Basic Tests' -Tag 'Unit' {
    Context 'Module initialization' {
        It 'Should have the module loaded' {
            $module = Get-Module -Name 'WinGetManifestFetcher'
            $module | Should -Not -BeNullOrEmpty
            $module.Name | Should -Be 'WinGetManifestFetcher'
        }
        
        It 'Should export Get-LatestWingetVersion function' {
            $command = Get-Command -Name 'Get-LatestWingetVersion' -ErrorAction SilentlyContinue
            $command | Should -Not -BeNullOrEmpty
            $command.CommandType | Should -Be 'Function'
            $command.Source | Should -Be 'WinGetManifestFetcher'
        }
    }
    
    Context 'Basic functionality' {
        It 'Should retrieve a simple package (7zip)' {
            # This is a basic test that should work even with rate limits
            $result = Get-LatestWingetVersion -App '7zip.7zip' -ErrorAction SilentlyContinue
            
            if ($result) {
                $result.PackageIdentifier | Should -Be '7zip.7zip'
                $result.PackageVersion | Should -Not -BeNullOrEmpty
                $result.PackageVersion | Should -Match '^\d+\.\d+$'  # e.g., 25.00
            } else {
                # If it fails, check if it's due to module initialization
                $error[0].Exception.Message | Should -Not -Match 'empty string'
                Set-ItResult -Skipped -Because "Could not retrieve package - possible API rate limit"
            }
        }
        
        It 'Should handle non-existent package gracefully' {
            { Get-LatestWingetVersion -App 'This.Does.Not.Exist.12345' -ErrorAction Stop } | 
                Should -Throw -ExpectedMessage "*not found*"
        }
    }
    
    Context 'Parameter validation' {
        It 'Should require App parameter' {
            # Get the command metadata to check parameter attributes
            $command = Get-Command -Name 'Get-LatestWingetVersion'
            $appParameter = $command.Parameters['App']
            
            # Verify App parameter is mandatory
            $appParameter | Should -Not -BeNullOrEmpty
            $appParameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | 
                Select-Object -ExpandProperty Mandatory | Should -Be $true
        }
        
        It 'Should not accept empty App parameter' {
            { Get-LatestWingetVersion -App '' -ErrorAction Stop } | 
                Should -Throw -ExpectedMessage "*null or empty*"
        }
    }
}