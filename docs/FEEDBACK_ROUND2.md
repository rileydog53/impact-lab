# Feedback round 2 (2026-11-26), checked against the current build

Joseph's condensed acceptance feedback, written while testing an **old build**. `launch.command` had rebuilt the app from a branch that was a day old (cb12a1c), before PR 36. Each item below is checked against the **current build**: main at 533dfe3, opened from the Desktop shortcut "Impact Lab (test build)".

**How each item was checked**
- **Built app:** text searched for in the app file itself.
- **Headless run:** a scene run with that build's `ImpactCheck run`.
- **Source only:** the code was read; nothing was run.

Nothing in this file counts as fixed until Joseph has seen it in the app (his item 9).

**Status**
- **Fixed in current build:** the behaviour changed after the build he tested.
- **Still applies:** nothing has changed it yet.
- **Can't tell:** it needs his scene or his eyes.

**Tag**
- **Interface:** screens, wording or controls only.
- **Physics:** the fix would change how the simulation calculates. That kind of change goes to Joseph first.

Overall status in his words: "Not accepted. Further testing underway."

| # | His words (condensed) | Status | Tag | What was checked |
|---|---|---|---|---|
| 1 | "Some materials, including copper, cannot use fracture despite other metals supporting it." | **Fixed in current build** | Interface | The old build blocked cracking for any Library material with no sourced crack numbers. PR 36 removed that block, and its message is no longer in the built app. Headless run on 533dfe3: the cascade showcase with cracking switched on for the copper bar ran to the end, in 7 s at the standard mesh, with `fracture: true` for copper. Bodies that still can't crack: round bodies, fixed supports, and a layered block that also has a V-notch. Round bodies are blocked because their mesh has no edges for cracks to follow, so changing that would be a physics change. |
| 2 | "Density and other properties are difficult to edit. Fracture energy, cohesive strength, and material models lack clear explanations." | **Partly fixed** | Interface | Built app: the ⓘ explanations are there ("About this setting" text, with everyday comparisons for crack start, crack resistance and how it behaves). Can't tell whether density is still hard to edit: that needs his eyes. |
| 3 | "Hollow enclosure editing works well, but selection states, thickness controls, numerical entry, and undo need improvement." | **Still applies** | Interface | Source only: none of these controls changed after the old build. |
| 4 | "Assembly-level overrides are confusing. Mesh adequacy warnings are excessive, and changing resolution does not produce clearly understandable performance improvements." | **Still applies** | Interface | Source only: the mesh notes and controls are the same apart from wording. |
| 5 | "Calculations can take approximately six minutes, with lag and inaccurate completion-time estimates near the end." | **Still applies** | Physics (speed) and Interface (estimate) | Source only: the solver and the time estimate are unchanged apart from wording. For scale, the copper cascade with cracking took 7 s at the standard mesh. **Hypothesis**, not checked: a six-minute run most likely comes from a fine mesh together with cracking on a stiff material, because crack faces are held shut by very stiff springs that force tiny steps. His scene file would settle it. |
| 6 | "The requested warning for bodies that will not make contact was absent in the tested build." | **Fixed in current build** | Interface | Built app: the text "Nothing is moving toward anything else…" and "The run ends before anything touches…" is in the app, with a button that lengthens the run. The forecast logic is checked in CI (LibraryForecast). To see it: in an assembly with two or more bodies, look just above Run length. |
| 7 | "Repetitive scientific warnings overwhelm the interface while failing to explain actionable consequences." | **Still applies** | Interface | Source only: per-body notes are unchanged, and PR 45 added one more (the smoothing warning). |
| 8 | "Calculated behavior, illustrative visuals, material assumptions, and model limitations must be clearly distinguished." | **Still applies** | Interface | Source only: no labelling pass has been done yet. |
| 9 | "Reported fixes must be verified in the actual delivered application, not merely identified in source code." | **Process fixed** | Process | The Desktop shortcut always opens the shared build. PR 46 stops `launch.command` from rebuilding old code. Claude now checks the build he actually has open, not just the source. |
| 10 | "Focus on usable experimental capabilities rather than additional restrictions, provenance displays, and explanatory warnings." | **Standing rule** | | Used to order the next builds below. |
| 11 | "The sabot did not fracture as expected during replay. I cannot determine whether this is physically reasonable…" | **Can't tell** | Interface (explain) or Physics | His sabot scene isn't saved anywhere on the Mac. See "Why a metal part may not crack" below. |
| 12 | "The simulation was slow enough that I was unwilling to repeat it." | **Still applies** | Physics (speed) | Same as item 5. |
| 13 | "No claims about its fixes should be accepted until they are observed in that version." | **Agreed** | | Items 1, 2 and 6 are the ones to look at in the current build. |

## Why a metal part may not crack (item 11)

A body cracks only if all three of these hold:

1. **"Can crack" is ticked for that body.** It is off by default.
2. **The pull inside it passes "Crack starts at".** For a Library metal, this starts at the top of the metal's strengthening table: about 225 MPa for soft copper and 345 MPa for aluminium.
3. **Enough energy goes into the crack** ("Crack resistance") to open it all the way.

A metal usually bends for good long before it reaches that pull. In the copper check above, the bar bent hard: about 10,000 J/m went into permanent bending, but no energy went into cracking. That matches real ductile metal, which dents and tears rather than shatters.

**Hypothesis**, not checked against his scene: the sabot bent instead of cracking for the same reason. Also, "Crack resistance" for metals is a placeholder (1000 J/m², not from a source). Saving the sabot scene (File > Save) would let this be checked headless and settled.
