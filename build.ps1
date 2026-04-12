#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Build script for WinGetManifestFetcher module

.DESCRIPTION
    This script uses PowerShellBuild to build the WinGetManifestFetcher module.
    It supports various tasks like build, test, analyze, and publish.

.PARAMETER Task
    The build task(s) to execute. Common tasks include:
    - Build: Compile the module
    - Test: Run Pester tests
    - Analyze: Run PSScriptAnalyzer
    - Publish: Publish to PowerShell Gallery
    - Clean: Clean build artifacts

.PARAMETER Bootstrap
    If specified, installs required build dependencies.

.EXAMPLE
    ./build.ps1
    Runs the default build task

.EXAMPLE
    ./build.ps1 -Task Test
    Runs the test task

.EXAMPLE
    ./build.ps1 -Task Build, Test, Publish -Bootstrap
    Installs dependencies, then builds, tests, and publishes the module
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Build', 'Test', 'Analyze', 'Publish', 'Clean')]
    [string[]]$Task = 'Build',

    [Parameter()]
    [switch]$Bootstrap
)

# Bootstrap dependencies
if ($Bootstrap) {
    Write-Host "Installing build dependencies..." -ForegroundColor Green
    
    $modules = @{
        'InvokeBuild'      = 'latest'
        'PowerShellBuild'  = 'latest'
        'Pester'           = '5.5.0'
        'PSScriptAnalyzer' = 'latest'
        'platyPS'          = 'latest'
    }
    
    foreach ($module in $modules.GetEnumerator()) {
        if (-not (Get-Module -Name $module.Key -ListAvailable)) {
            Write-Host "Installing $($module.Key)..." -ForegroundColor Yellow
            Install-Module -Name $module.Key -Force -Scope CurrentUser -SkipPublisherCheck
        }
    }
}

# Import InvokeBuild
Import-Module InvokeBuild -ErrorAction Stop

# Execute build tasks
Invoke-Build -Task $Task -File (Join-Path $PSScriptRoot 'WinGetManifestFetcher.build.ps1')