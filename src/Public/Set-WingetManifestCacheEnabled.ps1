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
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [bool]$Enabled
    )
    
    $script:CacheEnabled = $Enabled
    
    if ($Enabled) {
        if (-not (Test-Path -Path $script:CacheDirectory)) {
            try {
                New-Item -ItemType Directory -Path $script:CacheDirectory -Force | Out-Null
                Write-Verbose "Cache enabled at: $script:CacheDirectory"
            } catch {
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'CacheDirectoryCreateFailed',
                    [System.Management.Automation.ErrorCategory]::WriteError,
                    $script:CacheDirectory
                ))
                $script:CacheEnabled = $false
            }
        } else {
            Write-Verbose "Cache enabled"
        }
    } else {
        Write-Verbose "Cache disabled"
    }
}