# Hunting queries: We turned on Defender for Office 365. Now what?

Paste any of these into Advanced hunting in the Microsoft Defender portal. They need Defender for Office 365 Plan 2; `01` and `02` also need Entra ID P2 for `EntraIdSignInEvents`, and `02` needs the Microsoft 365 app connector in Defender for Cloud Apps for `CloudAppEvents`. They use `EntraIdSignInEvents` rather than `AADSignInEventsBeta`, which Microsoft retires on 19 October 2026; move your own queries before then.

| Query | Question it answers |
|---|---|
| [01-aitm-click-to-signin.kql](01-aitm-click-to-signin.kql) | Who clicked an email link and then signed in successfully from a different IP within an hour? The pattern an adversary-in-the-middle phishing kit leaves behind. |
| [02-inbox-rule-after-signin.kql](02-inbox-rule-after-signin.kql) | Which inbox rules delete, hide, mark as read or forward mail, and from which IPs did that user sign in? Covers rules made in PowerShell (`New-InboxRule`) and in Outlook or Graph (`UpdateInboxRules`). |
| [03-qr-code-campaign.kql](03-qr-code-campaign.kql) | Which domains arrive only inside QR code images, how many recipients got them, and how many are still in an inbox? Safe Links click counts stay near zero because the scan happens on a phone. |
| [04-scl-bypass-exposure.kql](04-scl-bypass-exposure.kql) | Which mail flow rules and connectors let inbound mail skip spam filtering, and how much of that mail carried a threat verdict? |
| [05-teams-post-delivery.kql](05-teams-post-delivery.kql) | Which Teams messages did Defender see, with which URLs, verdicts, safety tips and post-delivery actions such as ZAP? Covers external chats and internal messages that contain URLs. |
| [06-prompt-injection-verdicts.kql](06-prompt-injection-verdicts.kql) | Which inbound emails were caught by prompt injection protection? |
| [07-clicks-on-released-phish.kql](07-clicks-on-released-phish.kql) | Who clicked a link in an email that Defender quarantined and someone then released? Shows the original verdict and detection next to the click. |

Start with a short lookback in a large tenant; each query declares `Lookback` on its first line.
