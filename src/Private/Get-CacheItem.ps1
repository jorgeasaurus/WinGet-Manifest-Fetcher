function Get-CacheItem {
    <#
    .SYNOPSIS
        Retrieves an item from the cache if it exists and hasn't expired.
    
    .PARAMETER Key
        The cache key to retrieve.
    
    .PARAMETER ExpirationMinutes
        Override the default expiration time in minutes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        
        [Parameter()]
        [int]$ExpirationMinutes = $script:CacheExpirationMinutes
    )
    
    if (-not $script:CacheEnabled) {
        return $null
    }
    
    $cacheFile = Join-Path -Path $script:CacheDirectory -ChildPath "$Key.json"
    
    if (-not (Test-Path -Path $cacheFile)) {
        Write-Verbose "Cache miss: $Key (file not found)"
        return $null
    }
    
    try {
        $cacheData = Get-Content -Path $cacheFile -Raw | ConvertFrom-Json
        
        # Check cache version
        if ($cacheData.Version -ne $script:CacheVersion) {
            Write-Verbose "Cache miss: $Key (version mismatch)"
            Remove-Item -Path $cacheFile -Force -ErrorAction SilentlyContinue
            return $null
        }
        
        # Check expiration
        $cacheAge = (Get-Date) - [DateTime]$cacheData.Timestamp
        if ($cacheAge.TotalMinutes -gt $ExpirationMinutes) {
            Write-Verbose "Cache miss: $Key (expired, age: $($cacheAge.TotalMinutes) minutes)"
            Remove-Item -Path $cacheFile -Force -ErrorAction SilentlyContinue
            return $null
        }
        
        Write-Verbose "Cache hit: $Key (age: $([int]$cacheAge.TotalMinutes) minutes)"
        return $cacheData.Data
    } catch {
        Write-Verbose "Cache error reading $Key`: $_"
        Remove-Item -Path $cacheFile -Force -ErrorAction SilentlyContinue
        return $null
    }
}