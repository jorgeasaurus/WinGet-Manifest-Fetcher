# Changelog for WinGetManifestFetcher v1.4.0

## Version 1.4.0 - 2025-01-27

### New Features
- Added comprehensive test suite for popular applications
- Created automated test runners with code coverage support
- Added manual test scripts for quick verification

### Improvements
- Enhanced version sorting algorithm to handle complex version formats (e.g., Spotify's git hash suffixes)
- Improved sublevel directory handling for packages with nested structures
- Better error handling and messaging for 404 errors
- Implemented filtering to skip test/validation directories

### Bug Fixes
- Fixed module function loading when running from source (not built)
- Fixed script variable initialization issues in test environments
- Resolved version sorting issues for packages with non-standard version formats
- Fixed parameter validation tests to run without user prompts

### Module Changes
- Added automatic function loading for development/testing scenarios
- Enhanced module initialization with validation checks
- Improved cross-platform compatibility

### Test Suite Additions
- `Tests/Get-LatestWingetVersion.PopularApps.Tests.ps1` - Integration tests for 10 popular apps
- `Tests/Get-LatestWingetVersion.Basic.Tests.ps1` - Basic unit tests  
- `Tests/Run-PopularAppsTests.ps1` - Automated test runner
- `Examples/Test-PopularApps.ps1` - Manual verification script
- `Tests/Test-ModuleInitialization.ps1` - Module diagnostic helper

### Script Updates
- `Examples/AllLatestVersionsReport.ps1` - Enhanced with better error handling and filtering

### Technical Details
- Module now supports running directly from source without building
- All tests pass without requiring user interaction
- Code coverage reporting integrated with Pester 5.x
- Supports VS Code PowerShell extension test execution