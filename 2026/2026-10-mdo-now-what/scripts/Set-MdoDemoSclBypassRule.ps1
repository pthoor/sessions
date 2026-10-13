#requires -Version 7.2
<#
.SYNOPSIS
Creates or removes the narrowly scoped SCL -1 mail flow rule for act 4.
.DESCRIPTION
Connects to Exchange Online in the protected lab tenant and creates a mail flow rule
that sets SCL -1 only when the message comes from the one attacker test sender AND
carries the header x-mdodemo-scenario: sclbypass, which only Send-MdoDemoMail.ps1
-Scenario SclBypass adds. The rule recreates the misconfiguration the session warns
about without exposing the tenant to other senders. -Remove deletes it.
.PARAMETER SenderAddress
The attacker test account that sends the staged email.
.PARAMETER Organization
A domain the protected tenant owns. Interactive sign-in uses whichever account is
chosen in the browser, so the script checks that the connected tenant has this
accepted domain before it reads or writes any rule.
.PARAMETER UseDeviceCode
Signs in with the device code flow instead of a browser redirect, for hosts such as
Codespaces where the redirect cannot reach a local browser. Enter the code only at
https://microsoft.com/devicelogin and only for a sign-in you started.
.PARAMETER Remove
Deletes the demo rule instead of creating it.
.OUTPUTS
System.Management.Automation.PSCustomObject
.EXAMPLE
./Set-MdoDemoSclBypassRule.ps1 -SenderAddress attacker@contoso-attacker.example -Organization lab.example -Confirm
.EXAMPLE
./Set-MdoDemoSclBypassRule.ps1 -Organization lab.example -Remove -Confirm
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Create')]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory, ParameterSetName = 'Create')] [ValidateNotNullOrEmpty()] [string] $SenderAddress,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Organization,
    [Parameter(Mandatory, ParameterSetName = 'Remove')] [switch] $Remove,
    [switch] $UseDeviceCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ruleName = 'MDO demo - SCL -1 bypass (lab only)'
if (-not $Remove) {
    try { $address = [Net.Mail.MailAddress]::new($SenderAddress) } catch { throw 'SenderAddress must be one literal mail address.' }
    if ($address.Address -cne $SenderAddress) { throw 'SenderAddress must be one literal address without a display name.' }
}
$action = if ($Remove) { "Remove mail flow rule '$ruleName'" } else { "Create mail flow rule '$ruleName' for $SenderAddress" }
if (-not $PSCmdlet.ShouldProcess($Organization, $action)) { return }

Import-Module ExchangeOnlineManagement -ErrorAction Stop
Connect-ExchangeOnline -Organization $Organization -ShowBanner:$false -Device:$UseDeviceCode -ErrorAction Stop
try {
    $owned = Get-AcceptedDomain -ErrorAction Stop | Where-Object { $_.DomainName -ieq $Organization }
    if (-not $owned) {
        $default = (Get-AcceptedDomain -ErrorAction Stop | Where-Object Default).DomainName
        throw "Signed in to the tenant whose default domain is $default, which does not own $Organization. Sign in with an account in the protected tenant."
    }
    $existing = Get-TransportRule -Identity $ruleName -ErrorAction SilentlyContinue
    if ($Remove) {
        if ($existing) { Remove-TransportRule -Identity $ruleName -Confirm:$false -ErrorAction Stop }
        return [pscustomobject]@{ Organization = $Organization; Rule = $ruleName; Action = if ($existing) { 'Removed' } else { 'NotFound' } }
    }
    if ($existing) { throw "Mail flow rule '$ruleName' already exists; run with -Remove first." }
    New-TransportRule -Name $ruleName -From $SenderAddress -HeaderContainsMessageHeader 'x-mdodemo-scenario' -HeaderContainsWords 'sclbypass' -SetSCL -1 -Comments 'Session demo for the SCL -1 bypass act. Remove after the session.' -ErrorAction Stop | Out-Null
    [pscustomobject]@{ Organization = $Organization; Rule = $ruleName; Action = 'Created'; Sender = $SenderAddress }
} finally {
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
}
