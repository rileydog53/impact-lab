# Where things live

| Thing | Location | Tracked in git? |
|---|---|---|
| App source (Swift) | `Sources/ImpactPhysics`, `Sources/ImpactLab`, `Sources/ImpactCheck`, `Package.swift` | yes (main) |
| Product plan and Card 1-7 evidence | `PLAN.md`, `docs/PRODUCT_RECOVERY.md`, `docs/PHASE_0_*.md` | yes |
| Card 6 evidence and user checklist | `docs/audit-evidence/card6/`, `docs/CARD6_USER_CHECKLIST.md` | yes |
| Contact reporting, MPM prototype, scene format | `docs/CONTACT_REPORTING.md`, `docs/MPM_PROTOTYPE.md`, `docs/SCENE_FORMAT.md`, `docs/scene-examples/`, `docs/lab-examples/`, `docs/showcase/` | yes |
| **Decision record (master)** | Google Doc 16eP-voxibkm0itNqP-NTea9VBiM7zxA6SJO1nF-3R-4, append-only, dated | Google Docs |
| Beam verification study | `research/beam-verification/` on Joseph's Mac | **no, Mac only** |
| Design notes 01-04 (plastic work, source trees, scene v2, Card 6 reconciliation) | `research/design-notes/` on Mac; also in the project shared folder | **no, Mac only** (plus project folder) |
| Material-separation research tree and its PLAN.md | `research/material-separation/` on Mac | **no, untracked, Mac only** |
| Contact and metal-contact reports, figures, CSVs, materials architecture proposal | project shared folder (CONTACT_GATE_REPORT.md etc.) | no |
| Auditor and handoff scripts | `auditor.py`, `agent_audit.py`, `audit/` in the Mac working folder | no |
| Mac working folder | `~/Desktop/shopping(noVOL)` (has uncommitted edits at time of writing) | partly |
| Consolidated build clone used for PR 1 | `~/Desktop/TEMP/2026-11-24/impactlab-integration` | git clone |

## Preservation
Nothing was moved or deleted. `archive-copies/` holds **labelled copies** of the Mac-only research files so they survive if the Mac folder is lost. Originals stay where they are and win if they differ. `material-separation-PLAN.md.copy` is a copy of an *older, different* PLAN.md from another source tree (it contains Phase 0 material and an older Card 6 status); do not treat it as current.

## Quick rules
- For what Joseph approved: DECISIONS.md, then the Google Doc.
- For how to run checks: `swift build -c release`, then `.build/release/ImpactCheck --help`-style flags listed in PLAN.md.
- Git is handled quietly for Joseph; new branches only, no merges without his approval.
