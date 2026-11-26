# Contact and artificial viscosity for soft bodies touching stiff ones

Research note, 2026-11-26. Read-only: no code was changed or run for this. Scope is materials and contact mechanics only.

How to read the labels:

- **Manual says**: a direct statement on the linked page.
- **Code says**: read from Impact Lab's source on `main` (commit `7a2588d`), with file and line.
- **Inferred**: my own reasoning or arithmetic from the two above. Not run, not tested.

## Short answers

1. **Viscosity in rubber.** None of the big codes turns artificial viscosity off for rubber by default. They keep it on and let you **scale it per part** (Abaqus, LS-DYNA, Radioss), and they fold it into **each element's own time-step limit**, so a slow-wave material like rubber only limits itself. Radioss is the one that zeroes it by default, and only for one foam law.
2. **Contact.** The mainstream fix for soft-against-stiff overlap is **penalty contact whose stiffness is set from the nodes' mass and the time step** (LS-DYNA `SOFT=1`, Radioss `Istf=7`), not from the softer material's stiffness. Exact methods (Lagrange multipliers, Abaqus "kinematic") stop overlap fully but are less stable or lose energy at impact. The standard benchmark is the **Hertz contact problem** (cylinder pressed on a flat), with a rubber cylinder on a steel flat.

## What Impact Lab does today

### Artificial viscosity (bulk viscosity)

- **Code says:** while an element is squeezed it gets an extra pressure `q = ρ·l·(b1·c·|ε̇v| + b2²·l·ε̇v²)`, with Abaqus's defaults b1 = 0.06, b2 = 1.2, off unless a scene turns it on (`Sources/ImpactPhysics/BulkViscosity.swift`, `Physics.swift` ~944, `docs/BULK_VISCOSITY.md`).
- **Code says:** one number for the whole run. Every step it takes the largest damping fraction ξ found in **any** element, `ξ = b1 + b2²·(l/c)·|ε̇v|`, and stops the run if `√(1+ξ²) − ξ` falls below 0.8 of its starting value (`AssemblySimulation.swift` 884–896, `BulkViscosity.swift` 46–58).
- **Code says:** the time step is set once at the start from the stiffest body (`AssemblySimulation.swift` 547).
- **Code says:** the app's rubber is E = 3 MPa, Poisson 0.48 (capped from a real 0.4999), density 930 kg/m³ (`LibraryMaterialValues.swift` 42–47, `Physics.swift` 20).
- **Inferred:** that gives rubber a wave speed of about **168 m/s**, against about **5,860 m/s** for the app's steel, so roughly 35 times slower. The time step is set by the steel, so rubber elements sit far below their own limit.
- **Inferred:** because ξ divides by the element's own wave speed, the same squeeze rate gives rubber about 35 times more ξ than steel. A rough estimate (ξ ≈ 0.06 + 1.44·v/c at an impact face) says the stop trips for rubber struck at roughly **25 m/s or more**, where steel would need roughly 900 m/s. That stop is guarding the wrong thing: the rubber element is nowhere near going unstable, because the step was set by the steel.

### Contact

- **Code says:** contact is penalty, node into edge, done both ways (each body's boundary nodes are checked against the other body's edges, `BoundaryContact.swift` 145–155).
- **Code says:** each node's spring stiffness comes from **its own body's** Young's modulus times its share of boundary length times a fixed 2500 per metre (`BoundaryContact.swift` 81), doubled when fracture is on (`AssemblySimulation.swift` 416).
- **Inferred:** so a rubber node pushing into steel gets a rubber-soft spring, and a steel node pushing into rubber gets a steel-stiff spring. This is the "roughly the minimum of the two stiffnesses" case that the LS-DYNA notes below warn is too soft.
- **Inferred:** the fixed 2500 per metre does not change with mesh size, so the spring grows with element size. A coarse body gets a stiffer contact spring than a fine one. Worth checking on its own.
- **Code says:** the node is pushed toward the **nearest edge** of the body it is inside (`BoundaryContact.swift` 227–247). In a thin hollow wall, once a node is past the middle, the nearest edge is the far face, so it is pushed out the other side.
- **Code says:** overlap is measured as depth divided by the length of the edge pushed into (line 168), and with fracture on, a run stops when it passes 10% (`AssemblySimulation.swift` 970). The stop message now names both bodies (`overlapFailure`, ~770), which `docs/FEEDBACK.md` finding 26 asked for.

## Question 1: viscosity in low-wave-speed materials

### What the manuals say

- **Abaqus/Explicit**
  - Linear bulk viscosity is "always included", default 0.06. Quadratic, default 1.2, is "applied only if the volumetric strain rate is compressive" and is there "to prevent elements from collapsing under extremely high velocity gradients." ([Explicit dynamic analysis](https://abaqus-docs.mit.edu/2017/English/SIMACAEANLRefMap/simaanl-c-expdynamic.htm))
  - "Introducing damping to the solution reduces the stable time increment", with ξ "the fraction of critical damping in the highest mode", and "a trial stable time increment is computed for each element in the mesh." (same page, and the [theory page](https://abaqus-docs.mit.edu/2017/English/SIMACAETHERefMap/simathe-c-expdynamic.htm))
  - Per element set you can "scale the linear and quadratic bulk viscosities", each scale factor default 1.0, "suggested range ... between 0.0 and 1.0." ([*SECTION CONTROLS](https://abaqus-docs.mit.edu/2017/English/SIMACAEKEYRefMap/simakey-r-sectioncontrols.htm))
  - Nothing on the pages read says to turn it off for rubber.
- **LS-DYNA**
  - `*CONTROL_BULK_VISCOSITY` "sets the bulk viscosity coefficients globally", Q1 = 1.5 quadratic, Q2 = 0.06 linear. ([LS-DYNA User's Guide, Control Cards](https://ansyshelp.ansys.com/public/Views/Secured/corp/v242/en/lsdyna_ug/exd_ag_lsdyna_control_cards.html))
  - Per part, `*HOURGLASS` "defines hourglass and bulk viscosity properties which are referenced via HGID in the *PART command." ([Altair HyperMesh, Hourglass](https://help.altair.com/hwdesktop/hwx/topics/pre_processing/entities/hourglass_r.htm))
  - Not confirmed here: the element time-step formula with viscosity in it, `Δt = l / (Q + √(Q² + c²))`, `Q = C1·c + C0·l·|ε̇v|`. It is in the LS-DYNA Theory Manual, which was not read for this note (the PDF is very large).
- **Radioss (OpenRadioss is built from it)**
  - Defaults qa = 1.10 quadratic, qb = 0.05 linear, with "Default = 0.0 for /MAT/LAW70" (a foam law) for both. ([/PROP/TYPE14 SOLID](https://help.altair.com/hwsolvers/rad/topics/solvers/rad/prop_type14_solid_starter_r.htm))
  - The defaults are "relevant for hydrodynamics and high speed impact problems involving shock waves"; "for fluid dynamics and acoustics ... most generally set to very small values." ([Artificial Damping for Shock Waves](https://help.altair.com/hwsolvers/rad/topics/solvers/rad/articificial_damping_shock_waves_r.htm))
  - The same SOLID page recommends a distortion control flag (`I_control`) "for soft material, compressible foam, rubber materials". That is not a viscosity setting.
- **EUROPLEXUS**: nothing found on its bulk viscosity for this note.

### What that means

- **Manual says:** nobody switches it off for rubber by default; you scale it per part. Only Radioss zeroes it, and only for one foam law.
- **Manual says (Abaqus):** the limit is per element. **Inferred:** each element is judged against its own wave speed and size, so a slow rubber element only limits a step that it would set itself. Impact Lab instead compares the worst element in any body against one shared step.

## Question 2: which contact method best stops soft-stiff overlap

### The four families

- **Penalty, stiffness from the materials** (LS-DYNA `SOFT=0`, Radioss `Istf` 2–5, Impact Lab today)
  - **Manual says:** for dissimilar materials "the stiffness, which is roughly the minimum of the slave and master stiffness, may be too small", and "for crash analysis we do not recommend the option, SOFT = 0, unless prior experience shows that no problems occur." ([Contact stiffness calculation](https://lsdyna.ansys.com/?p=13140), [Contact modeling in LS-DYNA](https://lsdyna.ansys.com/contact-modeling-in-ls-dyna-3/))
- **Penalty, stiffness from nodal mass and time step** (LS-DYNA `SOFT=1`, Radioss TYPE25 `Istf=7`)
  - **Manual says:** k = max(SLSFAC·SFS·k0, SOFSCL·k1), with k1 from the contacting nodes' mass over the time step squared, SOFSCL default 0.1. "The SOFT=1 option is recommended for impact analysis where dissimilar materials come into contact", and it "will generally be more effective than Soft=0 for soft materials contacting stiff materials or where the mesh densities of the two contacting surfaces are dissimilar." For foam on metal it "often gives interface stiffness that are one or two orders-of-magnitude greater." ([SOFT option](https://lsdyna.ansys.com/?p=13360), [?p=13140](https://lsdyna.ansys.com/?p=13140), [LSTC FAQ contact.soft1](https://ftp.lstc.com/anonymous/outgoing/jday/faq/contact.soft1))
  - **Manual says:** "k1 is proportional to 1/(time step)^2. Thus, if the time step is cut in half, the contact stiffness increases by a factor of 4." ([Contact stiffness influenced by time step size](https://lsdyna.ansys.com/?p=3251))
  - **Manual says:** Radioss TYPE25 offers stiffness "only based on stability condition" (`Istf=7`), and "the penalty stiffness is constant and therefore the time step is not affected." ([/INTER/TYPE25](https://help.altair.com/hwsolvers/rad/topics/solvers/rad/inter_type25_starter_r.htm))
  - **Manual says:** LS-DYNA's segment-to-segment version (`SOFT=2`, "origins in Pinball contact") is "generally good at handling dissimilar mesh refinements or dissimilar material stiffnesses" and "can often be quite effective where other methods fail at treating contact at sharp corners." ([SOFT option](https://lsdyna.ansys.com/?p=13360), [Modeling guidelines for full vehicle contact](https://lsdyna.ansys.com/?p=13146))
- **Penalty that stiffens as the gap closes** (Radioss TYPE7)
  - **Manual says:** "after initial penetration, the stiffness is given as a function of the penetration distance and the rate of penetration," built to give "minimum crossing of surfaces", and its own time step is shortened to keep it stable: "Time step is reduced in case of high impact speed or contacts with small gap." ([TYPE7 theory](https://help.altair.com/hwsolvers/rad/topics/solvers/rad/theory_interfaces_general_purpose_contact_type7_r.htm), [/INTER/TYPE7](https://help.altair.com/hwsolvers/rad/topics/solvers/rad/inter_type7_starter_r.htm))
  - **Inferred:** a poor fit for Impact Lab while its step is fixed at the start.
- **Exact methods** (Lagrange multipliers, Abaqus "kinematic", EUROPLEXUS pinball)
  - **Manual says (Abaqus):** contact pairs use kinematic contact by default, general contact always uses penalty. In the Hertz benchmark the kinematic peak pressure "is within 1% of the classical solution" while penalty is "significantly lower" because of the overlap it allows. But "impact is plastic when the default hard, kinematic contact algorithm is used and the kinetic energy of the contacting nodes is lost." ([Abaqus/Explicit contact formulation](https://abaqus-docs.mit.edu/2017/English/SIMACAEGSARefMap/simagsa-c-cntexpformulation.htm), [Contact constraint enforcement](https://abaqus-docs.mit.edu/2017/English/SIMACAEITNRefMap/simaitn-c-expcontactconstraints.htm), [Hertz benchmark](https://abaqus-docs.mit.edu/2017/English/SIMACAEBMKRefMap/simabmk-c-hertzcontact.htm))
  - **Manual says (LS-DYNA):** its constraint contact keeps nodes "exactly on the master surface (zero penetration)", but "this contact has never been as stable as the penalty-based contacts and is, therefore, not recommended." ([Contact modeling in LS-DYNA](https://lsdyna.ansys.com/contact-modeling-in-ls-dyna-3/))
  - **Manual says (Radioss):** Lagrange gives "no time step collapse, due to high interface stiffness." ([/INTER/TYPE7](https://help.altair.com/hwsolvers/rad/topics/solvers/rad/inter_type7_starter_r.htm))
  - **Paper says (EUROPLEXUS):** its pinball contact started with Lagrange multipliers and later added penalty; the penalty form "needs some tuning parameters", and with multipliers "redundant constraints may be generated and the system of constraints may become singular." ([Casadei, Valsamos, Larcher, JRC 2023](https://publications.jrc.ec.europa.eu/repository/bitstream/JRC134229/JRC134229_01.pdf))
- **Defence node**: a contact-search idea from the research literature (Zhong and Nilsson). None of the manuals read uses it as a default, and no mainstream source was read for it here, so it is not recommended.

### One-pass, two-pass and the patch test

- **Paper says:** "one-pass algorithms are geometrically biased by the choice of a specific slave surface" and "two-pass algorithms generally over-constrain the contacting boundary surfaces." ([Jones and Papadopoulos, OSTI 767443](https://www.osti.gov/servlets/purl/767443))
- **Paper says:** "the classical one-pass node-to-segment (NTS) algorithms ... fail the contact patch test." ([Zavarise and De Lorenzis 2009, abstract](https://www.academia.edu/50629536/A_modified_node_to_segment_algorithm_passing_the_contact_patch_test))
- **Manual says (Abaqus):** "the balanced approach minimizes the penetration of the contacting bodies and, thus, provides more accurate results in most cases." Impact Lab's two-way check is this balanced kind.

### What that means

- **Inferred:** for Impact Lab the best fit is penalty with a mass-and-time-step stiffness floor, kept two-way. The step is fixed from the start, so the `1/Δt²` dependence that LS-DYNA warns about is harmless here, and a spring of 0.1·m/Δt² is far below the stability limit 4·m/Δt² by construction.
- **Inferred, rough:** for a 2 mm rubber node in a steel-set step near 1e-7 s, the mass-based spring is about a thousand times stiffer than today's rubber-based one. That matches the "orders of magnitude" LS-DYNA reports for foam on metal.
- **Inferred:** exact methods would lose impact energy (Abaqus kinematic) or need a joint solve every step (Lagrange), and Impact Lab's energy books and fracture energy guard care about energy. Not the first step.

## Recommendation for Impact Lab

In priority order. Each is one change. None is built yet.

1. **Mass-based floor on the contact spring.** Each node's spring becomes the larger of today's value and `0.1 × (smaller of the two contacting nodal masses) / Δt²`, as LS-DYNA `SOFT=1` does. Rubber nodes stop sinking into steel. *Physics/solver.*
2. **Pick the edge the node crossed, not the nearest edge.** Use the edge that the node's path from last step to this step went through, and fall back to the nearest edge only when there is none. This stops nodes being pushed out through thin hollow walls. *Physics/solver.* (Inferred design. The manuals solve this with contact thickness and segment-based contact, `SOFT=2`.)
3. **Check bulk viscosity element by element.** Compare each element's damped limit, from its own size and wave speed, against the actual step, instead of the worst ξ in any body against the shared step. A slow rubber element then only stops a run if it would really go unstable. *Physics/solver.*
4. **Allow a per-material viscosity scale from 0 to 1**, like Abaqus section controls and LS-DYNA's per-part `*HOURGLASS`. *Physics/solver plus interface* (a field in the scene format and the editor).
5. **Measure the overlap against the smaller element on either side**, not only the edge being pushed into, so a coarse corner on a fine edge isn't over-counted. It changes when runs stop. *Physics/solver.*
6. **Separate from contact:** the app's rubber wave speed (about 168 m/s) comes from capping Poisson at 0.48. Real rubber is nearly incompressible and its squeeze wave is much faster. That is a material-model question, not a contact one. *Physics/solver.*

Already done: the stop message names both bodies (finding 26's interface-only fix).

## Standard benchmark

**The Hertz contact problem**, as in the Abaqus Benchmarks Guide: a cylinder pressed onto a flat, plane strain, frictionless, and measuring peak pressure and contact width against the closed-form answer ([Hertz benchmark](https://abaqus-docs.mit.edu/2017/English/SIMACAEBMKRefMap/simabmk-c-hertzcontact.htm)). Abaqus runs it as two equal steel cylinders (radius 254 mm, E = 206 GPa).

- **For this problem:** run it as a **rubber cylinder on a steel flat**, then steel on rubber, at two mesh sizes. Pass marks: peak pressure and half-width within a few percent of Hertz, and maximum overlap a small fraction of an element.
- **Closed form (standard textbook result, Johnson, Contact Mechanics, 1985):** for load P per metre, half-width `a = √(4PR/(πE*))`, peak pressure `p0 = √(PE*/(πR))`, with `1/E* = (1−ν1²)/E1 + (1−ν2²)/E2`. Wikipedia's [Contact mechanics](https://en.wikipedia.org/wiki/Contact_mechanics) page covers this case, but its formulas didn't come through when I read it, so the formulas here are from the textbook result, not that page. Its stated limits: small elastic strains, contact small compared with the bodies, frictionless.
- **Second check, impact:** the Abaqus [truss impact on a rigid wall](https://ceae-server.colorado.edu/v2016/books/bmk/ch01s03ach34.html) benchmark. A bar hits a wall and should leave at its starting speed, with contact lasting two wave transits of the bar. It tests energy at contact, which the Hertz problem doesn't.
- **Third check, consistency:** the contact patch test (Taylor and Papadopoulos, 1991): two blocks with mismatched meshes pressed together should carry an even pressure.
