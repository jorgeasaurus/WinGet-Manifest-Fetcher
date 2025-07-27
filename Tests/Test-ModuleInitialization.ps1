# Helper script to test module initialization in different environments

param(
    [switch]$Verbose
)

Write-Host "Testing WinGet Manifest Fetcher module initialization..." -ForegroundColor Cyan

# Get module path
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'src', 'WinGetManifestFetcher.psd1'
Write-Host "Module path: $modulePath"

# Remove module if already loaded
if (Get-Module -Name WinGetManifestFetcher) {
    Write-Host "Removing existing module..." -ForegroundColor Yellow
    Remove-Module -Name WinGetManifestFetcher -Force
}

# Import module
Write-Host "Importing module..." -ForegroundColor Yellow
try {
    Import-Module $modulePath -Force -ErrorAction Stop -Verbose:$Verbose
    Write-Host "Module imported successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to import module: $_" -ForegroundColor Red
    exit 1
}

# Check module
$module = Get-Module -Name WinGetManifestFetcher
if ($module) {
    Write-Host "`nModule Information:" -ForegroundColor Cyan
    Write-Host "  Name: $($module.Name)"
    Write-Host "  Version: $($module.Version)"
    Write-Host "  ModuleBase: $($module.ModuleBase)"
    Write-Host "  ExportedFunctions: $($module.ExportedFunctions.Count)"
    
    # List WinGet functions
    $wingetFunctions = $module.ExportedFunctions.Keys | Where-Object { $_ -like '*WinGet*' }
    if ($wingetFunctions) {
        Write-Host "`nWinGet Functions:" -ForegroundColor Cyan
        $wingetFunctions | ForEach-Object { Write-Host "  - $_" }
    }
} else {
    Write-Host "Module not found after import!" -ForegroundColor Red
    exit 1
}

# Test basic function
Write-Host "`nTesting Get-LatestWingetVersion..." -ForegroundColor Cyan
try {
    $result = Get-LatestWingetVersion -App '7zip.7zip' -ErrorAction Stop
    Write-Host "SUCCESS: Got version $($result.PackageVersion)" -ForegroundColor Green
    
    # Check module variables
    Write-Host "`nChecking module variables..." -ForegroundColor Cyan
    $moduleInfo = Get-Module -Name WinGetManifestFetcher
    $moduleState = $moduleInfo | Select-Object -ExpandProperty SessionState
    
    # Try to access script variables through reflection
    try {
        $flags = [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static
        $internalVariables = $moduleState.GetType().GetField('_variables', $flags).GetValue($moduleState)
        
        Write-Host "Module has $($internalVariables.Count) internal variables" -ForegroundColor Gray
    } catch {
        Write-Host "Could not inspect module internal state" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "FAILED: $_" -ForegroundColor Red
    Write-Host "Stack trace:" -ForegroundColor DarkRed
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    
    # Additional debugging
    Write-Host "`nError details:" -ForegroundColor Red
    $_ | Format-List -Force
}

Write-Host "`nTest complete." -ForegroundColor Cyan