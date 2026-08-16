function Resolve-WingetPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$App,

        [string]$VersionSource
    )

    if ($VersionSource) {
        $pathParts = @($VersionSource -split '/')
        if ($pathParts.Count -lt 4 -or
            $pathParts[0] -ne $script:ManifestPath -or
            $pathParts[1] -notmatch '^[0-9a-z]$' -or
            @($pathParts | Where-Object { -not $_ -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
            throw "Invalid VersionSource format. Expected format: 'manifests/[letter]/[Publisher]/[Package]/...'"
        }

        $packageParts = @($pathParts[2..($pathParts.Count - 1)])
        $packageIdentifier = $packageParts -join '.'
        return [PSCustomObject]@{
            Publisher = $packageParts[0]
            Package   = $packageParts[1..($packageParts.Count - 1)] -join '.'
            Path      = $VersionSource
            PackageId = $packageIdentifier
        }
    }

    $publisher = $null
    $package = $null
    if ($App -match '^([^.]+)\.(.+)$') {
        $publisher = $Matches[1]
        $package = $Matches[2]
    } elseif ($App -match '^([^/]+)/(.+)$') {
        $publisher = $Matches[1]
        $package = $Matches[2]
    }

    if ($publisher -and $package) {
        $packagePath = "$script:ManifestPath/$($publisher.Substring(0, 1).ToLower())/$publisher/$($package -replace '\.', '/')"
        $packageIdentifier = "$publisher.$package"
        return [PSCustomObject]@{
            Publisher = $publisher
            Package   = $package
            Path      = $packagePath
            PackageId = $packageIdentifier
        }
    }

    return Search-WingetPackage -App $App
}
