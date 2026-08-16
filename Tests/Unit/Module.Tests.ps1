#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'TestHelper.ps1')

    if (-not ('WinGetManifestFetcherTests.StatusWebResponse' -as [type])) {
        Add-Type -TypeDefinition @'
namespace WinGetManifestFetcherTests {
    public sealed class StatusWebResponse : System.Net.WebResponse {
        public System.Net.HttpStatusCode StatusCode { get; private set; }
        public StatusWebResponse(System.Net.HttpStatusCode statusCode) { StatusCode = statusCode; }
    }
}
'@
    }
}

Describe 'Module public surface' {
    It 'Exports only the supported commands' {
        $expected = @(
            'Clear-WingetManifestCache'
            'Get-LatestWingetVersion'
            'Get-WingetManifestCacheInfo'
            'Get-WingetPackagesByPublisher'
            'Save-WingetInstaller'
            'Set-WingetManifestCacheEnabled'
        )

        @(Get-Command -Module WinGetManifestFetcher).Name | Sort-Object | Should -Be $expected
    }
}

Describe 'Native GitHub request security' {
    It 'does not mutate process-wide TLS settings per request' {
        InModuleScope WinGetManifestFetcher {
            $originalProtocol = [Net.ServicePointManager]::SecurityProtocol
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls
                $observedProtocol = $null
                Mock Invoke-RestMethod {
                    $script:observedProtocol = [Net.ServicePointManager]::SecurityProtocol
                    @{ ok = $true }
                }

                $null = Invoke-WingetGitHubRequest -UriFragment 'rate_limit'

                $script:observedProtocol | Should -Be ([Net.SecurityProtocolType]::Tls)
                [Net.ServicePointManager]::SecurityProtocol | Should -Be ([Net.SecurityProtocolType]::Tls)
            } finally {
                [Net.ServicePointManager]::SecurityProtocol = $originalProtocol
            }
        }
    }

    It 'translates a PS5 WebException 404 into the stable typed boundary error' {
        InModuleScope WinGetManifestFetcher {
            Mock Invoke-RestMethod {
                $response = [WinGetManifestFetcherTests.StatusWebResponse]::new([Net.HttpStatusCode]::NotFound)
                throw [Net.WebException]::new('arbitrary prose', $null, [Net.WebExceptionStatus]::ProtocolError, $response)
            }

            $failure = try { Invoke-WingetGitHubRequest -UriFragment 'missing' } catch { $_ }

            $failure.Exception | Should -BeOfType ([System.Management.Automation.ItemNotFoundException])
            $failure.FullyQualifiedErrorId | Should -BeLike 'WingetGitHubItemNotFound*'
        }
    }

    It 'reads status from a PS7 HttpResponseException' {
        InModuleScope WinGetManifestFetcher {
            $exceptionType = 'Microsoft.PowerShell.Commands.HttpResponseException' -as [type]
            if ($exceptionType) {
                $response = [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::NotFound)
                $exception = [Activator]::CreateInstance($exceptionType, @('arbitrary prose', $response))

                Get-WingetHttpStatusCode -Exception $exception | Should -Be 404
            }
        }
    }

    It 'preserves non-404 HTTP failures unchanged' {
        InModuleScope WinGetManifestFetcher {
            Mock Invoke-RestMethod {
                $response = [WinGetManifestFetcherTests.StatusWebResponse]::new([Net.HttpStatusCode]::InternalServerError)
                throw [Net.WebException]::new('server exploded', $null, [Net.WebExceptionStatus]::ProtocolError, $response)
            }

            $failure = try { Invoke-WingetGitHubRequest -UriFragment 'broken' } catch { $_ }

            $failure.Exception | Should -BeOfType ([Net.WebException])
            $failure.Exception.Message | Should -Be 'server exploded'
            $failure.FullyQualifiedErrorId | Should -Not -BeLike 'WingetGitHubItemNotFound*'
        }
    }
}

Describe 'Private boundary contracts' {
    It 'reports a missing Git tree segment through the stable typed boundary' {
        Mock Get-WingetGitHubTree {
            [PSCustomObject]@{ Entries = @(); Truncated = $false }
        } -ModuleName WinGetManifestFetcher

        $failure = try {
            InModuleScope WinGetManifestFetcher {
                Get-WingetGitHubTreeSha -OwnerName microsoft -RepositoryName winget-pkgs -Path 'manifests/missing'
            }
        } catch { $_ }

        $failure.Exception | Should -BeOfType ([System.Management.Automation.ItemNotFoundException])
        $failure.FullyQualifiedErrorId | Should -BeLike 'WingetGitHubItemNotFound*'
    }

    It 'preserves a single directory entry as a collection' {
        InModuleScope WinGetManifestFetcher {
            Mock Invoke-WingetGitHubRequest {
                [PSCustomObject]@{ name = '1.0'; type = 'dir' }
            }

            $directory = Get-GitHubContent -OwnerName microsoft -RepositoryName winget-pkgs -Path 'manifests/t/Test'

            @($directory.Entries) | Should -HaveCount 1
            $directory.Entries[0].name | Should -Be '1.0'
        }
    }

    It 'uses an unambiguous tuple when building cache keys' {
        InModuleScope WinGetManifestFetcher {
            $twoValues = New-WingetCacheKey -Namespace test -Label sample -Value @('a', 'b')
            $embeddedSeparator = New-WingetCacheKey -Namespace test -Label sample -Value "a`nb"

            $twoValues | Should -Not -Be $embeddedSeparator
        }
    }
}
