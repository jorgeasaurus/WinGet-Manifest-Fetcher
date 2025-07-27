#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs tests for Get-LatestWingetVersion against popular applications.

.DESCRIPTION
    This script executes Pester tests to verify that Get-LatestWingetVersion
    works correctly with popular applications from the WinGet repository.

.PARAMETER TestName
    Specific test name to run. If not specified, runs all tests.

.PARAMETER OutputFormat
    Pester output format. Default is 'Detailed'.

.EXAMPLE
    .\Run-PopularAppsTests.ps1
    Runs all popular app tests.

.EXAMPLE
    .\Run-PopularAppsTests.ps1 -TestName "*Spotify*"
    Runs only tests related to Spotify.
#>
[CmdletBinding()]
param(
    [string]$TestName,
    [ValidateSet('None', 'Default', 'Passed', 'Failed', 'Skipped', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed'
)

# Ensure we're in the correct directory
$TestPath = Join-Path -Path $PSScriptRoot -ChildPath 'Get-LatestWingetVersion.PopularApps.Tests.ps1'

if (-not (Test-Path $TestPath)) {
    Write-Error "Test file not found: $TestPath"
    exit 1
}

# Check if Pester is installed
if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -ge 5 })) {
    Write-Warning "Pester 5.0+ is not installed. Installing..."
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck
}

# Import Pester
Import-Module Pester -MinimumVersion 5.0.0

# Configure Pester
$config = New-PesterConfiguration
$config.Run.Path = $TestPath
$config.Output.Verbosity = $OutputFormat
$config.Run.PassThru = $true

if ($TestName) {
    $config.Filter.FullName = $TestName
}

# Add code coverage if running all tests
if (-not $TestName) {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'src', 'Public', 'Get-LatestWingetVersion.ps1'
    if (Test-Path $modulePath) {
        $config.CodeCoverage.Enabled = $true
        $config.CodeCoverage.Path = $modulePath
    }
}

Write-Host "Running Get-LatestWingetVersion tests for popular applications..." -ForegroundColor Cyan
Write-Host "This may take a few minutes as it queries the GitHub API for each app." -ForegroundColor Yellow

# Run the tests
$results = Invoke-Pester -Configuration $config

# Display summary
Write-Host "`nTest Summary:" -ForegroundColor Cyan
Write-Host "  Total Tests: $($results.TotalCount)" -ForegroundColor White
Write-Host "  Passed: $($results.PassedCount)" -ForegroundColor Green
Write-Host "  Failed: $($results.FailedCount)" -ForegroundColor $(if ($results.FailedCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Skipped: $($results.SkippedCount)" -ForegroundColor Yellow

if ($results.FailedCount -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    foreach ($test in $results.Failed) {
        Write-Host "  - $($test.ExpandedPath)" -ForegroundColor Red
        Write-Host "    Error: $($test.ErrorRecord[0].Exception.Message)" -ForegroundColor DarkRed
    }
    exit 1
}

exit 0