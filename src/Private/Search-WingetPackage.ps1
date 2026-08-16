function Search-WingetPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$App
    )

    if (-not $env:GITHUB_TOKEN) {
        throw "Broad package name search requires GITHUB_TOKEN. Use an exact package identifier such as 'Publisher.Package' for unauthenticated lookup."
    }

    if ($App -match '[\x00-\x1F\x7F]') {
        throw [System.ArgumentException]::new('App cannot contain control characters.', 'App')
    }

    $normalizedApp = $App -replace '[^\p{L}\p{Nd}]', ''
    $escapedApp = $App.Replace('\', '\\').Replace('"', '\"')
    $query = '"{0}" repo:{1}/{2} path:{3} extension:yaml' -f @(
        $escapedApp,
        $script:WinGetRepoOwner,
        $script:WinGetRepoName,
        $script:ManifestPath
    )
    $encodedQuery = [Uri]::EscapeDataString($query)
    $candidates = [System.Collections.Generic.List[object]]::new()
    $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $page = 1

    do {
        $searchResult = Invoke-WingetGitHubRequest -UriFragment "search/code?q=$encodedQuery&per_page=100&page=$page" -Method Get -Description "Search WinGet manifests for $App" -ErrorAction Stop
        if ($searchResult.incomplete_results) {
            throw "GitHub code search returned incomplete results for '$App' on page $page"
        }
        if ([long]$searchResult.total_count -gt 1000) {
            throw "GitHub code search reported more than the 1,000-result API limit for '$App'"
        }

        $searchItems = @($searchResult.items)
        foreach ($item in $searchItems) {
            $pathParts = @($item.path -split '/')
            if ($pathParts.Count -lt 6 -or
                $pathParts[0] -ne $script:ManifestPath -or
                $pathParts[1] -notmatch '^[0-9a-z]$' -or
                $pathParts[-1] -notlike '*.yaml' -or
                @($pathParts | Where-Object { -not $_ -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
                continue
            }

            $packageParts = @($pathParts[2..($pathParts.Count - 3)])
            if ($packageParts.Count -lt 2) {
                continue
            }

            $packageId = $packageParts -join '.'
            $packageName = $packageParts[1..($packageParts.Count - 1)] -join '.'
            $normalizedPackageId = $packageId -replace '[^\p{L}\p{Nd}]', ''
            $normalizedPackageName = $packageName -replace '[^\p{L}\p{Nd}]', ''
            $comparison = [System.StringComparison]::OrdinalIgnoreCase
            $rawMatch = $packageId.IndexOf($App, $comparison) -ge 0 -or
                $packageName.IndexOf($App, $comparison) -ge 0 -or
                $App.IndexOf($packageName, $comparison) -ge 0
            $normalizedMatch = $normalizedApp -and (
                $normalizedPackageId.IndexOf($normalizedApp, $comparison) -ge 0 -or
                $normalizedPackageName.IndexOf($normalizedApp, $comparison) -ge 0 -or
                $normalizedApp.IndexOf($normalizedPackageName, $comparison) -ge 0
            )
            if (-not $rawMatch -and -not $normalizedMatch) {
                continue
            }

            $packagePath = $pathParts[0..($pathParts.Count - 3)] -join '/'
            if ($seenPaths.Add($packagePath)) {
                $candidates.Add([PSCustomObject]@{
                    Publisher = $packageParts[0]
                    Package   = $packageName
                    Path      = $packagePath
                    PackageId = $packageId
                })
            }
        }

        $page++
    } while ($searchItems.Count -eq 100 -and (($page - 1) * 100) -lt $searchResult.total_count -and $page -le 10)

    return $candidates
}
