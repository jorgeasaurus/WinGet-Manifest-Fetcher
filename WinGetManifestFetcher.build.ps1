# Build script for WinGetManifestFetcher module

# Synopsis: Install required dependencies
task InstallDependencies {
    $requiredModules = @(
        @{Name = 'PowerShellForGitHub'; MinVersion = '0.16.0' },
        @{Name = 'powershell-yaml'; MinVersion = '0.4.0' },
        @{Name = 'Pester'; MinVersion = '5.0.0' },
        @{Name = 'PSScriptAnalyzer'; MinVersion = '1.19.0' }
    )
    
    foreach ($module in $requiredModules) {
        $installed = Get-Module -ListAvailable -Name $module.Name | 
                     Where-Object { $_.Version -ge $module.MinVersion }
        
        if (-not $installed) {
            Write-Build Yellow "Installing $($module.Name) $($module.MinVersion)..."
            Install-Module -Name $module.Name -MinimumVersion $module.MinVersion -Force -Scope CurrentUser
        }
    }
}

# Synopsis: Build the PowerShell module
task Build InstallDependencies, {
    $moduleName = 'WinGetManifestFetcher'
    $srcPath = Join-Path $BuildRoot 'src'
    $outPath = Join-Path $BuildRoot 'output'
    $modulePath = Join-Path $outPath $moduleName
    
    # Clean output directory
    if (Test-Path $outPath) {
        Remove-Item $outPath -Recurse -Force
    }
    
    # Create output directory
    $null = New-Item -ItemType Directory -Path $modulePath -Force
    
    # Copy manifest
    Copy-Item -Path (Join-Path $srcPath "$moduleName.psd1") -Destination $modulePath
    
    # Build module file
    $moduleDefinition = Get-Content -Path (Join-Path $srcPath "$moduleName.psm1") -Raw
    
    # Add private functions
    $privatePath = Join-Path $srcPath 'Private'
    if (Test-Path $privatePath) {
        Get-ChildItem -Path $privatePath -Filter '*.ps1' | ForEach-Object {
            $moduleDefinition += "`n`n# Private Function: $($_.BaseName)`n"
            $moduleDefinition += Get-Content -Path $_.FullName -Raw
        }
    }
    
    # Add public functions
    $publicPath = Join-Path $srcPath 'Public'
    if (Test-Path $publicPath) {
        Get-ChildItem -Path $publicPath -Filter '*.ps1' | ForEach-Object {
            $moduleDefinition += "`n`n# Public Function: $($_.BaseName)`n"
            $moduleDefinition += Get-Content -Path $_.FullName -Raw
        }
    }
    
    # Add Export-ModuleMember at the end
    $moduleDefinition += "`n`n# Export public functions`n"
    $moduleDefinition += "Export-ModuleMember -Function @(`n"
    $moduleDefinition += "    'Get-LatestWingetVersion',`n"
    $moduleDefinition += "    'Get-WingetPackagesByPublisher',`n"
    $moduleDefinition += "    'Save-WingetInstaller',`n"
    $moduleDefinition += "    'Clear-WingetManifestCache',`n"
    $moduleDefinition += "    'Get-WingetManifestCacheInfo',`n"
    $moduleDefinition += "    'Set-WingetManifestCacheEnabled'`n"
    $moduleDefinition += ")"
    
    # Write combined module file
    Set-Content -Path (Join-Path $modulePath "$moduleName.psm1") -Value $moduleDefinition -Encoding UTF8
    
    Write-Build Green "Module built successfully at: $modulePath"
}

# Synopsis: Run Pester tests
task Test InstallDependencies, {
    $testPath = Join-Path $BuildRoot 'Tests'
    $testFile = Join-Path $testPath 'WinGetManifestFetcher.Mock.Tests.ps1'
    
    if (Test-Path $testFile) {
        $results = Invoke-Pester -Path $testFile -PassThru
        
        if ($results.FailedCount -gt 0) {
            throw "Tests failed: $($results.FailedCount) tests failed"
        }
    }
}

# Synopsis: Run PSScriptAnalyzer
task Analyze InstallDependencies, {
    $srcPath = Join-Path $BuildRoot 'src'
    $settingsPath = Join-Path $BuildRoot 'PSScriptAnalyzerSettings.psd1'
    
    $results = Invoke-ScriptAnalyzer -Path $srcPath -Recurse -Settings $settingsPath
    
    if ($results) {
        $results | Format-Table -AutoSize
        throw "PSScriptAnalyzer found $($results.Count) issues"
    }
}

# Synopsis: Clean build artifacts
task Clean {
    Remove-Item -Path (Join-Path $BuildRoot 'output') -Recurse -Force -ErrorAction SilentlyContinue
}

# Synopsis: Publish to PowerShell Gallery
task Publish Build, Test, Analyze, {
    $outputPath = Join-Path $BuildRoot 'output' 'WinGetManifestFetcher'
    
    if (-not $env:PSGALLERY_API_KEY) {
        throw "PSGALLERY_API_KEY environment variable is not set"
    }
    
    Publish-Module -Path $outputPath -NuGetApiKey $env:PSGALLERY_API_KEY
}

# Default task
task . Build