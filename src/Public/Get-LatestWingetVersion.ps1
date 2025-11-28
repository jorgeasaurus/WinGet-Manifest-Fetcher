function Get-LatestWingetVersion {
    <#
    .SYNOPSIS
        Retrieves the latest installer information from a WinGet manifest.
    
    .DESCRIPTION
        Searches the microsoft/winget-pkgs repository for the specified application and returns
        detailed installer information from the latest version's manifest files, including all
        metadata from the package manifest, locale information, and installer details.
    
    .PARAMETER App
        The application name or ID to search for in the WinGet repository. Can be:
        - Full package identifier (e.g., "Microsoft.VisualStudioCode")
        - Package name (e.g., "Visual Studio Code")
        - Publisher/Package format (e.g., "Microsoft/VisualStudioCode")
    
    .PARAMETER VersionSource
        Optional direct path to the package version directory in the repository.
        Example: "manifests/a/Adobe/Acrobat/Reader/64-bit"
        When provided, skips the search and goes directly to the specified path.
    
    .EXAMPLE
        Get-LatestWingetVersion -App "Greenshot"
        Returns all information for the latest version of Greenshot.
    
    .EXAMPLE
        Get-LatestWingetVersion -App "Microsoft.PowerToys"
        Returns all information for the latest version of Microsoft PowerToys.
    
    .EXAMPLE
        $result = Get-LatestWingetVersion -App "7zip.7zip"
        $result.Installers | Where-Object { $_.Architecture -eq 'x64' -and $_.InstallerType -eq 'msi' }
        Returns the latest version info for 7-Zip and filters for x64 MSI installer.
    
    .EXAMPLE
        Get-LatestWingetVersion -App "Adobe Acrobat" -VersionSource "manifests/a/Adobe/Acrobat/Reader/64-bit"
        Uses the direct path to quickly retrieve Adobe Acrobat Reader information without searching.
    
    .OUTPUTS
        PSCustomObject with the following properties:
        - PackageIdentifier: The WinGet package identifier
        - PackageVersion: The version of the package
        - PackageName: The display name of the package
        - Publisher: The publisher of the package
        - PublisherUrl: URL to the publisher's website
        - PublisherSupportUrl: URL for publisher support
        - PrivacyUrl: URL to privacy policy
        - Author: The author of the package
        - License: The license of the package
        - LicenseUrl: URL to the license text
        - Copyright: Copyright information
        - CopyrightUrl: URL to copyright information
        - ShortDescription: Brief description of the package
        - Description: Full description of the package
        - Moniker: Short alias for the package
        - Tags: Array of tags associated with the package
        - ReleaseNotes: Notes for this release
        - ReleaseNotesUrl: URL to full release notes
        - Installers: Array of installer objects containing:
          - Architecture: Processor architecture (x64, x86, arm64, etc.)
          - InstallerType: Type of installer (exe, msi, msix, etc.)
          - InstallerUrl: Direct download URL
          - InstallerSha256: SHA256 hash of the installer
          - Scope: Installation scope (user, machine)
          - InstallerSwitches: Silent and interactive install parameters
          - UpgradeBehavior: How upgrades are handled
          - Dependencies: Any dependencies required
          - ProductCode: MSI product code (if applicable)
          - FileExtensions: Associated file extensions
          - Protocols: Associated protocols
          - Commands: Associated commands
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('ApplicationName')]
        [string]$App,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VersionSource
    )
    
    begin {
        if ($VersionSource) {
            Write-Verbose "Using provided version source: $VersionSource"
        } else {
            Write-Verbose "Searching for package '$App' in $($script:WinGetRepoOwner)/$($script:WinGetRepoName) repository..."
        }
        
        # Initialize results array
        $packageResults = @()
    }
    
    process {
        try {
            # Generate cache key for the entire result
            $cacheKey = "package_$($App -replace '[^\w\-\.]', '_')"
            if ($VersionSource) {
                $cacheKey = "package_direct_$($VersionSource -replace '[^\w\-\.]', '_')"
            }
            
            # Check cache first
            $cachedResult = Get-CacheItem -Key $cacheKey
            if ($cachedResult) {
                Write-Verbose "Returning cached result for $App"
                $packageResults += $cachedResult
                return
            }
            
            # If VersionSource is provided, use it directly
            if ($VersionSource) {
                # Extract package info from the path
                # Example: "manifests/a/Adobe/Acrobat/Reader/64-bit" -> Adobe.Acrobat.Reader.64-bit
                $pathParts = $VersionSource -split '/'
                if ($pathParts.Count -ge 3) {
                    # Skip 'manifests' and letter directory
                    $packageParts = $pathParts[2..($pathParts.Count - 1)]
                    $packageId = $packageParts -join '.'
                    
                    $foundPackages = @(@{
                            Publisher = $packageParts[0]
                            Package   = $packageParts[1..($packageParts.Count - 1)] -join '.'
                            Path      = $VersionSource
                            PackageId = $packageId
                        })
                    
                    Write-Verbose "Using direct path for package: $packageId"
                } else {
                    throw "Invalid VersionSource format. Expected format: 'manifests/[letter]/[Publisher]/[Package]/...'"
                }
            } else {
                # Original search logic
                # Parse the application name to determine search strategy
                $packagePath = $null
                $searchPublisher = $null
                $searchPackage = $null
            
                # Check if it's a full package identifier (Publisher.Package)
                if ($App -match '^([^.]+)\.(.+)$') {
                    $searchPublisher = $Matches[1]
                    $searchPackage = $Matches[2]
                    Write-Verbose "Detected package identifier format: $searchPublisher.$searchPackage"
                }
                # Check if it's Publisher/Package format
                elseif ($App -match '^([^/]+)/(.+)$') {
                    $searchPublisher = $Matches[1]
                    $searchPackage = $Matches[2]
                    Write-Verbose "Detected publisher/package format: $searchPublisher/$searchPackage"
                }
            
                # If we have publisher and package, try direct path
                if ($searchPublisher -and $searchPackage) {
                    $firstLetter = $searchPublisher.Substring(0, 1).ToLower()
                    # Replace dots with forward slashes in the package name for path construction
                    $packagePathPart = $searchPackage -replace '\.', '/'
                    $packagePath = "$ManifestPath/$firstLetter/$searchPublisher/$packagePathPart"
                
                    Write-Verbose "Found package path: $packagePath"

                    try {
                        $testContent = Get-GitHubContent -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -Path $packagePath -ErrorAction Stop

                        # Check if we got a single directory item (PowerShellForGitHub quirk)
                        if ($testContent -and $testContent.type -eq 'dir') {
                            $foundPackages = @(@{
                                    Publisher = $searchPublisher
                                    Package   = $searchPackage
                                    Path      = $packagePath
                                    PackageId = "$searchPublisher.$searchPackage"
                                })
                        }
                    } catch {
                        Write-Verbose "Package not found at direct path, will search"
                        $foundPackages = @()
                    }
                }
            
                # If direct path didn't work or wasn't applicable, search common publishers
                if (-not $foundPackages -or $foundPackages.Count -eq 0) {
                    Write-Verbose "Searching for package by name..."
                
                    # Common publishers to check first for optimization
                    $commonPublishers = @(
                        'Microsoft', 'Mozilla', 'Google', 'Adobe', 'Oracle', 'VideoLAN',
                        '7zip', 'Notepad++', 'Python', 'NodeJS', 'Git', 'Docker',
                        'JetBrains', 'GitHub', 'Zoom', 'Slack', 'Discord', 'Spotify',
                        'Greenshot', 'Igor Pavlov'
                    )
                
                    $foundPackages = @()
                
                    # First, check common publishers
                    foreach ($publisher in $commonPublishers) {
                        $firstLetter = $publisher.Substring(0, 1).ToLower()
                        $publisherPath = "$ManifestPath/$firstLetter/$publisher"
                    
                        try {
                            $packages = Get-GitHubContent -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -Path $publisherPath -ErrorAction SilentlyContinue
                        
                            if ($packages) {
                                # Handle PowerShellForGitHub structure
                                $packageList = if ($packages -is [array]) { $packages } elseif ($packages.entries) { $packages.entries } else { @() }
                                
                                foreach ($pkg in $packageList | Where-Object { $_.type -eq 'dir' }) {
                                    if ($pkg.name -like "*$App*" -or $App -like "*$($pkg.name)*" -or 
                                        "$publisher.$($pkg.name)" -like "*$App*" -or $App -like "*$publisher.$($pkg.name)*") {
                                        Write-Verbose "Found potential match: $publisher.$($pkg.name)"
                                        $foundPackages += @{
                                            Publisher = $publisher
                                            Package   = $pkg.name
                                            Path      = "$publisherPath/$($pkg.name)"
                                            PackageId = "$publisher.$($pkg.name)"
                                        }
                                    }
                                }
                            }
                        } catch {
                            # Silently continue if publisher doesn't exist
                            Write-Verbose "Publisher not found: $pub - continuing search"
                        }
                    
                        # Stop searching if we found matches
                        if ($foundPackages.Count -gt 0) {
                            break
                        }
                    }
                
                    # If still no results, do a broader search (but limited to avoid timeout)
                    if ($foundPackages.Count -eq 0) {
                        Write-Verbose "No matches in common publishers, searching more broadly..."
                    
                        # Get first letter of search term for targeted search
                        $searchLetter = $App.Substring(0, 1).ToLower()
                    
                        try {
                            $publisherDirs = Get-GitHubContent -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -Path "$ManifestPath/$searchLetter" -ErrorAction Stop
                        
                            # Handle PowerShellForGitHub structure
                            $dirList = if ($publisherDirs -is [array]) { $publisherDirs } elseif ($publisherDirs.entries) { $publisherDirs.entries } else { @() }
                        
                            foreach ($pubDir in $dirList | Where-Object { $_.type -eq 'dir' } | Select-Object -First 20) {
                                try {
                                    $packages = Get-GitHubContent -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -Path $pubDir.path -ErrorAction SilentlyContinue
                                
                                    $packageList = if ($packages -is [array]) { $packages } elseif ($packages.entries) { $packages.entries } else { @() }
                                
                                    foreach ($pkg in $packageList | Where-Object { $_.type -eq 'dir' }) {
                                        if ($pkg.name -like "*$App*" -or $App -like "*$($pkg.name)*") {
                                            Write-Verbose "Found potential match: $($pubDir.name).$($pkg.name)"
                                            $foundPackages += @{
                                                Publisher = $pubDir.name
                                                Package   = $pkg.name
                                                Path      = "$($pubDir.path)/$($pkg.name)"
                                                PackageId = "$($pubDir.name).$($pkg.name)"
                                            }
                                        }
                                    }
                                } catch {
                                    # Continue on error - package directory might not have accessible content
                                    Write-Verbose "Could not access package content for $($pkg.name) - continuing"
                                }
                            }
                        } catch {
                            Write-Warning "Could not search manifests directory: $_"
                        }
                    }
                }
            } # End of else block for non-VersionSource path
            
            if ($foundPackages.Count -eq 0) {
                Write-Warning "Package '$App' not found in WinGet repository."
                throw "Package not found: $App"
            }
            
            Write-Verbose "Found $($foundPackages.Count) potential package(s)"
            
            # Process each found package
            foreach ($package in $foundPackages) {
                Write-Verbose "Processing package: $($package.PackageId)"
                
                try {
                    # Get version directories
                    Write-Verbose "Retrieving version folders..."
                    $versionContent = Get-GitHubContent -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -Path $package.Path -ErrorAction Stop

                    # Handle PowerShellForGitHub returning different structures
                    $versionDirs = if ($versionContent -is [array]) {
                        $versionContent
                    } elseif ($versionContent.entries) {
                        # PowerShellForGitHub returns directory contents in 'entries' property
                        $versionContent.entries
                    } else {
                        @() # Empty array if no content
                    }
                    
                    if (-not $versionDirs -or $versionDirs.Count -eq 0) {
                        Write-Verbose "No version directories found for $($package.PackageId)"
                        continue
                    }
                    
                    if ($package.Path -eq 'manifests/m/Mozilla/Firefox') {
                        $versionDirs = $versionDirs | Where-Object { $_.name -match '^([\d]+(?:\.[\d]+)*)' }
                    }

                    # Sort versions and get the latest
                    Write-Verbose "Found $($versionDirs.Count) versions. Determining latest version..."
                    $ignoreFolders = 'X|VideoCapture|Telegraph|WiiBalanceBoard|Extension|Module|CN|.validation|Preview|Nightly|Beta|Alpha|Experimental|Canary|Dev|Test|RC|ReleaseCandidate|LTS|EXE'
                    $sortedVersions = $versionDirs |
                    Where-Object { $_.type -eq 'dir' -and $_.name -notmatch $ignoreFolders } |
                    Sort-Object -Property @{
                        Expression = {
                            # Extract the numeric prefix (e.g. "1.2.69.448" from "1.2.69.448.ge76b8882")
                            if ($_.name -match '^([\d]+(?:\.[\d]+)*)') {
                                $numeric = $Matches[1]
                                try {
                                    # Use Version on the pure numeric string
                                    [Version]$numeric
                                } catch {
                                    # Fallback if the numeric string isn't a valid Version
                                    $_.name
                                }
                            } else {
                                # No leading numeric portion: sort by raw name
                                $_.name
                            }
                        }
                    } -Descending
                    
                    if (-not $sortedVersions -or $sortedVersions.Count -eq 0) {
                        Write-Verbose "No valid versions found for $($package.PackageId)"
                        continue
                    }
                    
                    $latestVersion = $sortedVersions[0]
                    Write-Verbose "Latest version: $($latestVersion.name)"
                    
                    # Starting from the most recent version, find the first with a valid installer manifest
                    for ($i = 0; $i -lt $sortedVersions.Count; $i++) {
                    
                        $checkVersion = $sortedVersions[$i]
                        Write-Verbose "Checking version: $($checkVersion.name)"
                    
                        # Get manifest files for the latest version
                        $versionPath = $package.Path + "/" + $checkVersion.name
                        Write-Verbose "Fetching installer manifest: $versionPath/$($package.PackageId).installer.yaml"
                    
                        $manifestContent = Get-GitHubContent -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -Path $versionPath -ErrorAction Stop
                    
                        # Handle PowerShellForGitHub structure for manifest files
                        $manifestFiles = if ($manifestContent -is [array]) {
                            $manifestContent
                        }
                        elseif ($manifestContent.entries) {
                            $manifestContent.entries
                        }
                        else {
                            @()
                        }
                    
                        # Find the manifest files
                        $installerManifest = $manifestFiles | Where-Object { $_.name -like '*installer.yaml' } | Select-Object -First 1
                        $defaultManifest = $manifestFiles | Where-Object { $_.name -like '*.yaml' -and $_.name -notlike '*installer.yaml' -and $_.name -notlike '*.locale.*.yaml' } | Select-Object -First 1
                        $localeManifest = $manifestFiles | Where-Object { $_.name -like '*.locale.en-US.yaml' } | Select-Object -First 1
                    
                        # If installer manifest found, break the loop
                        if ($installerManifest) {
                            break
                        }

                        # No installer manifest found for this version
                        if ($i -lt ($sortedVersions.Count - 1)) {
                            Write-Verbose "No installer manifest found for version $($checkVersion.name), checking next version..."
                        }
                        else {
                            Write-Verbose "No installer manifest found for any version of $($package.PackageId)"
                        }
                    }

                    # Ensure we have an installer manifest
                    if (-not $installerManifest) {
                        continue
                    }
                    
                    # Download and parse the manifests
                    Write-Verbose "Parsing YAML manifest..."
                    
                    # Parse installer manifest
                    $installerContent = Invoke-RestMethod -Uri $installerManifest.download_url -ErrorAction Stop
                    $installerData = ConvertFrom-Yaml -Yaml $installerContent -ErrorAction Stop
                    
                    # Parse default manifest for package metadata
                    $packageData = @{}
                    if ($defaultManifest) {
                        try {
                            $defaultContent = Invoke-RestMethod -Uri $defaultManifest.download_url -ErrorAction Stop
                            $packageData = ConvertFrom-Yaml -Yaml $defaultContent -ErrorAction Stop
                        } catch {
                            Write-Verbose "Could not parse default manifest: $_"
                        }
                    }
                    
                    # Parse locale manifest for additional metadata
                    $localeData = @{}
                    if ($localeManifest) {
                        try {
                            $localeContent = Invoke-RestMethod -Uri $localeManifest.download_url -ErrorAction Stop
                            $localeData = ConvertFrom-Yaml -Yaml $localeContent -ErrorAction Stop
                        } catch {
                            Write-Verbose "Could not parse locale manifest: $_"
                        }
                    }
                    
                    # Build the result object with all metadata
                    $result = [PSCustomObject]@{
                        PackageIdentifier   = $installerData.PackageIdentifier
                        PackageVersion      = $installerData.PackageVersion
                        PackageName         = if ($localeData.PackageName) { $localeData.PackageName } elseif ($packageData.PackageName) { $packageData.PackageName } else { $null }
                        Publisher           = if ($localeData.Publisher) { $localeData.Publisher } elseif ($packageData.Publisher) { $packageData.Publisher } else { $null }
                        PublisherUrl        = if ($localeData.PublisherUrl) { $localeData.PublisherUrl } elseif ($packageData.PublisherUrl) { $packageData.PublisherUrl } else { $null }
                        PublisherSupportUrl = if ($localeData.PublisherSupportUrl) { $localeData.PublisherSupportUrl } elseif ($packageData.PublisherSupportUrl) { $packageData.PublisherSupportUrl } else { $null }
                        PrivacyUrl          = if ($localeData.PrivacyUrl) { $localeData.PrivacyUrl } elseif ($packageData.PrivacyUrl) { $packageData.PrivacyUrl } else { $null }
                        Author              = if ($localeData.Author) { $localeData.Author } elseif ($packageData.Author) { $packageData.Author } else { $null }
                        License             = if ($localeData.License) { $localeData.License } elseif ($packageData.License) { $packageData.License } else { $null }
                        LicenseUrl          = if ($localeData.LicenseUrl) { $localeData.LicenseUrl } elseif ($packageData.LicenseUrl) { $packageData.LicenseUrl } else { $null }
                        Copyright           = if ($localeData.Copyright) { $localeData.Copyright } elseif ($packageData.Copyright) { $packageData.Copyright } else { $null }
                        CopyrightUrl        = if ($localeData.CopyrightUrl) { $localeData.CopyrightUrl } elseif ($packageData.CopyrightUrl) { $packageData.CopyrightUrl } else { $null }
                        ShortDescription    = if ($localeData.ShortDescription) { $localeData.ShortDescription } elseif ($packageData.ShortDescription) { $packageData.ShortDescription } else { $null }
                        Description         = if ($localeData.Description) { $localeData.Description } elseif ($packageData.Description) { $packageData.Description } else { $null }
                        Moniker             = if ($localeData.Moniker) { $localeData.Moniker } elseif ($packageData.Moniker) { $packageData.Moniker } else { $null }
                        Tags                = if ($localeData.Tags) { $localeData.Tags } elseif ($packageData.Tags) { $packageData.Tags } else { @() }
                        ReleaseNotes        = if ($localeData.ReleaseNotes) { $localeData.ReleaseNotes } elseif ($packageData.ReleaseNotes) { $packageData.ReleaseNotes } else { $null }
                        ReleaseNotesUrl     = if ($localeData.ReleaseNotesUrl) { $localeData.ReleaseNotesUrl } elseif ($packageData.ReleaseNotesUrl) { $packageData.ReleaseNotesUrl } else { $null }
                        Installers          = @() # Will be populated below
                    }
                    
                    # Process installers
                    $installers = if ($installerData.Installers) { $installerData.Installers } else { @($installerData) }
                    Write-Verbose "Found $($installers.Count) installers in manifest"
                    
                    $installerObjects = @()
                    foreach ($installer in $installers) {
                        $installerObj = [PSCustomObject]@{
                            Architecture      = $installer.Architecture
                            InstallerType     = if ($installer.InstallerType) { $installer.InstallerType } else { $installerData.InstallerType }
                            InstallerUrl      = $installer.InstallerUrl
                            InstallerSha256   = $installer.InstallerSha256
                            Scope             = if ($installer.Scope) { $installer.Scope } else { $installerData.Scope }
                            InstallerSwitches = if ($installer.InstallerSwitches) { $installer.InstallerSwitches } else { $installerData.InstallerSwitches }
                            UpgradeBehavior   = if ($installer.UpgradeBehavior) { $installer.UpgradeBehavior } else { $installerData.UpgradeBehavior }
                            Dependencies      = if ($installer.Dependencies) { $installer.Dependencies } else { $installerData.Dependencies }
                            ProductCode       = $installer.ProductCode
                            FileExtensions    = if ($installer.FileExtensions) { $installer.FileExtensions } else { $installerData.FileExtensions }
                            Protocols         = if ($installer.Protocols) { $installer.Protocols } else { $installerData.Protocols }
                            Commands          = if ($installer.Commands) { $installer.Commands } else { $installerData.Commands }
                            InstallerLocale   = if ($installer.InstallerLocale) { $installer.InstallerLocale } else { $installerData.InstallerLocale }
                        }
                        $installerObjects += $installerObj
                    }
                    
                    # Add installers to result
                    $result.Installers = $installerObjects
                    
                    $packageResults += $result
                    
                } catch {
                    Write-Warning "Error processing package $($package.PackageId): $_"
                    Write-Verbose "Full error: $($_.Exception.Message)"
                    continue
                }
            }
            
        } catch {
            if ($_.Exception.Message -like "*Package not found*") {
                throw $_
            } else {
                Write-Error "Error searching for application: $_"
                throw
            }
        }
    }
    
    end {
        if ($packageResults.Count -eq 0) {
            Write-Warning "Package '$App' not found in the WinGet repository. Please verify the package identifier is correct."
            Write-Verbose "Search completed with no results. The package may not exist, or may have been removed from the repository."
        } else {
            # Cache the result before returning
            $result = $packageResults[0]
            Set-CacheItem -Key $cacheKey -Data $result
            
            # Return the first result (should typically be only one)
            return $result
        }
    }
}