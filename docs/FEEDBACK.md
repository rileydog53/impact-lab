# Impact Lab feedback log

Joey's raw feedback, sorted into distinct findings. Each finding keeps his own words with a short verbatim quote. Duplicates are merged into one finding. Where his meaning isn't clear, the finding is marked **Unclear** instead of being interpreted.

Finding numbers are permanent. New chunks add new numbers, so a number always points to the same finding.

## How to read a finding

**Block level** (how much it stops Joey from using the lab):

- **Blocking**: he can't do what he set out to do.
- **Slows me down**: he can work around it, but it costs time or trust.
- **Minor**: an annoyance, doesn't stop the work.
- **Unclear**: the feedback doesn't say.

**Change type:**

- **Physics/solver**: the fix needs a change to how the simulation computes things.
- **Interface/wording**: the fix is in the app's screens, labels or help text only.
- **Not known yet**: can't tell from the feedback alone.

Anything that isn't Joey's own words is labeled as a description or a repo note.

## Chunk log

| Chunk | Date | What it covered |
|---|---|---|
| 1 | 2026-11-25 | Plate inside an enclosure bends instead of punching through; the "bendability" setting has no name he knows |

## Findings by block level

| # | Finding | Category | Block level | Change type |
|---|---|---|---|---|
| 1 | Strong plate bends like a crayon instead of punching through | Bug | Blocking | Not known yet |
| 2 | Doesn't know the name of the "bendability" setting | Confusing wording | Slows me down | Interface/wording |

## Bugs

### 1. A strong, no-fracture plate bends instead of punching through the enclosure and panel

- **His words:** "it bends like a fucking crayon, even though I've maxed out the bendability thing"
- **What he set up (his words):** "The internal volume is a high density, high strength, no fracture. Low mesh, the external enclosure has fracture turned on more dense mesh, and the internal should penetrate through it and break into the plating."
- **What he expected:** the inner plate goes through the enclosure and breaks into the panel.
- **What happened (description of his screenshot, not his words):** "Rectangular Plate 3" (blue, fracture off, coarse mesh) sits inside "Hollow Enclosure 2" (brown, finer-meshed shell), moving left toward a "Carbon-skinned aluminium panel" fixed at its base. The plate bent into a curved banana shape inside the enclosure, and the enclosure wrapped and smeared around it. Nothing went into the panel, only a contact point on its face. Dashed outlines show the original shapes.
- **Block level:** Blocking. This is the experiment he was trying to run.
- **Change type:** Not known yet. It could be the solver, the material limits, or the setup. See the repo note below.
- **Repo note (Claude's reading of the code, not Joey's words, not checked against his scene file):** in the body Material settings, "Young’s modulus (MPa)" can only be set between 0.5 and 4 MPa, which is rubber-soft. If the plate used those editor numbers rather than a Material Library profile, "maxed out" would still be very bendy. This is a lead to check, not a conclusion.

## Missing features

None yet.

## Confusing wording

### 2. He doesn't know what the "bendability" setting is called

- **His words:** "I've maxed out the bendability thing, and I don't know what to call that"
- **Block level:** Slows me down. He can't name the setting, so he can't tell whether he changed the right one.
- **Change type:** Interface/wording.
- **Repo note (Claude's reading, not Joey's words):** **Unclear** which control he means. The body Material settings have three that change how a body bends or gives: "Young’s modulus (MPa)" (stiffness), "Yield / E (%)" (when it starts to bend permanently) and "Hardening / E (%)" (how much it stiffens as it bends). The last two only show when Response is set to Elastoplastic. He said more on this "will be coming in the feedback", so this stays open until that chunk arrives.

## Ideas

None yet.

## Frustrations

None yet. Finding 1 carries clear frustration, but it's filed once, as a bug, rather than twice.

## Concerns

None yet.
