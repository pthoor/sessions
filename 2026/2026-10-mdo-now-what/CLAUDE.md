# Session: We turned on Defender for Office 365. Now what?

Speaker: Pierre Thoor. Same session, two deliveries in one week:

| Event | Date | Venue | Folder |
|---|---|---|---|
| Experts Live Sweden 2026 | Tue 2026-10-13, 09:40-10:30, Room Coligo | Folkets hus, Barnhusgatan 12, Stockholm | `events/else-2026/` |
| NIC 2026 | Thu 2026-10-15 (to confirm on the NIC agenda) | Oslo Spektrum, Oslo | `events/nic-2026/` |

The Experts Live Sweden slot is 50 minutes; the run of show in `plan.md` follows it. Confirm the NIC slot before Thursday.

## Abstract (Sessionize, as submitted)

This session picks up where deployment ends and real security operations begin. Through live demonstrations, we investigate actual attack scenarios - AiTM phishing campaigns, post-compromise inbox rule abuse, QR code evasion, and the silent SCL -1 bypass that lets threats walk straight past your filters.

You'll see the full investigation lifecycle in Threat Explorer and Email Entity Panel, write Advanced Hunting queries that surface what dashboards miss, and walk through the false positive and false negative workflows that keep your detection sharp. We also cover the newly released Teams protection capabilities in MDO - because attackers aren't limiting themselves to email anymore.

No slides-only theory. Every concept is demonstrated with real emails, real headers, and real KQL. You'll walk out with ready-to-use hunting queries and investigation techniques you can run in your own tenant on Monday.

## Rules for this session

- **Demo over slides, always.** A slide earns its place only if it frames a demo, credits someone, or is the takeaway. Text and code slides stay hidden in the deck as fallbacks rather than being deleted.
- **Slides use each event's PowerPoint template**, not the repo's HTML `frontend-slides` default. The speaker chose this for these deliveries. Event templates and working decks stay as `*.local.pptx` and are never committed; only a reviewed PDF export may be committed after the session.
- Every promise in the abstract maps to a demo in `plan.md`. Do not cut a promised topic without saying so on stage.
- Prompt injection is the bonus act. It reuses the lab in `../mdo-prompt-injection/` and its locked verifier; stage claims follow that lab's `runbook.md`.
- KQL in `kql/` is the "ready-to-use" handout. Each query must run unchanged in a fresh tenant with Defender for Office 365 Plan 2 and Entra ID P2. Use `EntraIdSignInEvents`; `AADSignInEventsBeta` is retired on 2026-10-19.
