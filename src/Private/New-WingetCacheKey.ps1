function New-WingetCacheKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z][a-z0-9_]*$')]
        [string]$Namespace,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Label,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$Value
    )

    $safeLabel = $Label -replace '[^\w\-\.]', '_'
    if ($safeLabel.Length -gt 48) {
        $safeLabel = $safeLabel.Substring(0, 48)
    }

    # Length-prefix each value so embedded separators cannot make distinct
    # input tuples hash identically (for example @('a', 'b') and "a`nb").
    $canonicalValue = ($Value | ForEach-Object { "$($_.Length):$_" }) -join '|'
    $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $hashAlgorithm.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canonicalValue))
        $hash = ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
    } finally {
        $hashAlgorithm.Dispose()
    }

    "${Namespace}_${safeLabel}_${hash}"
}
