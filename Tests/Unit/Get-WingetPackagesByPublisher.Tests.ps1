#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'TestHelper.ps1')
}

Describe 'Get-WingetPackagesByPublisher' {
    BeforeEach {
        Mock Get-CacheItem { $null } -ModuleName WinGetManifestFetcher
        Mock Set-CacheItem -ModuleName WinGetManifestFetcher
        Mock Resolve-WingetPublisher {
            [PSCustomObject]@{ Name = 'Python'; Path = 'manifests/p/Python'; Sha = 'python-sha' }
        } -ModuleName WinGetManifestFetcher
        Mock Get-WingetPublisherPackagePath {
            @('Python/3.12', 'Python/3.13')
        } -ModuleName WinGetManifestFetcher
    }

    It 'maps the canonical publisher and package-path contracts to results' {
        $result = Get-WingetPackagesByPublisher Python

        $result.PackageIdentifier | Should -Be @('Python.Python.3.12', 'Python.Python.3.13')
        Should -Invoke Resolve-WingetPublisher -Times 1 -Exactly -ModuleName WinGetManifestFetcher
        Should -Invoke Get-WingetPublisherPackagePath -Times 1 -Exactly -ModuleName WinGetManifestFetcher -ParameterFilter {
            $PublisherSha -eq 'python-sha' -and $MaxResults -eq 0
        }
        Should -Invoke Set-CacheItem -Times 1 -Exactly -ModuleName WinGetManifestFetcher
    }

    It 'passes the remaining result limit to package enumeration' {
        Mock Get-WingetPublisherPackagePath { @('App1', 'App2') } -ModuleName WinGetManifestFetcher

        Get-WingetPackagesByPublisher Python -MaxResults 2 | Should -HaveCount 2

        Should -Invoke Get-WingetPublisherPackagePath -Times 1 -Exactly -ModuleName WinGetManifestFetcher -ParameterFilter {
            $MaxResults -eq 2
        }
    }

    It 'adds latest versions when requested' {
        Mock Get-WingetPublisherPackagePath { @('App') } -ModuleName WinGetManifestFetcher
        Mock Get-LatestWingetVersion {
            [PSCustomObject]@{ PackageVersion = '1.0' }
        } -ModuleName WinGetManifestFetcher

        $result = Get-WingetPackagesByPublisher Python -IncludeVersions

        $result.LatestVersion | Should -Be '1.0'
        Should -Invoke Get-LatestWingetVersion -Times 1 -Exactly -ModuleName WinGetManifestFetcher
    }

    It 'returns cached packages without resolving publishers' {
        Mock Get-CacheItem {
            [PSCustomObject]@{ PackageIdentifier = 'Python.Python.3.13' }
        } -ModuleName WinGetManifestFetcher

        (Get-WingetPackagesByPublisher Python).PackageIdentifier | Should -Be 'Python.Python.3.13'
        Should -Invoke Resolve-WingetPublisher -Times 0 -Exactly -ModuleName WinGetManifestFetcher
    }

    It 'preserves resolver failures without caching' {
        Mock Resolve-WingetPublisher { throw 'API rate limit exceeded' } -ModuleName WinGetManifestFetcher

        { Get-WingetPackagesByPublisher Python -ErrorAction Stop } | Should -Throw '*API rate limit exceeded*'
        Should -Invoke Set-CacheItem -Times 0 -Exactly -ModuleName WinGetManifestFetcher
    }
}

Describe 'Publisher resolution' {
    BeforeEach {
        Mock Get-WingetGitHubTreeSha { 'manifests-sha' } -ModuleName WinGetManifestFetcher
    }

    It 'resolves an exact publisher directly from its numeric shard' {
        Mock Get-WingetGitHubTree {
            param($TreeReference)
            switch ($TreeReference) {
                'manifests-sha' { [PSCustomObject]@{ Entries = @(@{ type = 'tree'; path = '7'; sha = '7-sha' }); Truncated = $false } }
                '7-sha' { [PSCustomObject]@{ Entries = @(@{ type = 'tree'; path = '7zip'; sha = '7zip-sha' }); Truncated = $false } }
                default { throw "Unexpected tree: $TreeReference" }
            }
        } -ModuleName WinGetManifestFetcher

        $result = InModuleScope WinGetManifestFetcher { Resolve-WingetPublisher -Publisher 7zip }

        $result.Name | Should -Be '7zip'
        $result.Sha | Should -Be '7zip-sha'
        Should -Invoke Get-WingetGitHubTree -Times 2 -Exactly -ModuleName WinGetManifestFetcher
    }

    It 'searches every numeric and letter shard for partial matches' {
        Mock Get-WingetGitHubTree {
            param($TreeReference)
            switch ($TreeReference) {
                'manifests-sha' { [PSCustomObject]@{ Entries = @(
                    @{ type = 'tree'; path = '7'; sha = '7-sha' }
                    @{ type = 'tree'; path = 'p'; sha = 'p-sha' }
                ); Truncated = $false } }
                '7-sha' { [PSCustomObject]@{ Entries = @(@{ type = 'tree'; path = 'SevenLabs'; sha = 'seven-sha' }); Truncated = $false } }
                'p-sha' { [PSCustomObject]@{ Entries = @(@{ type = 'tree'; path = 'ProjectSeven'; sha = 'project-sha' }); Truncated = $false } }
                default { throw "Unexpected tree: $TreeReference" }
            }
        } -ModuleName WinGetManifestFetcher

        $result = InModuleScope WinGetManifestFetcher {
            $oldToken = $env:GITHUB_TOKEN
            try {
                $env:GITHUB_TOKEN = 'test-token'
                @(Resolve-WingetPublisher -Publisher Seven)
            } finally {
                $env:GITHUB_TOKEN = $oldToken
            }
        }

        $result.Name | Should -Be @('SevenLabs', 'ProjectSeven')
        Should -Invoke Get-WingetGitHubTree -Times 3 -Exactly -ModuleName WinGetManifestFetcher
    }

    It 'treats wildcard metacharacters as literal publisher text' {
        Mock Get-WingetGitHubTree {
            param($TreeReference)
            switch ($TreeReference) {
                'manifests-sha' { [PSCustomObject]@{ Entries = @(@{ type = 'tree'; path = 'a'; sha = 'a-sha' }); Truncated = $false } }
                'a-sha' { [PSCustomObject]@{ Entries = @(@{ type = 'tree'; path = 'Acme[Tools'; sha = 'acme-sha' }); Truncated = $false } }
                default { throw "Unexpected tree: $TreeReference" }
            }
        } -ModuleName WinGetManifestFetcher

        $result = InModuleScope WinGetManifestFetcher {
            $oldToken = $env:GITHUB_TOKEN
            try {
                $env:GITHUB_TOKEN = 'test-token'
                @(Resolve-WingetPublisher -Publisher '[Tools')
            } finally {
                $env:GITHUB_TOKEN = $oldToken
            }
        }

        $result.Name | Should -Be 'Acme[Tools'
    }

    It 'requires authentication before a complete partial search' {
        Mock Get-WingetGitHubTree {
            param($TreeReference)
            if ($TreeReference -eq 'manifests-sha') {
                return [PSCustomObject]@{ Entries = @(@{ type = 'tree'; path = 'p'; sha = 'p-sha' }); Truncated = $false }
            }
            [PSCustomObject]@{ Entries = @(); Truncated = $false }
        } -ModuleName WinGetManifestFetcher

        InModuleScope WinGetManifestFetcher {
            $oldToken = $env:GITHUB_TOKEN
            try {
                Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
                { Resolve-WingetPublisher -Publisher Missing -ErrorAction Stop } | Should -Throw '*requires GITHUB_TOKEN*'
            } finally {
                $env:GITHUB_TOKEN = $oldToken
            }
        }
    }
}

Describe 'Publisher package-path enumeration' {
    It 'uses lazy non-recursive traversal and stops at MaxResults' {
        Mock Get-WingetGitHubTree {
            param($TreeReference, $Recursive)
            if ($Recursive) { throw 'Bounded traversal must not request a recursive snapshot' }
            switch ($TreeReference) {
                'publisher-sha' { [PSCustomObject]@{ Truncated = $false; Entries = @(
                    @{ type = 'tree'; path = 'App1'; sha = 'app1-sha' }
                    @{ type = 'tree'; path = 'App2'; sha = 'app2-sha' }
                ) } }
                'app1-sha' { [PSCustomObject]@{ Truncated = $false; Entries = @(@{ type = 'tree'; path = '1.0'; sha = 'version1-sha' }) } }
                'version1-sha' { [PSCustomObject]@{ Truncated = $false; Entries = @(@{ type = 'blob'; path = 'Publisher.App1.yaml' }) } }
                default { throw "Unexpected tree: $TreeReference" }
            }
        } -ModuleName WinGetManifestFetcher

        $paths = InModuleScope WinGetManifestFetcher { @(Get-WingetPublisherPackagePath -PublisherSha publisher-sha -MaxResults 1) }

        $paths | Should -Be 'App1'
        Should -Invoke Get-WingetGitHubTree -Times 3 -Exactly -ModuleName WinGetManifestFetcher -ParameterFilter { -not $Recursive }
        Should -Invoke Get-WingetGitHubTree -Times 0 -Exactly -ModuleName WinGetManifestFetcher -ParameterFilter { $TreeReference -eq 'app2-sha' }
    }

    It 'uses one complete recursive snapshot when available' {
        Mock Get-WingetGitHubTree {
            [PSCustomObject]@{
                Truncated = $false
                Entries = @(
                    @{ type = 'blob'; path = 'Python/3.12/3.12.10/Python.Python.3.12.yaml' }
                    @{ type = 'blob'; path = 'Python/3.13/3.13.7/Python.Python.3.13.yaml' }
                )
            }
        } -ModuleName WinGetManifestFetcher

        $paths = InModuleScope WinGetManifestFetcher { @(Get-WingetPublisherPackagePath -PublisherSha publisher-sha) }

        $paths | Should -Be @('Python/3.12', 'Python/3.13')
        Should -Invoke Get-WingetGitHubTree -Times 1 -Exactly -ModuleName WinGetManifestFetcher -ParameterFilter { $Recursive }
    }

    It 'falls back to path-aware non-recursive traversal when the snapshot is truncated' {
        Mock Get-WingetGitHubTree {
            param($TreeReference, $Recursive)
            if ($Recursive) { return [PSCustomObject]@{ Truncated = $true; Entries = @() } }
            switch ($TreeReference) {
                'publisher-sha' { [PSCustomObject]@{ Truncated = $false; Entries = @(@{ type = 'tree'; path = 'App'; sha = 'app-sha' }) } }
                'app-sha' { [PSCustomObject]@{ Truncated = $false; Entries = @(@{ type = 'tree'; path = '1.0'; sha = 'version-sha' }) } }
                'version-sha' { [PSCustomObject]@{ Truncated = $false; Entries = @(@{ type = 'blob'; path = 'Publisher.App.yaml' }) } }
                default { throw "Unexpected tree: $TreeReference" }
            }
        } -ModuleName WinGetManifestFetcher

        $paths = InModuleScope WinGetManifestFetcher { @(Get-WingetPublisherPackagePath -PublisherSha publisher-sha) }

        $paths | Should -Be 'App'
        Should -Invoke Get-WingetGitHubTree -Times 4 -Exactly -ModuleName WinGetManifestFetcher
    }
}

AfterAll {
    Remove-Module WinGetManifestFetcher -Force -ErrorAction SilentlyContinue
}
