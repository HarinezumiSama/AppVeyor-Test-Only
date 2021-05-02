<#PSScriptInfo

.VERSION 0.1.0
.GUID d8cfca48-e1e6-4569-bdc1-9ea27e46ecbc
.AUTHOR Vitalii Maklai a.k.a. HarinezumiSama
.COMPANYNAME
.COPYRIGHT Copyright (C) Vitalii Maklai
.TAGS Cryptography Encryption
.LICENSEURI
.PROJECTURI
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES

.DESCRIPTION
Provides:
    - cmdlet Download-AppveyorJobArtifacts
#>

#Requires -Version 5.1

using namespace System
using namespace System.Diagnostics
using namespace System.IO

$Script:ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
Microsoft.PowerShell.Core\Set-StrictMode -Version 1

function Download-AppveyorJobArtifacts
{
    [CmdletBinding(PositionalBinding = $false, DefaultParameterSetName = 'ArtifactFilter')]
    param
    (
        [Parameter()]
        [Uri] $ApiRootUri = 'https://ci.appveyor.com/api',

        [Parameter()]
        [string] $ApiToken,

        [Parameter()]
        [string] $AccountName,

        [Parameter()]
        [string] $ProjectSlug,

        [Parameter()]
        [string] $BuildId,

        [Parameter()]
        [string] $SourceJobName = ([string]::Empty),

        [Parameter()]
        [string] $DestinationDirectory,

        [Parameter(ParameterSetName = 'ArtifactFilter')]
        [string[]] $ArtifactFilter = $null,

        [Parameter(ParameterSetName = 'ArtifactName')]
        [string[]] $ArtifactName = $null,

        [Parameter()]
        [switch] $Flatten,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $PassThru
    )

    if (!$ApiRootUri -or $ApiRootUri.Scheme -inotin @([uri]::UriSchemeHttps))
    {
        throw [ArgumentException]::new('The valid URI of the Appveyor API must be provided.', 'ApiRootUri')
    }
    if ([string]::IsNullOrWhiteSpace($ApiToken))
    {
        throw [ArgumentException]::new('The Appveyor API token cannot be blank.', 'ApiToken')
    }
    if ([string]::IsNullOrWhiteSpace($AccountName))
    {
        throw [ArgumentException]::new('The current Appveyor account name cannot be blank.', 'AccountName')
    }
    if ([string]::IsNullOrWhiteSpace($ProjectSlug))
    {
        throw [ArgumentException]::new('The current Appveyor project slug cannot be blank.', 'ProjectSlug')
    }
    if ([string]::IsNullOrWhiteSpace($BuildId))
    {
        throw [ArgumentException]::new('The current Appveyor build ID cannot be blank.', 'BuildId')
    }
    if ([object]::ReferenceEquals($SourceJobName, $null))
    {
        throw [ArgumentNullException]::new('SourceJobName')
    }
    if ([string]::IsNullOrWhiteSpace($DestinationDirectory))
    {
        throw [ArgumentException]::new('The path to the destination directory cannot be blank.', 'DestinationDirectory')
    }
    if ($ArtifactFilter -and $ArtifactName)
    {
        throw [ArgumentException]::new('The "ArtifactFilter" and "ArtifactName" parameters cannot be specified at the same time.')
    }

    [string] $resolvedDestinationDirectoryPath = [Path]::GetFullPath($DestinationDirectory)

    $ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

    [ValidateNotNullOrEmpty()] [string] $apiUrl = $ApiRootUri.ToString().TrimEnd('/')
    [hashtable] $headers = @{ Authorization = "Bearer $ApiToken"; 'Content-Type' = 'application/json' }

    Write-Host "Getting last build information of the Appveyor project ""$AccountName/$ProjectSlug""."

    [ValidateNotNull()] [psobject] $projectLastBuildResponse = `
        Invoke-RestMethod `
            -UseBasicParsing `
            -Headers $headers `
            -Method Get `
            -Uri "$apiUrl/projects/$([uri]::EscapeDataString($AccountName))/$([uri]::EscapeDataString($ProjectSlug))"

    [ValidateNotNull()] [psobject] $projectLastBuildInfo = $projectLastBuildResponse | Select-Object -ExpandProperty 'build'

    [ValidateNotNullOrEmpty()] [string] $projectLastBuildId = $projectLastBuildInfo.buildId
    if ($projectLastBuildId -cne $BuildId)
    {
        throw "The Appveyor build ""$BuildId"" is not the last build (""$projectLastBuildId"")."
    }

    [psobject[]] $sourceJobs = $projectLastBuildInfo.jobs | ? { $_.name -ceq $SourceJobName }

    [psobject[]] $sourceJob = `
        switch ($sourceJobs.Count)
        {
            0
            {
                [string[]] $jobNamesString = `
                    ($projectLastBuildInfo.jobs | Select-Object -ExpandProperty name | % { """$_""" }) -join ', '

                throw "No job with the name ""$SourceJobName"" is found in the Appveyor build ""$projectLastBuildId""" `
                    + " (available jobs: $jobNamesString)."
            }

            1
            {
                $sourceJobs[0]
                break
            }

            default
            {
                throw "Multiple jobs with the name ""$SourceJobName"" are found in the Appveyor build ""$projectLastBuildId""" `
                    + ": $($sourceJobs.Count)."
            }
        }

    [ValidateNotNullOrEmpty()] [string] $sourceJobId = $sourceJob.jobId

    Write-Host "Getting information about the artifacts of the Appveyor build job ""$SourceJobName"" (ID: ""$sourceJobId"")."

    [psobject[]] $artifacts = `
        Invoke-RestMethod `
            -UseBasicParsing `
            -Headers $headers `
            -Method Get `
            -Uri "$apiUrl/buildjobs/$sourceJobId/artifacts"

    if (!$artifacts)
    {
        throw "No artifacts are found in the Appveyor job ""$sourceJobId""."
    }

    function Normalize-ArtifactPath([string] $path)
    {
        return $path.Replace([Path]::AltDirectorySeparatorChar, [Path]::DirectorySeparatorChar)
    }

    [psobject[]] $matchingArtifacts = $artifacts
    if ($ArtifactName)
    {
        $matchingArtifacts = @()
        foreach ($artifactNameItem in $ArtifactName)
        {
            [psobject[]] $foundArtifacts = `
                $artifacts | ? { (Normalize-ArtifactPath $_.fileName) -ceq (Normalize-ArtifactPath $artifactNameItem) }

            [psobject[]] $foundArtifact = `
                switch ($foundArtifacts.Count)
                {
                    0
                    {
                        [string[]] $artifactNamesString = `
                            ($artifacts | Select-Object -ExpandProperty fileName | % { """$_""" }) -join ', '

                        throw "No artifact with the name ""$artifactNameItem"" is found in the Appveyor job ""$sourceJobId""" `
                            + " (available artifacts: $artifactNamesString)."
                    }

                    1
                    {
                        $foundArtifacts[0]
                        break
                    }

                    default
                    {
                        throw "Multiple artifacts with the name ""$artifactNameItem"" are found in the Appveyor job ""$sourceJobId""" `
                            + ": $($foundArtifacts.Count)."
                    }
                }

            $matchingArtifacts += $foundArtifact
        }
    }

    [int] $downloadedArtifactCount = 0
    foreach ($artifact in $matchingArtifacts)
    {
        [ValidateNotNullOrEmpty()] [string] $artifactFileName = $artifact.fileName

        if ($ArtifactFilter)
        {
            [bool] $hasMatch = `
                ($ArtifactFilter | % { (Normalize-ArtifactPath $artifactFileName) -clike (Normalize-ArtifactPath $_) }) -contains $true
            if (!$hasMatch)
            {
                continue
            }
        }

        [string] $artifactUrl = "$apiUrl/buildjobs/$sourceJobId/artifacts/$([uri]::EscapeDataString($artifactFileName))"

        [string] $localArtifactRelativePath = if ($Flatten) { [Path]::GetFileName($artifactFileName) } else { $artifactFileName }

        [string] $localArtifactFilePath = [Path]::GetFullPath(
            [Path]::Combine($resolvedDestinationDirectoryPath, $localArtifactRelativePath))

        [string] $localArtifactDirectoryPath = [Path]::GetDirectoryName($localArtifactFilePath)
        if (![Directory]::Exists($localArtifactDirectoryPath))
        {
            Write-Host "Creating directory ""$localArtifactDirectoryPath""."
            [Directory]::CreateDirectory($localArtifactDirectoryPath) | Out-Null
        }

        if ([File]::Exists($localArtifactFilePath))
        {
            if (!$Force)
            {
                throw "Not downloading the artifact ""$artifactFileName"" to the file ""$localArtifactFilePath""" `
                    + " because the destination file already exists. Use '-Force' to overwrite."
            }

            Write-Host "Deleting the existing file ""$localArtifactFilePath""."
            [File]::SetAttributes($localArtifactFilePath, [FileAttributes]::Normal) | Out-Null
            [File]::Delete($localArtifactFilePath) | Out-Null
        }

        [string] $message = "Downloading the Appveyor job artifact ""$artifactFileName"" to ""$localArtifactFilePath"""

        Write-Host "$message..."
        [Stopwatch] $stopwatch = [Stopwatch]::StartNew()
        Invoke-WebRequest -UseBasicParsing -Headers $headers -Method Get -Uri $artifactUrl -OutFile $localArtifactFilePath | Out-Null
        $stopwatch.Stop() | Out-Null
        Write-Host "$message - DONE (elapsed: $($stopwatch.Elapsed))."
        $downloadedArtifactCount++

        if ($PassThru)
        {
            Write-Output -NoEnumerate -InputObject $localArtifactFilePath
        }
    }

    [string] $downloadedArtifactSuffix = if ($downloadedArtifactCount -eq 1) { $null } else { 's' }
    Write-Host "Downloaded $downloadedArtifactCount artifact$($downloadedArtifactSuffix)."
}