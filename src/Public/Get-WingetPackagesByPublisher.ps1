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
        - LatestVersion: The latest version (if IncludeVersions is specified)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Publisher,
        
        [Parameter()]
        [switch]$IncludeVersions,
        
        [Parameter()]
        [int]$MaxResults = 0
    )
    
    begin {
        Write-Verbose "Searching for packages by publisher: $Publisher"
        $packages = @()
    }
    
    process {
        try {
            # Generate cache key for publisher search
            $cacheKey = "publisher_$($Publisher -replace '[^\w\-\.]', '_')_$(if($IncludeVersions){'withver'}else{'nover'})_$MaxResults"
            
            # Check cache first
            $cachedResult = Get-CacheItem -Key $cacheKey
            if ($cachedResult) {
                Write-Verbose "Returning cached result for publisher: $Publisher"
                return $cachedResult
            }
            
            # First, try exact publisher match
            $firstLetter = $Publisher.Substring(0, 1).ToLower()
            $publisherPath = "$ManifestPath/$firstLetter/$Publisher"
            
            $publishersToCheck = @()
            
            try {
                # Check if exact publisher exists
                $content = Get-GitHubContent -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -Path $publisherPath -ErrorAction Stop
                
                if ($content) {
                    Write-Verbose "Found exact publisher match: $Publisher"
                    $publishersToCheck += @{
                        Name = $Publisher
                        Path = $publisherPath
                    }
                }
            } catch {
                Write-Verbose "No exact match for publisher '$Publisher', searching for partial matches..."
            }
            
            # If no exact match or user wants partial matches, search more broadly
            if ($publishersToCheck.Count -eq 0) {
                # Search in all letter directories
                $searchLetters = @($firstLetter)
                
                # If the search term is short, also check other letters
                if ($Publisher.Length -le 3) {
                    $searchLetters = @('a'..'z' | ForEach-Object { $_.ToString() })
                }
                
                foreach ($letter in $searchLetters) {
                    try {
                        $letterPath = "$ManifestPath/$letter"
                        $publisherDirs = Get-GitHubContent -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -Path $letterPath -ErrorAction SilentlyContinue
                        
                        if ($publisherDirs) {
                            $dirList = if ($publisherDirs -is [array]) { $publisherDirs } elseif ($publisherDirs.entries) { $publisherDirs.entries } else { @() }
                            
                            foreach ($dir in $dirList | Where-Object { $_.type -eq 'dir' }) {
                                if ($dir.name -like "*$Publisher*") {
                                    Write-Verbose "Found publisher match: $($dir.name)"
                                    $publishersToCheck += @{
                                        Name = $dir.name
                                        Path = $dir.path
                                    }
                                }
                            }
                        }
                    } catch {
                        # Continue searching - this is expected for non-existent paths
                        Write-Verbose "Path not found: $testPath - continuing search"
                    }
                    
                    # Stop if we've found enough publishers
                    if ($MaxResults -gt 0 -and $publishersToCheck.Count -ge $MaxResults) {
                        break
                    }
                }
            }
            
            if ($publishersToCheck.Count -eq 0) {
                Write-Warning "No publishers found matching '$Publisher'"
                return
            }
            
            Write-Verbose "Found $($publishersToCheck.Count) publisher(s) to check"
            
            # Process each publisher
            foreach ($pub in $publishersToCheck) {
                try {
                    $packageDirs = Get-GitHubContent -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -Path $pub.Path -ErrorAction Stop
                    
                    $packageList = if ($packageDirs -is [array]) { $packageDirs } elseif ($packageDirs.entries) { $packageDirs.entries } else { @() }
                    
                    foreach ($pkg in $packageList | Where-Object { $_.type -eq 'dir' }) {
                        $packageInfo = [PSCustomObject]@{
                            Publisher = $pub.Name
                            PackageName = $pkg.name
                            PackageIdentifier = "$($pub.Name).$($pkg.name)"
                            ManifestPath = $pkg.path
                            LatestVersion = $null
                        }
                        
                        # Get version information if requested
                        if ($IncludeVersions) {
                            try {
                                Write-Verbose "Getting version info for $($packageInfo.PackageIdentifier)"
                                $versionInfo = Get-LatestWingetVersion -App $packageInfo.PackageIdentifier -VersionSource $pkg.path -ErrorAction SilentlyContinue
                                if ($versionInfo) {
                                    $packageInfo.LatestVersion = $versionInfo.PackageVersion
                                }
                            } catch {
                                Write-Verbose "Could not get version for $($packageInfo.PackageIdentifier): $_"
                            }
                        }
                        
                        $packages += $packageInfo
                        
                        # Check if we've reached the maximum results
                        if ($MaxResults -gt 0 -and $packages.Count -ge $MaxResults) {
                            Write-Verbose "Reached maximum results limit of $MaxResults"
                            break
                        }
                    }
                } catch {
                    Write-Warning "Error processing publisher $($pub.Name): $_"
                }
                
                # Check if we've reached the maximum results
                if ($MaxResults -gt 0 -and $packages.Count -ge $MaxResults) {
                    break
                }
            }
            
        } catch {
            Write-Error "Error searching for publisher packages: $_"
            throw
        }
    }
    
    end {
        if ($packages.Count -eq 0) {
            Write-Warning "No packages found for publisher matching '$Publisher'"
        } else {
            Write-Verbose "Found $($packages.Count) package(s)"
            
            # Cache the result before returning
            Set-CacheItem -Key $cacheKey -Data $packages
            
            return $packages
        }
    }
}