# Staging: Monday 2026-10-12

Every act needs evidence in the protected tenant before Tuesday. This is the order that produces it in one morning. Allow two hours of hands-on time plus ingestion waits; Advanced hunting can lag up to an hour.

## Lessons from the first staging run (2026-10-12)

- Run Exchange Online steps and Microsoft Graph steps in separate `pwsh` processes. Exchange Online loads an older MSAL and Graph sign-in then fails with `Method not found ... WithLogging`.
- In a Codespace, browser sign-in works once `~/.local/bin/xdg-open` forwards to `$BROWSER`; device code sign-in may be blocked by Conditional Access (error 53003).
- The InvoiceLink lure was quarantined as High confidence phish by Advanced filter. Act 1 uses that: release it to the lab user, then click. Do not reword the lure to evade detection.

## Before you start

- PowerShell 7.2 or later on your laptop, with `Microsoft.Graph.Authentication` 2.39.0 and `ExchangeOnlineManagement` 3.10.1.
- The prompt-injection lab's `demo/config/lab.local.psd1` is already filled in from the September runs; these scripts reuse its attacker tenant, protected mailbox and allowed domains.
- The protected lab user is in scope of Safe Links and anti-phishing (Standard or Strict preset).
- Two browser profiles: attacker test user and protected lab user. A phone that can share a hotspot.

Run everything from `2026/2026-10-mdo-now-what`:

```powershell
$config = '../mdo-prompt-injection/demo/config/lab.local.psd1'
```

Each send script previews first without signing in. Open the `results/<RunId>.preview.local.html` it writes, then rerun with `-AcknowledgeLabUse -Confirm` to send.

## Sequence

| Time | Act | Step | Command or action |
|---|---|---|---|
| 08:00 | 4 | Create the scoped SCL -1 rule in the protected tenant as an Exchange admin. It matches only the attacker test sender plus the demo header. Rules can take up to 30 minutes to apply. | `./scripts/Set-MdoDemoSclBypassRule.ps1 -SenderAddress <attacker test sender> -Organization <protected tenant domain> -Confirm` |
| 08:05 | 1 | Send the supplier invoice as the attacker. | `./scripts/Send-MdoDemoMail.ps1 -Scenario InvoiceLink -ConfigPath $config -AcknowledgeLabUse -Confirm` |
| 08:10 | 1 | On your normal network, open the invoice in Outlook as the protected user and click **View invoice INV-48213**. Safe Links records the click; the `.invalid` page fails to load, which is expected. | Manual |
| 08:15 | 1, 2 | Switch the laptop to the phone hotspot. In a private window, sign in to `outlook.office.com` as the protected user. This is the "attacker replaying the session" sign-in from a second IP. | Manual |
| 08:20 | 2 | Still on the second network, create the hiding rule in Outlook on the web as the protected user: name `.`, subject includes invoice, remittance or payment, move to Archive, mark as read, stop processing more rules. The rule and the sign-in share the unfamiliar IP. `Set-MdoDemoInboxRule.ps1` does the same through Graph but needs user consent for Microsoft Graph Command Line Tools, which a locked-down tenant blocks; do not grant tenant-wide admin consent for it. | Manual |
| 08:25 | | Switch back to your normal network. | |
| 08:30 | 3 | Send the QR lure. Open it once as the protected user; do not scan it. | `./scripts/Send-MdoDemoMail.ps1 -Scenario QrCode -ConfigPath $config -AcknowledgeLabUse -Confirm` |
| 08:40 | 4 | Send the payment notice that carries the bypass header. | `./scripts/Send-MdoDemoMail.ps1 -Scenario SclBypass -ConfigPath $config -AcknowledgeLabUse -Confirm` |
| 08:45 | 6 | Send the Teams message. It is the lab's exfiltration carrier, so act 6 can show that Teams sees the URL but has no prompt-injection verdict. | `../mdo-prompt-injection/demo/Send-XpiaTest.ps1 -PayloadId exfil-visible -Channel Teams -TargetProfile Protected -ConfigPath $config -AcknowledgeLabUse -Confirm` |
| 08:50 | 7 | Prompt-injection wave 0, then wave 1 after the baseline verdict. | `../mdo-prompt-injection/runbook.md` |
| 09:15 | 4, 6 | After the SCL -1 rule has applied, run MET read-only as Security Reader and keep the HTML report open in a tab for acts 4 and 6. MET-EXO007 must list the demo rule; MET-Teams004 shows ZAP for Teams. | `Install-Module MET -Scope CurrentUser; Connect-METSession; Invoke-METAssessment -CheckId MET-EXO007, MET-Teams004 \| Get-METReport -Format HTML -OutputPath ./results` (rename the report to `*.local.html`) |
| 10:00 | all | Run `kql/01` to `kql/06` in Advanced hunting. Save each as a shared query in a folder named "Now what". Every act must return at least one row; if one is empty, check the table below. | Portal |
| 10:30 | all | Record a fallback walkthrough per act as `events/else-2026/fallback/<act>.local.mp4`. | |

## If a query is empty

| Query | Likely cause |
|---|---|
| `01` | No `ClickAllowed` row: Safe Links did not wrap the link for this user, or the click came from a non-Outlook client. The sign-in IP equals the click IP: the hotspot step was skipped. |
| `02` | The rule was created before the hotspot sign-in, or ingestion has not caught up. `RuleDetail` shows the raw parameters for any rule action. |
| `03` | The QR image was not extracted. Check the email entity page URL tab for a QR code URL before assuming a hunting gap. |
| `04` | `ConfidenceLevel` does not hold the SCL under `Spam` in this tenant; the `ExchangeTransportRule` branch still returns the message once the rule applied. If neither returns it, the rule had not replicated before the send. |
| `05` | The chat is internal and the message has no URL, or the Teams send failed. Check the lab run record. |
| `06` | Prompt-injection wave 0 has not produced a verdict yet. |

## Act 5 needs no staging

Submit the QR lure from Threat Explorer as **Should have been blocked** live on stage, then open **Submissions** to show the result and the Tenant Allow/Block List entry. If the submission result takes too long, show yesterday's result from Monday's rehearsal.

## Teardown after Thursday

```powershell
./scripts/Set-MdoDemoInboxRule.ps1 -ConfigPath $config -Remove -Confirm
./scripts/Set-MdoDemoSclBypassRule.ps1 -Organization <protected tenant domain> -Remove -Confirm
```

Delete the staged messages from the protected mailbox after any evidence you want to keep is exported. Run records stay in `results/*.local.*` and are never committed.
