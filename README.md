# WinGet Manifest Fetcher

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/WinGetManifestFetcher)](https://www.powershellgallery.com/packages/WinGetManifestFetcher)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/WinGetManifestFetcher)](https://www.powershellgallery.com/packages/WinGetManifestFetcher)
[![License](https://img.shields.io/github/license/jorgeasaurus/WinGet-Manifest-Fetcher)](LICENSE)

Use this module to retrieve WinGet package metadata and installers from the
[`microsoft/winget-pkgs`](https://github.com/microsoft/winget-pkgs) repository.
You do not need the WinGet client.

## Requirements

- PowerShell 5.1 or later. PowerShell 7 is recommended.
- Internet access to GitHub
- `powershell-yaml` 0.4.0 or later

The PowerShell Gallery package installs the YAML module dependency.

## Install from PowerShell Gallery

```powershell
Install-Module WinGetManifestFetcher -Scope CurrentUser
Import-Module WinGetManifestFetcher
```

## Import from source

Run this command from the repository root:

```powershell
Import-Module ./src/WinGetManifestFetcher.psd1 -Verbose -Force
```

Include `./` and the `.psd1` extension. Without `./`, PowerShell treats the
value as a module name and searches the module directories.

To build and import the packaged artifact:

```powershell
./build.ps1 -Task Build -Bootstrap
Import-Module ./output/WinGetManifestFetcher/WinGetManifestFetcher.psd1
```

## GitHub authentication

Exact package identifiers and repository paths work without authentication.
Broad package-name search requires a token:

```powershell
$env:GITHUB_TOKEN = 'your-token'
Import-Module WinGetManifestFetcher
```

For public repository reads, use a token with the least privilege available.
Never commit a token or write it to logs.

## Commands

| Command | Purpose |
| --- | --- |
| `Get-LatestWingetVersion` | Get package metadata and installer records |
| `Get-WingetPackagesByPublisher` | Find packages by exact or partial publisher name |
| `Save-WingetInstaller` | Download an installer and validate its SHA256 hash |
| `Get-WingetManifestCacheInfo` | Inspect the local cache |
| `Clear-WingetManifestCache` | Remove cached manifests |
| `Set-WingetManifestCacheEnabled` | Enable or disable caching for the session |

Use `Get-Help <command> -Full` for complete parameter documentation.

## Examples

```powershell
# Get the latest package metadata.
$package = Get-LatestWingetVersion -App 'Microsoft.PowerToys'
$package.Installers | Where-Object Architecture -eq 'x64'

# Search by display name (requires GITHUB_TOKEN) or use a known repository path.
Get-LatestWingetVersion -App 'Visual Studio Code'
Get-LatestWingetVersion -App '7zip.7zip' `
    -VersionSource 'manifests/7/7zip/7zip'

# Find packages from a publisher.
Get-WingetPackagesByPublisher -Publisher 'Microsoft' -MaxResults 10
Get-WingetPackagesByPublisher -Publisher 'JetBrains' -IncludeVersions

# Download and return file information.
$file = Save-WingetInstaller -App 'Git.Git' -Architecture x64 `
    -Path ./Downloads -PassThru
$file | Format-List Name, PackageVersion, Architecture, HashVerified

# Preview a download without changing files.
Save-WingetInstaller -App 'Mozilla.Firefox' -WhatIf
```

`Save-WingetInstaller` uses HTTPS. It validates the manifest SHA256 hash before
it places the installer at its final path. Use `-SkipHashValidation` only when
the manifest does not contain a hash.

## Cache

The module caches successful queries for 60 minutes. It removes expired,
invalid, or incompatible entries automatically.

Default locations:

- Windows: `%LOCALAPPDATA%\WinGetManifestFetcher\Cache`
- macOS: `~/Library/Caches/WinGetManifestFetcher`
- Linux: `$XDG_CACHE_HOME/WinGetManifestFetcher` or `~/.cache/WinGetManifestFetcher`

```powershell
Get-WingetManifestCacheInfo
Clear-WingetManifestCache
Clear-WingetManifestCache -Force
Set-WingetManifestCacheEnabled -Enabled $false
Set-WingetManifestCacheEnabled -Enabled $true
```

## Development

```powershell
# Unit tests and enforced coverage threshold
./build.ps1 -Task Test -Bootstrap

# Static analysis and module build
./build.ps1 -Task Analyze,Build -Bootstrap

# Live GitHub integration tests
./build.ps1 -Task Build,Test,Analyze,Integration -Bootstrap
```

### Commit messages

- Write a capitalized, imperative subject. Do not add a final period.
- Limit the subject to approximately 50 characters.
- Add a blank line before an optional body.
- Wrap body text at approximately 72 characters.
- Explain what changed and why. Let the diff show how.
- Put issue references at the end.

Example:

```text
Fix source-module import example

Use an explicit relative path and manifest extension so PowerShell
loads the module from the repository instead of searching PSModulePath.
```

For more information, see
[A Note About Git Commit Messages](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html)
and [How to Write a Git Commit Message](https://cbea.ms/git-commit/).

### Documentation style

- Use active voice and present tense.
- Address the reader as `you`.
- Use the imperative mood for instructions.
- Use short sentences and consistent technical terms.
- Put one action in each procedural step.
- Avoid slang, idioms, and ambiguous words.
- Test each command before you publish it.

These rules apply the clarity principles from
[ASD-STE100 Simplified Technical English](https://www.asd-ste100.org/STE_faq.html)
and the [Google developer documentation style guide](https://developers.google.com/style/).
They do not claim full ASD-STE100 conformance.

## Troubleshooting

- If PowerShell cannot load the source module, include the relative-path marker
  and manifest extension: `./src/WinGetManifestFetcher.psd1`.
- If the module cannot find a package, verify its identifier in `winget-pkgs`.
  Set `GITHUB_TOKEN` before you search with a broad name.
- If GitHub limits your requests, use an exact identifier, set `GITHUB_TOKEN`,
  or supply `-VersionSource`.
- If YAML parsing fails, update `powershell-yaml`. The module skips malformed
  package versions.
- If `YamlDotNet.Core.Parser` fails on Windows ARM64, use Windows PowerShell 5.1.
  This error comes from an upstream `powershell-yaml` compatibility issue.

## License

Licensed under the [MIT License](LICENSE). This independent project is not
affiliated with Microsoft or the official WinGet project.
