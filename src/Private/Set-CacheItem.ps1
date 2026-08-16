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
        [Parameter(Mandatory)]
        [string]$Key,
        
        [Parameter(Mandatory)]
        [object]$Data
    )
    
    if (-not $script:CacheEnabled) {
        return
    }
    
    $cacheFile = Join-Path -Path $script:CacheDirectory -ChildPath "$Key.json"
    $temporaryFile = Join-Path -Path $script:CacheDirectory -ChildPath ".$Key.$([Guid]::NewGuid().ToString('N')).tmp"
    
    try {
        $cacheEntry = @{
            Version = $script:CacheVersion
            Timestamp = (Get-Date).ToString('o')
            Data = $Data
        }

        $json = $cacheEntry | ConvertTo-Json -Depth 10
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($json)
        $stream = New-Object IO.FileStream($temporaryFile, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally {
            $stream.Dispose()
        }

        Complete-WingetAtomicFileWrite -TemporaryPath $temporaryFile -DestinationPath $cacheFile -ReplaceExisting
        $temporaryFile = $null
        Write-Verbose "Cached: $Key"
    } catch {
        Write-Verbose "Cache error writing $Key`: $_"
    } finally {
        if ($temporaryFile) {
            Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue
        }
    }
}
