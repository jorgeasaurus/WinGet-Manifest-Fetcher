#Requires -Version 5.1

<#
.SYNOPSIS
    WinGet Manifest Fetcher - Retrieve installer information from WinGet manifests without WinGet client
.DESCRIPTION
    This module provides functionality to query the microsoft/winget-pkgs repository and retrieve
    installer information from WinGet manifests without requiring the WinGet client to be installed.
.NOTES
    Author: WinGet Manifest Fetcher Contributors
    Version: 1.4.0
#>

# Import required modules
$ErrorActionPreference = 'Stop'

# Check for required modules and provide helpful error messages
$requiredModules = @(
    @{Name = 'PowerShellForGitHub'; MinVersion = '0.16.0' },
    @{Name = 'powershell-yaml'; MinVersion = '0.4.0' }
)

foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module.Name | Where-Object { $_.Version -ge $module.MinVersion })) {
        throw "Required module '$($module.Name)' version $($module.MinVersion) or higher is not installed. Please run: Install-Module -Name $($module.Name) -MinimumVersion $($module.MinVersion)"
    }
    Import-Module $module.Name -MinimumVersion $module.MinVersion -ErrorAction Stop
}

# Module-level variables
$script:WinGetRepoOwner = 'microsoft'
$script:WinGetRepoName = 'winget-pkgs'
$script:ManifestPath = 'manifests'

# Verify variables are set
if (-not $script:WinGetRepoOwner -or -not $script:WinGetRepoName) {
    Write-Warning "Module variables not properly initialized. Setting defaults."
    $script:WinGetRepoOwner = 'microsoft'
    $script:WinGetRepoName = 'winget-pkgs'
    $script:ManifestPath = 'manifests'
}

# Cache configuration
$script:CacheEnabled = $true
# Cross-platform cache directory configuration
if ($IsWindows -or (-not (Test-Path Variable:IsWindows) -and $env:OS -eq 'Windows_NT')) {
    # Windows
    $script:CacheDirectory = Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath (Join-Path -Path 'WinGetManifestFetcher' -ChildPath 'Cache')
} elseif ($IsMacOS -or (-not (Test-Path Variable:IsMacOS) -and $env:OS -ne 'Windows_NT' -and (uname) -eq 'Darwin')) {
    # macOS
    $script:CacheDirectory = Join-Path -Path $HOME -ChildPath (Join-Path -Path 'Library' -ChildPath (Join-Path -Path 'Caches' -ChildPath 'WinGetManifestFetcher'))
} else {
    # Linux and other Unix-like systems
    if ($env:XDG_CACHE_HOME) {
        $script:CacheDirectory = Join-Path -Path $env:XDG_CACHE_HOME -ChildPath 'WinGetManifestFetcher'
    } else {
        $script:CacheDirectory = Join-Path -Path (Join-Path -Path $HOME -ChildPath '.cache') -ChildPath 'WinGetManifestFetcher'
    }
}
$script:CacheExpirationMinutes = 60  # Default cache expiration time
$script:CacheVersion = '1.0'  # Cache version for invalidation

# Disable PowerShellForGitHub telemetry by default
Set-GitHubConfiguration -DisableTelemetry -SessionOnly

# Configure GitHub authentication if token is available
if ($env:GITHUB_TOKEN) {
    $secureToken = ConvertTo-SecureString -String $env:GITHUB_TOKEN -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential("token", $secureToken)
    Set-GitHubAuthentication -Credential $credential -SessionOnly
    Write-Verbose "GitHub authentication configured from GITHUB_TOKEN environment variable"
} else {
    Write-Warning "No GitHub authentication configured. API rate limits will apply. Set GITHUB_TOKEN environment variable or use Set-GitHubAuthentication."
}

# Initialize cache directory
if ($script:CacheEnabled -and -not (Test-Path -Path $script:CacheDirectory)) {
    try {
        New-Item -ItemType Directory -Path $script:CacheDirectory -Force | Out-Null
        Write-Verbose "Created cache directory: $script:CacheDirectory"
    } catch {
        Write-Warning "Failed to create cache directory: $_"
        $script:CacheEnabled = $false
    }
}

# NOTE: PowerShellBuild will automatically include all functions from src/Private and src/Public
# Private functions will be available within the module
# Public functions will be exported

# When running from source (not built), manually dot-source the functions
$moduleRoot = $PSScriptRoot
if (-not $moduleRoot) {
    $moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Check if we're running from source by looking for the src folder structure
$srcPath = $moduleRoot
if (Test-Path (Join-Path $srcPath 'Private') -PathType Container) {
    Write-Verbose "Running from source - loading functions manually"
    
    # Dot source the private functions
    $privateFunctions = Get-ChildItem -Path (Join-Path $srcPath 'Private') -Filter '*.ps1' -Recurse
    foreach ($function in $privateFunctions) {
        Write-Verbose "Loading private function: $($function.Name)"
        . $function.FullName
    }
    
    # Dot source the public functions
    $publicFunctions = Get-ChildItem -Path (Join-Path $srcPath 'Public') -Filter '*.ps1' -Recurse
    foreach ($function in $publicFunctions) {
        Write-Verbose "Loading public function: $($function.Name)"
        . $function.FullName
    }
    
    # Export public functions
    $publicFunctionNames = $publicFunctions.BaseName
    Export-ModuleMember -Function $publicFunctionNames
}