#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'TestHelper.ps1')
}

Describe 'Save-WingetInstaller' {
    BeforeEach {
        Mock Get-LatestWingetVersion {
            [PSCustomObject]@{
                PackageIdentifier = '7zip.7zip'
                PackageName = '7-Zip'
                PackageVersion = '23.01'
                Installers = @(
                    [PSCustomObject]@{
                        Architecture = 'x64'
                        InstallerType = 'exe'
                        InstallerUrl = 'https://example.test/7z-x64.exe'
                        InstallerSha256 = '9F64A747E1B97F131FABB6B447296C9B6F0201E79FB3C5356E6C77E89B6A806A'
                    }
                    [PSCustomObject]@{
                        Architecture = 'x86'
                        InstallerType = 'msi'
                        InstallerUrl = 'https://example.test/7z-x86.msi'
                        InstallerSha256 = '9F64A747E1B97F131FABB6B447296C9B6F0201E79FB3C5356E6C77E89B6A806A'
                    }
                )
            }
        } -ModuleName WinGetManifestFetcher
        Mock Get-Command { $null } -ModuleName WinGetManifestFetcher -ParameterFilter { $Name -eq 'Start-BitsTransfer' }
        Mock Invoke-WebRequest {
            [IO.File]::WriteAllBytes($OutFile, [byte[]](1, 2, 3, 4))
        } -ModuleName WinGetManifestFetcher
    }

    It 'exposes the supported parameter contract' {
        $command = Get-Command Save-WingetInstaller

        $command.Parameters.App.Attributes.Mandatory | Should -BeTrue
        $command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        $architecture = $command.Parameters.Architecture.Attributes |
            Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] }
        $architecture.ValidValues | Should -Be @('x64', 'x86', 'arm64', 'arm', 'neutral')
    }

    It 'stages, validates, and commits real bytes to a new destination' {
        $destination = Join-Path $TestDrive 'downloads'

        $result = Save-WingetInstaller 7zip.7zip -Path $destination -PassThru

        $result.FullName | Should -Be (Join-Path $destination '7z-x64.exe')
        $result.PackageId | Should -Be '7zip.7zip'
        $result.PackageVersion | Should -Be '23.01'
        $result.Architecture | Should -Be 'x64'
        $result.HashVerified | Should -BeTrue
        [IO.File]::ReadAllBytes($result.FullName) | Should -Be ([byte[]](1, 2, 3, 4))
        @(Get-ChildItem $destination -Filter '*.download' -Force) | Should -HaveCount 0
    }

    It 'selects the requested architecture and installer type' {
        $result = Save-WingetInstaller 7zip.7zip -Path $TestDrive -Architecture x86 -InstallerType msi -PassThru

        $result.Name | Should -Be '7z-x86.msi'
        $result.Architecture | Should -Be 'x86'
        $result.InstallerType | Should -Be 'msi'
    }

    It 'preserves PackageNotFound without creating the destination' {
        $destination = Join-Path $TestDrive 'missing-package'
        Mock Get-LatestWingetVersion {
            $exception = [Management.Automation.ItemNotFoundException]::new("Package 'Missing.Package' not found")
            throw [Management.Automation.ErrorRecord]::new(
                $exception,
                'PackageNotFound',
                [Management.Automation.ErrorCategory]::ObjectNotFound,
                'Missing.Package'
            )
        } -ModuleName WinGetManifestFetcher

        $failure = try { Save-WingetInstaller Missing.Package -Path $destination -ErrorAction Stop } catch { $_ }

        $failure.FullyQualifiedErrorId | Should -BeLike 'PackageNotFound*'
        Test-Path $destination | Should -BeFalse
    }

    It 'reports NoInstallersFound without creating the destination' {
        $destination = Join-Path $TestDrive 'no-installers'
        Mock Get-LatestWingetVersion { [PSCustomObject]@{ Installers = @() } } -ModuleName WinGetManifestFetcher

        $failure = try { Save-WingetInstaller Test.Empty -Path $destination -ErrorAction Stop } catch { $_ }

        $failure.FullyQualifiedErrorId | Should -BeLike 'NoInstallersFound*'
        Test-Path $destination | Should -BeFalse
    }

    It 'preserves the architecture error identity' {
        $destination = Join-Path $TestDrive 'bad-architecture'

        $failure = try { Save-WingetInstaller 7zip.7zip -Path $destination -Architecture arm64 -ErrorAction Stop } catch { $_ }

        $failure.FullyQualifiedErrorId | Should -BeLike 'ArchitectureNotFound*'
        Test-Path $destination | Should -BeFalse
    }

    It 'preserves the installer-type error identity' {
        $destination = Join-Path $TestDrive 'bad-type'

        $failure = try { Save-WingetInstaller 7zip.7zip -Path $destination -InstallerType zip -ErrorAction Stop } catch { $_ }

        $failure.FullyQualifiedErrorId | Should -BeLike 'InstallerTypeNotFound*'
        Test-Path $destination | Should -BeFalse
    }

    It 'rejects HTTP before creating the destination or downloading' {
        $destination = Join-Path $TestDrive 'insecure'
        Mock Get-LatestWingetVersion {
            [PSCustomObject]@{ Installers = @([PSCustomObject]@{
                Architecture = 'x64'; InstallerType = 'exe'
                InstallerUrl = 'http://example.test/app.exe'; InstallerSha256 = 'AA'
            }) }
        } -ModuleName WinGetManifestFetcher

        $failure = try { Save-WingetInstaller Test.Insecure -Path $destination -ErrorAction Stop } catch { $_ }

        $failure.FullyQualifiedErrorId | Should -BeLike 'InsecureInstallerUrl*'
        Test-Path $destination | Should -BeFalse
        Should -Invoke Invoke-WebRequest -ModuleName WinGetManifestFetcher -Times 0
    }

    It 'requires a manifest hash before creating the destination' {
        $destination = Join-Path $TestDrive 'missing-hash'
        Mock Get-LatestWingetVersion {
            [PSCustomObject]@{ Installers = @([PSCustomObject]@{
                Architecture = 'x64'; InstallerType = 'exe'
                InstallerUrl = 'https://example.test/app.exe'; InstallerSha256 = $null
            }) }
        } -ModuleName WinGetManifestFetcher

        $failure = try { Save-WingetInstaller Test.NoHash -Path $destination -ErrorAction Stop } catch { $_ }

        $failure.FullyQualifiedErrorId | Should -BeLike 'InstallerHashMissing*'
        Test-Path $destination | Should -BeFalse
        Should -Invoke Invoke-WebRequest -ModuleName WinGetManifestFetcher -Times 0
    }

    It 'does not replace an existing file without Force' {
        $destination = Join-Path $TestDrive 'existing'
        $null = New-Item -ItemType Directory -Path $destination
        $target = Join-Path $destination '7z-x64.exe'
        [IO.File]::WriteAllText($target, 'original')

        $failure = try { Save-WingetInstaller 7zip.7zip -Path $destination -ErrorAction Stop } catch { $_ }

        $failure.FullyQualifiedErrorId | Should -BeLike 'FileExists*'
        [IO.File]::ReadAllText($target) | Should -Be 'original'
        Should -Invoke Invoke-WebRequest -ModuleName WinGetManifestFetcher -Times 0
    }

    It 'atomically replaces an existing file with Force and completes backup cleanup' {
        $destination = Join-Path $TestDrive 'forced-replacement'
        $null = New-Item -ItemType Directory -Path $destination
        $target = Join-Path $destination '7z-x64.exe'
        [IO.File]::WriteAllText($target, 'original')

        $result = Save-WingetInstaller 7zip.7zip -Path $destination -Force -PassThru

        $result.FullName | Should -Be $target
        [IO.File]::ReadAllBytes($target) | Should -Be ([byte[]](1, 2, 3, 4))
        @(Get-ChildItem $destination -Filter '*.download' -Force) | Should -HaveCount 0
        @(Get-ChildItem $destination -Filter '*.bak' -Force) | Should -HaveCount 0
    }

    It 'preserves an existing file when forced validation fails' {
        $destination = Join-Path $TestDrive 'forced-mismatch'
        $null = New-Item -ItemType Directory -Path $destination
        $target = Join-Path $destination '7z-x64.exe'
        [IO.File]::WriteAllText($target, 'original')
        Mock Get-FileHash { [PSCustomObject]@{ Hash = 'WRONG' } } -ModuleName WinGetManifestFetcher

        $failure = try { Save-WingetInstaller 7zip.7zip -Path $destination -Force -ErrorAction Stop } catch { $_ }

        $failure.FullyQualifiedErrorId | Should -BeLike 'HashMismatch*'
        [IO.File]::ReadAllText($target) | Should -Be 'original'
        @(Get-ChildItem $destination -Filter '*.download' -Force) | Should -HaveCount 0
    }

    It 'preserves an existing file and cleans staged bytes when a forced commit fails' {
        $destination = Join-Path $TestDrive 'forced-commit-failure'
        $null = New-Item -ItemType Directory -Path $destination
        $target = Join-Path $destination '7z-x64.exe'
        [IO.File]::WriteAllText($target, 'original')
        Mock Complete-WingetAtomicFileWrite {
            param($TemporaryPath, $DestinationPath, $ReplaceExisting)
            [IO.File]::Exists($TemporaryPath) | Should -BeTrue
            [IO.File]::ReadAllText($DestinationPath) | Should -Be 'original'
            $ReplaceExisting | Should -BeTrue
            throw 'commit failed'
        } -ModuleName WinGetManifestFetcher

        { Save-WingetInstaller 7zip.7zip -Path $destination -Force -ErrorAction Stop } | Should -Throw '*commit failed*'

        [IO.File]::ReadAllText($target) | Should -Be 'original'
        @(Get-ChildItem $destination -Filter '*.download' -Force) | Should -HaveCount 0
    }

    It 'cleans staged bytes and reports DownloadFailed after a network error' {
        $destination = Join-Path $TestDrive 'download-failure'
        Mock Invoke-WebRequest { throw 'network unavailable' } -ModuleName WinGetManifestFetcher

        $failure = try { Save-WingetInstaller 7zip.7zip -Path $destination -ErrorAction Stop } catch { $_ }

        $failure.FullyQualifiedErrorId | Should -BeLike 'DownloadFailed*'
        @(Get-ChildItem $destination -Force) | Should -HaveCount 0
    }

    It 'cleans staged bytes when hash calculation fails' {
        $destination = Join-Path $TestDrive 'hash-failure'
        Mock Get-FileHash { throw 'hash read error' } -ModuleName WinGetManifestFetcher

        { Save-WingetInstaller 7zip.7zip -Path $destination -ErrorAction Stop } | Should -Throw '*hash read error*'
        @(Get-ChildItem $destination -Force) | Should -HaveCount 0
    }

    It 'allows an explicitly unverified download' {
        $destination = Join-Path $TestDrive 'skip-hash'
        Mock Get-LatestWingetVersion {
            [PSCustomObject]@{
                PackageIdentifier = 'Test.NoHash'; PackageName = 'No Hash'; PackageVersion = '1.0'
                Installers = @([PSCustomObject]@{
                    Architecture = 'x64'; InstallerType = 'exe'
                    InstallerUrl = 'https://example.test/app.exe'; InstallerSha256 = $null
                })
            }
        } -ModuleName WinGetManifestFetcher

        $result = Save-WingetInstaller Test.NoHash -Path $destination -SkipHashValidation -PassThru -WarningVariable warnings

        $result.HashVerified | Should -BeFalse
        $warnings.Message | Should -BeLike '*Hash validation skipped*'
        Test-Path $result.FullName | Should -BeTrue
    }

    It 'honors WhatIf without creating or downloading' {
        $destination = Join-Path $TestDrive 'what-if'

        Save-WingetInstaller 7zip.7zip -Path $destination -WhatIf

        Test-Path $destination | Should -BeFalse
        Should -Invoke Invoke-WebRequest -ModuleName WinGetManifestFetcher -Times 0
    }
}

AfterAll {
    Remove-Module WinGetManifestFetcher -Force -ErrorAction SilentlyContinue
}
