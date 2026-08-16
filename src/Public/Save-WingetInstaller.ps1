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
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, Position = 0)]
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
    
    Write-Verbose "Getting package information for '$App'..."
    $package = Get-LatestWingetVersion -App $App -ErrorAction Stop
    if (-not $package.Installers) {
        Write-Error -Exception ([System.Exception]::new("No installers found for package '$App'")) -ErrorId NoInstallersFound -Category ObjectNotFound -TargetObject $App -ErrorAction Stop
    }

    $availableInstallers = @($package.Installers)
    if ($Architecture) {
        $availableInstallers = @($availableInstallers | Where-Object { $_.Architecture -eq $Architecture })
        if ($availableInstallers.Count -eq 0) {
            Write-Error -Exception ([System.Exception]::new("No installer found for architecture '$Architecture'")) -ErrorId ArchitectureNotFound -Category ObjectNotFound -TargetObject $Architecture -ErrorAction Stop
        }
    }
    if ($InstallerType) {
        $availableInstallers = @($availableInstallers | Where-Object { $_.InstallerType -eq $InstallerType })
        if ($availableInstallers.Count -eq 0) {
            Write-Error -Exception ([System.Exception]::new("No installer found for type '$InstallerType'")) -ErrorId InstallerTypeNotFound -Category ObjectNotFound -TargetObject $InstallerType -ErrorAction Stop
        }
    }

    $installer = $availableInstallers | Sort-Object @{ Expression = {
        switch ($_.Architecture) { 'x64' { 0 }; 'x86' { 1 }; default { 2 } }
    } } | Select-Object -First 1
    $uri = [Uri]$installer.InstallerUrl
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne [Uri]::UriSchemeHttps) {
        Write-Error -Exception ([System.Security.SecurityException]::new("Installer URL must use HTTPS: $($installer.InstallerUrl)")) -ErrorId InsecureInstallerUrl -Category SecurityError -TargetObject $installer.InstallerUrl -ErrorAction Stop
    }
    if (-not $SkipHashValidation -and [string]::IsNullOrWhiteSpace($installer.InstallerSha256)) {
        Write-Error -Exception ([System.Security.SecurityException]::new('Installer manifest does not provide a SHA256 hash. Use -SkipHashValidation to download without verification.')) -ErrorId InstallerHashMissing -Category SecurityError -TargetObject $installer.InstallerUrl -ErrorAction Stop
    }

    $filename = [IO.Path]::GetFileName($uri.LocalPath)
    if (-not [IO.Path]::GetExtension($filename)) {
        $extension = switch ($installer.InstallerType) {
            'msi' { '.msi' }
            'msix' { '.msix' }
            'zip' { '.zip' }
            default { '.exe' }
        }
        $filename = "$($package.PackageIdentifier)_$($package.PackageVersion)_$($installer.Architecture)$extension"
    }

    $destinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $outputPath = Join-Path -Path $destinationPath -ChildPath $filename
    if ((Test-Path -LiteralPath $outputPath) -and -not $Force) {
        Write-Error -Exception ([IO.IOException]::new("File already exists: $outputPath. Use -Force to overwrite.")) -ErrorId FileExists -Category ResourceExists -TargetObject $outputPath -ErrorAction Stop
    }

    if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($destinationPath, 'Create directory')) {
            $null = New-Item -ItemType Directory -Path $destinationPath -Force
        } elseif (-not $WhatIfPreference) {
            return
        }
    }
    if (-not $PSCmdlet.ShouldProcess($installer.InstallerUrl, "Download to $outputPath")) {
        return
    }

    $temporaryPath = Join-Path -Path $destinationPath -ChildPath ".$filename.$([Guid]::NewGuid().ToString('N')).download"
    try {
        try {
            if (Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue) {
                Start-BitsTransfer -Source $installer.InstallerUrl -Destination $temporaryPath -Description "Downloading $($package.PackageName)"
            } else {
                Invoke-WebRequest -Uri $installer.InstallerUrl -OutFile $temporaryPath -UseBasicParsing
            }
        } catch {
            Write-Error -Exception $_.Exception -ErrorId DownloadFailed -Category ConnectionError -TargetObject $installer.InstallerUrl -ErrorAction Stop
        }

        if ($SkipHashValidation) {
            Write-Warning 'Hash validation skipped. The file integrity has not been verified.'
        } else {
            $actualHash = (Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash
            if ($actualHash -ne $installer.InstallerSha256) {
                Write-Error -Exception ([System.Security.SecurityException]::new("Hash verification failed. Expected: $($installer.InstallerSha256), Actual: $actualHash")) -ErrorId HashMismatch -Category SecurityError -TargetObject $temporaryPath -ErrorAction Stop
            }
        }

        Complete-WingetAtomicFileWrite -TemporaryPath $temporaryPath -DestinationPath $outputPath -ReplaceExisting:$Force
        $temporaryPath = $null
        if ($PassThru) {
            Get-Item -LiteralPath $outputPath | Add-Member -MemberType NoteProperty -Name PackageId -Value $package.PackageIdentifier -PassThru |
                Add-Member -MemberType NoteProperty -Name PackageVersion -Value $package.PackageVersion -PassThru |
                Add-Member -MemberType NoteProperty -Name Architecture -Value $installer.Architecture -PassThru |
                Add-Member -MemberType NoteProperty -Name InstallerType -Value $installer.InstallerType -PassThru |
                Add-Member -MemberType NoteProperty -Name HashVerified -Value (-not $SkipHashValidation) -PassThru
        }
    } finally {
        if ($temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}
