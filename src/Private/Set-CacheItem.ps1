function Set-CacheItem {
    <#
    .SYNOPSIS
        Stores an item in the cache.
    
    .PARAMETER Key
        The cache key to store.
    
    .PARAMETER Data
        The data to cache.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        
        [Parameter(Mandatory = $true)]
        [object]$Data
    )
    
    if (-not $script:CacheEnabled) {
        return
    }
    
    $cacheFile = Join-Path -Path $script:CacheDirectory -ChildPath "$Key.json"
    
    try {
        $cacheEntry = @{
            Version = $script:CacheVersion
            Timestamp = (Get-Date).ToString('o')
            Data = $Data
        }
        
        $cacheEntry | ConvertTo-Json -Depth 10 | Out-File -FilePath $cacheFile -Force
        Write-Verbose "Cached: $Key"
    } catch {
        Write-Verbose "Cache error writing $Key`: $_"
    }
}