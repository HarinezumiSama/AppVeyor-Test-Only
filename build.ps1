#Requires -Version 5

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
        [string] $unnamedArgumentsAsString = if ($UnnamedArguments) { ($UnnamedArguments | % { """$_""" }) -join ', ' } else { '<none>' }
        Write-Host "UnnamedArguments: $unnamedArgumentsAsString"

        # Write-LogSeparator
        #
        # Get-ChildItem env:* | Sort-Object Name | Select-Object Name, Value | Format-Table * -Wrap

        Write-LogSeparator

        $PSScriptRoot `
            | Get-ChildItem -Recurse `
            | Select-Object -Property FullName, Mode, Length `
            | Group-Object -Property { Split-Path -Parent $_.FullName } `
            | % { ''; ''; "Directory ""$($_.Name)"""; ''; $_.Group } `
            | Out-Host

        Write-LogSeparator

        & git config --list --show-origin --show-scope

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

        if ($BuildOnly -or $Deployment)
        {
            return
        }

        [bool] $simulatedTestSuccess = $true #$TestFramework -ine 'net472'

        Set-Content `
            -LiteralPath "$PSScriptRoot\TestResult.txt" `
            -Value "Simulated Test Result: $simulatedTestSuccess" `
            -Encoding UTF8 `
            | Out-Null

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