function Get-WingetPackagesByPublisher {
    <#
    .SYNOPSIS
        Retrieves all packages from a specific publisher in the WinGet repository.
    
    .DESCRIPTION
        Searches the microsoft/winget-pkgs repository for all packages published by
        the specified publisher and returns their basic information.
    
    .PARAMETER Publisher
        The publisher name to search for. Can be:
        - Exact publisher name (e.g., "Microsoft", "Google", "Adobe")
        - Partial publisher name (will search for matches)
    
    .PARAMETER IncludeVersions
        If specified, retrieves version information for each package found.
        Note: This will make additional API calls and may take longer.
    
    .PARAMETER MaxResults
        Maximum number of packages to return. Default is unlimited.
    
    .EXAMPLE
        Get-WingetPackagesByPublisher -Publisher "Microsoft"
        Returns all packages published by Microsoft.
    
    .EXAMPLE
        Get-WingetPackagesByPublisher -Publisher "Adobe" -IncludeVersions
        Returns all Adobe packages with their latest version information.
    
    .EXAMPLE
        Get-WingetPackagesByPublisher -Publisher "JetBrains" -MaxResults 10
        Returns up to 10 packages from JetBrains.
    
    .OUTPUTS
        PSCustomObject[] with the following properties:
        - Publisher: The publisher name
        - PackageName: The package name
        - PackageIdentifier: The full WinGet package identifier
        - ManifestPath: Path to the package in the repository
        - LatestVersion: The latest version (only present when -IncludeVersions is specified)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Publisher,
        
        [Parameter()]
        [switch]$IncludeVersions,
        
        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxResults = 0
    )
    
    Write-Verbose "Searching for packages by publisher: $Publisher"
    $packages = [System.Collections.Generic.List[PSCustomObject]]::new()
    $cacheKey = New-WingetCacheKey -Namespace publisher -Label $Publisher -Value @($Publisher, [string][bool]$IncludeVersions, [string]$MaxResults)

    # Check cache first
    $cachedResult = Get-CacheItem -Key $cacheKey
    if ($cachedResult) {
        Write-Verbose "Returning cached result for publisher: $Publisher"
        return $cachedResult
    }

    $publishersToCheck = @(Resolve-WingetPublisher -Publisher $Publisher -ErrorAction Stop)

    if ($publishersToCheck.Count -eq 0) {
        Write-Warning "No publishers found matching '$Publisher'"
        Write-Warning "No packages found for publisher matching '$Publisher'"
        return
    }

    Write-Verbose "Found $($publishersToCheck.Count) publisher(s) to check"

    $addPackage = {
        param($PublisherInfo, [string]$PackageName, [string]$ManifestPath)

        $packageProps = @{
            Publisher = $PublisherInfo.Name
            PackageName = $PackageName
            PackageIdentifier = "$($PublisherInfo.Name).$PackageName"
            ManifestPath = $ManifestPath
        }

        if ($IncludeVersions) {
            $packageProps['LatestVersion'] = $null

            try {
                Write-Verbose "Getting version info for $($packageProps.PackageIdentifier)"
                $versionInfo = Get-LatestWingetVersion -App $packageProps.PackageIdentifier -VersionSource $ManifestPath -ErrorAction SilentlyContinue
                if ($versionInfo) {
                    $packageProps['LatestVersion'] = $versionInfo.PackageVersion
                }
            } catch {
                Write-Verbose "Could not get version for $($packageProps.PackageIdentifier): $_"
            }
        }

        $packages.Add([PSCustomObject]$packageProps)
    }

    # Process each publisher
    foreach ($pub in $publishersToCheck) {
        $remainingResults = if ($MaxResults -gt 0) { $MaxResults - $packages.Count } else { 0 }
        $selectedPackagePaths = @(Get-WingetPublisherPackagePath -PublisherSha $pub.Sha -MaxResults $remainingResults)

        foreach ($relativePackagePath in $selectedPackagePaths) {
            $packageName = ($relativePackagePath -split '/') -join '.'
            & $addPackage $pub $packageName "$($pub.Path)/$relativePackagePath"
        }

        # Check if we've reached the maximum results
        if ($MaxResults -gt 0 -and $packages.Count -ge $MaxResults) {
            break
        }
    }

    if ($packages.Count -gt 0) {
        Set-CacheItem -Key $cacheKey -Data $packages
    }
    if ($packages.Count -eq 0) {
        Write-Warning "No packages found for publisher matching '$Publisher'"
        return
    }

    Write-Verbose "Found $($packages.Count) package(s)"
    return $packages
}
