function Set-WingetManifestCacheEnabled {
    <#
    .SYNOPSIS
        Enables or disables the WinGet manifest cache.
    
    .PARAMETER Enabled
        Whether to enable or disable the cache.
    
    .EXAMPLE
        Set-WingetManifestCacheEnabled -Enabled $false
        Disables caching.
    
    .EXAMPLE
        Set-WingetManifestCacheEnabled -Enabled $true
        Enables caching.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )
    
    $script:CacheEnabled = $Enabled
    
    if ($Enabled) {
        if (-not (Test-Path -Path $script:CacheDirectory)) {
            try {
                New-Item -ItemType Directory -Path $script:CacheDirectory -Force | Out-Null
                Write-Host "Cache enabled at: $script:CacheDirectory"
            } catch {
                Write-Error "Failed to create cache directory: $_"
                $script:CacheEnabled = $false
            }
        } else {
            Write-Host "Cache enabled"
        }
    } else {
        Write-Host "Cache disabled"
    }
}