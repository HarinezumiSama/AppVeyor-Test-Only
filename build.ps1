#Requires -Version 5

using namespace System
using namespace System.Management.Automation

[CmdletBinding(PositionalBinding = $false)]
param
(
    [Parameter()]
    [string] $TestRuntime = $null
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
        Write-Host "TestRuntime = ""$TestRuntime"""

        Write-LogSeparator

        & git config --list --show-origin --show-scope

        Write-LogSeparator

        [string] $s = Get-Content -Raw -Path ./winFile.txt
        $s | ConvertTo-Json -Depth 4 | Out-Host

        Write-LogSeparator
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