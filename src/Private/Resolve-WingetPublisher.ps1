function Resolve-WingetPublisher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Publisher
    )

    $manifestSha = Get-WingetGitHubTreeSha -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -Path $script:ManifestPath
    $manifestTree = Get-WingetGitHubTree -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -TreeReference $manifestSha
    $shards = @($manifestTree.Entries | Where-Object { $_.type -eq 'tree' -and $_.path -match '^[0-9a-z]$' -and $_.sha })
    $exactShardName = $Publisher.Substring(0, 1).ToLowerInvariant()
    $exactShard = $shards | Where-Object { $_.path -eq $exactShardName } | Select-Object -First 1

    if ($exactShard) {
        $exactShardTree = Get-WingetGitHubTree -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -TreeReference $exactShard.sha
        $exactPublisher = $exactShardTree.Entries |
            Where-Object { $_.type -eq 'tree' -and $_.path -eq $Publisher -and $_.sha } |
            Select-Object -First 1
        if ($exactPublisher) {
            return [PSCustomObject]@{
                Name = $exactPublisher.path
                Path = "$script:ManifestPath/$($exactShard.path)/$($exactPublisher.path)"
                Sha  = $exactPublisher.sha
            }
        }
    }

    if (-not $env:GITHUB_TOKEN) {
        throw "Partial publisher search requires GITHUB_TOKEN. Use the exact publisher name for unauthenticated lookup."
    }

    $publisherMatches = [System.Collections.Generic.List[object]]::new()
    foreach ($shard in $shards) {
        $shardTree = if ($exactShard -and $shard.sha -eq $exactShard.sha) {
            $exactShardTree
        } else {
            Get-WingetGitHubTree -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -TreeReference $shard.sha
        }

        foreach ($entry in @($shardTree.Entries | Where-Object {
            $_.type -eq 'tree' -and
            $_.sha -and
            $_.path.IndexOf($Publisher, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        })) {
            $publisherMatches.Add([PSCustomObject]@{
                Name = $entry.path
                Path = "$script:ManifestPath/$($shard.path)/$($entry.path)"
                Sha  = $entry.sha
            })
        }
    }

    return $publisherMatches
}
