function Get-WingetPublisherPackagePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PublisherSha,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxResults = 0
    )

    $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $packagePaths = [System.Collections.Generic.List[string]]::new()
    $addManifestPath = {
        param([string]$ManifestPath)

        $parts = @($ManifestPath -split '/')
        if ($parts.Count -lt 3) {
            return
        }

        $packagePath = $parts[0..($parts.Count - 3)] -join '/'
        if ($seenPaths.Add($packagePath)) {
            $packagePaths.Add($packagePath)
        }
    }

    $walkNonRecursive = {
        $work = New-Object System.Collections.Stack
        $work.Push(@{ Sha = $PublisherSha; Prefix = '' })
        while ($work.Count -gt 0 -and ($MaxResults -eq 0 -or $packagePaths.Count -lt $MaxResults)) {
            $current = $work.Pop()
            $tree = Get-WingetGitHubTree -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -TreeReference $current.Sha
            $entries = @($tree.Entries)

            foreach ($blob in @($entries | Where-Object { $_.type -eq 'blob' -and $_.path -like '*.yaml' })) {
                $manifestPath = if ($current.Prefix) { "$($current.Prefix)/$($blob.path)" } else { $blob.path }
                & $addManifestPath $manifestPath
                if ($MaxResults -gt 0 -and $packagePaths.Count -ge $MaxResults) {
                    break
                }
            }

            if ($MaxResults -gt 0 -and $packagePaths.Count -ge $MaxResults) {
                continue
            }

            $children = @($entries | Where-Object { $_.type -eq 'tree' -and $_.sha })
            for ($index = $children.Count - 1; $index -ge 0; $index--) {
                $child = $children[$index]
                $prefix = if ($current.Prefix) { "$($current.Prefix)/$($child.path)" } else { $child.path }
                $work.Push(@{ Sha = $child.sha; Prefix = $prefix })
            }
        }
    }

    if ($MaxResults -gt 0) {
        & $walkNonRecursive
    } else {
        $snapshot = Get-WingetGitHubTree -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -TreeReference $PublisherSha -Recursive -AllowTruncated
        if ($snapshot.Truncated) {
            & $walkNonRecursive
        } else {
            foreach ($manifest in @($snapshot.Entries | Where-Object { $_.type -eq 'blob' -and $_.path -like '*.yaml' })) {
                & $addManifestPath $manifest.path
            }
        }
    }

    if ($MaxResults -gt 0) {
        return @($packagePaths | Select-Object -First $MaxResults)
    }
    return @($packagePaths)
}
