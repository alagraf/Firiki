# Labour contract templates and the routing set (PoC capability 4)

`contracts/`: 10 Greek labour contract templates, drafted by Claude Code from the Labour Code
(Π.Δ. 62/2025) and the laws of `../GreekLabourLibrary` (owner's choice, 2026-10-29). Each is marked
as a proof-of-concept draft that is not legal advice. Every clause that states a rule cites its
article, and the cited text was checked against the Code's PDF.

| # | id | Contract | Main articles |
|---|---|---|---|
| 1 | `indefinite_full_time` | Indefinite-term, full-time | 1, 2 (probation up to 6 months), 73, 194 |
| 2 | `fixed_term` | Fixed-term (seasonal, replacement, project) | 73, 94–100, 323–325 |
| 3 | `part_time` | Part-time | 113 (written, notified within 8 days; extra hours +12%) |
| 4 | `rotating_work` | Rotating: full days, fewer days or weeks | 113 §3 (imposed: at most 9 months a year) |
| 5 | `unpredictable_schedule` | Unpredictable schedule, on call | 73 §1 ιγ', 190 (at least 24 hours' notice) |
| 6 | `telework` | Telework | 130 (§4 costs, §10 right to disconnect) |
| 7 | `apprenticeship` | Apprenticeship, ages 15–18 | 136 (up to 1 year, 70% of the minimum wage) |
| 8 | `internship` | Student internship | 137, 138 |
| 9 | `temporary_agency` | Temporary agency work | 114–129 (joint liability) |
| 10 | `urgent_needs` | Urgent needs, up to 2 days a week | 578Α (Ν. 5239/2025 article 21) |

Each file has front matter (`id`, Greek and English title, articles, Greek and English keywords and
description) for the router, then the contract with `{{placeholders}}`. The ten common terms come
from article 73 §1 of the Code (the essential terms an employer must state).

The Code doesn't regulate domestic workers or a mutual-termination agreement as contract types, so
the suggested set in `Docs/Thesis/plans/poc-remaining-work.md` was changed: temporary agency work
and urgent-needs hiring replace them, and seasonal work is a case of the fixed-term template.

`routing_v1.jsonl`: 66 prompts, 6 per template (3 Greek, 3 English) and 6 that fit none, labelled
with the template id or `none`, split 44 dev / 22 test. Worded as users ask, not from the templates'
keywords. Tune the router on dev only.

When the router is built, the templates move to `OpenIntelligence/Resources/LabourContractTemplates/`
so they ship in the app.
