function Get-WingetPackageVersionEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageIdentifier
    )

    $packageContent = Get-GitHubContent -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -Path $Path
    $contentEntries = @($packageContent.Entries)
    if ($contentEntries.Count -lt 1000) {
        $versionTrees = @($contentEntries |
            Where-Object { $_.type -eq 'dir' -and $_.sha } |
            ForEach-Object {
                [PSCustomObject]@{
                    name = $_.name
                    path = $_.name
                    type = 'dir'
                    sha  = $_.sha
                }
            })
    } else {
        # The Contents API caps directory listings at 1,000 entries. At the
        # cap, resolve through uncapped Git trees so no versions are omitted.
        $packageSha = Get-WingetGitHubTreeSha -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -Path $Path
        $packageTree = Get-WingetGitHubTree -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -TreeReference $packageSha
        $versionTrees = @($packageTree.Entries |
            Where-Object { $_.type -eq 'tree' -and $_.sha } |
            ForEach-Object {
                [PSCustomObject]@{
                    name = $_.path
                    path = $_.path
                    type = 'dir'
                    sha  = $_.sha
                }
            })
    }

    foreach ($versionEntry in $versionTrees) {
        $versionTree = Get-WingetGitHubTree -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -TreeReference $versionEntry.sha
        $singletonName = "$PackageIdentifier.yaml"
        $installerName = "$PackageIdentifier.installer.yaml"
        $localePrefix = "$PackageIdentifier.locale."
        $hasPackageManifest = @($versionTree.Entries | Where-Object {
            if ($_.type -ne 'blob') {
                return $false
            }

            $name = [string]$_.path
            $name.Equals($singletonName, [System.StringComparison]::OrdinalIgnoreCase) -or
            $name.Equals($installerName, [System.StringComparison]::OrdinalIgnoreCase) -or
            ($name.StartsWith($localePrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
                $name.EndsWith('.yaml', [System.StringComparison]::OrdinalIgnoreCase) -and
                $name.Length -gt ($localePrefix.Length + '.yaml'.Length))
        }).Count -gt 0
        if ($hasPackageManifest) {
            return $versionTrees
        }
    }

    throw [System.IO.InvalidDataException]::new("Path '$Path' is not a manifest-bearing package leaf for '$PackageIdentifier'")
}
