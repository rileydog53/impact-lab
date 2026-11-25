# Impact Lab feedback log

Joey's raw feedback, sorted into distinct findings. Each finding keeps his own words with a short verbatim quote. Duplicates are merged into one finding. Where his meaning isn't clear, the finding is marked **Unclear** instead of being interpreted.

Finding numbers are permanent. New chunks add new numbers, so a number always points to the same finding.

## How to read a finding

**Block level** (how much it stops Joey from using the lab):

- **Blocking**: he can't do what he set out to do.
- **Slows me down**: he can work around it, but it costs time or runs.
- **Minor**: an annoyance, doesn't stop the work.
- **Unclear**: the feedback doesn't say.

**Change type:**

- **Physics/solver**: the fix needs a change to how the simulation computes things.
- **Interface/wording**: the fix is in the app's screens, labels, help text or bookkeeping only.
- **Not known yet**: can't tell from the feedback alone.

Anything that isn't Joey's own words is labeled as a description or a repo note. Repo notes are Claude's reading of the code, not checked against his saved scene files.

## Chunk log

| Chunk | Date | What it covered |
|---|---|---|
| 1 | 2026-11-25 | Plate inside an enclosure bends instead of punching through; the "bendability" setting has no name he knows |
| 1b | 2026-11-25 | Screenshot of that run; view options; the ParaView export |
| 2 | 2026-11-25 | Live testing, sections 1 to 16: setting up the carbon-skinned aluminium panel run |
| 3 | 2026-11-25 | Live testing part 2, sections 17 to 30: results, a clamped panel, runs that ended before contact |
| 4 | 2026-11-25 | The ParaView export can't be sent as one file |
| 5 | 2026-11-25 | Live testing part 4, sections 49 to 54: another run that started too far apart, time estimates, run message wording. Sections 31 to 48 not received yet |

## What he was testing (context, his words)

- Chunk 1: "The internal volume is a high density, high strength, no fracture. Low mesh, the external enclosure has fracture turned on more dense mesh, and the internal should penetrate through it and break into the plating."
- Chunk 2: "How a high fracture energy material can protect a high cohesive strength material that has a lower fracture energy." He set the carbon fibre layer's fracture energy to 2150 against 1300 for the aluminium, and said "I don't know if that's how carbon fiber really works. I don't really care, it's just an experiment."
- Chunk 3: a steel ball made more oblate, the panel clamped on its top edge, then speed and duration raised.

## Findings by block level

| # | Finding | Category | Block level | Change type |
|---|---|---|---|---|
| 1 | Strong plate bends like a crayon instead of punching through | Bug | Blocking | Not known yet |
| 2 | Material settings need plain words | Confusing wording | Blocking | Interface/wording |
| 15 | No warning that a run ends before the bodies touch | Missing feature | Slows me down | Interface/wording |
| 17 | ParaView export can't be shared easily | Bug | Slows me down | Interface/wording |
| 3 | Doesn't know what the ParaView export is | Confusing wording | Slows me down | Interface/wording |
| 5 | Can't tell how to keep the steel ball from fracturing | Confusing wording | Slows me down | Interface/wording |
| 14 | Can't clamp two edges of one body | Missing feature | Slows me down | Physics/solver (likely) |
| 11 | Bond strength and fracture energy are easy to mix up | Confusing wording | Slows me down | Interface/wording |
| 7 | Extra fine mesh "seemed to not change anything" | Bug | Unclear | Not known yet |
| 6 | Wishes the steel ball's fracture could be turned on | Missing feature | Unclear | Not known yet |
| 18 | Time estimate: "really actually hard to tell if you've succeeded" | Confusing wording | Unclear | Not known yet |
| 19 | Run message about "CPU lane" and "element weight" | Confusing wording | Unclear | Interface/wording |
| 4 | View options: "none of them show much meaning" | Confusing wording | Unclear | Not known yet |
| 12 | Interior mesh choice: which one is normal | Confusing wording | Unclear | Not known yet |
| 13 | "I was getting desperate" | Frustration | Unclear | Not known yet |
| 9 | Can't resize the view panel against the data panel | Missing feature | Minor | Interface/wording |
| 16 | Log run times to improve time estimates | Missing feature | Minor | Interface/wording |
| 8 | Background grid lines are confusing | Confusing wording | Minor | Interface/wording |
| 10 | The ball's mesh looked far too dense at first | Concern | Minor | Interface/wording |

## Bugs

### 1. A strong, no-fracture plate bends instead of punching through the enclosure and panel

- **His words:** "it bends like a fucking crayon, even though I've maxed out the bendability thing"
- **What he expected (his words):** "the internal should penetrate through it and break into the plating."
- **What happened (description of his screenshot, not his words):** "Rectangular Plate 3" (blue, fracture off, coarse mesh) sits inside "Hollow Enclosure 2" (brown, finer-meshed shell), moving left toward a "Carbon-skinned aluminium panel" fixed at its base. The plate bent into a curved banana shape inside the enclosure, and the enclosure wrapped and smeared around it. Nothing went into the panel, only a contact point on its face. Dashed outlines show the original shapes.
- **Block level:** Blocking. This is the experiment he was trying to run.
- **Change type:** Not known yet. It could be the solver, the material limits, or the setup.
- **Repo note:** in the body Material settings, "Young’s modulus (MPa)" can only be set between 0.5 and 4 MPa, which is rubber-soft. If the plate used those editor numbers rather than a Material Library profile, "maxed out" would still be very bendy. A lead to check, not a conclusion.

### 17. The ParaView export can't be shared easily

- **His words:** "well, then that's a bug to report. The fact that we can't do that easily."
- **What happened (description, not his words):** the export writes one file per frame (60 for this run) plus a .pvd index. He tried to send the run, but could attach only 16 files and no zip, so the full run couldn't be sent.
- **Block level:** Slows me down. He couldn't hand over a whole run.
- **Change type:** Interface/wording. It's about how the export is packaged; the solver doesn't change.
- **Related:** finding 3 (he doesn't know what the export is for).

### 7. Extra fine mesh seemed to change nothing

- **His words:** "It's going to use an extra fine mesh. That seemed to not change anything."
- **Block level:** Unclear. He kept going and set finer levels after it.
- **Change type:** Not known yet.
- **Unclear:** whether he means the mesh on screen didn't change, or the result didn't.

## Missing features

### 15. No warning or estimate when a run will end before the bodies meaningfully touch

Merged from chunk 3, sections 21, 25 and 27, and chunk 5, section 50.

- **His words:** "Oh, because it never made contact. That's hilarious." and "I think I might have set the simulation time step to end before any significant contact really." and, in chunk 5, "I didn't set the runtime to be long enough or for the positions to be close enough at the start."
- **What he asked for (his words):** "an estimate of like when the bodies will impact if available, or like a warning that says, Hey, like you've selected this time step ... it does not appear that any meaningful simulation will actually occur"
- He wants it shown while he types the duration: "something above it".
- **Block level:** Slows me down. Three of his runs ended before or at first contact.
- **Change type:** Interface/wording. It reads the setup before a run; the solver itself doesn't change.

### 14. Can't clamp two edges of one body

- **His words:** "what if we have it be supported, clamp the top edge? Is there any way to clamp both?"
- **Block level:** Slows me down. He settled for one clamped edge.
- **Change type:** Physics/solver (likely).
- **Repo note:** Support is a single choice per body today (Fixed support, or clamp left, right, bottom or top edge), so two clamped edges would need a new kind of boundary condition, not only a new menu item.

### 6. Wishes the steel ball's fracture could be turned on

- **His words:** "Oh, no sourced fracture estimate. Well, I wish I could turn it on."
- **Block level:** Unclear. In the same breath he wanted the ball not to fracture (see finding 5).
- **Change type:** Not known yet.
- **Repo note:** the editor doesn't offer the fracture switch on round bodies or on profiles with no sourced estimate.

### 9. Can't resize the view panel against the data panel

- **His words:** "I should be able to kind of adjust the relative size of like the upper and lower panels ... which would be ideal, but that's okay."
- **Block level:** Minor ("but that's okay").
- **Change type:** Interface/wording.

### 16. Log run times so the time estimate gets better

- **His words:** "there should be some way that it logs calculation times and then builds a database so that it can provide more accurate estimates going forward. Not a massive problem."
- Context (his words): "Estimate around 67 seconds ... Already done, only 32 seconds."
- **Block level:** Minor ("Not a massive problem").
- **Change type:** Interface/wording.

## Confusing wording

### 2. Material settings need plain words

Merged from chunk 1 (the "bendability thing"), chunk 2, section 7, and chunk 5, section 52.

- **His words:** "I've maxed out the bendability thing, and I don't know what to call that" and "I don't know what linear coefficient or quadratic coefficients are. Like, we need plain words, like how hard it is to break, how much it resists pulling, or how much it resists bending." and "What is artificial bulk viscosity shock smoothing."
- **Block level:** Blocking. He can't tell whether he changed the setting he meant to.
- **Change type:** Interface/wording.
- **Repo note:** "Linear coefficient b1" and "Quadratic coefficient b2" belong to the "Artificial bulk viscosity (shock smoothing)" setting. **Unclear** which control is the "bendability thing". Body Material settings have three candidates: "Young’s modulus (MPa)" (stiffness), "Yield / E (%)" (when it starts to bend permanently) and "Hardening / E (%)" (how much it stiffens as it bends). The last two show only when Response is Elastoplastic.

### 3. He doesn't know what the ParaView export is

- **His words:** "Let me export the results for para view. I don't know what that means."
- **Block level:** Slows me down.
- **Change type:** Interface/wording.
- **Note:** the file he exported (a .pvd) is only an index of 60 frames from 0 to 5 ms. The frame files it points to weren't sent, so it holds no results by itself.

### 5. Can't tell how to keep the steel ball from fracturing

- **His words:** "So, for the steel ball, we're not going to let it fracture. How do I do that? It seems like I can't do that."
- **Block level:** Slows me down.
- **Change type:** Interface/wording.
- **Repo note:** fracture looks to be already off for this ball and can't be switched on. The message he saw only talks about a missing sourced estimate, so it doesn't say plainly "this body will not fracture".

### 11. Bond strength and fracture energy are easy to mix up

- **His words:** "The carbon fiber, the bond. Okay, wait, that's the bond strength. I meant the fracture energy should be higher."
- **Block level:** Slows me down. He caught it himself this time.
- **Change type:** Interface/wording.

### 18. Hard to tell from the time estimate whether he's "succeeded"

- **His words:** "estimating at two minutes for seven, estimating at two minutes for five, estimating at twenty-one seconds for one, estimating at twenty-one seconds for two ... I guess you can tell how it balloons, but ... it is really actually hard to tell if you've succeeded."
- **Block level:** Unclear.
- **Change type:** Not known yet.
- **Unclear:** what "succeeded" means here. It may be about picking a long enough duration (finding 15) or about the estimate itself (finding 16). Not merged until he says.

### 19. Run message about "CPU lane" and "element weight"

- **His words (reading the message aloud):** "one CPU lane, two latent dispatch needs at least 5,000 element weight on the lighter lane. And this lane, this assembly is 1448."
- **Block level:** Unclear.
- **Change type:** Interface/wording.
- **Unclear:** he read it out without saying whether it made sense. Filed because it's the same kind of technical wording as finding 2.

### 4. View options don't show much

- **His words:** "none of them show much meaning crack separation with high detail with the body velocity"
- **Block level:** Unclear.
- **Change type:** Not known yet.
- **Unclear:** dictation was rough. It may mean the result views showed little, or something else.

### 12. Interior mesh choice: which one is the normal one

- **His words:** "Oh, okay, it's kind of a okay, okay, that's the normal one, okay."
- **Block level:** Unclear.
- **Change type:** Not known yet.
- **Unclear:** he may have just been finding his way; nothing here says it was a problem.

### 8. Background grid lines are confusing

- **His words:** "Oh, I'm getting confused with the grid lines in the background. LOL."
- **Block level:** Minor.
- **Change type:** Interface/wording.

## Ideas

None yet.

## Frustrations

### 13. "I was getting desperate"

- **His words:** "I was getting desperate because I was like, man, fuck does this shit fucking mean?"
- **Block level:** Unclear.
- **Change type:** Not known yet.
- **Unclear:** which part of the lab this was about. Finding 1 also carries clear frustration but is filed once, as a bug.

## Concerns

### 10. The ball's mesh looked far too dense at first

- **His words:** "that ball, it just has a crazy, crazy, crazy, crazy, crazy amount of triangles for a ball. Am I insane?"
- He then found the cause himself (his words): "Oh, oh, okay, assembly mesh is X4. Okay, that's appropriate for a simulation like this." He set it to Standard: "That was easy."
- **Block level:** Minor. Resolved by him.
- **Change type:** Interface/wording.

## Not filed

Kept out of the list because they aren't problems or requests:

- Praise: "Fit assembly as a button works well." Results: "Ooh, ooh, this is good." Run times: "It took 115 seconds. That's not bad." Direction: "This is definitely evolving towards the product ... that I'm looking at for Impact Lab." Excitement: "I'm actually excited to see what comes out of this for once."
- The live estimate, which he approves of: "it's updated for measure speed while it runs, so that's what's the most important."
- Hardware use, which he approves of: "It's cranking my GPU. It's cranking my CPU. And if it were any other way, I would be pissed the fuck off right now."
- Setup narration, tangents (dictation length, self-directed humour, where his ideas come from), and an interruption about another task.
