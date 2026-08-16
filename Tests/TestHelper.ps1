# Test helper for loading the source module with file-backed script extents.

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$moduleName = 'WinGetManifestFetcher'
$sourceRoot = Join-Path -Path $projectRoot -ChildPath 'src'
$modulePath = Join-Path -Path $sourceRoot -ChildPath 'WinGetManifestFetcher.psd1'

Get-Module -Name $moduleName -All | Remove-Module -Force -ErrorAction SilentlyContinue
Import-Module $modulePath -Force -Global -ErrorAction Stop
