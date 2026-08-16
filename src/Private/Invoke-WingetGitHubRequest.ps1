function Get-WingetHttpStatusCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $currentException = $Exception
    while ($currentException) {
        $responseProperty = $currentException.PSObject.Properties['Response']
        if ($responseProperty -and $responseProperty.Value) {
            $statusProperty = $responseProperty.Value.PSObject.Properties['StatusCode']
            if ($statusProperty -and $null -ne $statusProperty.Value) {
                return [int]$statusProperty.Value
            }
        }
        $currentException = $currentException.InnerException
    }

    return $null
}

function Invoke-WingetGitHubRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UriFragment,

        [string]$Method = 'Get',

        [string]$Description
    )

    $headers = @{
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'WinGetManifestFetcher'
    }
    if ($env:GITHUB_TOKEN) {
        $headers.Authorization = "Bearer $($env:GITHUB_TOKEN)"
    }

    if ($Description) {
        Write-Verbose $Description
    }

    $uri = "https://api.github.com/$UriFragment"
    try {
        Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -ErrorAction Stop
    } catch {
        if ((Get-WingetHttpStatusCode -Exception $_.Exception) -eq 404) {
            $exception = [System.Management.Automation.ItemNotFoundException]::new("GitHub resource was not found: $uri")
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'WingetGitHubItemNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $uri
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        throw
    }
}

function Get-GitHubContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OwnerName,

        [Parameter(Mandatory)]
        [string]$RepositoryName,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $encodedPath = ($Path -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $response = Invoke-WingetGitHubRequest -UriFragment "repos/$OwnerName/$RepositoryName/contents/$encodedPath"
    [PSCustomObject]@{
        Entries = @($response)
    }
}

function Get-WingetGitHubTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OwnerName,

        [Parameter(Mandatory)]
        [string]$RepositoryName,

        [Parameter(Mandatory)]
        [string]$TreeReference,

        [switch]$Recursive,

        [switch]$AllowTruncated
    )

    $suffix = if ($Recursive) { '?recursive=1' } else { '' }
    $response = Invoke-WingetGitHubRequest -UriFragment "repos/$OwnerName/$RepositoryName/git/trees/$TreeReference$suffix"
    if (-not $response) {
        throw "GitHub returned no tree for '$TreeReference'"
    }
    if ($response.truncated -and -not $AllowTruncated) {
        throw "GitHub returned a truncated tree for '$TreeReference'"
    }

    [PSCustomObject]@{
        Entries  = @($response.tree)
        Truncated = [bool]$response.truncated
    }
}

function Get-WingetGitHubTreeSha {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OwnerName,

        [Parameter(Mandatory)]
        [string]$RepositoryName,

        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Branch = 'master'
    )

    $treeReference = $Branch
    foreach ($segment in $Path -split '/') {
        $treeResult = Get-WingetGitHubTree -OwnerName $OwnerName -RepositoryName $RepositoryName -TreeReference $treeReference
        $entry = $treeResult.Entries |
            Where-Object { $_.type -eq 'tree' -and $_.path -eq $segment } |
            Select-Object -First 1
        if (-not $entry.sha) {
            $exception = [System.Management.Automation.ItemNotFoundException]::new("GitHub tree path was not found: $Path")
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'WingetGitHubItemNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $Path
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        $treeReference = $entry.sha
    }

    $treeReference
}
