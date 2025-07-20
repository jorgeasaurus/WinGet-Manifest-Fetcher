function Save-WingetInstaller {
    <#
    .SYNOPSIS
        Downloads a WinGet package installer with hash verification.
    
    .DESCRIPTION
        Downloads the installer file for a specified WinGet package and verifies its integrity
        using the SHA256 hash from the manifest. Supports filtering by architecture and installer type.
    
    .PARAMETER App
        The package identifier (e.g., 'Microsoft.PowerToys', '7zip.7zip').
    
    .PARAMETER Path
        The directory where the installer should be saved. Defaults to current directory.
    
    .PARAMETER Architecture
        The architecture to download (e.g., 'x64', 'x86', 'arm64'). If not specified, 
        prefers x64, then x86, then arm64.
    
    .PARAMETER InstallerType
        The installer type to download (e.g., 'exe', 'msi', 'msix'). If not specified,
        downloads the first available installer.
    
    .PARAMETER Force
        Overwrites existing files without prompting.
    
    .PARAMETER SkipHashValidation
        Skips SHA256 hash validation. Not recommended unless necessary.
    
    .PARAMETER PassThru
        Returns the downloaded file information.
    
    .EXAMPLE
        Save-WingetInstaller -App 'Microsoft.PowerToys'
        Downloads the latest PowerToys installer to the current directory.
    
    .EXAMPLE
        Save-WingetInstaller -App '7zip.7zip' -Path 'C:\Downloads' -Architecture 'x64'
        Downloads the x64 version of 7-Zip to C:\Downloads.
    
    .EXAMPLE
        Save-WingetInstaller -App 'Git.Git' -InstallerType 'exe' -PassThru
        Downloads the EXE installer for Git and returns the file information.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$App,
        
        [Parameter(Position = 1)]
        [string]$Path = $(Get-Location),
        
        [Parameter()]
        [ValidateSet('x64', 'x86', 'arm64', 'arm', 'neutral')]
        [string]$Architecture,
        
        [Parameter()]
        [string]$InstallerType,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$SkipHashValidation,
        
        [Parameter()]
        [switch]$PassThru
    )
    
    begin {
        # Ensure the target directory exists
        if (-not (Test-Path -Path $Path)) {
            if ($PSCmdlet.ShouldProcess($Path, "Create directory")) {
                New-Item -ItemType Directory -Path $Path -Force | Out-Null
            }
        }
        
        # Get the absolute path
        $Path = Resolve-Path -Path $Path
    }
    
    process {
        try {
            Write-Verbose "Getting package information for '$App'..."
            
            # Get the package information
            $package = Get-LatestWingetVersion -App $App -ErrorAction Stop
            
            if (-not $package) {
                Write-Error "Package '$App' not found"
                return
            }
            
            if (-not $package.Installers -or $package.Installers.Count -eq 0) {
                Write-Error "No installers found for package '$App'"
                return
            }
            
            # Filter installers based on criteria
            $availableInstallers = $package.Installers
            
            # Filter by architecture if specified
            if ($Architecture) {
                $availableInstallers = $availableInstallers | Where-Object { $_.Architecture -eq $Architecture }
                if (-not $availableInstallers) {
                    Write-Error "No installer found for architecture '$Architecture'"
                    return
                }
            }
            
            # Filter by installer type if specified
            if ($InstallerType) {
                $availableInstallers = $availableInstallers | Where-Object { $_.InstallerType -eq $InstallerType }
                if (-not $availableInstallers) {
                    Write-Error "No installer found for type '$InstallerType'"
                    return
                }
            }
            
            # Select the best installer
            $installer = if ($availableInstallers -is [array]) {
                # Prefer x64, then x86, then arm64
                $preferred = $availableInstallers | Where-Object { $_.Architecture -eq 'x64' } | Select-Object -First 1
                if (-not $preferred) {
                    $preferred = $availableInstallers | Where-Object { $_.Architecture -eq 'x86' } | Select-Object -First 1
                }
                if (-not $preferred) {
                    $preferred = $availableInstallers | Select-Object -First 1
                }
                $preferred
            } else {
                $availableInstallers
            }
            
            if (-not $installer) {
                Write-Error "No suitable installer found"
                return
            }
            
            # Construct filename
            $uri = [Uri]$installer.InstallerUrl
            $filename = [System.IO.Path]::GetFileName($uri.LocalPath)
            
            # If no extension in URL, try to determine from installer type
            if (-not [System.IO.Path]::GetExtension($filename)) {
                $extension = switch ($installer.InstallerType) {
                    'exe' { '.exe' }
                    'msi' { '.msi' }
                    'msix' { '.msix' }
                    'zip' { '.zip' }
                    default { '.exe' }
                }
                $filename = "$($package.PackageIdentifier)_$($package.PackageVersion)_$($installer.Architecture)$extension"
            }
            
            $outputPath = Join-Path -Path $Path -ChildPath $filename
            
            # Check if file already exists
            if ((Test-Path -Path $outputPath) -and -not $Force) {
                Write-Error "File already exists: $outputPath. Use -Force to overwrite."
                return
            }
            
            # Download the file
            if ($PSCmdlet.ShouldProcess($installer.InstallerUrl, "Download to $outputPath")) {
                Write-Host "Downloading $($package.PackageName) $($package.PackageVersion) ($($installer.Architecture))..." -ForegroundColor Cyan
                Write-Verbose "URL: $($installer.InstallerUrl)"
                Write-Verbose "Destination: $outputPath"
                
                try {
                    # Use BITS if available (Windows), otherwise use WebClient
                    if (Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue) {
                        Start-BitsTransfer -Source $installer.InstallerUrl -Destination $outputPath -Description "Downloading $($package.PackageName)"
                    } else {
                        $webClient = New-Object System.Net.WebClient
                        $webClient.DownloadFile($installer.InstallerUrl, $outputPath)
                    }
                    
                    Write-Host "Download complete: $outputPath" -ForegroundColor Green
                } catch {
                    Write-Error "Failed to download installer: $_"
                    return
                }
                
                # Verify hash if not skipped
                if (-not $SkipHashValidation -and $installer.InstallerSha256) {
                    Write-Host "Verifying hash..." -ForegroundColor Cyan
                    Write-Verbose "Expected SHA256: $($installer.InstallerSha256)"
                    
                    $actualHash = (Get-FileHash -Path $outputPath -Algorithm SHA256).Hash
                    Write-Verbose "Actual SHA256: $actualHash"
                    
                    if ($actualHash -eq $installer.InstallerSha256) {
                        Write-Host "Hash verification successful" -ForegroundColor Green
                    } else {
                        Write-Error "Hash verification failed! The downloaded file may be corrupted or tampered with."
                        Write-Error "Expected: $($installer.InstallerSha256)"
                        Write-Error "Actual:   $actualHash"
                        
                        # Remove the potentially corrupted file
                        Remove-Item -Path $outputPath -Force
                        return
                    }
                } elseif ($SkipHashValidation) {
                    Write-Warning "Hash validation skipped. The file integrity has not been verified."
                } else {
                    Write-Warning "No hash available in manifest. Cannot verify file integrity."
                }
                
                # Return file info if requested
                if ($PassThru) {
                    Get-Item -Path $outputPath | Add-Member -MemberType NoteProperty -Name 'PackageId' -Value $package.PackageIdentifier -PassThru |
                    Add-Member -MemberType NoteProperty -Name 'PackageVersion' -Value $package.PackageVersion -PassThru |
                    Add-Member -MemberType NoteProperty -Name 'Architecture' -Value $installer.Architecture -PassThru |
                    Add-Member -MemberType NoteProperty -Name 'InstallerType' -Value $installer.InstallerType -PassThru |
                    Add-Member -MemberType NoteProperty -Name 'HashVerified' -Value (-not $SkipHashValidation -and $installer.InstallerSha256) -PassThru
                }
            }
        } catch {
            Write-Error "Error downloading installer: $_"
        }
    }
}