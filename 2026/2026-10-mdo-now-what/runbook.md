# Runbook: We turned on Defender for Office 365. Now what?

## Before each delivery

- Browser profile signed in to the demo tenant's Defender portal, zoom 150 %, notifications off.
- Tabs, left to right: Threat Explorer (All email, last 7 days), Advanced hunting with the six `kql/` files saved as queries, Incidents, Submissions, Quarantine, Exchange admin center mail flow rules, Teams web client.
- Prompt-injection scorecard query filled from Monday's run records and saved.
- Recorded walkthrough for every act in `events/<event>/fallback/` as `.local.mp4`.

## Beats

| Act | Start on | Say | Click | Land on |
|---|---|---|---|---|
| 1 | Explorer | "Defender delivered this. Now what?" | Filter recipient, open the invoice mail, **Open email entity**, URL tab, then Advanced hunting `01` | Released high-confidence phish, then a sign-in from a second IP minutes after the click |
| 2 | Advanced hunting | "The attacker's first job is to stop you seeing replies." | Run `02`, expand `Parameters` | Rule "." moving invoice mail to Archive, created in Outlook on the web from the same IP as the unfamiliar sign-in |
| 3 | Explorer | "Safe Links can't rewrite a picture." | Open QR mail, Email preview, Advanced hunting `03` | `SafeLinksClicks = 0` while recipients > 0 |
| 4 | Entity page headers | "This one you configured yourself." | Message headers, `SCL:-1`, then `04` | The demo rule name with `BypassRequested` > 0; in a real tenant, any rule with `DeliveredWithThreat` > 0 |
| 5 | Explorer | "A miss is a ticket to Microsoft, not a shrug." | Submit the QR mail as should have been blocked; open Submissions | Submission result and allow/block entry |
| 6 | Teams | "Same attacker, other app." | Teams message in Explorer, then `05` | ZAP row in `MessagePostDeliveryEvents` |
| 7 | Scorecard | "Some emails aren't written for you at all." | Run the scorecard, open the hidden-HTML cell, Email preview, **Show concealed text**, then the Unicode-tag cell | Hidden instruction revealed; tag-character cell stays invisible or is shown, stated as observed |

## Never

- Send attack traffic live.
- Show unblurred tenant identifiers, real addresses or message IDs on screen longer than needed; prefer the demo tenant only.
- Claim Teams prompt-injection detection.
