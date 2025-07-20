# Test Helper for WinGetManifestFetcher Module
# This script loads the module for testing in the PSStucco structure

$ErrorActionPreference = 'Stop'

# Get paths
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ModuleName = 'WinGetManifestFetcher'

# Remove module if already loaded
Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction SilentlyContinue

# Build the module in memory for testing
$ModuleDefinition = @"
#Requires -Version 5.1

<#
.SYNOPSIS
    WinGet Manifest Fetcher - Retrieve installer information from WinGet manifests without WinGet client
.DESCRIPTION
    This module provides functionality to query the microsoft/winget-pkgs repository and retrieve
    installer information from WinGet manifests without requiring the WinGet client to be installed.
#>

# Import required modules
`$ErrorActionPreference = 'Stop'

# Check for required modules and provide helpful error messages
`$requiredModules = @(
    @{Name = 'PowerShellForGitHub'; MinVersion = '0.16.0' },
    @{Name = 'powershell-yaml'; MinVersion = '0.4.0' }
)

foreach (`$module in `$requiredModules) {
    if (-not (Get-Module -ListAvailable -Name `$module.Name | Where-Object { `$_.Version -ge `$module.MinVersion })) {
        throw "Required module '`$(`$module.Name)' version `$(`$module.MinVersion) or higher is not installed. Please run: Install-Module -Name `$(`$module.Name) -MinimumVersion `$(`$module.MinVersion)"
    }
    Import-Module `$module.Name -MinimumVersion `$module.MinVersion -ErrorAction Stop
}

# Module-level variables
`$script:WinGetRepoOwner = 'microsoft'
`$script:WinGetRepoName = 'winget-pkgs'
`$script:ManifestPath = 'manifests'

# Cache configuration
`$script:CacheEnabled = `$true
# Cross-platform cache directory configuration
if (`$IsWindows -or (-not (Test-Path Variable:IsWindows) -and `$env:OS -eq 'Windows_NT')) {
    # Windows
    `$script:CacheDirectory = Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath 'WinGetManifestFetcher' -AdditionalChildPath 'Cache'
} elseif (`$IsMacOS -or (-not (Test-Path Variable:IsMacOS) -and `$env:OS -ne 'Windows_NT' -and (uname) -eq 'Darwin')) {
    # macOS
    `$script:CacheDirectory = Join-Path -Path `$HOME -ChildPath 'Library' -AdditionalChildPath 'Caches', 'WinGetManifestFetcher'
} else {
    # Linux and other Unix-like systems
    `$script:CacheDirectory = Join-Path -Path (`$env:XDG_CACHE_HOME ?? (Join-Path -Path `$HOME -ChildPath '.cache')) -ChildPath 'WinGetManifestFetcher'
}
`$script:CacheExpirationMinutes = 60  # Default cache expiration time
`$script:CacheVersion = '1.0'  # Cache version for invalidation

# Configure GitHub authentication if token is available
if (`$env:GITHUB_TOKEN) {
    `$secureToken = ConvertTo-SecureString -String `$env:GITHUB_TOKEN -AsPlainText -Force
    `$credential = New-Object System.Management.Automation.PSCredential("token", `$secureToken)
    Set-GitHubAuthentication -Credential `$credential -SessionOnly
    Write-Verbose "GitHub authentication configured from GITHUB_TOKEN environment variable"
} else {
    Write-Warning "No GitHub authentication configured. API rate limits will apply. Set GITHUB_TOKEN environment variable or use Set-GitHubAuthentication."
}

# Initialize cache directory
if (`$script:CacheEnabled -and -not (Test-Path -Path `$script:CacheDirectory)) {
    try {
        New-Item -ItemType Directory -Path `$script:CacheDirectory -Force | Out-Null
        Write-Verbose "Created cache directory: `$script:CacheDirectory"
    } catch {
        Write-Warning "Failed to create cache directory: `$_"
        `$script:CacheEnabled = `$false
    }
}

"@

# Load all private functions
$PrivatePath = Join-Path $ProjectRoot 'src' 'Private'
if (Test-Path $PrivatePath) {
    Get-ChildItem -Path $PrivatePath -Filter '*.ps1' | ForEach-Object {
        $ModuleDefinition += "`n`n# Private Function: $($_.BaseName)`n"
        $ModuleDefinition += Get-Content -Path $_.FullName -Raw
    }
}

# Load all public functions
$PublicPath = Join-Path $ProjectRoot 'src' 'Public'
if (Test-Path $PublicPath) {
    $PublicFunctions = Get-ChildItem -Path $PublicPath -Filter '*.ps1'
    $PublicFunctions | ForEach-Object {
        $ModuleDefinition += "`n`n# Public Function: $($_.BaseName)`n"
        $ModuleDefinition += Get-Content -Path $_.FullName -Raw
    }
}

# Add export statement
$FunctionNames = $PublicFunctions.BaseName -join ', '
$ModuleDefinition += "`n`n# Export public functions`nExport-ModuleMember -Function $FunctionNames"

# Create the module
New-Module -Name $ModuleName -ScriptBlock ([ScriptBlock]::Create($ModuleDefinition)) | Import-Module -Force -Global

Write-Verbose "Module $ModuleName loaded for testing"