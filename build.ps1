#Requires -Version 5.1

using namespace System
using namespace System.Management.Automation

[CmdletBinding(PositionalBinding = $false)]
param
(
    [Parameter()]
    [switch] $BuildOnly,

    [Parameter()]
    [switch] $Deployment,

    [Parameter()]
    [string] $TestFramework = $null,

    [Parameter()]
    [switch] $AppveyorDownloadBuildJobArtifacts,

    [Parameter()]
    [string] $AppveyorApiToken,

    [Parameter()]
    [Uri] $AppveyorApiRootUri = 'https://ci.appveyor.com/api',

    [Parameter()]
    [string] $AppveyorAccountName = $env:APPVEYOR_ACCOUNT_NAME,

    [Parameter()]
    [string] $AppveyorProjectSlug = $env:APPVEYOR_PROJECT_SLUG,

    [Parameter()]
    [string] $AppveyorBuildId = $env:APPVEYOR_BUILD_ID,

    [Parameter()]
    [string] $AppveyorBuildNumber = $env:APPVEYOR_BUILD_NUMBER,

    [Parameter()]
    [string] $OriginalAppveyorBuildVersion = $env:APPVEYOR_BUILD_VERSION,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $UnnamedArguments = @()
)
begin
{
    $Script:ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    Microsoft.PowerShell.Core\Set-StrictMode -Version 1

    . "$PSScriptRoot\HarinezumiSama.Utilities.Appveyor.ps1"

    function Get-ErrorDetails([ValidateNotNull()] [System.Management.Automation.ErrorRecord] $errorRecord = $_)
    {
        [ValidateNotNull()] [System.Exception] $exception = $errorRecord.Exception
        while ($exception -is [System.Management.Automation.RuntimeException] -and $exception.InnerException -ne $null)
        {
            $exception = $exception.InnerException
        }

        [string[]] $lines = `
        @(
            $exception.Message,
            '',
            '<<<',
            "Exception: '$($exception.GetType().FullName)'",
            "FullyQualifiedErrorId: '$($errorRecord.FullyQualifiedErrorId)'"
        )

        if (![string]::IsNullOrWhiteSpace($errorRecord.ScriptStackTrace))
        {
            $lines += `
            @(
                '',
                'Script stack trace:',
                '-------------------',
                $($errorRecord.ScriptStackTrace)
            )
        }

        if (![string]::IsNullOrWhiteSpace($exception.StackTrace))
        {
            $lines += `
            @(
                '',
                'Exception stack trace:',
                '----------------------',
                $($exception.StackTrace)
            )
        }

        $lines += '>>>'

        return ($lines -join ([System.Environment]::NewLine))
    }

    function Write-LogSeparator
    {
        Write-Host ''
        Write-Host -ForegroundColor Magenta ('-' * 100)
        Write-Host ''
    }

    function Print-FileList
    {
        [CmdletBinding(PositionalBinding = $false)]
        param ()

        Write-LogSeparator

        $PSScriptRoot `
            | Get-ChildItem -Recurse `
            | Select-Object -Property FullName, Mode, Length `
            | Group-Object -Property { Split-Path -Parent $_.FullName } `
            | % { ''; ''; "Directory ""$($_.Name)"""; ''; $_.Group } `
            | Out-Host

        Write-LogSeparator
    }

    function Download-AppveyorBuildJobArtifacts
    {
        [CmdletBinding(PositionalBinding = $false)]
        param ()

        if (!$AppveyorDownloadBuildJobArtifacts)
        {
            return
        }

        if ([string]::IsNullOrWhiteSpace($AppveyorApiToken))
        {
            throw [ArgumentException]::new('The Appveyor API token cannot be blank.', 'AppveyorApiToken')
        }
        if (!$AppveyorApiRootUri -or $AppveyorApiRootUri.Scheme -inotin @([uri]::UriSchemeHttp, [uri]::UriSchemeHttps))
        {
            throw [ArgumentException]::new('The valid URI of the Appveyor API must be provided.', 'AppveyorApiRootUri')
        }
        if ([string]::IsNullOrWhiteSpace($AppveyorAccountName))
        {
            throw [ArgumentException]::new('The current Appveyor account name cannot be blank.', 'AppveyorAccountName')
        }
        if ([string]::IsNullOrWhiteSpace($AppveyorProjectSlug))
        {
            throw [ArgumentException]::new('The current Appveyor project slug cannot be blank.', 'AppveyorProjectSlug')
        }
        if ([string]::IsNullOrWhiteSpace($AppveyorBuildId))
        {
            throw [ArgumentException]::new('The current Appveyor build ID cannot be blank.', 'AppveyorBuildId')
        }

        [ValidateNotNullOrEmpty()] [string] $artifactsContainerJobName = 'Build'

        [ValidateNotNullOrEmpty()] [string] $downloadLocation = [System.IO.Path]::Combine($PSScriptRoot, '.downloadedArtifacts')

        Download-AppveyorJobArtifacts `
            -ApiRootUri $AppveyorApiRootUri `
            -ApiToken $AppveyorApiToken `
            -AccountName $AppveyorAccountName `
            -ProjectSlug $AppveyorProjectSlug `
            -BuildId $AppveyorBuildId `
            -SourceJobName $artifactsContainerJobName `
            -DestinationDirectory $downloadLocation
    }
}
process
{
    [Console]::ResetColor()
    Write-LogSeparator

    try
    {
        Write-Host "BuildOnly: $BuildOnly"
        Write-Host "Deployment: $Deployment"
        Write-Host "TestFramework: ""$TestFramework"""
        Write-Host ''
        Write-Host "AppveyorDownloadBuildJobArtifacts: $AppveyorDownloadBuildJobArtifacts"
        Write-Host "AppveyorApiRootUri: ""$AppveyorApiRootUri"""
        Write-Host "AppveyorAccountName: ""$AppveyorAccountName"""
        Write-Host "AppveyorProjectSlug: ""$AppveyorProjectSlug"""
        Write-Host "AppveyorBuildId: ""$AppveyorBuildId"""
        Write-Host "AppveyorBuildNumber: ""$AppveyorBuildNumber"""
        Write-Host "OriginalAppveyorBuildVersion: ""$OriginalAppveyorBuildVersion"""
        Write-Host ''
        [string] $unnamedArgumentsAsString = if ($UnnamedArguments) { ($UnnamedArguments | % { """$_""" }) -join ', ' } else { '<none>' }
        Write-Host "UnnamedArguments: $unnamedArgumentsAsString"

        Write-LogSeparator

        Add-AppveyorMessage `
            -Verbose `
            -Message "Starting the build for ""$AppveyorAccountName/$AppveyorProjectSlug""."

        Get-ChildItem env:* | Sort-Object Name | Select-Object Name, Value | Format-Table * -Wrap

        Print-FileList

        & git config --list --show-origin --show-scope

        Write-LogSeparator

        if ([string]::IsNullOrWhiteSpace($OriginalAppveyorBuildVersion))
        {
            throw [ArgumentException]::new('The original Appveyor build version cannot be blank.', 'OriginalAppveyorBuildVersion')
        }

        Update-AppveyorBuild `
            -Verbose `
            -Version "$OriginalAppveyorBuildVersion [1.2.3]"

        Write-LogSeparator

        Download-AppveyorBuildJobArtifacts

        [string] $s = Get-Content -Raw -Path ./winFile.txt
        $s | ConvertTo-Json -Depth 4 | Out-Host

        Write-LogSeparator

        if ($BuildOnly)
        {
            Compress-Archive `
                -Verbose `
                -Path "$PSScriptRoot\*" `
                -DestinationPath "$PSScriptRoot\artifact.zip" `
                -CompressionLevel Optimal `
                | Out-Null

            Write-LogSeparator
        }

        if ($BuildOnly -or $Deployment)
        {
            Print-FileList
            return
        }

        [bool] $simulatedTestSuccess = $true #$TestFramework -ine 'net472'

        Set-Content `
            -LiteralPath "$PSScriptRoot\TestResult-$TestFramework.txt" `
            -Value "Simulated Test Result: $simulatedTestSuccess" `
            -Encoding UTF8 `
            | Out-Null

        Print-FileList

        if (!$simulatedTestSuccess)
        {
            throw 'SIMULATED test failure.'
        }
    }
    catch
    {
        [string] $errorDetails = Get-ErrorDetails

        [Console]::ResetColor()
        Write-LogSeparator
        Write-Host -ForegroundColor Red $errorDetails
        Write-LogSeparator

        throw
    }
}