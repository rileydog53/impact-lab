# Feedback plan

Written 2026-11-25 from `docs/FEEDBACK.md` (39 findings, main at 785f638) and the contact-overlap notes in draft PR 32. This is a reading of the feedback against the code and a proposed order of work. No code has been changed.

**Status labels.** *Verified in code*: I read the code path and it does what is written here. *Agent-reported*: taken from the earlier code investigations in FEEDBACK.md without re-reading. *Hypothesis*: a likely explanation that needs a run (or Joseph) to confirm. None of his scenes were re-run; his plate-in-enclosure scene file isn't in the repo folder.

## The main finding: two material scales in one experiment

Most of the blocking findings (1, 26, 27, 33, and much of 29 and 34) trace back to one design leftover, not to the solver.

- **Verified in code.** A body you draw or add yourself gets the old "illustrative" material: Young's modulus 1 MPa, density 1000 kg/m³ (`Physics.swift:12`). That is softer than a rubber band.
- **Verified in code.** The editor boxes for that material only allow Young's modulus 0.5 to 4 MPa and density 500 to 2500 kg/m³ (`SceneConfiguration.swift:32-33`, used at `AssemblyEditor.swift:418-420` and `:872-877`, clamped at `:1173`). The solver and the scene reader accept 0.5 MPa to 400 GPa and 100 to 25,000 kg/m³ (`Physics.swift:18-19`, `SceneDocument.swift:573-574`). The editor note even says these are "illustrative numbers chosen to show a behaviour, not a real material" (`AssemblyEditor.swift:402`).
- **Verified in code.** The presets and the Material Library use real materials. The carbon-skinned panel he built on is 70 GPa aluminium with a 70 GPa carbon skin (`docs/layered-examples/carbon-skin-aluminium-panel.json`).
- **Verified in code.** Yield is set as 1 to 3.5% of Young's modulus (`MaterialImpact.swift:11`). Real steel yields at about 0.1% of its modulus, so even a stiff custom body couldn't be given a realistic yield.

So his plate-in-enclosure experiment put two rubber-soft bodies (a "high-strength" plate capped at 4 MPa and 2500 kg/m³, and an enclosure) against a real aluminium panel about 20,000 times stiffer. What follows from that:

- **Finding 1, the plate bending "like a crayon": verified in code.** At 4 MPa the plate is rubber. It did what rubber does. The "bendability thing" he maxed out is almost certainly the Young's modulus box (hypothesis, but he names Young's modulus himself in section 93).
- **Finding 33, numbers corrected to 500 and "4 is the highest": verified in code.** Those are the editor limits above.
- **Findings 31 and 39, slow runs: verified in code, cause partly hypothesis.** One time step is used for the whole scene, set by the stiffest body (`AssemblySimulation.swift:547`). The 70 GPa panel on a x4 mesh forces a tiny step, while the soft bodies crawl toward it, so most of the run is spent on steps where nothing touches. Skipping ahead before contact (subcycling or a different method) would be a new solver method, which isn't approved; the fix inside the rules is to warn and to make real materials the normal case.
- **Finding 26, contact overlap: partly verified, cause hypothesis.** See the next section.

## Finding 26: why runs stop with "contact overlap"

What the code does (verified in code, matching PR 32):

1. The 10% check (`AssemblySimulation.swift:949`) applies to *every* contact in the scene as soon as *any* body has fracture on (`hasFracture`). His panel has fracture on, so the rubber plate pressing on the inside of the rubber enclosure is held to the same rule. Without fracture anywhere the same overlap would not stop the run.
2. Overlap is measured against the length of the edge being pushed into (`BoundaryContact.swift:168`). The panel's x4 mesh has very short edges, so a small real overlap reads as a big percentage.
3. The push-back force for a node uses the stiffness of the node's own body (`BoundaryContact.swift:81`). A 1 MPa enclosure node pressed into a 70 GPa panel is pushed back by a rubber-sized force, while a heavy body behind it keeps pushing.
4. The push goes toward the nearest edge of the other body (`BoundaryContact.swift:237`). Inside a thin hollow wall, once a node is past the middle, the nearest edge is the *inner* face, so the node is pushed through. This fits "it just lets it go through".
5. The step size is fixed for the run; nothing retries a smaller step.

My reading (hypothesis): the failures come mostly from the scale mismatch. A rubber body at tens of m/s is moving at or above its own wave speed (about 32 m/s for the default material), so its elements crush and its boundary nodes sink into the stiff panel faster than the rubber-sized push-back can stop them. That is why going slower didn't help much: at the speeds where the rubber behaves, the bodies barely reach each other in the duration he set (finding 27). PR 32's line "going slower can't fix it" is too strong. Slower impacts do reduce overlap in a penalty contact; they just couldn't get his run under the limit within a useful duration.

How to test it (proposed benchmark, before any solver change): recreate his plate-in-enclosure scene, run it headless with `ImpactCheck` at 5, 10 and 20 m/s, once as he built it and once with Material Library steel for the plate and aluminium for the enclosure. If the real-material version runs through, the fix is Build 1 and the solver doesn't change. If it still trips, Build 3 is needed.

## Every finding, read against the code

Kind: **Bug** (the app does something wrong), **Limit** (works as built, but the built limit is the problem), **Wording** (a label, message or explanation), **Guide** (best fixed by explaining in the user guide), **Wish** (new feature).

| # | What it really means | Kind | Status | Build |
|---|---|---|---|---|
| 26 | Contact check stops the run; caused mostly by rubber-scale bodies against a real-scale panel, made worse by a scene-wide strict check and short panel edges. Message doesn't name the bodies. | Bug + Wording | Mechanism verified; cause hypothesis | 1 (message, warnings, real materials); 3 if still failing |
| 29 | Sum of 26, 27, 1, 33. | — | Verified (it's a summary) | 1 |
| 27 | Workarounds (slower, coarser) leave nothing to see. Goes away with 26. | Limit | Hypothesis | 1 |
| 28 | Lost the fun. Same causes. | — | — | 1 |
| 1 | Plate is rubber because custom bodies are capped at 4 MPa. | Limit | Verified in code | 1 |
| 33 | Editor clamps E to 0.5-4 MPa and density to 500-2500; solver accepts 0.5 MPa-400 GPa and 100-25,000. | Limit | Verified in code | 1 |
| 2 | Science terms with no plain meaning. | Wording | Verified (labels read) | 1 |
| 34 | No sense of scale for the numbers. Needs reference points beside each box ("steel ≈ 200 GPa, rubber ≈ 0.01 GPa"). | Wording | Verified (no such hints exist) | 1 |
| 35 | Had to ask ChatGPT. Same as 2 and 34, plus the guide (PR 31) only covers presets and running, not building or materials. | Guide | Verified (guide read) | 1 |
| 15 | No warning that a run ends before the bodies touch. Gaps and speeds are known before the run, so a time-to-contact estimate is simple. | Wish | Verified (nothing like it exists) | 1 |
| 17 | Export writes one file per frame plus a `.pvd` index; can't be sent as one file. Fix: also save one zip. | Wish | Agent-reported | 2 |
| 3 | "ParaView export" means nothing to him. Rename and explain ("files for the free ParaView viewer"). | Wording | Verified | 2 |
| 24 | The 2 mm carbon layer is hard to click on the canvas. | Bug | Hypothesis (hit area not checked) | 2 |
| 25 | Typing "-50" is awkward in the number box. | Bug | Hypothesis (macOS number field behaviour) | 2 |
| 5 | Steel ball already can't fracture (round bodies can't), but the message only says "no sourced fracture estimate". Say "this body will not crack" plainly. | Wording | Verified (`AssemblyEditor.swift:216`) | 1 |
| 21 | Pin run / compare with reference: unclear what each does. | Wording | Verified (no explanation in the view) | 2 |
| 14 | Only one clamped edge per body. Holding two edges would reuse the existing held-node mechanism, but it changes the boundary-condition model in the physics package. | Wish | Verified (`AssemblyScene.swift:150`) | 3 (his yes) |
| 11 | Bond strength vs fracture energy mixed up. Plain names fix it ("how hard to start a crack" vs "how much energy to grow it"). | Wording | Verified | 1 |
| 36 | Lowest fracture energy didn't crack on touch. In this model a crack *starts* when stress reaches the strength; energy only sets how easily it *grows*. So lowering energy alone doesn't make it crack on touch. | Guide | Mechanism verified; what he saw is hypothesis | 1 |
| 7 | "Extra fine mesh changed nothing." Likely a body with its own mesh size, which overrides the assembly setting, or the change wasn't visible at that zoom. | Unclear | Hypothesis | Question |
| 6 | Library metals can't use fracture unless a sourced estimate exists; round bodies never can. | Limit | Verified | 1 (say it plainly); more estimates need literature |
| 23 | Library has exactly four materials (steel, stainless, aluminium, copper: `MaterialProfile.swift:164`). Carbon fabric, epoxy, glass and PVB exist only inside presets. | Wish | Verified | 1 (literature values only) |
| 20 | Energy residual: he can't tell what's normal. Show "good / check / bad" with the threshold. | Wording | Verified | 2 |
| 30 | Own mesh size is only offered on drawn (outline) bodies (`AssemblyEditor.swift:598`), not on rectangles or round bodies. | Limit | Verified; which body he meant is hypothesis | 2 |
| 18 | Hard to tell from the estimate whether he's "succeeded". Probably wants to know the run will be long enough to show contact, i.e. finding 15. | Unclear | Hypothesis | 1 (with 15) |
| 4 | View options "don't show much meaning". Possibly because the runs barely reached contact. | Unclear | Hypothesis | Recheck after Build 1 |
| 12 | Interior mesh choice: he found the normal one. Add "(normal)" to the default. | Wording | — | 2 |
| 37 | Casing didn't deform like metal: he set it elastic (springs back by definition) and it was rubber-scale. Real aluminium with plasticity would dent. | Guide | Verified (cause) | 1 |
| 39 | Runs feel slow. See 31: global step set by the stiffest body. | Limit | Verified mechanism | 1 (warn); speedups only via approved profiling work |
| 13 | "I was getting desperate." Same as 2, 34, 35. | — | — | 1 |
| 16 | Time estimate off; log run times to improve it. A small local log on his Mac is enough. | Wish | — | 2 |
| 9 | Resize the view panel against the data panel (split divider). | Wish | — | 2 |
| 32 | "Process peak resident memory" is lifetime-of-app (`ru_maxrss`, `AssemblyComputationStatus.swift:16`), so it can't reset. Show this run's peak instead, sampled during the run. | Wording | Verified | 2 |
| 8 | Background grid always drawn (`AssemblyCanvas.swift:294`); add an on/off toggle. | Wish | Verified | 2 |
| 19 | Advisories are developer language ("CPU lane", "latent dispatch"). Rewrite as one plain sentence plus a "details" disclosure. | Wording | Verified (he read one out) | 2 |
| 22 | Resizing the bonded second material: it's "local width/height"; rename. | Wording | — | 2 |
| 38 | Mesh advisory fires on an automatic mesh he didn't set. The automatic size should satisfy its own advisory, or the advisory should say what to change. | Bug | Hypothesis | 2 |
| 31 | Steps before contact shouldn't be heavy. True in principle; see 39. | Limit | Verified mechanism | 1 (warn) |
| 10 | Ball looked over-meshed at x4; he fixed it himself. Show the mesh level beside the triangle count. | Wording | — | 2 |

## Proposed builds

### Build 1: make his own experiment work (most blocking)

Interface and material data only. No change to the solver's equations, contact or time stepping.

1. **Real materials for bodies he builds.** Open the editor's Young's modulus and density boxes to the ranges the solver already accepts, shown in GPa/MPa as fits. Let yield be typed in MPa (or allow realistic fractions down to about 0.05%). New bodies start from a real Library material instead of the 1 MPa illustrative one (see question 2).
2. **More Library materials**, literature values only, averaged per project rule: at least the ones the presets already use (carbon-fibre fabric, structural epoxy, glass, PVB) plus a few common ones (polycarbonate, natural rubber, a hardwood). Elastic or the existing J2 plasticity only; no new constitutive laws. A crushable foam (his "density 300") would need a new law and is left out unless he says otherwise.
3. **Plain words.** Each material and fracture box gets a plain name, a one-line meaning and a scale hint (for example "Stiffness (Young's modulus): steel 200 GPa, aluminium 70, wood 10, rubber 0.01"). Bond strength vs fracture energy renamed as "how hard to start a crack" vs "energy to grow it". "Fracture off" said plainly when a body can't crack.
4. **Pre-run warnings**: estimated time until first contact vs the duration he set, shown above the duration box (15, 18); a warning when a soft body meets one far stiffer, or a body moves faster than its own wave speed (26).
5. **Contact failure message names the two bodies** and the likely reason (the deepest pair is already recorded as `rejectedContactDomains`, `AssemblySimulation.swift:951`, but only test tools read it).
6. **User guide section** on building your own experiment: choosing materials, what the numbers mean at everyday scale, how cracks start vs grow, why a run can be slow.

Check: the 7 showcase presets and the regression baseline must give bit-identical results (no solver change). Then the headless benchmark in the finding-26 section, and an app smoke test of building his plate-in-enclosure from Library materials.

Who decides: interface work, on the coordinator's call. Item 1's new default and item 2's material list are flagged to Joseph as questions below.

### Build 2: polish and sharing

Interface only: one-file export and plain ParaView naming (17, 3), grid toggle (8), resizable panels (9), this-run peak memory (32), easier negative velocity (25), easier layer selection (24), pin/reference explained (21), energy residual verdict (20), plain advisories and the automatic-mesh advisory bug (19, 38), per-body mesh size on rectangles (30), run-time log for better estimates (16), small labels (12, 22, 10).

Check: presets bit-identical; app smoke test of each changed control.

### Build 3: needs Joseph's yes (physics)

Only if the Build 1 benchmark still fails with real materials:

- **Contact robustness.** Recommended order, smallest first: (a) apply the 10% stop only to pairs where a body actually has fracture on; (b) measure overlap against the longer of the two meshes' edge lengths; (c) push back with the stiffer body's stiffness; (d) instead of stopping, retry the step at half size a few times. Each changes how contact is computed, so each needs his approval.
- Check for any of them: his recreated scene runs at 5, 10 and 20 m/s; every existing regression scene that never hit the limit stays bit-identical; energy residual no worse; the existing contact and wave-speed checks in `ImpactCheck` stay within their tolerances.
- **Two clamped edges on one body (14).** Small, reuses the existing clamp, but it is a boundary-condition change in the physics package. Check: one-edge clamps bit-identical; a two-edge clamped beam matches the textbook fixed-fixed deflection.

Not proposed (outside the approved scope): skipping steps before contact (a new time-integration method), crushable foam, heat, high speed.

## Questions for Joseph

1. **Where is the plate-in-enclosure scene saved?** I need the file to run the benchmark. Best guess: it wasn't saved; I'll recreate it from his screenshot description if so.
2. **Should a new body start as a real material (say aluminium) instead of the illustrative rubber-soft one?** Recommendation: yes. The illustrative material would stay available as "Soft demo material".
3. **"Still only four": do you want more Library materials, and which?** Best guess: yes, starting with carbon fibre, epoxy, glass, PVB, polycarbonate, rubber and wood.
4. **Two unclear lines, correct me if wrong:** "hard to tell if you've succeeded" (18) means "will this run be long enough to see the impact", and "extra fine mesh changed nothing" (7) means the result looked the same, not the mesh on screen.

## Needs his yes

- Build 3 (any contact change, two-edge clamp).
- Question 2 (default material) changes what a new body is.

Everything else is interface, wording or literature material data.

## Joseph's answers (2026-11-25, 23:09 to 23:14 UTC)

- **Soft demo material:** remove it as a choice. Every new body starts as a real material. The old values stay in the physics package only, so old scenes and checks replay exactly. Done in Build 1.
- **Library:** four materials is far too few. Add metals as well as the non-metals listed. Build 1 adds titanium and brass, plus carbon fibre, window glass, epoxy, polycarbonate, PVB, rubber and oak (values: `docs/library-materials.md`).
- **Plain words:** the layman's term leads and the technical term may follow in brackets, e.g. "Bends for good at (yield strength)". This applies to every label, note and stop message.
- **"Succeeded"** means knowing before the run whether the bodies will touch, when, and how long the run goes on after that. Build 1 adds this above Run length.
- **Scene file:** he thinks he saved it, but it wasn't in the usual places, so it is rebuilt in `docs/feedback-benchmarks/` (as he built it, and with real materials).
- **Contact overlap:** "fix it". That is his yes to fix contact rather than only diagnose it, but done properly: first re-run the rebuilt scene with real materials after Build 1, then fix any remaining cause with a named published method and a benchmark, and show him the solver change before merge (Build 3).
- **Speed:** the 150 m/s cap felt too low. High speed is still not approved, so first check whether real materials and fixed contact make the existing range meaningful.
