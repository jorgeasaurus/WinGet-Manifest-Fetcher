function Complete-WingetAtomicFileWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemporaryPath,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [switch]$ReplaceExisting
    )

    if ([IO.File]::Exists($DestinationPath)) {
        if (-not $ReplaceExisting) {
            throw [IO.IOException]::new("File already exists: $DestinationPath")
        }

        # File.Replace rejects a null backup path on some supported runtimes.
        # Cleanup happens only after a successful atomic commit and cannot
        # change the operation's outcome.
        $backupPath = "$DestinationPath.$([Guid]::NewGuid().ToString('N')).bak"
        [IO.File]::Replace($TemporaryPath, $DestinationPath, $backupPath)
        try {
            [IO.File]::Delete($backupPath)
        } catch {
            Write-Verbose "Could not remove atomic-write backup '$backupPath': $_"
        }
    } else {
        [IO.File]::Move($TemporaryPath, $DestinationPath)
    }
}
