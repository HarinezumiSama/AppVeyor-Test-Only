#Requires -Version 5.1

using namespace System
using namespace System.Management.Automation

[CmdletBinding(PositionalBinding = $false)]
param
(
    [Parameter()]
    [switch] $BuildOnly,

    [Parameter()]
    [string] $AppveyorAccountName = $env:APPVEYOR_ACCOUNT_NAME,

    [Parameter()]
    [string] $AppveyorProjectSlug = $env:APPVEYOR_PROJECT_SLUG,

    [Parameter()]
    [string] $AppveyorBuildNumber = $env:APPVEYOR_BUILD_NUMBER,

    [Parameter()]
    [string] $AppveyorOriginalBuildVersion = $env:APPVEYOR_BUILD_VERSION,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $UnnamedArguments = @()
)
begin
{
    $Script:ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    Microsoft.PowerShell.Core\Set-StrictMode -Version 1

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
}
process
{
    [Console]::ResetColor()
    Write-LogSeparator

    try
    {
        Write-Host "BuildOnly: $BuildOnly"
        Write-Host ''
        Write-Host "AppveyorAccountName: ""$AppveyorAccountName"""
        Write-Host "AppveyorProjectSlug: ""$AppveyorProjectSlug"""
        Write-Host "AppveyorBuildNumber: ""$AppveyorBuildNumber"""
        Write-Host "AppveyorOriginalBuildVersion: ""$AppveyorOriginalBuildVersion"""
        Write-Host ''
        [string] $unnamedArgumentsAsString = if ($UnnamedArguments) { ($UnnamedArguments | % { """$_""" }) -join ', ' } else { '<none>' }
        Write-Host "UnnamedArguments: $unnamedArgumentsAsString"

        Write-LogSeparator

        Get-ChildItem env:* | Sort-Object Name | Select-Object Name, Value | Format-Table * -Wrap

        Print-FileList

        & git config --list --show-origin --show-scope

        Write-LogSeparator

        if ([string]::IsNullOrWhiteSpace($AppveyorAccountName))
        {
            throw [ArgumentException]::new('The Appveyor account name cannot be blank.', 'AppveyorAccountName')
        }
        if ([string]::IsNullOrWhiteSpace($AppveyorProjectSlug))
        {
            throw [ArgumentException]::new('The Appveyor project slug cannot be blank.', 'AppveyorProjectSlug')
        }
        if ([string]::IsNullOrWhiteSpace($AppveyorBuildNumber))
        {
            throw [ArgumentException]::new('The Appveyor build number cannot be blank.', 'AppveyorBuildNumber')
        }
        if ([string]::IsNullOrWhiteSpace($AppveyorOriginalBuildVersion))
        {
            throw [ArgumentException]::new('The original Appveyor build version cannot be blank.', 'AppveyorOriginalBuildVersion')
        }

        Add-AppveyorMessage `
            -Verbose `
            -Message "Starting the build for ""$AppveyorAccountName/$AppveyorProjectSlug""."

        [string] $computedVersion = '1.2.3'

        Set-AppveyorBuildVariable -Name CI_DEPLOYMENT_VERSION -Value "$computedVersion [build $AppveyorBuildNumber]"

        Update-AppveyorBuild `
            -Verbose `
            -Version "v$($computedVersion): $AppveyorOriginalBuildVersion"

        Write-LogSeparator

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

        if ($BuildOnly)
        {
            Print-FileList
            return
        }

        [bool] $simulatedTestSuccess = $true

        Set-Content `
            -LiteralPath "$PSScriptRoot\TestResult.txt" `
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