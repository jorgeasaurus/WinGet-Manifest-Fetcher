@{
    Run = @{
        Path = './Tests/Unit'
        PassThru = $true
        SkipRemainingOnFailure = 'None'
    }

    Filter = @{
        ExcludeTag = @('Integration')
    }

    CodeCoverage = @{
        Enabled = $true
        Path = @(
            './src/WinGetManifestFetcher.psm1'
            './src/Private/*.ps1'
            './src/Public/*.ps1'
        )
        CoveragePercentTarget = 80
    }

    Output = @{
        Verbosity = 'Detailed'
        StackTraceVerbosity = 'FirstLine'
        CIFormat = 'Auto'
    }

    Should = @{
        ErrorAction = 'Stop'
    }
}
