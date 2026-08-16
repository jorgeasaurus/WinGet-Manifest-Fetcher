#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Builds, tests, integrates, analyzes, publishes, or cleans WinGetManifestFetcher.

.PARAMETER Task
    One or more tasks to run. Defaults to Build.

.PARAMETER Bootstrap
    Downloads pinned build dependencies into the repository-local build cache.

.EXAMPLE
    ./build.ps1 -Task Build,Test,Analyze -Bootstrap
#>

[CmdletBinding()]
param(
    [ValidateSet('Build', 'Test', 'Integration', 'Analyze', 'Publish', 'Clean')]
    [string[]]$Task = 'Build',

    [switch]$Bootstrap
)

$ErrorActionPreference = 'Stop'
$moduleName = 'WinGetManifestFetcher'
$sourcePath = Join-Path $PSScriptRoot 'src'
$outputPath = Join-Path $PSScriptRoot 'output'
$moduleOutputPath = Join-Path $outputPath $moduleName
$validationStampPath = Join-Path $outputPath 'validation.json'
$buildModulePath = Join-Path (Join-Path $PSScriptRoot '.build') 'modules'
$dependencies = [ordered]@{
    'powershell-yaml'     = '0.4.12'
    'Pester'              = '6.1.0'
    'PSScriptAnalyzer'    = '1.25.0'
}

function Get-BuildDependencyManifestPath {
    param([Parameter(Mandatory)][string]$Name)

    $modulePath = Join-Path (Join-Path $buildModulePath $Name) ([string]$dependencies[$Name])
    return Join-Path $modulePath "$Name.psd1"
}

function Initialize-BuildModulePath {
    $modulePaths = @($env:PSModulePath -split [IO.Path]::PathSeparator)
    if ($buildModulePath -notin $modulePaths) {
        $env:PSModulePath = $buildModulePath + [IO.Path]::PathSeparator + $env:PSModulePath
    }
}

function Save-BuildDependencies {
    $null = New-Item -ItemType Directory -Path $buildModulePath -Force
    foreach ($dependency in $dependencies.GetEnumerator()) {
        $manifestPath = Get-BuildDependencyManifestPath -Name $dependency.Key
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            Write-Host "Downloading $($dependency.Key) $($dependency.Value) to $buildModulePath..."
            Save-Module -Name $dependency.Key -RequiredVersion $dependency.Value -Path $buildModulePath -Repository PSGallery -Force
        }
    }
}

function Import-BuildDependency {
    param([Parameter(Mandatory)][string]$Name)

    $version = $dependencies[$Name]
    $manifestPath = Get-BuildDependencyManifestPath -Name $Name
    try {
        Import-Module -Name $manifestPath -RequiredVersion $version -Force -ErrorAction Stop
    } catch {
        throw "Required build dependency '$Name' $version is unavailable. Run ./build.ps1 -Task $($Task -join ',') -Bootstrap."
    }
}

function Invoke-Clean {
    Remove-Item -LiteralPath $outputPath -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-DirectoryFingerprint {
    param([Parameter(Mandatory)][string]$Path)

    $root = [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
    $entries = foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse | Sort-Object FullName) {
        $relativePath = $file.FullName.Substring($root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
        "$relativePath`0$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash)"
    }

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($entries -join "`n"))
        return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Get-ValidationInputsFingerprint {
    $entries = [System.Collections.Generic.List[string]]::new()
    $directories = [ordered]@{ src = $sourcePath; Tests = (Join-Path $PSScriptRoot 'Tests') }
    foreach ($directory in $directories.GetEnumerator()) {
        $root = [IO.Path]::GetFullPath($directory.Value).TrimEnd([char[]]@('\', '/'))
        foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse | Sort-Object FullName) {
            $relativePath = $file.FullName.Substring($root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
            $entries.Add("$($directory.Key)/$relativePath`0$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash)")
        }
    }
    foreach ($fileName in @('PSScriptAnalyzerSettings.psd1', 'build.ps1')) {
        $filePath = Join-Path $PSScriptRoot $fileName
        $entries.Add("$fileName`0$((Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash)")
    }

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($entries -join "`n"))
        return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Write-ValidationStamp {
    $stamp = [ordered]@{
        Schema = 2
        ValidationInputsFingerprint = Get-ValidationInputsFingerprint
        ArtifactFingerprint = Get-DirectoryFingerprint -Path $moduleOutputPath
    }
    $stamp | ConvertTo-Json | Set-Content -LiteralPath $validationStampPath -Encoding UTF8
    Write-Host "Validated artifact stamped at $validationStampPath"
}

function Assert-ValidatedOutput {
    if (-not (Test-Path -LiteralPath $validationStampPath)) {
        throw 'The built module has not passed Build, Test, and Analyze together.'
    }

    $stamp = Get-Content -LiteralPath $validationStampPath -Raw | ConvertFrom-Json
    if ($stamp.Schema -ne 2 -or
        $stamp.ValidationInputsFingerprint -ne (Get-ValidationInputsFingerprint) -or
        $stamp.ArtifactFingerprint -ne (Get-DirectoryFingerprint -Path $moduleOutputPath)) {
        throw 'The validated module is stale or has been modified. Run Build, Test, and Analyze again.'
    }
}

function Invoke-ModuleBuild {
    Invoke-Clean
    $null = New-Item -ItemType Directory -Path $moduleOutputPath -Force

    foreach ($item in @("$moduleName.psd1", "$moduleName.psm1", 'Private', 'Public')) {
        Copy-Item -LiteralPath (Join-Path $sourcePath $item) -Destination $moduleOutputPath -Recurse
    }

    $manifestPath = Join-Path $moduleOutputPath "$moduleName.psd1"
    $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    Get-Module -Name $moduleName -All | Remove-Module -Force -ErrorAction SilentlyContinue
    try {
        Import-Module $manifestPath -Force -ErrorAction Stop
        $expectedCommands = @($manifest.ExportedFunctions.Keys | Sort-Object)
        $actualCommands = @((Get-Command -Module $moduleName).Name | Sort-Object)
        if (Compare-Object -ReferenceObject $expectedCommands -DifferenceObject $actualCommands) {
            throw "Built module exports do not match the manifest: $($actualCommands -join ', ')"
        }
    } finally {
        Get-Module -Name $moduleName -All | Remove-Module -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Module built at $moduleOutputPath"
}

function Invoke-Tests {
    Import-BuildDependency 'powershell-yaml'
    Import-BuildDependency 'Pester'

    $configurationData = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'Tests/PesterConfiguration.psd1')
    $results = Invoke-Pester -Configuration (New-PesterConfiguration -Hashtable $configurationData)
    if ($results.Result -ne 'Passed') {
        throw "Tests failed: result $($results.Result), $($results.FailedCount) tests failed"
    }
    $coverageTarget = [double]$configurationData.CodeCoverage.CoveragePercentTarget
    if ($results.CodeCoverage.CoveragePercent -lt $coverageTarget) {
        throw "Code coverage $($results.CodeCoverage.CoveragePercent)% is below the required $coverageTarget%"
    }
}

function Invoke-IntegrationTests {
    Assert-ValidatedOutput
    Import-BuildDependency 'powershell-yaml'
    Import-BuildDependency 'Pester'

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = Join-Path $PSScriptRoot 'Tests/Integration'
    $configuration.Run.PassThru = $true
    $configuration.Filter.Tag = 'Integration'
    $configuration.Output.Verbosity = 'Detailed'
    $results = Invoke-Pester -Configuration $configuration
    if ($results.Result -ne 'Passed') {
        throw "Integration tests failed: result $($results.Result), $($results.FailedCount) tests failed"
    }
}

function Invoke-Analysis {
    Import-BuildDependency 'PSScriptAnalyzer'

    $results = Invoke-ScriptAnalyzer -Path $sourcePath -Recurse -Settings (Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1')
    if ($results) {
        $results | Format-Table -AutoSize
        throw "PSScriptAnalyzer found $($results.Count) issues"
    }
}

function Invoke-Publish {
    Assert-ValidatedOutput
    if (-not $env:PSGALLERY_API_KEY) {
        throw 'PSGALLERY_API_KEY environment variable is not set'
    }

    Publish-Module -Path $moduleOutputPath -NuGetApiKey $env:PSGALLERY_API_KEY
}

Initialize-BuildModulePath
if ($Bootstrap) {
    Save-BuildDependencies
}

$executionPlan = [System.Collections.Generic.List[string]]::new()
foreach ($requestedTask in $Task) {
    if (-not $executionPlan.Contains($requestedTask)) {
        $executionPlan.Add($requestedTask)
    }
}

$completedTasks = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($taskName in $executionPlan) {
    Write-Host "Running $taskName..."
    switch ($taskName) {
        'Build'   { Invoke-ModuleBuild }
        'Test'    { Invoke-Tests }
        'Integration' { Invoke-IntegrationTests }
        'Analyze' { Invoke-Analysis }
        'Publish' { Invoke-Publish }
        'Clean'   { Invoke-Clean }
    }
    $null = $completedTasks.Add($taskName)
    if (-not (Test-Path -LiteralPath $validationStampPath) -and
        $completedTasks.Contains('Build') -and
        $completedTasks.Contains('Test') -and
        $completedTasks.Contains('Analyze')) {
        Write-ValidationStamp
    }
}
