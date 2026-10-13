#requires -Version 7.2
<#
.SYNOPSIS
Creates or removes the post-compromise inbox rule for act 2.
.DESCRIPTION
Signs in interactively as the protected lab user with delegated
MailboxSettings.ReadWrite and creates the classic attacker rule: a rule named "."
that moves invoice, remittance and payment mail to Conversation History (or Archive
when that folder does not exist), marks it read and stops further rules. Run it from
a second network after the act 1 click so the sign-in and the rule share an
unfamiliar IP. -Remove deletes only rules named "." in that mailbox.
.PARAMETER ConfigPath
Path to the prompt-injection lab's lab.local.psd1; Targets.Protected.TenantId is used.
.PARAMETER UseDeviceCode
Signs in with the device code flow instead of a browser redirect, for hosts such as
Codespaces where the redirect cannot reach a local browser. Enter the code only at
https://microsoft.com/devicelogin and only for a sign-in you started.
.PARAMETER Remove
Deletes the demo rule instead of creating it.
.OUTPUTS
System.Management.Automation.PSCustomObject
.EXAMPLE
./Set-MdoDemoInboxRule.ps1 -ConfigPath ../../mdo-prompt-injection/demo/config/lab.local.psd1 -Confirm
.EXAMPLE
./Set-MdoDemoInboxRule.ps1 -ConfigPath ../../mdo-prompt-injection/demo/config/lab.local.psd1 -Remove -Confirm
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ConfigPath,
    [switch] $Remove,
    [switch] $UseDeviceCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../mdo-prompt-injection/demo/modules/Xpia.Core.psm1') -Force
$configuration = Import-XpiaLabConfiguration -Path $ConfigPath
$mailbox = $configuration.Targets.Protected.MailRecipientAddress
$ruleName = '.'
$rulesUri = 'https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messageRules'
$action = if ($Remove) { "Remove inbox rules named '$ruleName'" } else { "Create hiding inbox rule '$ruleName'" }
if (-not $PSCmdlet.ShouldProcess($mailbox, $action)) { return }

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Connect-MgGraph -TenantId $configuration.Targets.Protected.TenantId -Scopes @('MailboxSettings.ReadWrite') -ContextScope Process -NoWelcome -UseDeviceCode:$UseDeviceCode -ErrorAction Stop | Out-Null
try {
    $signedIn = (Get-MgContext).Account
    if ($signedIn -ine $mailbox) { throw "Signed in as $signedIn; sign in as the protected lab user $mailbox." }
    $existing = @((Invoke-MgGraphRequest -Method GET -Uri $rulesUri -ErrorAction Stop).value | Where-Object { $_.displayName -ceq $ruleName })
    if ($Remove) {
        foreach ($rule in $existing) {
            Invoke-MgGraphRequest -Method DELETE -Uri "$rulesUri/$($rule.id)" -ErrorAction Stop | Out-Null
        }
        return [pscustomobject]@{ Mailbox = $mailbox; Action = 'Removed'; RuleCount = $existing.Count; Folder = $null }
    }
    if ($existing.Count -gt 0) { throw "An inbox rule named '$ruleName' already exists; run with -Remove first." }
    $folder = $null
    foreach ($wellKnownName in @('conversationhistory', 'archive')) {
        try {
            $folder = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me/mailFolders/$wellKnownName" -ErrorAction Stop
            break
        } catch {
            $folder = $null
        }
    }
    if ($null -eq $folder) { throw 'Neither Conversation History nor Archive exists in this mailbox.' }
    $body = @{
        displayName = $ruleName
        sequence = 1
        isEnabled = $true
        conditions = @{ subjectContains = @('invoice', 'remittance', 'payment') }
        actions = @{ moveToFolder = $folder.id; markAsRead = $true; stopProcessingRules = $true }
    }
    $created = Invoke-MgGraphRequest -Method POST -Uri $rulesUri -Body ($body | ConvertTo-Json -Depth 5 -Compress) -ContentType 'application/json' -ErrorAction Stop
    [pscustomobject]@{ Mailbox = $mailbox; Action = 'Created'; RuleCount = 1; Folder = $folder.displayName; RuleId = $created.id }
} finally {
    if (Get-MgContext) { Disconnect-MgGraph | Out-Null }
}
