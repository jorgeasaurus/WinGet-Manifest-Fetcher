function Get-WingetManifestCacheInfo {
    <#
    .SYNOPSIS
        Gets information about the WinGet manifest cache.
    
    .DESCRIPTION
        Returns statistics about the cache including size, item count, and age of items.
    
    .EXAMPLE
        Get-WingetManifestCacheInfo
        Returns cache statistics.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    if (-not $script:CacheEnabled) {
        Write-Warning "Cache is disabled"
        return
    }
    
    if (-not (Test-Path -Path $script:CacheDirectory)) {
        Write-Verbose "Cache directory does not exist"
        return [PSCustomObject]@{
            Enabled = $script:CacheEnabled
            Directory = $script:CacheDirectory
            ItemCount = 0
            TotalSizeMB = 0
            OldestItemAge = $null
            NewestItemAge = $null
            ExpirationMinutes = $script:CacheExpirationMinutes
        }
    }
    
    $cacheFiles = Get-ChildItem -Path $script:CacheDirectory -Filter "*.json" -ErrorAction SilentlyContinue
    
    if ($cacheFiles.Count -eq 0) {
        return [PSCustomObject]@{
            Enabled = $script:CacheEnabled
            Directory = $script:CacheDirectory
            ItemCount = 0
            TotalSizeMB = 0
            OldestItemAge = $null
            NewestItemAge = $null
            ExpirationMinutes = $script:CacheExpirationMinutes
        }
    }
    
    $totalSize = ($cacheFiles | Measure-Object -Property Length -Sum).Sum / 1MB
    $now = Get-Date
    
    $ages = @()
    foreach ($file in $cacheFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            if ($content.Timestamp) {
                $age = $now - [DateTime]$content.Timestamp
                $ages += $age
            }
        } catch {
            # Skip invalid cache files
            Write-Verbose "Skipping invalid cache file: $($file.Name)"
        }
    }
    
    $result = [PSCustomObject]@{
        Enabled = $script:CacheEnabled
        Directory = $script:CacheDirectory
        ItemCount = $cacheFiles.Count
        TotalSizeMB = [Math]::Round($totalSize, 2)
        OldestItemAge = if ($ages.Count -gt 0) { ($ages | Sort-Object -Descending | Select-Object -First 1).ToString() } else { $null }
        NewestItemAge = if ($ages.Count -gt 0) { ($ages | Sort-Object | Select-Object -First 1).ToString() } else { $null }
        ExpirationMinutes = $script:CacheExpirationMinutes
    }
    
    return $result
}