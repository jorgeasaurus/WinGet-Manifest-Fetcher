#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Quick test script to verify Get-LatestWingetVersion works with popular apps.

.DESCRIPTION
    This script tests Get-LatestWingetVersion against a selection of popular
    applications to ensure version retrieval and sorting works correctly.
#>

# Import the module
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'src', 'WinGetManifestFetcher.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

# Verify module is loaded
if (-not (Get-Module -Name WinGetManifestFetcher)) {
    Write-Error "Failed to load WinGetManifestFetcher module"
    exit 1
}

# Check if GitHub authentication is configured
if (-not $env:GITHUB_TOKEN) {
    Write-Warning "No GITHUB_TOKEN environment variable found. API rate limits may apply."
    Write-Host "To avoid rate limits, set a GitHub token: `$env:GITHUB_TOKEN = 'your-token-here'" -ForegroundColor Yellow
}

# Define test apps
$testApps = @(
    @{ Id = 'Spotify.Spotify'; Name = 'Spotify' },
    @{ Id = 'Microsoft.VisualStudioCode'; Name = 'VS Code' },
    @{ Id = '7zip.7zip'; Name = '7-Zip' },
    @{ Id = 'Mozilla.Firefox'; Name = 'Firefox' },
    @{ Id = 'Google.Chrome'; Name = 'Chrome' },
    @{ Id = 'VideoLAN.VLC'; Name = 'VLC' },
    @{ Id = 'Git.Git'; Name = 'Git' },
    @{ Id = 'Python.Python.3.12'; Name = 'Python 3.12' }
)

Write-Host "Testing Get-LatestWingetVersion with popular applications..." -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Gray

$results = @()
$errors = @()

foreach ($app in $testApps) {
    Write-Host "`nTesting $($app.Name) ($($app.Id))..." -ForegroundColor Yellow -NoNewline
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Get-LatestWingetVersion -App $app.Id -ErrorAction Stop
        $stopwatch.Stop()
        
        Write-Host " SUCCESS" -ForegroundColor Green
        Write-Host "  Version: $($result.PackageVersion)" -ForegroundColor White
        Write-Host "  Publisher: $($result.Publisher)" -ForegroundColor Gray
        Write-Host "  Installers: $($result.Installers.Count) found" -ForegroundColor Gray
        
        if ($result.Installers -and $result.Installers.Count -gt 0) {
            $architectures = $result.Installers.Architecture | Sort-Object -Unique
            Write-Host "  Architectures: $($architectures -join ', ')" -ForegroundColor Gray
            
            # Show first installer URL as example
            $firstInstaller = $result.Installers[0]
            $urlDisplay = if ($firstInstaller.InstallerUrl.Length -gt 60) {
                $firstInstaller.InstallerUrl.Substring(0, 57) + "..."
            } else {
                $firstInstaller.InstallerUrl
            }
            Write-Host "  Example URL: $urlDisplay" -ForegroundColor DarkGray
        }
        
        Write-Host "  Time: $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
        
        $results += [PSCustomObject]@{
            App = $app.Name
            Id = $app.Id
            Version = $result.PackageVersion
            Status = 'Success'
            Time = $stopwatch.ElapsedMilliseconds
        }
        
        # Special checks for known version formats
        switch ($app.Id) {
            'Spotify.Spotify' {
                if ($result.PackageVersion -match '^1\.1\.') {
                    Write-Warning "  Spotify might be returning an old version. Expected 1.2.x, got $($result.PackageVersion)"
                }
            }
            'Python.Python.3.12' {
                if ($result.PackageVersion -notmatch '^3\.12\.') {
                    Write-Warning "  Python version doesn't match expected pattern. Expected 3.12.x, got $($result.PackageVersion)"
                }
            }
        }
        
    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor DarkRed
        
        $errors += [PSCustomObject]@{
            App = $app.Name
            Id = $app.Id
            Error = $_.Exception.Message
        }
        
        $results += [PSCustomObject]@{
            App = $app.Name
            Id = $app.Id
            Version = 'N/A'
            Status = 'Failed'
            Time = 0
        }
    }
}

# Summary
Write-Host "`n" + ("=" * 70) -ForegroundColor Gray
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Gray

$successCount = ($results | Where-Object { $_.Status -eq 'Success' }).Count
$failCount = ($results | Where-Object { $_.Status -eq 'Failed' }).Count

Write-Host "`nTotal Apps Tested: $($results.Count)" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })

# Display results table
Write-Host "`nResults Table:" -ForegroundColor Cyan
$results | Format-Table -AutoSize

if ($errors.Count -gt 0) {
    Write-Host "`nErrors:" -ForegroundColor Red
    $errors | Format-Table -AutoSize -Wrap
}

# Performance stats
$avgTime = ($results | Where-Object { $_.Status -eq 'Success' } | Measure-Object -Property Time -Average).Average
if ($avgTime) {
    Write-Host "`nAverage response time: $([math]::Round($avgTime, 2))ms" -ForegroundColor Gray
}

# Cache info
Write-Host "`nCache Information:" -ForegroundColor Cyan
Get-WingetManifestCacheInfo | Format-List