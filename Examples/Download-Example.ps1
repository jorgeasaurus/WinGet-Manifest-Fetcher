# Example: Download installers with hash verification

# Import the module
./build.ps1
Import-Module ./output/WinGetManifestFetcher/WinGetManifestFetcher.psd1

# Example 1: Download latest 7-Zip installer
Write-Host "`nExample 1: Downloading 7-Zip installer..." -ForegroundColor Yellow
Save-WingetInstaller -App '7zip.7zip' -Path './Downloads' -Architecture 'x64' -Force

# Example 2: Download Git installer with verbose output
Write-Host "`nExample 2: Downloading Git installer with verbose output..." -ForegroundColor Yellow
Save-WingetInstaller -App 'Git.Git' -Path './Downloads' -Force

# Example 3: Download specific installer type
Write-Host "`nExample 3: Downloading Notepad++ MSI installer..." -ForegroundColor Yellow
Save-WingetInstaller -App 'Notepad++.Notepad++' -Path './Downloads' -InstallerType 'nullsoft' -PassThru

# Example 4: Using WhatIf to preview
Write-Host "`nExample 4: Preview download without actually downloading..." -ForegroundColor Yellow
Save-WingetInstaller -App 'Microsoft.VisualStudioCode' -Path './Downloads' -WhatIf

# Example 5: Skip hash validation (not recommended)
Write-Host "`nExample 5: Download without hash validation..." -ForegroundColor Yellow
Save-WingetInstaller -App 'VideoLAN.VLC' -Path './Downloads' -SkipHashValidation -PassThru

# Show downloaded files
Write-Host "`nDownloaded files:" -ForegroundColor Green
Get-ChildItem -Path './Downloads' | Format-Table Name, Length, LastWriteTime