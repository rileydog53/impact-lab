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

Anything that isn't Joey's own words is labeled as a description or a repo note. Repo notes are Claude's reading of the code, not checked against his saved scene files. "Section" numbers are the numbers in his own live-testing notes.

## In his own words, the overall verdict

He asked for this to be kept exactly as he said it, not softened:

> "This is pissing me off. This is insane. **Clarify that this is insane. Don't edit over that.**"

> "The goal is so simple, right? But I can't even try to see if we're reaching that goal."

> "As you can tell I'm satisfied with the editing but every other part of it is bad objectively bad because what's the point of it? What's the point of all this simulation architecture if I can't do a simulation that I want to build."

> "I'm still on one experiment trying to see one cool result, and that's not good."

He also asked that this fact be preserved: "The fact that I had to ask ChatGPT for help on how to ask how to run the preserve this fact." (finding 35)

## Chunk log

| Chunk | Date | What it covered |
|---|---|---|
| 1 | 2026-11-25 | Plate inside an enclosure bends instead of punching through; the "bendability" setting has no name he knows |
| 1b | 2026-11-25 | Screenshot of that run; view options; the ParaView export |
| 2 | 2026-11-25 | Live testing sections 1 to 16: setting up the carbon-skinned aluminium panel run |
| 3 | 2026-11-25 | Sections 17 to 30: results, a clamped panel, runs that ended before contact |
| 4 | 2026-11-25 | The ParaView export can't be sent as one file |
| 5 | 2026-11-25 | Sections 49 to 54: another run that started too far apart, time estimates, run message wording |
| 6 | 2026-11-25 | Sections 31 to 48: delamination result, editing a copy, building the plate-in-enclosure body |
| 7 | 2026-11-25 | Sections 55 to 70: repeated "contact overlap" failures, body mesh size, losing the fun |
| 8 | 2026-11-25 | Sections 71 to 95: more failures, slow-motion workarounds, input limits, not knowing what the material numbers mean, asking ChatGPT |
| 9 | 2026-11-25 | Sections 96 to 103: "something's not right", advisories on an automatic mesh, slow runs, peak memory again. Code investigation of finding 1 added |

## What he was testing (context)

- Chunk 1 (his words): "The internal volume is a high density, high strength, no fracture. Low mesh, the external enclosure has fracture turned on more dense mesh, and the internal should penetrate through it and break into the plating."
- Chunk 2 (his words): "How a high fracture energy material can protect a high cohesive strength material that has a lower fracture energy." He set the carbon fibre layer's fracture energy to 2150 against 1300 for the aluminium, and said "I don't know if that's how carbon fiber really works. I don't really care, it's just an experiment."
- Chunk 3 (summary): a steel ball made more oblate, the panel clamped on its top edge, then speed and duration raised.
- Chunks 6 to 8 (summary): he edited a copy with a stronger bond between the panel's layers, then replaced the ball with a plate inside a hollow enclosure joined by a spring, reshaped both outlines on the canvas, and ran it again and again at lower speeds and coarser meshes after repeated contact failures.

## Findings by block level

| # | Finding | Category | Block level | Change type |
|---|---|---|---|---|
| 26 | Runs stop with "contact overlap by more than 10% of an edge" | Bug | Blocking | Physics/solver (likely) |
| 29 | Editing is fine, but basic experiments don't run | Frustration | Blocking | Not known yet |
| 27 | Workarounds sacrifice fidelity and leave nothing to see | Concern | Blocking | Physics/solver (likely) |
| 28 | The lab stopped being fun ("boring mode") | Frustration | Blocking | Not known yet |
| 1 | Strong plate bends like a crayon instead of punching through | Bug | Blocking | Interface/wording (per code investigation) |
| 33 | Input limits clamp the numbers he types | Missing feature | Blocking | Interface/wording (per code investigation) |
| 2 | Settings need plain words | Confusing wording | Blocking | Interface/wording |
| 34 | No sense of what the numbers mean in this simulation | Confusing wording | Blocking | Interface/wording |
| 35 | Had to ask ChatGPT how to run it | Frustration | Blocking | Interface/wording |
| 15 | No warning that a run ends before the bodies touch | Missing feature | Slows me down | Interface/wording |
| 17 | ParaView export can't be shared easily | Bug | Slows me down | Interface/wording |
| 24 | Can't select the carbon fibre layer easily | Bug | Slows me down | Interface/wording |
| 25 | Can't easily type a negative velocity | Bug | Slows me down | Interface/wording |
| 3 | Doesn't know what the ParaView export is | Confusing wording | Slows me down | Interface/wording |
| 5 | Can't tell how to keep the steel ball from fracturing | Confusing wording | Slows me down | Interface/wording |
| 21 | Pin run and reference comparison are confusing | Confusing wording | Slows me down | Interface/wording |
| 14 | Can't clamp two edges of one body | Missing feature | Slows me down | Physics/solver (likely) |
| 11 | Bond strength and fracture energy are easy to mix up | Confusing wording | Slows me down | Interface/wording |
| 36 | Lowest fracture energy didn't give what he expected | Bug | Unclear | Not known yet |
| 7 | Extra fine mesh "seemed to not change anything" | Bug | Unclear | Not known yet |
| 6 | Material Library profiles can't be used with fracture | Missing feature | Unclear | Not known yet |
| 23 | Material Library "still only four" hardening profiles | Missing feature | Unclear | Not known yet |
| 20 | Can't tell whether the energy residual is normal | Confusing wording | Unclear | Interface/wording |
| 30 | Couldn't set the mesh size on one body | Confusing wording | Unclear | Not known yet |
| 18 | Time estimate: "really actually hard to tell if you've succeeded" | Confusing wording | Unclear | Not known yet |
| 4 | View options: "none of them show much meaning" | Confusing wording | Unclear | Not known yet |
| 12 | Interior mesh choice: which one is normal | Confusing wording | Unclear | Not known yet |
| 37 | Outer casing doesn't deform like metal | Concern | Unclear | Not known yet |
| 39 | Runs feel very slow | Frustration | Unclear | Not known yet |
| 13 | "I was getting desperate" | Frustration | Unclear | Not known yet |
| 16 | Time estimates are off; log run times to improve them | Missing feature | Minor | Interface/wording |
| 9 | Can't resize the view panel against the data panel | Missing feature | Minor | Interface/wording |
| 32 | Peak memory should reset for each run | Missing feature | Minor | Interface/wording |
| 8 | Background grid lines confuse him; wants them off | Confusing wording | Minor | Interface/wording |
| 19 | Run and mesh advisory messages are technical and get skimmed | Confusing wording | Minor | Interface/wording |
| 22 | How to resize the bonded second material isn't obvious | Confusing wording | Minor | Interface/wording |
| 38 | Advisories fire on a mesh he didn't set; testing should have caught it | Concern | Minor | Not known yet |
| 31 | Steps before contact shouldn't be heavy to calculate | Concern | Minor | Not known yet |
| 10 | The ball's mesh looked far too dense at first | Concern | Minor | Interface/wording |

## Bugs

### 26. Runs stop at contact with "contact overlap by more than 10% of an edge"

Merged from sections 56, 61, 62, 68, 71, 80 and 91.

- **His words:** "It doesn't even try. It makes contact and it just lets it go through. It doesn't treat the mesh at all. It doesn't accept the mesh at all. It's just stupid."
- "Failure again, despite how slow I made things. Agonizingly slow."
- "can somebody explain to me why I care? ... that's the number one problem with any physics engine where you have two things that bounce into each other."
- He calls it "the overlap issue, which is the biggest problem that we have."
- **The message he saw (as he read it out):** "Overlap, contact overlap by more than 10% of an edge. Try slower impact or a different mesh."
- **Block level:** Blocking. It stopped run after run, at every speed he tried.
- **Change type:** Physics/solver (likely).
- **Code investigation:** pending. A separate read-only look at this failure is running; its findings go here when they come in.

### 1. A strong plate bends instead of punching through the enclosure and panel

Merged from chunk 1 and sections 93 and 102.

- **His words:** "it bends like a fucking crayon, even though I've maxed out the bendability thing"
- Later: "The other problem was that the internal slug bent. Why? Young's modulus. I don't understand what that is."
- In section 102: "Okay, I'm unimpressed. I'm unimpressed. I'm watching my slug make hysterically." (**Unclear** wording; the screenshot he mentions, 5.41.32 PM, wasn't attached.)
- **What he expected (his words):** "the internal should penetrate through it and break into the plating."
- **What happened (description of his screenshot, not his words):** "Rectangular Plate 3" (blue, fracture off, coarse mesh) sits inside "Hollow Enclosure 2" (brown, finer-meshed shell), moving left toward a "Carbon-skinned aluminium panel" fixed at its base. The plate bent into a curved banana shape inside the enclosure, and the enclosure wrapped and smeared around it. Nothing went into the panel, only a contact point on its face. Dashed outlines show the original shapes.
- **Block level:** Blocking. This is the experiment he was trying to run.
- **Change type:** Interface/wording, per the code investigation below.
- **Code investigation (a separate read-only look at the code, not his words; he asked for it to be kept here):**
  - The Young's modulus box in the body editor clamps to 0.5 to 4 MPa (`SceneConfiguration.swift:32`, used at `AssemblyEditor.swift:418`, clamped at `:1173`). That's rubber-soft. He hit the same limit himself in section 94 ("4 is the highest"), see finding 33.
  - The solver itself accepts 0.5 MPa to 400 GPa (`Physics.swift:18`, `SceneDocument.swift:573`), so the limit is in the editor only.
  - Density stops at 2500 kg/m³ in the editor.
  - Yield is Young's modulus times "Yield / E", so the highest yield the editor allows is about 0.14 MPa (`MaterialImpact.swift:11`, `:16`).
  - Turning fracture off changes no stiffness (`Physics.swift:893` to `907`).
  - A coarse mesh makes thin plates stiffer, not softer (`AssemblyAdvisories.swift:92`), so the coarse mesh isn't why it bent.
  - The investigation's guess (not confirmed by him): the "bendability thing" is Young's modulus.
  - Likely fix: widen the editor's range, with no solver change.
  - Workaround today: apply Structural Steel from the Material Library to the plate.

### 17. The ParaView export can't be shared easily

- **His words:** "well, then that's a bug to report. The fact that we can't do that easily."
- **What happened (description, not his words):** the export writes one file per frame (60 for this run) plus a .pvd index. He tried to send the run, but could attach only 16 files and no zip, so the full run couldn't be sent.
- **Block level:** Slows me down. He couldn't hand over a whole run.
- **Change type:** Interface/wording. It's about how the export is packaged; the solver doesn't change.
- **Related:** finding 3.

### 24. Can't select the carbon fibre layer easily

- **His words:** "I can't select the carbon fiber very easily."
- **Block level:** Slows me down.
- **Change type:** Interface/wording.

### 25. Can't easily type a negative velocity

- **His words:** "I can't easily type negative 50."
- **Block level:** Slows me down.
- **Change type:** Interface/wording.

### 36. Lowest fracture energy didn't give the result he expected

- **His words:** "Okay, not what I expected ... The fracture energy on this shit on the outer mesh is so low, it's as low as it goes. It should be fracturing the second something fucking touches it, right? And the answer to that is yes, it should, because that's what ... being suggested to me."
- **Block level:** Unclear.
- **Change type:** Not known yet.
- **Unclear:** he doesn't say what the outer mesh actually did. He also says he can't judge it: "I also don't understand what Young's modulus and stuff is, so I can't really tell you what I should have expected" (finding 34).

### 7. Extra fine mesh seemed to change nothing

- **His words:** "It's going to use an extra fine mesh. That seemed to not change anything."
- **Block level:** Unclear. He kept going and set finer levels after it.
- **Change type:** Not known yet.
- **Unclear:** whether he means the mesh on screen didn't change, or the result didn't.

## Missing features

### 33. Input limits clamp the numbers he types

Merged from sections 88 and 94.

- **His words:** "Still some limits on the numbers I can type in. That corrected to 500. I don't love that."
- "Okay, so that's fucking stupid of Young's modulus ... 4 is the highest"
- **What he was trying (his words):** "this should have a density of like 300."
- **Block level:** Blocking. The limits stop him setting the materials his experiment needs.
- **Change type:** Interface/wording for Young's modulus, per the code investigation under finding 1: the solver accepts far stiffer values and only the editor limits them. The density limits weren't checked against the solver.
- **Repo note:** the body editor allows density 500 to 2500 kg/m³ and Young's modulus 0.5 to 4 MPa.

### 15. No warning or estimate when a run will end before the bodies meaningfully touch

Merged from sections 21, 25, 27 and 50.

- **His words:** "Oh, because it never made contact. That's hilarious." and "I think I might have set the simulation time step to end before any significant contact really." and "I didn't set the runtime to be long enough or for the positions to be close enough at the start."
- **What he asked for (his words):** "an estimate of like when the bodies will impact if available, or like a warning that says, Hey, like you've selected this time step ... it does not appear that any meaningful simulation will actually occur"
- He wants it shown while he types the duration: "something above it".
- **Block level:** Slows me down. Three of his runs ended before or at first contact.
- **Change type:** Interface/wording. It reads the setup before a run; the solver itself doesn't change.

### 14. Can't clamp two edges of one body

- **His words:** "what if we have it be supported, clamp the top edge? Is there any way to clamp both?"
- **Block level:** Slows me down. He settled for one clamped edge.
- **Change type:** Physics/solver (likely).
- **Repo note:** Support is a single choice per body today (Fixed support, or clamp left, right, bottom or top edge), so two clamped edges would need a new kind of boundary condition, not only a new menu item.

### 6. Material Library profiles can't be used with fracture

Merged from sections 5 and 42.

- **His words:** "Oh, no sourced fracture estimate. Well, I wish I could turn it on." (steel ball) and "material library copper jacket no you can't do that with a fracture model." (copper)
- **Block level:** Unclear. Both times he switched to something else.
- **Change type:** Not known yet.
- **Repo note:** the editor doesn't offer the fracture switch on round bodies or on profiles with no sourced estimate.

### 23. Material Library has "still only four" hardening profiles

- **His words:** "Let's go to the materials library still four and here still only four post-yield hardenings"
- **Block level:** Unclear.
- **Change type:** Not known yet.
- **Unclear:** "still only four" may mean he wants more profiles. He didn't say so.

### 16. Time estimates are off; log run times so they get better

Merged from sections 21, 28 and 57.

- **His words:** "there should be some way that it logs calculation times and then builds a database so that it can provide more accurate estimates going forward. Not a massive problem."
- Context (his words): "Estimate around 67 seconds ... Already done, only 32 seconds." and, after halving the speed, "Still estimated at two minutes, which is odd."
- **Block level:** Minor ("Not a massive problem").
- **Change type:** Interface/wording.

### 9. Can't resize the view panel against the data panel

- **His words:** "I should be able to kind of adjust the relative size of like the upper and lower panels ... which would be ideal, but that's okay."
- **Block level:** Minor ("but that's okay").
- **Change type:** Interface/wording.

### 32. Peak memory should reset for each run

Merged from sections 67 and 101.

- **His words:** "It should reset its process peak resident memory for each calculation." and "It still displays process peak resident memory, but like that's for the entire process."
- **Block level:** Minor.
- **Change type:** Interface/wording.

## Confusing wording

### 2. Settings need plain words

Merged from chunk 1 and sections 7, 36, 42, 52, 55, 58, 73, 89 and 93.

- **His words:** "we need plain words, like how hard it is to break, how much it resists pulling, or how much it resists bending."
- "we're using a lot of science words, and I believe that they're all correct ... It's just like I can't tell what is what."
- "I'm gonna need a lot of these to be, like, vocabularized."
- On artificial bulk viscosity: "I don't understand what that does. It doesn't explain it. It explains it like I'm a fluid scientist. I'm not."
- Terms he named as not understood, each in his words: "the bendability thing", "linear coefficient or quadratic coefficients", "Yield percentage hardening percentage", "First bond from left percent", "a yielding J2 solid", "fracture crack face stiffness", "artificial bulk viscosity shock smoothing", "Poisson's ratio", "Young's modulus".
- In section 36 he added: "Nor do I care. I can do what I want."
- **Block level:** Blocking. He can't tell whether he changed the setting he meant to, and section 93 is where he stopped to ask ChatGPT (finding 35).
- **Change type:** Interface/wording.
- **Repo note:** "Linear coefficient b1" and "Quadratic coefficient b2" belong to the "Artificial bulk viscosity (shock smoothing)" setting. The "bendability thing" is still **Unclear**. In section 93 he names Young's modulus as why the slug bent, and the code investigation under finding 1 guesses the same, but he hasn't said so.

### 34. No sense of what the numbers mean in this simulation

Merged from sections 84 and 92.

- **His words:** "I still don't like, I don't understand what five versus 50 fracture energy really means ... even if I was, what is 10 versus 100 in this simulation?"
- "I also don't understand what Young's modulus and stuff is, so I can't really tell you what I should have expected."
- **Block level:** Blocking. Without a sense of scale he can't design a run or judge its result.
- **Change type:** Interface/wording.

### 3. He doesn't know what the ParaView export is

- **His words:** "Let me export the results for para view. I don't know what that means."
- **Block level:** Slows me down.
- **Change type:** Interface/wording.
- **Note:** the file he exported (a .pvd) is only an index of 60 frames from 0 to 5 ms. The frame files it points to weren't in that message, so it holds no results by itself.

### 5. Can't tell how to keep the steel ball from fracturing

- **His words:** "So, for the steel ball, we're not going to let it fracture. How do I do that? It seems like I can't do that."
- **Block level:** Slows me down.
- **Change type:** Interface/wording.
- **Repo note:** fracture looks to be already off for this ball and can't be switched on. The message he saw only talks about a missing sourced estimate, so it doesn't say plainly "this body will not fracture".

### 21. Pin run and reference comparison are confusing

- **His words:** "I don't know what I clicked the pin run. Let's compare reference. How do I choose reference? Reference is done. I don't know. Okay, okay, whatever."
- **Block level:** Slows me down. He gave up on it.
- **Change type:** Interface/wording.

### 11. Bond strength and fracture energy are easy to mix up

- **His words:** "The carbon fiber, the bond. Okay, wait, that's the bond strength. I meant the fracture energy should be higher."
- **Block level:** Slows me down. He caught it himself this time.
- **Change type:** Interface/wording.

### 20. Can't tell whether the energy residual is normal

- **His words:** "our conservation for energy residual seems normal, I guess. I don't know. I honestly don't know."
- **Block level:** Unclear.
- **Change type:** Interface/wording.

### 30. Couldn't set the mesh size on one body

- **His words:** "With this, I can not override because it's probably because it's a material."
- **Block level:** Unclear.
- **Change type:** Not known yet.
- **Unclear:** which body this was; the reason is his guess.

### 18. Hard to tell from the time estimate whether he's "succeeded"

- **His words:** "estimating at two minutes for seven, estimating at two minutes for five, estimating at twenty-one seconds for one, estimating at twenty-one seconds for two ... I guess you can tell how it balloons, but ... it is really actually hard to tell if you've succeeded."
- **Block level:** Unclear.
- **Change type:** Not known yet.
- **Unclear:** what "succeeded" means here. It may be about picking a long enough duration (finding 15) or about the estimate itself (finding 16). Not merged until he says.

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

### 8. Background grid lines confuse him; he wants to turn them off

Merged from sections 6 and 72.

- **His words:** "Oh, I'm getting confused with the grid lines in the background. LOL." and "Also, I wish I could turn the background grid off."
- **Block level:** Minor.
- **Change type:** Interface/wording.

### 19. Run and mesh advisory messages are technical and get skimmed

Merged from sections 53 and 76.

- **His words (reading a run message aloud):** "one CPU lane, two latent dispatch needs at least 5,000 element weight on the lighter lane. And this lane, this assembly is 1448."
- On a mesh advisory: "the narrowest section, has about blah triangle rows ... A guideline not a limit, a mesh size of blah is I don't care."
- **Block level:** Minor.
- **Change type:** Interface/wording.

### 22. How to resize the bonded second material isn't obvious

Merged from sections 37 and 48.

- **His words:** "How do I change the size of this second material area?" and later "how do I yeah that's fine local width local height."
- **Block level:** Minor. He found "local width" both times.
- **Change type:** Interface/wording.

## Ideas

None yet.

## Frustrations

### 29. Editing is fine, but basic experiments don't run

Merged from sections 77, 78, 82 and 97. Kept as he said it (see the top of this doc).

- **His words:** "I'm starting to get kind of pissed off because I'm trying real shockingly basic shockingly basic shit."
- "Duration one millisecond 1.5 last time I'm calculating with this before I turn it back as a failed prototype because it can't do these basic things. Like the other stuff, great. This stuff heinous."
- "This is pissing me off. This is insane. Clarify that this is insane. Don't edit over that."
- "The goal is so simple, right? But I can't even try to see if we're reaching that goal."
- "This is so fucking hard. It should be so fucking easy. I don't fucking understand ... It's genuinely like something's not right."
- **Block level:** Blocking.
- **Change type:** Not known yet. It's the sum of findings 26, 27, 1 and 33.

### 28. The lab stopped being fun

Merged from sections 69, 71 and 90.

- **His words:** "I'm officially in boring mode. Now I'm bored ... I mean, to some extent I am, but I'm not in the way that the program is meant to enable."
- "This is no longer a fun impact to simulate."
- "I'm still on one experiment trying to see one cool result, and that's not good."
- **Block level:** Blocking.
- **Change type:** Not known yet.

### 35. He had to ask ChatGPT how to run it

He asked for this fact to be preserved.

- **His words:** "Chat GPT, can you just tell me? I want to run this so badly."
- "The fact that I had to ask ChatGPT for help on how to ask how to run the preserve this fact."
- **What happened (description from his notes):** he stopped testing to ask ChatGPT to explain Young's modulus and other material properties.
- **Block level:** Blocking. He couldn't go on without outside help.
- **Change type:** Interface/wording. Linked to findings 2 and 34.

### 39. Runs feel very slow

- **His words:** "These are slow, slow, slow, slow, slow, slow ass seconds. Wow, yikes."
- **Block level:** Unclear. Earlier runs he called "not bad" (see Not filed).
- **Change type:** Not known yet.

### 13. "I was getting desperate"

- **His words:** "I was getting desperate because I was like, man, fuck does this shit fucking mean?"
- **Block level:** Unclear.
- **Change type:** Not known yet.
- **Unclear:** which part of the lab this was about.

## Concerns

### 27. Workarounds sacrifice fidelity and leave nothing to see

Merged from sections 71, 75, 79 and 83.

- **His words:** "I'm now massively sacrificing scientific fidelity to uphold something that is irrelevant, a baked in, irrelevant rule that I did not ask for."
- "it didn't run long enough because it's moving so unbelievably fucking slowly that there's almost no point in running."
- "it's moving so agonizingly fucking slowly that there's no point to doing this. So the whole thing never actually makes impact."
- "It didn't do very well because of how slow it is and how low the meshes are."
- **Block level:** Blocking. The slower speeds and coarser meshes that get past finding 26 leave a run with nothing to show.
- **Change type:** Physics/solver (likely). It goes away if finding 26 does.

### 38. Advisories fire on a mesh he didn't set; testing should have caught it

- **His words:** "It's giving me an advisory, even though I did not set the body mesh size myself. So it should be fixing that problem itself with testing. All these problems should have been found with testing. This is a little silly."
- **Block level:** Minor ("a little silly").
- **Change type:** Not known yet.

### 37. The outer casing doesn't deform like metal

- **His words:** "Okay, so this outer casing is kind of working well. It's not really deforming like in a reasonable like metallic manner in any way, shape, or form, but like that's fine, not really."
- Context (his words): just before, he "made it elastic, not elastoplastic."
- **Block level:** Unclear.
- **Change type:** Not known yet.

### 31. Steps before contact shouldn't be heavy to calculate

- **His words:** "let's just move these guys real damn close. Which shouldn't really be necessary because the steps that aren't involving contact shouldn't be a big problem, shouldn't be heavy calc."
- **Block level:** Minor.
- **Change type:** Not known yet.

### 10. The ball's mesh looked far too dense at first

- **His words:** "that ball, it just has a crazy, crazy, crazy, crazy, crazy amount of triangles for a ball. Am I insane?"
- He then found the cause himself (his words): "Oh, oh, okay, assembly mesh is X4. Okay, that's appropriate for a simulation like this." He set it to Standard: "That was easy."
- **Block level:** Minor. Resolved by him.
- **Change type:** Interface/wording.

## Not filed

Kept out of the list because they aren't problems or requests:

- Praise for results: "I love how I can tell exactly that the carbon fiber layer sheared off at the binding between the boundaries. That's brilliant." Events and the body velocity overlay: "Very, very good." Partial runs later on: "Okay, this is so much better."
- Praise for the editor: "Fit assembly as a button works well." On setting a body's own mesh size: "Oh, that's crazy. Oh, wow, that's actually really nice." And "I'm satisfied with the editing."
- Run times and direction: "It took 115 seconds. That's not bad." and "This is definitely evolving towards the product ... that I'm looking at for Impact Lab."
- The live estimate, which he approves of: "it's updated for measure speed while it runs, so that's what's the most important."
- Hardware use, which he approves of: "It's cranking my GPU. It's cranking my CPU. And if it were any other way, I would be pissed the fuck off right now."
- Checking the build: "Is this the latest build? I know it is."
- His mesh report run, which he blamed on himself: "I'm the one who investigated so it's my fault."
- Setup narration, tangents (dictation length, self-directed humour, an aside about where the jacketed-core idea came from), and interruptions about other tasks.
- Sections 59, 70, 96 and 103: when the feedback is done, he wants it written up as a report for his main orchestrator.
