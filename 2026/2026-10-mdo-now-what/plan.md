# Plan: We turned on Defender for Office 365. Now what?

## Shape

One fictional incident carries the whole session: a supplier invoice leads to a compromised mailbox, the attacker hides their tracks, then shifts to QR codes, Teams and finally the AI that reads the user's mail. Each act is a demo; slides only open and close.

| Time | Act | Abstract promise | Deck slides | Query |
|---|---|---|---|---|
| 09:40 | Open | | 1-4 | |
| 09:43 | Protection order and policy priority | Threat Explorer and Email entity context | 5-8, 12, 13, 15 | |
| 09:47 | AiTM: the click that MFA did not stop | AiTM phishing | 19 | `01-aitm-click-to-signin.kql` |
| 09:53 | Inbox rule: hiding the evidence | Post-compromise inbox rule abuse | 21 | `02-inbox-rule-after-signin.kql` |
| 09:57 | SCL -1: the door you opened yourself | SCL -1 bypass | 24 | `04-scl-bypass-exposure.kql` |
| 10:01 | QR code: the URL Safe Links never saw | QR code evasion | 25 | `03-qr-code-campaign.kql` |
| 10:05 | Get it right next time | False positive and false negative workflows | 27, 29 | Portal |
| 10:10 | Teams | Newly released Teams protection | 31 | `05-teams-post-delivery.kql` |
| 10:15 | Bonus: the email written for the AI | Detection capabilities shipped this year | 33, 34 | `06-prompt-injection-verdicts.kql`, `../mdo-prompt-injection/kql/matrix-scorecard.kql` |
| 10:22 | Take home and tools | Ready-to-use queries | 35, with a QR code to `kql/`; 36, MET and DMARC for Defender XDR with a QR code each | |
| 10:25 | Q&A | | 37 | |

Fifty minutes, Experts Live Sweden. Slides 9-11, 14, 16-18, 20, 22, 23, 26, 28, 30 and 32 are hidden in the deck: text-heavy framing and on-screen code that the live demos replace. The code slides stay as fallbacks if a query fails.

## Deck

`events/else-2026/slides/ELSE_MDO.local.pptx`, on the Experts Live Sweden template: 23 visible slides, eight of them DEMO dividers. The speaker notes on every demo slide carry the clicks, the query file and the fallback. The take-home slide's QR code opens `github.com/pthoor/sessions/tree/main/2026/2026-10-mdo-now-what/kql`, which only resolves once this folder is merged to `main`.

## Demo inventory

Staged Monday morning by [staging.md](staging.md); every script is one item per invocation, previews before it signs in, and only uses reserved `.invalid` destinations.

| Act | Evidence | Staged by |
|---|---|---|
| 1 | Supplier invoice with a Safe Links click, then a successful sign-in from a second IP within the hour | `scripts/Send-MdoDemoMail.ps1 -Scenario InvoiceLink`, a manual click, then an Outlook sign-in over a phone hotspot |
| 2 | Inbox rule named "." moving invoice mail to Conversation History, created from the hotspot IP | `scripts/Set-MdoDemoInboxRule.ps1` |
| 3 | MFA re-registration lure whose only URL is inside an inline QR image | `scripts/Send-MdoDemoMail.ps1 -Scenario QrCode` |
| 4 | Payment notice that a scoped SCL -1 rule lets bypass spam filtering | `scripts/Set-MdoDemoSclBypassRule.ps1`, then `scripts/Send-MdoDemoMail.ps1 -Scenario SclBypass` |
| 5 | Live false-negative submission of the act 3 email | Nothing to stage |
| 6 | External Teams message with a URL | The lab's `Send-XpiaTest.ps1 -PayloadId exfil-visible -Channel Teams`; the cross-tenant Teams send path is still unproven, so fall back to any existing external Teams message in Explorer |
| 7 | Prompt-injection matrix | `../mdo-prompt-injection/runbook.md` waves 0 and 1 |

The staging recreates the signals each attack leaves, not the attack itself: no credential-harvesting proxy is built, and the act 1 "attacker" sign-in is the lab user over a second network. Say so on stage in one sentence; the hunting technique is identical.

## Risks

| Risk | Mitigation |
|---|---|
| Hunting data for staged events older than 30 days | Stage on Monday; queries default to 7 or 30 days |
| Conference Wi-Fi or portal outage | Recorded walkthrough per act; slide 5 for the matrix |
| `ConfidenceLevel` JSON shape differs from the query's `Spam` key | The `ExchangeTransportRule` branch still finds the message; confirm on Monday |
| Entity preview unavailable for quarantined mail | Open from the quarantine page instead |
| Show concealed text renamed or unavailable in the tenant | Show the raw HTML from Download email; say it plainly |
| Disclosure gate for a new prompt-injection miss | Decide before Tuesday per `../mdo-prompt-injection/runbook.md`; show the verdict only |
| Two events in three days | NIC reuses the ELSE deck; update only template and event slides |
