> COPY made 2026-11-24 for preservation. Original: research/design-notes/04-card6-acceptance-reconciliation-next-milestone.md on Joseph's Mac (untracked). The original wins if they differ.

# 4. Card 6 acceptance, build reconciliation, open questions, backlog and next milestone

Date: 2026-11-24. Planning and documentation only. No code, branch, merge or PR state was changed while writing this.
Status key: **[verified]** read in code, git or a stored file on this Mac today; **[recorded]** read from an evidence file produced earlier, not re-run today; **[hypothesis]** inference, untested.
Three kinds of claim are kept apart throughout: **personal acceptance** (Joseph's judgment of the app), **numerical verification** (the solver solves its equations correctly), **physical validation** (the equations match real materials; needs measured data the project does not have).

Source read: consolidated build, separate clone `~/Desktop/TEMP/2026-11-24/impactlab-integration`, branch `claude/project-thread-x71vkq` at `ec21689`, draft PR rileydog53/impact-lab#1.

---

## 1. Acceptance recorded

Google Doc section 24 holds Joseph's acceptance verbatim: Card 6 ACCEPTED for the consolidated laboratory recovery build, application experience and demonstrated functionality only, not scientific validation of any material or fracture model, plus his ten confirmed improvements. Nothing else was marked approved. Section 6 still says A-006 PENDING because the doc is append-only; section 24 governs it.

Which build he accepted [verified]: the running app process `.../impactlab-integration/.build/Impact Lab.app` was started 2026-11-24 00:56 ET, and its binary is from 00:56, after the branch head `ec21689` (2026-11-23 22:47 ET). The working tree has no tracked changes. **A second, older app is also still running**, from `~/Desktop/impactlab-materials` (started 2026-11-23 21:09, the build he tested before, `ff7304b`). Both share the bundle id `local.shopping.impactlab`, so they share saved preferences, including the runtime speed calibration. Worth quitting the old one so the two windows are not confused.

---

## 2. Reconciliation with the engineering decision record

### What is in the consolidated build [verified, git]
Linear on top of `main` 724e32b (main is an ancestor, so PR 1 would merge without conflicts):

| Commit | Content | Decision-record basis |
|---|---|---|
| 5446268, ff7304b | Materials: absolute fracture strength in Pa, sourced toughness estimates, reserved material-state schema, legacy-replay gate, Copy Summary | section 19 approval 2 (design notes), section 23 item 1 |
| d00c8f0 (merged at 05eca4a) | Contact reported as pulses with stated windows; raw peak labelled diagnostic; metal low-speed rebound kept OPEN | 17c, approved reporting-only |
| 62dc811 | Fixed supports, clamped edges, gravity, spring preload, with gates `--supports-gravity`, `--lab-examples`, `--run-cost` | section 23 items 3, 4 |
| ec21689 | Workbench UI: explanations, run-time warnings, anchor dragging, Edit a Copy, run history | section 23 items 2, 4, 5 |

Already contained, nothing left to merge: `claude/fracture-audit` (1fd5e7f), `claude/project-thread-dhtt8a` (ff7304b), `contact-reporting` (d00c8f0). PR 1 changes 41 files, +2,413 / −130.

### What is still outside it [verified, git]
- `material-separation` (47ccaad, 3 commits on 724e32b: 717f8dc, fc188ee, 47ccaad). Experimental tensile initiation and symmetric crack kinematics. Held out on purpose (section 23 item 1, D-003). A trial merge (`git merge-tree`, nothing written) **conflicts** with the consolidated build in `AssemblyEditor.swift` and `AssemblyScene.swift`, and touches `AssemblySimulation.swift`, `MaterialFracture.swift`, `SceneDocument.swift` and the scene schema.
- `fem-deformation-study` (717f8dc, 1 commit). A research measurement with a small hook in `AssemblySimulation.swift`. A trial merge **conflicts** there.
- PR 1 itself: still DRAFT, not merged.

### Duplicated or stale [verified unless marked]
1. **Two competing "strength in pascals" fields.** The integrated materials work added `MaterialFractureSettings.strength` (absolute Pa, initiation on total traction). The held-out branch adds `tensileStrength` (absolute Pa) that also switches the initiation rule to tension only. If both ever land, a scene could carry two strengths with different meanings. They should become one strength value plus an explicit "initiation rule" choice. This is a design decision for whenever material-separation is reviewed, not now.
2. **Extra local copies.** `~/Desktop/impactlab-materials`, `~/Desktop/TEMP/2026-11-23/impactlab-contact-reporting`, and the worktree `~/Desktop/TEMP/2026-11-22/impactlab-claude-audit` hold nothing that is not already in the consolidated build or main. Only `main`, the integration clone and `research/material-separation` are still needed.
3. **Remote branches whose work is fully contained:** `claude/fracture-audit`, `claude/project-thread-dhtt8a`, `contact-reporting`. Harmless, but clutter once PR 1 merges.
4. **Research that exists only on this Mac.** In the main checkout `research/` (beam-bending verification, design notes 01 to 04), `tests/`, `reports/`, audit scripts and handoff docs are untracked, so they are not on GitHub. The beam-bending result in particular is evidence the roadmap leans on.
5. **PLAN.md still shows Card 6 unchecked** on every branch, and the doc's A-006 line reads PENDING (by design, see section 24).
6. **Research note 02** recommended replacing the nested `research/material-separation` clone with a worktree. Still open, low priority.

### Safest integration path to main (PROPOSAL, nothing done, merging needs Joseph's yes)
1. On the PR 1 branch, one docs-only commit: tick Card 6 in PLAN.md with a one-line pointer to doc section 24.
2. Fresh release build of that head and re-run the existing gates: `--legacy-replay`, `--supports-gravity`, `--lab-examples`, `--run-cost`, `--contact-reporting`, `--materials`, `--scene-documents`, plus `--fracture-convergence` (about 1.5 min wall time in the recorded run). Criteria unchanged.
3. Tag the current main (`pre-card6-main` at 724e32b) so main can always be returned to it.
4. Mark PR 1 ready and merge it as a merge commit (main is an ancestor, so no conflicts are possible).
5. After merge: keep `material-separation` and `fem-deformation-study` as research branches. Each gets re-cut on the new main only when its own review is approved, resolving the strength-field duplication (item 1 above) at that time.
6. Separately, with OK: push the untracked `research/` notes to a docs branch so they are on GitHub, and move the three stale local copies to the Trash.

---

## 3. Open questions answered from the code

### 3a. Geometry restrictions: necessary, implementation limit, or arbitrary? [verified from code unless marked]

The key fact: the mesher uses an **absolute** cell size, about 9 mm at Standard (`AssemblyScene.swift` `makeBody`, `size / 0.009`), divided by the refinement (Fine ≈4.5 mm, Extra fine ≈3 mm, up to ×7 ≈1.3 mm), with at least 3 cells across. So a 10 mm block would already mesh, with 3 smaller cells. The 25 mm minimum is a validation constant (`sizeRange = 0.025...0.30`), not something the mesher needs.

| # | Restriction | Where | Cause | Class | What relaxing it takes |
|---|---|---|---|---|---|
| G1 | Body size ≥ 25 mm | `AssemblyPart.sizeRange` | Keeps ≥3 triangles across at Standard mesh. The mesher would still give 3 cells for smaller bodies. | **Implementation choice** tied to the fixed absolute mesh size | Make the minimum follow the chosen mesh (for example at least 3 cells at the selected refinement) and state the real consequences on screen: a small body means small triangles, so a short timestep (dt ∝ cell size / wave speed) and a longer run. Widening a range keeps old scenes valid. Small. |
| G2 | 3 rows across is "enough" | same | Not a scientific criterion. Beam verification (doc 2026-11-24 entry) needed about **8 rows** through the thickness for under 5% error in bending at L/h = 20 (period error −23% at 2 rows, −7% at 4, −1.4% at 8). | **Genuine numerical limit**, currently not explained | Warn when a body in bending has fewer than about 8 rows: "bending will be too stiff". Display only. |
| G3 | Body size ≤ 300 mm (fixed supports ≤ 1,000 mm) | `sizeRange`, `fixtureWidthRange` | Triangle count and run time. Code text says so: "a workshop limit … not a physical limit". | **Arbitrary UI bound** | Replace with the run-time estimate and warnings that now exist. Small. |
| G4 | Only three shapes: block, enclosure (hollow rectangle), round (ellipse) | `AssemblyPart.Shape` | Each shape has its own hand-written structured mesher; there is no general triangulator. | **Implementation limit** | Polygon outlines need an unstructured mesher (constrained Delaunay with quality refinement), polygon editing on the canvas, and re-checking contact, fracture insertion and the legacy replay on the new meshes. Largest item on the list. |
| G5 | V-notch: blocks only, from the bottom edge, offset ±30%, width 12–36%, depth 2–45% | `Notch.isValid` | The notch is made by warping the structured block mesh, so extreme values would invert or flatten triangles. | **Implementation limit** | Subsumed by G4 (draw the notch as part of a polygon). |
| G6 | Enclosure wall ≥ 5 mm and ≤ 40% of the smaller side | `AssemblyPart.isValid` | The wall always gets 2 × refinement layers regardless of thickness, so a thin wall gives thin slivers and a tiny timestep; ≤40% keeps a cavity. | **Implementation limit** | Choose wall layers from thickness and mesh size. Small to medium. |
| G7 | Bonded layers: blocks only, vertical interfaces, each ≥10% of width, at most 3, elastic only, no notch or fracture | `BondedLayer` | Layers share nodes in one mesh; plasticity and fracture are per body, not per region. | **Implementation limit** | Per-element plasticity and fracture state (relates to the reserved material-state schema). Medium. |
| G8 | No fracture on round bodies | `isValid`, editor line 395 | No reason is given in code. The ellipse mesh has a central fan and ring sectors; crack insertion has only been verified on structured rectangles. **[hypothesis]** it is an unverified mesh family, not a known failure. | **Verification gap** | Run the existing fracture gates on an ellipse mesh; enable if they pass. Small to medium. |
| G9 | Supported bodies cannot fracture | `supportConflict` | Stated in code: crack insertion duplicates nodes, which would move held nodes. | **Implementation limit** | Carry the held-node list through node duplication, then a gate. Medium. Matters for clamped-cantilever fracture. |
| G10 | Positions within ±1 m, rotation ±360°, speed ≤ 150 m/s | `isValid` | Validation bounds. The speed bound is sensible because the model has no rate or temperature dependence. | Mostly **arbitrary**; speed bound is **model scope** | Widen position bounds freely; keep and explain the speed bound. |
| G11 | At most 8 bodies and 12 connections | `maximumParts`, `maximumConnections`, since the first assembly lab commit | No reason in code. **[hypothesis]** contact pair count and UI colors. | **Arbitrary / implementation** | Raise with the run-time estimate as the guard. Small. |
| G12 | Poisson ratio ≤ 0.48 | `assemblyPoissonRange` | Constant-strain triangles lock (become artificially stiff) near incompressibility. | **Genuine numerical limit** | Needs element changes (roadmap B6). Explain on screen. |
| G13 | Spring stiffness 500–250,000 N/m per metre depth; failure extension 0.5–40 mm; preload ±50 mm | `AssemblyConnection.isValid` | UI bounds. Very stiff springs shorten the timestep (already named by the timestep diagnosis). | Mostly **arbitrary** | Widen with explanation. |
| G14 | Gravity 0–50 m/s², straight down only | `gravityRange` | Design choice of the first gravity version. | **Arbitrary** | Allow a direction. Small solver change, needs approval. |
| G15 | One mesh size per body (no local refinement near a notch or contact) | `Resolution` | Structured meshing. | **Implementation limit** | Comes with G4. |

Item 16 ("explain genuine numerical restrictions rather than silently preventing"): the editor now shows a reason under the size fields, but typed values outside a range are still silently set to the nearest limit (`numeric(...)` clamps). Showing "set to 25 mm because …" at the moment of clamping is a small UI fix.

### 3b. Is the runtime estimate adaptive? [verified]
Three separate mechanisms exist:
1. **The step count is exact.** The timestep is fixed for the whole run (`AssemblySimulation.dt` is a constant computed once, including the fracture face-stiffness bound in advance), so steps = duration / dt is known before starting.
2. **The pre-run time estimate learns across runs.** It is steps × element work ÷ a speed. The speed starts at 10 million element updates per second; after each *completed* run longer than 0.5 s it is updated as a 50/50 average of the old value and the measured one, and stored in the app preferences (`runtimeWarnings.measuredRate`). Cancelled runs do not count.
3. **The in-run "remaining" figure is a live extrapolation**: elapsed wall time × (simulated time left ÷ simulated time done). It gets more accurate as the run progresses, by construction.

What his experience most likely was: the stored speed on this Mac today is **10.25 million** updates per second, within 2.5% of the starting default [verified, `defaults read local.shopping.impactlab`]. So the across-run learning barely moved the pre-run estimate. The improvement he saw is most likely (a) the live remaining-time figure converging during each run, and (b) different scenes (mesh, fracture on or off) honestly producing different estimates [hypothesis on attribution; the mechanisms themselves are verified]. A limitation: there is one global speed for all scene types, though contact-heavy and fracture-heavy runs cost different amounts per element.

Why costs range from seconds to an hour (items 35, 36): the timestep is set by the stiffest thing in the scene divided by the smallest triangle. Fracture on a stiff material is the usual culprit: crack faces get a stiffness of at least 30·E/h (`MaterialFracture.swift` line 190), which made metal timesteps about 44 times smaller in the verified probe (doc 17c). Finer meshes cost twice over: more triangles and a shorter step. The app already names the limiting cause before a run.

### 3c. How can a user tell whether fracture is on for the selected body? [verified]
Today, only by opening the **Material** section of the inspector (collapsed by default) and looking at the "Material fracture" checkbox. The body list shows "· fixed", "· clamped" and "· own mesh" tags but no fracture tag, and the canvas draws nothing for fracture until a crack has actually formed. The label also differs by material ("Material fracture (sourced estimate)" for metal profiles). Where fracture is unavailable, a caption explains why (round body, bonded layers, unsupported metal profile). Fix (UI only, small): a "· fracture" tag in the body list, a small marker on the canvas outline, and a one-line summary at the top of the inspector.

### 3d. Is the modified three-point-bend screenshot credible?
I have not seen the screenshot file itself; this assessment is from what the build can do. The shipped example (`docs/lab-examples/three-point-bend.json`) is elastic with no fracture, so his version had Material fracture turned on for the bar (allowed, because the bar is not a support).

What makes it **plausible as behaviour** [verified mechanism, hypothesis for his specific run]:
- Cracks are inserted between existing triangles when the recovered traction on a face reaches the cohesive strength, with the normal component not compressive (`MaterialFracture.insert`). In a bar bent over two rollers the largest tension is at the bottom near midspan, so localized damage there with overall bending elsewhere is what the model should produce.
- Energy bookkeeping with fracture on is checked by existing gates (balance error under 0.5% on the notched-bend fixture) [recorded].

What limits it **as evidence** [verified unless marked]:
- In this build the initiation rule uses the *total* traction (normal plus shear). A tension-only rule exists only on the held-out branch. Shear-driven initiation near supports or under the load is possible in principle [hypothesis for his run].
- Crack paths can only follow triangle edges, so the path depends on the mesh pattern. The recorded gate shows a staggered mesh dissipating about 13% more energy than an aligned one on the same notch (zigzag floor 11.8%) [recorded].
- The only fracture convergence ever shown is one centred notched-bend fixture: crack energy converged within 2% (×6→×7 and half timestep), but the **time the crack goes through was NOT converged** (8% and 29% changes) [recorded, `docs/audit-evidence/convergence-x6x7.txt`].
- The app itself labels fracture at Standard to Extra fine mesh as "Coarse fracture preview. Crack paths and fragment motion are qualitative."
- Supports and gravity were added after every fracture gate was written; no gate combines fracture with supports or gravity.
- The weight arrives at 0.2 m/s, so the event is dynamic, not a quasi-static bend test, and the contact force is a penalty value.
- Constant-strain triangles are too stiff in bending unless there are about 8 or more rows through the bar.

So: credible as a **qualitative** picture of where a bent bar should start to fail, and good user-experience evidence. Not evidence of when it fails, at what load, or along what exact path.

What independent fracture-enabled verification would look like (bounded, not a campaign):
1. **Mesh and timestep series on his own scene:** three refinements and one half-timestep run, reporting initiation time and load, crack length, fracture energy and final separation, with an observed convergence order and "not converged" stated plainly where true.
2. **Energy balance with fracture on**, including supports and gravity: input work = kinetic + elastic + cohesive stored + fracture dissipated + contact, within the existing 0.5% criterion.
3. **Fracture energy vs Gc × crack length** for a straight crack (aligned mesh), with the zigzag floor stated for staggered meshes.
4. **Initiation load vs beam theory:** in a slow three-point bend, the crack should start when the bottom-fibre stress 3PL/(2bh²) reaches the strength; compare the measured load at first insertion.
5. **One published case:** a notched beam (SENB) peak load against the linear-elastic fracture mechanics formula for a beam much larger than the cohesive length E·Gc/σ², where the two theories should agree.
6. A short pass with fracture on but strength set too high to crack, to confirm the fracture option does not change the elastic answer.
None of this is physical validation; it shows the equations are solved consistently.

---

## 4. Prioritized backlog (observations 11–45), next to the scientific roadmap

Priority: **P1** small, removes confusion now; **P2** meaningful capability, one bounded piece each; **P3** larger or depends on others. Size is a rough guess [hypothesis].

| Pri | Item | From his notes | Size | Touches physics? |
|---|---|---|---|---|
| P1 | Fracture visible at a glance: body-list tag, canvas marker, inspector summary line, and a plain reason for every unsupported fracture combination | 19, 20 | S | No |
| P1 | Size minimum follows the mesh; state cost and bending-accuracy consequences; say when a typed value was clamped and why | 12, 15, 16 | S | No (range widening, scene compatible) |
| P1 | Remember the last-used folder for Open and Save (today the panel starts in the current file's folder, or the system default for a new experiment) | 38, 39 | S | No |
| P1 | Spring panel shows all four quantities together: starting length, rest length (= starting length − preload), stiffness, preload and starting force; draw the spring as stretched or compressed relative to rest | 24–27 | S–M | No |
| P2 | Clean view mode plus layer toggles (geometry, mesh, material boundaries, field colour, connections, supports, velocity arrows) | 28–32 | M | No |
| P2 | Save / reopen / copy / compare as ordinary document behaviour: Duplicate, Revert, recent files, compare any two saved runs, not only a pinned one | 40 | M | No |
| P2 | Separate verification fixtures from the user library: move verified cases into ImpactCheck-only "fixtures" (kept for regression), keep a small user library of genuinely different phenomena (wave transit, permanent set, crack growth, preloaded mechanism, settling under gravity) | 41–45 | M | No |
| P2 | Relax arbitrary bounds (G3, G10, G11, G13) behind run-time warnings | 11, 14 | S | No |
| P2 | Enable fracture on round bodies if gates pass (G8) | 17, 20 | S–M | Verification only |
| P3 | General polygon geometry and canvas shape editing, replacing specialized controls such as V-notch (G4, G5, G15) | 11, 13, 14 | L | Mesher, plus re-verification |
| P3 | Fracture on supported/clamped bodies (G9); per-region plasticity and fracture in bonded layers (G7) | 17, 20 | M each | Yes, needs approval |

Scientific roadmap items that stay where they are (doc 18.6): A2 convergence protocol, A4 result/provenance design, B2 material-state slot and thermal ledger, B6 element improvements if bending needs them, plastic-work accounting relabel (note 01, decision 5), material-separation review, CST bending in thick beams and with Poisson > 0.

---

## 5. Next bounded scientific milestone (PROPOSAL, not started)

### Recommendation: Fracture verification as a first-class capability
Why this one, over the alternatives:
- Joseph says fracture is central (17) and asks for fracture-enabled verification (18) and an independent credibility check of his bend result (23). Today fracture convergence exists for **one** fixture, and the app gives the user no way to check their own fracture scene.
- **General polygon geometry** is the bigger product win, but it multiplies untested mesh and fracture combinations. Verifying fracture first means every new shape can be checked with the same tool later. The P1 items above relieve most of the geometry frustration cheaply in the meantime.
- **Plastic-work accounting** matters before heating, and heating is not next. It is small and reporting-only, so it can run alongside as a separate approval (rename "Plastic dissipation" to what it is, add true plastic work as a reported quantity), without taking the milestone slot.

### Scope
1. **A "Check fracture sensitivity" study in the app**, built on the existing refinement study: runs the user's own scene at the next two refinements and at half timestep, and reports initiation time, load at first crack, crack length, fracture energy, final separation and energy error, each marked "converged within X%" or "not converged" with the numbers. Uses the existing solver unchanged.
2. **Four new ImpactCheck fracture gates** with fixed criteria, run in release builds:
   - F1 energy balance with fracture on together with supports and gravity (three-point bend), error < 0.5%;
   - F2 fracture enabled but uncracked gives the same elastic result as fracture off (bit-identical or within round-off);
   - F3 straight-crack fracture energy within 5% of Gc × crack length on an aligned mesh, staggered-mesh excess reported against the 11.8% zigzag floor;
   - F4 slow three-point bend: load at first insertion within 10% of beam theory at the refinement that gives ≥ 8 rows, with the coarse-mesh error reported.
3. **One published comparison**, reported not gated: SENB peak load against the LEFM formula at a size well above the cohesive length E·Gc/σ², stating the size ratio used.
4. A short document page "What fracture results mean" linked from the app, with the three claim types kept apart.

### Acceptance criteria
- F1 to F4 pass, or a failure is reported honestly with its cause; no criterion loosened to pass.
- The sensitivity study runs on Joseph's modified three-point bend and on the Bending Fracture Example, and its report says plainly which numbers converge.
- Legacy replay of the 11 baseline scenes stays bit-identical; existing gates unchanged.
- Total added gate run time under about 5 minutes on the M4 (the existing fracture-convergence gate took about 1.5 min in its recorded run).
- Joseph runs the sensitivity check on his own scene in one short hands-on session.

### Risks
- Results may show his bend case is not converged in time or path. That is a useful finding, not a milestone failure, and fixing it would be separate work.
- Fracture on stiff materials is slow (timestep about 44 times smaller on metal); fixtures use compliant illustrative materials, with at most one short metal case.
- F4 depends on bending accuracy of constant-strain triangles; coarse meshes will miss by a known amount.
- Stress recovery near supports and load points may trigger early shear initiation under the total-traction rule; the gates would expose it rather than fix it.

### What it would NOT include
- Merging or integrating the held-out tensile-initiation branch (material-separation); at most a side-by-side report if Joseph asks.
- Any new crack-insertion method, remeshing (P-001), XFEM, phase-field or other replacements (P-002), or removing the 30·E/h cost.
- Polygon geometry, fracture on round or supported bodies, heating, rate effects.
- Physical validation against laboratory measurements.
- Performance tuning that changes numerical safeguards.

---

## Plain English (for a biologist)

Joseph's acceptance is now written into the planning document exactly as he said it: the app works well enough as a lab bench, but that is not a claim the fracture or material models are proven.

The build he accepted is one tidy combination of the approved work. Two research lines are deliberately kept out, and both would clash with it if added today, so they wait for their own review. Merging the accepted build into the main line is a clean, conflict-free step once he says yes.

Most geometry limits are not laws of nature. The 25 mm minimum exists because the mesh, the grid of small triangles the computer calculates on, uses a fixed triangle size of about 9 mm. A smaller body would work, it would just make the calculation slower. The real scientific caution points the other way: a bar needs about eight layers of triangles through its thickness before it bends correctly, so even 25 mm bodies on the standard mesh bend too stiffly.

The time estimate does learn from past runs, but on his Mac that learning changed it by only about 2%. What he saw improving is mostly the "time remaining" figure during a run, which gets sharper as the run progresses.

Whether fracture is on is currently hidden in a collapsed panel. That should be a visible tag.

His bent-bar picture shows the right kind of behaviour: overall bending, with damage where the bar is stretched most. But the program has only ever checked crack calculations carefully on one test case, and even there the moment of breaking was not stable when the triangles were made smaller. So the picture is encouraging, not proof. The recommended next step is to build that checking into the app, so any fracture experiment can be re-run at finer settings and the app says which numbers hold steady.

---

## Decisions for Joseph (none taken)
1. Approve the integration path in section 2: re-run gates, tag old main, merge PR 1 into main.
2. Approve the recommended milestone (fracture verification as a first-class capability), or pick general geometry instead.
3. Approve the four P1 backlog items as one small UI batch, done alongside or before the milestone.
4. Optional housekeeping: push `research/` notes to a docs branch, move the three stale local copies to the Trash, quit the older running app.
