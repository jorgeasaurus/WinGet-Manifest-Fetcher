@{
    # Pester Configuration for WinGetManifestFetcher
    
    # Test Discovery
    TestDiscovery = @{
        # Directories to search for tests
        Path = @(
            './Tests/Unit',
            './Tests/Integration',
            './Tests/WinGetManifestFetcher.Tests.ps1'
        )
        
        # Test name filter
        FullNameFilter = '*'
        
        # Tags to include/exclude
        TagFilter = @()
        ExcludeTagFilter = @()
    }
    
    # Run Settings
    Run = @{
        # Exit after tests
        Exit = $false
        
        # Throw on failures
        Throw = $false
        
        # Pass thru results
        PassThru = $true
        
        # Skip remaining tests after failure threshold
        SkipRemainingOnFailure = 'None'
    }
    
    # Code Coverage Settings
    CodeCoverage = @{
        # Enable code coverage
        Enabled = $false
        
        # Files to analyze
        Path = @('./WinGetManifestFetcher.psm1')
        
        # Output settings
        OutputFormat = 'CoverageGutters'
        OutputPath = './TestResults/Coverage.xml'
        OutputEncoding = 'UTF8'
        
        # Coverage thresholds
        CoveragePercentTarget = 80
    }
    
    # Test Results
    TestResult = @{
        # Enable test result output
        Enabled = $true
        
        # Output format
        OutputFormat = 'NUnitXml'
        OutputPath = './TestResults/TestResults.xml'
        OutputEncoding = 'UTF8'
        
        # Include coverage in test results
        TestSuiteName = 'WinGetManifestFetcher'
    }
    
    # Output Settings
    Output = @{
        # Verbosity level
        Verbosity = 'Detailed'
        
        # Stack trace verbosity
        StackTraceVerbosity = 'FirstLine'
        
        # CI mode (simplified output)
        CIFormat = 'Auto'
    }
    
    # Filter Settings
    Filter = @{
        # Tags
        Tag = @()
        ExcludeTag = @()
        
        # Line filter for specific tests
        Line = @()
        
        # Full name filters
        FullName = @()
        ExcludeFullName = @()
    }
    
    # Should Behavior
    Should = @{
        # Error action
        ErrorAction = 'Stop'
    }
    
    # Debug Settings
    Debug = @{
        # Show full errors
        ShowFullErrors = $true
        
        # Write debug messages
        WriteDebugMessages = $false
        
        # Write debug messages from Pester
        WriteDebugMessagesFrom = @('Discovery', 'Skip', 'Mock', 'CodeCoverage')
        
        # Show navigation markers
        ShowNavigationMarkers = $false
        
        # Return raw result object
        ReturnRawResultObject = $false
    }
}