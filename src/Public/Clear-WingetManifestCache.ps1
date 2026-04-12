function Clear-WingetManifestCache {
    <#
    .SYNOPSIS
        Clears the WinGet manifest cache.
    
    .DESCRIPTION
        Removes all cached items from the WinGet manifest cache directory.
    
    .PARAMETER Force
        If specified, clears the cache without prompting for confirmation.
    
    .EXAMPLE
        Clear-WingetManifestCache
        Clears the cache after prompting for confirmation.
    
    .EXAMPLE
        Clear-WingetManifestCache -Force
        Clears the cache without prompting.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    [OutputType([void])]
    param(
        [Parameter()]
        [switch]$Force
    )
    
    if (-not $script:CacheEnabled) {
        Write-Warning "Cache is disabled"
        return
    }
    
    if (-not (Test-Path -Path $script:CacheDirectory)) {
        Write-Verbose "Cache directory does not exist"
        return
    }
    
    $cacheFiles = Get-ChildItem -Path $script:CacheDirectory -Filter "*.json" -ErrorAction SilentlyContinue
    
    if ($cacheFiles.Count -eq 0) {
        Write-Verbose "Cache is already empty"
        return
    }
    
    if ($Force -or $PSCmdlet.ShouldProcess("$($cacheFiles.Count) cached items", "Clear")) {
        try {
            Remove-Item -Path (Join-Path -Path $script:CacheDirectory -ChildPath "*.json") -Force
            Write-Verbose "Cleared $($cacheFiles.Count) cached items"
        } catch {
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'CacheClearFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $script:CacheDirectory
            ))
        }
    }
}