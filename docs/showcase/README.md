# Impact Lab showcase

Three ready-to-run experiments that show what Impact Lab's existing mathematics can do today, and where it stops. They use only the normal scene format and the existing solver. Nothing in them is scripted or animated: every motion, dent and crack below was calculated.

**To run one:** in Impact Lab, click **Open**, go to this folder (`docs/showcase`), pick a file, and press **Calculate**. Every body stays fully editable in the workshop.

All numbers below come from `ImpactCheck --showcase docs/showcase/<file>.json` on the M1 MacBook Air (release build). For the two cascade scenes, the native app produced the identical step count.

---

## 1. Main showcase: multi-material impact cascade (`cascade.json`)

**The experiment.** A small stainless-steel slug flies at 80 m/s into a copper bar that leans at 25°. It hits above the bar's middle, so the bar both dents and starts to spin. The spinning bar then strikes two more bodies: a stainless puck sitting above it, and a tilted aluminum plate. The plate in turn topples into a steel block. Every body is a real metal profile from the Material Library, and every body can bend permanently.

**What actually happens (4 ms of simulated time):**

| Time | Event |
|---|---|
| 0.308 ms | The slug hits the copper bar |
| 2.080 ms | The spinning bar strikes the aluminum plate |
| 2.085 ms | The bar's top end clips the stainless puck |
| 2.358 ms | The plate is driven into the steel block |

| Body | Ends moving at | Rotated | Peak permanent strain |
|---|---|---|---|
| Stainless slug (started at 80 m/s) | 3.9 m/s right, 16.2 m/s down (bounced off) | −35° | 9.6% (flattened face) |
| Copper bar | 8.2 right, 7.0 up m/s | **−45°** | **21.7%** (badly bent) |
| Stainless puck | 2.5 right, 11.1 up m/s | −6° | 1.0% |
| Aluminum plate | 5.6 right, 10.8 down m/s | −1° | 8.5% |
| Steel block | 11.0 m/s right | −21° | 3.6% |

**Where the energy went.** The slug brought 24,253 J per metre of depth. At the end:
- 5,478 J/m is still motion;
- 10,328 J/m was dissipated by permanent bending;
- 8,030 J/m is stored as "hardening energy", the model's bookkeeping for how much stronger the bent metal has become;
- 417 J/m is still in elastic vibration.

The total stays balanced to within 0.001% throughout.

**Behaviors demonstrated:**
- Metal-dependent permanent deformation.
- Off-centre impact turning into rotation.
- Momentum handed down a chain of separate bodies.
- Secondary and tertiary contacts.
- Calculated stress fields.
- A complete energy ledger.

**Best things to look at:**
- **Plastic strain** at the end, to see where each metal bent.
- **Von Mises stress** around 2.1 ms, as the bar hits the puck.
- **Events**, to jump between contacts.
- **Measurements → Energy**, to watch kinetic energy turn into plastic dissipation.

**Cost.** 214,741 time steps (each 0.0186 µs) in about 78 s, using under 150 MB of memory.

Screenshots from the native app:
- [initial setup](screenshots/1-cascade-initial.jpg);
- [bar striking the puck, stress view, 2.13 ms](screenshots/4-cascade-2.13ms-stress-bar-hits-puck.jpg);
- [plate hitting the block, 2.36 ms](screenshots/3-cascade-2.36ms-plate-hits-block.jpg);
- [final plastic strain, 4 ms](screenshots/2-cascade-final-plastic-strain.jpg).

---

## 2. Controlled comparison: copper bar vs stainless bar (`cascade-stainless-bar.json`)

**The experiment.** This scene is identical to the main showcase except for one change: the tilted bar is **304 stainless steel instead of annealed copper**. Everything else is the same: geometry, positions, speeds, mesh and timing. Making the same swap by hand in the app gives exactly the same calculation (231,573 steps).

| Measurement | Copper bar | Stainless bar |
|---|---:|---:|
| Bar's peak permanent strain | 21.7% | **5.0%** |
| Slug's peak permanent strain | 9.6% | 12.2% |
| Slug's rotation | −35° | **−112°** |
| Bar hits puck at | 2.085 ms | 1.721 ms |
| Puck's final upward speed | 11.1 m/s | **18.1 m/s** |
| Aluminum plate's peak permanent strain | 8.5% | **15.3%** |
| Steel block: speed / rotation | 11.0 m/s / −21° | 10.3 m/s / −24° |
| Energy left as motion | 5,478 J/m | 7,723 J/m |
| Energy dissipated by bending | 10,328 J/m | 11,270 J/m |

**What it shows.** The soft copper bar acts like a crumple zone: it soaks up deformation and passes on less. The much stronger stainless bar barely bends, so the damage moves elsewhere. The slug itself flattens more and tumbles away spinning, the puck is flung harder, and the aluminum plate bends nearly twice as much. One material choice changes the outcome for every body in the chain.

Screenshot: [side-by-side plastic strain, copper (left) vs stainless (right)](screenshots/5-comparison-copper-vs-stainless-bar.jpg). To recreate it, run `cascade.json`, press **Pin**, then **Reset Run**, assign 304 stainless to the bar, press **Calculate**, and open **Compare** with **Plastic strain**.

---

## 3. Fracture showcase: brittle tile (`brittle-tile-fracture.json`)

**The experiment.** A tile made of a soft, brittle, made-up material (stiffness 1 MPa, about like a firm foam) rests on two free-standing posts, with a notch cut under the impact point. A heavier round hammer drops onto it at 3 m/s. Impact Lab's illustrative crack model lets cracks start, open and release pieces.

**What actually happens (80 ms of simulated time):**

| Time | Event |
|---|---|
| 0.48 ms | First crack damage begins |
| 1.87 ms | The first crack face fully fails |
| 7.48 ms | The first piece breaks free, and fragments start hitting each other |
| later | Fragments tumble onto the posts and the catcher plate below |

- The tile ends in **55 pieces**. Six large pieces hold 86% of its mass; the rest is small debris. In total 202 crack faces opened.
- The hammer passes through the tile, and the free-standing posts are knocked over.
- **Energy:** of 21.8 J/m brought in by the hammer, 5.47 J/m (25%) was spent creating crack surfaces. The total balances to within 0.24%.
- **Cost:** 98,202 steps in about 20 s.

**Best things to look at:**
- **Interface damage** just after 0.5 ms, as cracking begins.
- **Crack separation** after about 2 ms.
- **Events → First detached piece** (7.48 ms).
- Playback to the end, to watch the fragments scatter.

**How it was tuned, honestly.**
- With very low toughness (1 J/m²), the tile shattered into 286 pieces, mostly single mesh triangles. That is the mesh dictating the result, not believable physics.
- With high toughness and a faster hammer (12 J/m² at 3.5 m/s), the app's own safeguard stopped the run because energy stopped balancing by more than 2%.
- The shipped settings (7 J/m², a notch, 3 m/s) are the middle ground. No crack path was prescribed: where the tile breaks is calculated.

**Screenshots:** none yet for this scene. The native screenshots could not be captured without taking over the screen while it was in use. Open the file and press Calculate to see it.

---

## Limitations of these results

- **Flat 2-D world.** The model is a slice ("plane strain"), so forces and energies are per metre of depth. Real 3-D impacts spread differently.
- **Minimum body size of 25 mm.** There are no thin sheets, wires or small fragments-as-bodies.
- **No ground, gravity or friction.** Supports are just more free bodies, which is why the posts topple. Contacts are frictionless.
- **Metal behavior after yielding is illustrative.** The four metal profiles have real stiffness, density and yield values, but their hardening curves are approximate. Trust the trends (copper bends more than stainless) more than the exact percentages. The cascade runs at one mesh fineness; no refinement study was done for these scenes.
- **Metals cannot break.** The cascade shows bending only. Real copper at 21.7% strain would be close to tearing in places.
- **Fracture is illustrative.** The crack model belongs to a made-up soft material, not to any real metal or ceramic. The debris size is set by the mesh. A finer mesh would give different fragments.
- **One stiff body slows everything.** The time step for the whole scene is set by the stiffest, smallest element, which is why 4 ms of metal impact needs over 200,000 steps.

## What of the original vision is still unsupported

- **Large, flowing deformation** of the kind that tears a mesh. Extreme cases end with the energy safeguard stopping the run rather than continuing. (An alternative particle-based method, MPM, is being prototyped separately to explore this.)
- **Realistic material failure:** metal tearing, ductile fracture, spalling, and failure criteria calibrated against real materials.
- **True fragmentation** with physically sized fragments, independent of the mesh.
- **Fixed supports, gravity, friction, applied loads,** and speed- or temperature-dependent materials.
- **Full 3-D,** and bodies thinner than 25 mm.

These scenes show the current ceiling honestly: rich, energy-consistent elastic–plastic collisions between real metals, and illustrative cracking in soft brittle materials. They do not yet show metals failing or deforming beyond what a fixed mesh can follow.
