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
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('ApplicationName')]
        [string]$App,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VersionSource
    )
    
    if ($VersionSource) {
        Write-Verbose "Using provided version source: $VersionSource"
    } else {
        Write-Verbose "Searching for package '$App' in $($script:WinGetRepoOwner)/$($script:WinGetRepoName) repository..."
    }

    $firstError = $null
    $notFoundCause = $null

    $cacheValue = if ($VersionSource) { $VersionSource } else { $App }
    $cachePrefix = if ($VersionSource) { 'package_direct' } else { 'package' }
    $cacheKey = New-WingetCacheKey -Namespace $cachePrefix -Label $cacheValue -Value $cacheValue

    # Check cache first
    $cachedResult = Get-CacheItem -Key $cacheKey
    if ($cachedResult) {
        Write-Verbose "Returning cached result for $App"
        return $cachedResult
    }

    $foundPackages = @(Resolve-WingetPackage -App $App -VersionSource $VersionSource -ErrorAction Stop)

    Write-Verbose "Found $($foundPackages.Count) potential package(s)"

    $candidateQueue = New-Object System.Collections.Queue
    foreach ($candidate in $foundPackages) {
        $candidateQueue.Enqueue($candidate)
    }
    $exactFallbackApp = if (-not $VersionSource -and ($App -match '^([^.]+)\.(.+)$' -or $App -match '^([^/]+)/(.+)$')) {
        $App
    } else {
        $null
    }

    # Process each found package
    while ($candidateQueue.Count -gt 0) {
        $package = $candidateQueue.Dequeue()
        Write-Verbose "Processing package: $($package.PackageId)"

        # Resolve the package leaf before processing it. Only this phase may
        # reinterpret an exact-looking display name as a broad search.
        Write-Verbose "Retrieving version folders..."
        try {
            $versionDirs = @(Get-WingetPackageVersionEntry -Path $package.Path -PackageIdentifier $package.PackageId -ErrorAction Stop)
        } catch {
            if ($exactFallbackApp -and
                ($_.Exception -is [System.Management.Automation.ItemNotFoundException] -or
                    $_.Exception -is [System.IO.InvalidDataException])) {
                $searchApp = $exactFallbackApp
                $exactFallbackApp = $null
                $notFoundCause = $_.Exception
                if ($env:GITHUB_TOKEN) {
                    foreach ($candidate in @(Search-WingetPackage -App $searchApp -ErrorAction Stop)) {
                        $candidateQueue.Enqueue($candidate)
                    }
                }
                continue
            }

            if (-not $firstError) {
                $firstError = $_
            }
            Write-Warning "Error processing package $($package.PackageId): $_"
            Write-Verbose "Full error: $($_.Exception.Message)"
            continue
        }
        $exactFallbackApp = $null

        try {
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
            $sortedVersions = @($versionDirs |
                Where-Object { $_.type -eq 'dir' -and $_.name -notmatch $ignoreFolders } |
                Sort-Object -Property @{
                Expression = {
                    # Extract the numeric prefix (e.g. "1.2.69.448" from "1.2.69.448.ge76b8882")
                    if ($_.name -match '^([\d]+(?:\.[\d]+)*)') {
                        # [Version] supports at most four components. Build a lexical key
                        # whose component lengths and values preserve numeric ordering.
                        ($Matches[1] -split '\.' | ForEach-Object {
                            $component = $_.TrimStart('0')
                            if ($component.Length -eq 0) {
                                $component = '0'
                            }
                            '{0:D10}:{1}' -f $component.Length, $component
                        }) -join '.'
                    } else {
                        # No leading numeric portion: sort by raw name
                        $_.name
                    }
                }
            } -Descending)

            if (-not $sortedVersions -or $sortedVersions.Count -eq 0) {
                Write-Verbose "No valid versions found for $($package.PackageId)"
                continue
            }

            $latestVersion = $sortedVersions[0]
            Write-Verbose "Latest version: $($latestVersion.name)"

            # Starting from the most recent version, find the first with a valid installer manifest
            $installerManifest = $null
            $defaultManifest = $null
            $localeManifest = $null
            $versionContentError = $null
            for ($i = 0; $i -lt $sortedVersions.Count; $i++) {

                $checkVersion = $sortedVersions[$i]
                Write-Verbose "Checking version: $($checkVersion.name)"

                # Get manifest files for the latest version
                $versionPath = $package.Path + "/" + $checkVersion.name
                Write-Verbose "Fetching installer manifest: $versionPath/$($package.PackageId).installer.yaml"

                try {
                    $manifestContent = Get-GitHubContent -OwnerName $script:WinGetRepoOwner -RepositoryName $script:WinGetRepoName -Path $versionPath -ErrorAction Stop
                    $manifestFiles = @($manifestContent.Entries)
                } catch {
                    if (-not $versionContentError) {
                        $versionContentError = $_
                    }
                    Write-Verbose "Could not read version directory $versionPath`: $_"
                    continue
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
                if ($versionContentError) {
                    throw $versionContentError
                }
                Write-Warning "Package '$($package.PackageId)' exists but no version has a valid installer manifest."
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

            # Build metadata from locale (preferred) or default manifest
            $metadataFields = @(
                'PackageName', 'Publisher', 'PublisherUrl', 'PublisherSupportUrl',
                'PrivacyUrl', 'Author', 'License', 'LicenseUrl',
                'Copyright', 'CopyrightUrl', 'ShortDescription', 'Description',
                'Moniker', 'Tags', 'ReleaseNotes', 'ReleaseNotesUrl'
            )
            $metadataProps = [ordered]@{
                PackageIdentifier = $installerData.PackageIdentifier
                PackageVersion    = $installerData.PackageVersion
            }
            foreach ($field in $metadataFields) {
                $metadataProps[$field] = if ($localeData[$field]) { $localeData[$field] }
                                         elseif ($packageData[$field]) { $packageData[$field] }
                                         else { $null }
            }
            $metadataProps['Installers'] = @()
            $result = [PSCustomObject]$metadataProps
            if (-not $result.Tags) { $result.Tags = @() }

            # Process installers
            $installers = if ($installerData.Installers) { $installerData.Installers } else { @($installerData) }
            Write-Verbose "Found $($installers.Count) installers in manifest"

            $installerObjects = [System.Collections.Generic.List[object]]::new()
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
                $installerObjects.Add($installerObj)
            }

            # Add installers to result
            $result.Installers = $installerObjects

            Set-CacheItem -Key $cacheKey -Data $result
            return $result

        } catch {
            if (-not $firstError) {
                $firstError = $_
            }
            Write-Warning "Error processing package $($package.PackageId): $_"
            Write-Verbose "Full error: $($_.Exception.Message)"
            continue
        }
    }

    if ($firstError) {
        $PSCmdlet.ThrowTerminatingError($firstError)
    }

    $exception = [System.Management.Automation.ItemNotFoundException]::new("Package not found: $App", $notFoundCause)
    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $exception,
        'PackageNotFound',
        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
        $App
    )
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}
