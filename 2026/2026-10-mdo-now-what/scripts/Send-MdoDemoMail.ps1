#requires -Version 7.2
<#
.SYNOPSIS
Sends one staged demo email for the "Now what?" session.
.DESCRIPTION
Builds the InvoiceLink, QrCode or SclBypass message, validates that every URL points
at a reserved .invalid host, and sends exactly one item from the attacker test account
through delegated Microsoft Graph Mail.Send to the protected lab mailbox in the lab
configuration. Without -AcknowledgeLabUse it renders a local preview and makes no
sign-in or Graph request. Each invocation writes results/<RunId>.run.local.json.
.PARAMETER Scenario
InvoiceLink (act 1), QrCode (act 3) or SclBypass (act 4).
.PARAMETER ConfigPath
Path to the prompt-injection lab's lab.local.psd1; its AttackerTenantId,
Targets.Protected.MailRecipientAddress and AllowedRecipientDomains are reused.
.PARAMETER ResultsDirectory
Directory for the run record and local HTML preview; defaults to the session results folder.
.PARAMETER UseDeviceCode
Signs in with the device code flow instead of a browser redirect, for hosts such as
Codespaces where the redirect cannot reach a local browser. Enter the code only at
https://microsoft.com/devicelogin and only for a sign-in you started.
.PARAMETER AcknowledgeLabUse
Required to sign in and send. Omit it for a local preview.
.OUTPUTS
System.Management.Automation.PSCustomObject
.EXAMPLE
./Send-MdoDemoMail.ps1 -Scenario QrCode -ConfigPath ../../mdo-prompt-injection/demo/config/lab.local.psd1
.EXAMPLE
./Send-MdoDemoMail.ps1 -Scenario QrCode -ConfigPath ../../mdo-prompt-injection/demo/config/lab.local.psd1 -AcknowledgeLabUse -Confirm
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory)] [ValidateSet('InvoiceLink', 'QrCode', 'SclBypass')] [string] $Scenario,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ConfigPath,
    [ValidateNotNullOrEmpty()] [string] $ResultsDirectory = (Join-Path $PSScriptRoot '../results'),
    [switch] $AcknowledgeLabUse,
    [switch] $UseDeviceCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/MdoDemo.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../../mdo-prompt-injection/demo/modules/Xpia.Core.psm1') -Force
$configuration = Import-XpiaLabConfiguration -Path $ConfigPath
$recipient = $configuration.Targets.Protected.MailRecipientAddress
$resultsDirectory = $ResultsDirectory
[void][IO.Directory]::CreateDirectory($resultsDirectory)
$runId = New-MdoRunId -ResultsDirectory $resultsDirectory -Now ([datetime]::UtcNow)
$message = New-MdoDemoMessage -Scenario $Scenario -RunId $runId -AllowedDomains $configuration.AllowedRecipientDomains
$record = [pscustomobject][ordered]@{
    RunId = $runId
    Scenario = $Scenario
    Subject = $message.Subject
    QrText = $message.QrText
    SentAtUtc = $null
    TransportStatus = 'Preview'
    FailureType = $null
}
$recordPath = Join-Path $resultsDirectory "$runId.run.local.json"
$previewPath = Join-Path $resultsDirectory "$runId.preview.local.html"
$body = $message.Body
foreach ($attachment in @($message.Attachments | Where-Object IsInline)) {
    $body = $body.Replace("cid:$($attachment.ContentId)", "data:$($attachment.ContentType);base64,$($attachment.ContentBytes)")
}
[IO.File]::WriteAllText($previewPath, $body, [Text.UTF8Encoding]::new($false))

if ($AcknowledgeLabUse) {
    if ($PSCmdlet.ShouldProcess($recipient, "Send one staged $Scenario demo email $runId")) {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        try {
            Connect-MgGraph -TenantId $configuration.AttackerTenantId -Scopes @('Mail.Send') -ContextScope Process -NoWelcome -UseDeviceCode:$UseDeviceCode -ErrorAction Stop | Out-Null
            $request = ConvertTo-MdoGraphMailRequest -Message $message -Recipient $recipient
            $record.SentAtUtc = [datetime]::UtcNow.ToString('o', [cultureinfo]::InvariantCulture)
            $response = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/me/sendMail' -Body ($request | ConvertTo-Json -Depth 10 -Compress) -ContentType 'application/json' -OutputType HttpResponseMessage -ErrorAction Stop
            try {
                $record.TransportStatus = if ($null -ne $response -and $response.StatusCode -eq [Net.HttpStatusCode]::Accepted) { 'Accepted' } else { 'Failed' }
            } finally { if ($response -is [IDisposable]) { $response.Dispose() } }
        } catch {
            $record.TransportStatus = 'Failed'
            $record.FailureType = $_.Exception.GetType().Name
            Write-Warning ('Send failed: ' + ($_.Exception.Message -replace '(?i)bearer\s+\S+', 'Bearer [redacted]'))
        } finally {
            if (Get-MgContext) { Disconnect-MgGraph | Out-Null }
        }
    } else {
        $record.TransportStatus = 'Declined'
    }
}
[IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$record
