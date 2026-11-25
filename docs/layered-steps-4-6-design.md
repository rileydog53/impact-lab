# Layered target plan, steps 4 to 6: design notes

Written 24 November 2026 as a read-only design audit of `main` at `42f764c` (after PR 4, the fracture guard fix, and PR 6, outline bodies). Open PR 5 (per-layer plasticity and fracture, plan steps 2 and 3) was read for where it touches the same code, but it is not merged and nothing here depends on it.

Nothing was built or run. This cloud machine has no Swift, and the code needs Apple's `simd` and CoreGraphics. Every number below is either a hand calculation, a calculation that copies a formula from the code into Python, or a value from a cited source.

How claims are marked:

- **[code]** read directly from the Swift source on `main`, with file and function.
- **[calc]** a hand or scripted calculation done for this note.
- **[source]** checked against the linked page during this audit.
- **[recall]** stated from memory of the literature and not checked against a source during this audit. Treat these as leads to confirm, not facts.

---

## Summary

| Step | Conclusion |
|---|---|
| 4. Artificial bulk viscosity | Use the standard linear plus quadratic bulk viscosity (von Neumann–Richtmyer quadratic term plus a linear term, as in Wilkins 1980 and LS-DYNA), LS-DYNA defaults Q1 = 1.5, Q2 = 0.06, compression only, off by default. It hooks into one place, `Simulation.assembleElements` in `Sources/ImpactPhysics/Physics.swift`, which both solvers call. Its energy goes in a new `viscous` term that is part of `AssemblyEnergy.total`, so the existing energy guard sees it. |
| 5. Spall hand calculation | For a plate hitting an **equal** plate, the two release waves meet **at the impact interface**, at 2h/c after impact. A contact interface cannot carry tension, so the ideal 1D answer is no spall: the plates separate, the striker stops and the target leaves at the impact speed. Peak tension ρcv/2 only appears inside material when the target is thicker than the striker. Exact numbers for steel and aluminium at 50 and 100 m/s are in the tables, for both the asked-for equal-plate case and the usual 1:2 case. This is flagged for Joey's decision, not substituted. |
| 6. Locking test | A plane-strain flat-punch compression of a perfectly plastic block has a known limit pressure, (2 + π)k. A mesh that locks keeps climbing past it. A uniform-compression control, where these triangles are exact, separates locking from plasticity bugs. If locking shows, the fix is the Bonet and Burton averaged nodal pressure, applied per material so it never averages across a layer boundary. |
| Fracture-on three-point bend, about 3.6× slower | About 2.5× of it is more time steps. Turning fracture on for any body (1) doubles every contact penalty, (2) adds the contact allowance and the crack-face stiffness (at least 30·E/h) at every triangle corner, and (3) divides by one corner's mass instead of a node's full mass. The remaining factor of about 1.4 per step is extra work each step, mainly the self-contact search and the crack check. The 2.5× is computed from the code's own step formula. The 1.4× is inferred from your 3.6×, not measured. |

---

## Step 4. Artificial bulk viscosity

### What to use

The recommendation is the standard linear plus quadratic artificial bulk viscosity. It adds a pressure q to an element only while the element is being compressed:

```
if  ε̇_v < 0:   q = ρ · l · ( Q1 · l · ε̇_v²  −  Q2 · c · ε̇_v )
otherwise:      q = 0
```

- ε̇_v is the volumetric strain rate (the rate of change of ln J; in plane strain this is the in-plane trace because F_zz = 1).
- ρ is the current density, c the elastic longitudinal wave speed, and l the element's characteristic length.
- The quadratic term (Q1) is von Neumann and Richtmyer's original term. It spreads a shock over a few elements. The linear term (Q2) damps the ringing behind the front.
- Defaults: Q1 = 1.5, Q2 = 0.06. **[source]** [Ansys LS-DYNA User's Guide 2024 R2, *CONTROL_BULK_VISCOSITY](https://ansyshelp.ansys.com/public/Views/Secured/corp/v242/en/lsdyna_ug/exd_ag_lsdyna_control_cards.html) lists "Q1 = 1.5. Quadratic Artificial Viscosity" and "Q2 = 0.06. Linear Artificial Viscosity". The [d3view note on LS-DYNA bulk viscosity](https://www.d3view.com/bulk-viscosity-for-shells-and-solids-in-ls-dyna/) gives the same defaults, says a positive strain-rate trace is ignored (compression only), says the element dimension is the square root of area in 2D, and says the dissipated energy is "included in the overall energy balance".
- The formula itself, with these symbols and signs, is **[recall]** from the LS-DYNA Theory Manual. The pages above describe it in words only. Confirm it against the Theory Manual before coding.
- Origins: J. von Neumann and R. D. Richtmyer, "A Method for the Numerical Calculation of Hydrodynamic Shocks", J. Appl. Phys. 21 (1950) 232–237, [doi:10.1063/1.1699639](https://doi.org/10.1063/1.1699639) **[source]**. M. L. Wilkins, "Use of artificial viscosity in multidimensional fluid dynamic calculations", J. Comput. Phys. 36 (1980) 281–303, [doi:10.1016/0021-9991(80)90161-8](https://doi.org/10.1016/0021-9991(80)90161-8) **[source]** for the citation; that Wilkins argues for the linear plus quadratic combination and for compression-only use is **[recall]**. Background: L. G. Margolin's review linked in the plan doc.

Why this and not something else: it is what production explicit codes ship as the default, it is cheap (one extra term per element), it needs no extra unknowns, and it has decades of calibration behind its two numbers. Constant-strain triangles have no hourglass modes, so the hourglass controls that LS-DYNA pairs with it are not needed here **[recall]** (a constant-strain triangle has no zero-energy modes besides rigid motion).

Choices that are mine (engineering judgement, not from a source):

- **Length l.** Use l = √(2·A·J), the current-area version of the size measure the repo already uses for wave-transit time in `docs/CONTACT_REPORTING.md` (√(2 × triangle area)). LS-DYNA uses √A in 2D. The difference is a factor √2 in l, which is the same as rescaling Q1 by 2 and Q2 by √2. Whichever is chosen, write it down next to Q1 and Q2, because it changes the effective coefficients.
- **c.** The element's elastic longitudinal wave speed, `Material.waveSpeed`, from `body.elementMaterials?[i] ?? body.material`. That already handles per-element materials (and PR 5's layers).
- **Off by default.** A new optional scene setting, for example `"bulkViscosity": { "quadratic": 1.5, "linear": 0.06 }`, read into an optional `BulkViscosity?` that is `nil` when absent. When `nil`, no new arithmetic runs at all, so `--legacy-replay check` stays bit-identical.
- **Not in the crack test.** Store the element's stress for crack insertion (`trialPiola`) *before* adding q. q is a numerical stress, and it only ever adds compression, so this only matters in mixed states, but crack strength should be judged on the material's own stress.

### Where it hooks in

**[code]** Every element stress in both solvers comes from one function: `Simulation.assembleElements` in `Sources/ImpactPhysics/Physics.swift` (the private generic function near line 782 on `main`). `BodyStep.assemble` calls it for the Assembly tab (`AssemblySimulation.step`), and `Simulation.step` calls it for the legacy presets. Inside the per-element loop the code has:

- `position` = the trial positions at the end of the step (`BodyStep.nextPosition`),
- `body.position` = the accepted positions at the start of the step,
- `fx`, `fy` = the columns of F, and `j` = det F,
- `stress` = the first Piola stress, built either by `J2Model.update` or by the neo-Hookean branch.

The hook goes right after `stress` is built and before the finite check:

```swift
// Sketch, not compiled. viscosity is nil unless the scene turns it on.
if let viscosity {
    let old0 = body.position[e.b] - body.position[e.a]
    let old1 = body.position[e.c] - body.position[e.a]
    let jOld = cross2D(old0 * e.g1.x + old1 * e.g2.x, old0 * e.g1.y + old1 * e.g2.y)
    let rate = log(j / jOld) / dt              // volumetric strain rate over the step
    if rate < 0 {
        let material = body.elementMaterials?[i] ?? body.material
        let density = material.density / j      // current density
        let l = (2 * e.area * j).squareRoot()
        let q = density * l * (viscosity.quadratic * l * rate * rate - viscosity.linear * material.waveSpeed * rate)
        // P_q = −q · J · F^(−T) = −q · cofactor(F)
        stress = ElementPiola(stress.x - q * Point(fy.y, -fy.x), stress.y - q * Point(-fx.y, fx.x))
        qNext[i] = q
    } else { qNext[i] = 0 }
}
```

`Point(fy.y, -fy.x)` and `Point(-fx.y, fx.x)` are the cofactor columns the neo-Hookean branch already uses for its pressure term **[code]**. The rate comes from positions only (ln of the area ratio over one step), so the velocity-Verlet order does not need to change: in this scheme (x_{n+1} − x_n)/dt is exactly the half-step velocity.

Plumbing this needs:

1. `dt` and the optional viscosity passed into `assembleElements` (through `BodyStep`, which already carries per-body state).
2. A per-element `q` array pair in `BodyStep`, `q` and `qNext`, swapped in `accept()` like `strain`/`nextStrain`, so a rejected step leaves no trace. PR 5 changes `ElementHistory` and `BodyStep.init` but not this loop's shape, so the hook point is the same on that branch **[code, PR 5 diff]**.

### Time step

The step is fixed once, at the start of a run: `dt = stepScale · 0.8 / √(max ω²)` in `AssemblySimulation.init` **[code]**. Viscosity shortens the stable step. LS-DYNA's element step with bulk viscosity is Δt = l / (Q + √(Q² + c²)) with Q = Q2·c + Q1·l·|ε̇_v| **[recall]**.

- The linear part is known in advance. With Q2 = 0.06 it shortens the step by the factor √(1 + Q2²) − Q2 ≈ 0.942 **[calc]**. Apply that factor at the start, only when viscosity is on.
- The quadratic part depends on the strain rate, which is unknown in advance. At a front, l·|ε̇_v| is roughly the velocity jump, so Q1·l·|ε̇_v|/c ≈ 1.5 × (50 m/s ÷ 5,856 m/s) ≈ 0.013 for steel at 100 m/s impact **[calc]**. That is small against the 0.8 margin, but it should be checked, not assumed: compute each compressing element's limit in the kernel, keep the worst ratio, and stop the step with a plain message ("artificial viscosity needs a shorter step; lower stepScale") if it is ever exceeded. Never let it go silently unstable.

### How to report its energy

Viscosity removes energy, like plastic flow, so it must be a running total, not a state.

- Per step, the work done against the viscous stress in element e is ΔW_e = A_e · q̄_e · (J_n − J_{n+1}), with q̄ the trapezoid average ½(q_n + q_{n+1}). This is ≥ 0 because q is only non-zero while J falls. The trapezoid matches how the repo already books spring and link work (`0.5 * (old.force + new.force) * (new.extension − old.extension)` in `Sources/ImpactCheck/Assembly.swift`) **[code]**. The exact discrete work of the Verlet scheme differs from this by a higher-order amount **[recall]**; the energy check will show the size of that difference.
- Add `viscous` to `AssemblyEnergy` and include it in `total`. **[code]** The fracture energy guard is `EnergyAcceptance.accepts(residual: trial.total − initialEnergy, …)` in `AssemblySimulation.step`, so anything in `total` is automatically inside the check. If viscosity were left out of `total`, the guard would read the dissipated energy as an error and start rejecting steps.
- Keep the accepted running total in the simulation and set `trial.viscous = acceptedViscous + ΣΔW_e` each step, so rejected steps do not add to it.
- Give it its own line in the energy chart and the results export, and its own field in the legacy `Diagnostics`.
- Report the fraction viscous / initial energy at the end of each run. In a plain elastic bar the linear term still damps the wave a little, so the bar wave-speed check should also print how much energy went to viscosity, not only the speed.

### Checks for step 4 (proposed)

- Viscosity off: `--legacy-replay check` bit-identical, regression suite unchanged.
- Viscosity on, elastic bar: wave speed still within the current tolerance, viscous energy reported.
- Viscosity on, plate impact (step 5 setup): peak stress overshoot above ρcv/2 reported with viscosity off and on. Off should show ringing (Gibbs-type overshoot), on should not. The front width should be a few elements.

---

## Step 5. Spall hand calculation (1D, elastic)

### The 1D picture

Two plates of the same material, striker thickness δ moving at speed v, target thickness T at rest, same width. In 1D uniaxial strain **[recall, standard plate-impact wave theory; for example Meyers, *Dynamic Behavior of Materials*, 1994, and Antoun et al., *Spall Fracture*, 2003]**:

- Equal impedance means the interface moves at u = v/2 after impact.
- A compressive stress σ = ρ·c·u = ρ·c·v/2 runs into both plates at the longitudinal wave speed c.
- Each wave reflects from its free back face as a release wave, which brings stress back to zero.
- The striker's release wave crosses the interface at t = 2δ/c and runs on into the target. The target's own release starts back from its rear face at t = T/c.
- **[calc]** The two release waves meet where c·t − 2δ = 2T − c·t, so at t = (T + δ)/c, at a distance **δ from the target's back face**. Where they overlap, the stress is −σ: a tension of ρ·c·v/2, lasting about 2δ/c.

c must be the longitudinal (uniaxial strain) speed √((λ + 2μ)/ρ), not the bar speed √(E/ρ). That is exactly `Material.waveSpeed` in the code, and plane strain has the same longitudinal speed as 3D **[code, calc]**.

### The case asked for: equal plates (T = δ = h)

**[calc]** With T = δ, the meeting point δ from the back face is the impact interface itself, and the meeting time is 2h/c.

- The interface is a contact, not a bond, so it cannot carry tension. In the ideal 1D picture the plates simply come apart at t = 2h/c. The striker ends at rest and the target leaves at speed v (a complete momentum swap, as for equal elastic balls).
- Peak tension inside either plate: zero. No spall.
- Tension ρcv/2 at t = 2h/c would appear only if the two plates were bonded at the interface (for example with PR 5's bond law).

So the equal-plate run is a good **no-spall control**, not a spall test. It has a crisp prediction: no crack anywhere, separation at 2h/c, striker velocity near 0 and target centre-of-mass velocity near v afterwards, with any numerical ringing showing up as spurious tension.

The plan's wording ("about one striker thickness in from the back") is the thicker-target case. The usual laboratory choice is T = 2δ **[recall]**, which puts the spall plane in the middle of the target at t = 3δ/c. That case is given below too, as an option for Joey to pick. It is not a substitute for the equal-plate case.

### Material values used

| | E | ρ | ν | c from these values **[calc]** | Handbook longitudinal c **[source]** |
|---|---|---|---|---|---|
| Steel: repo profile "Structural Steel (A36-like)" | 200 GPa | 7,850 kg/m³ | 0.30 | **5,856 m/s** | 5,890 m/s ("Steel, 1020") |
| Aluminium: repo profile "6061-T6 Aluminum" | 68.9 GPa | 2,700 kg/m³ | 0.33 | **6,149 m/s** | 6,320 m/s ("Aluminum") |

- E, ρ and ν are the repo's own reference profiles in `Sources/ImpactPhysics/MaterialProfile.swift` **[code]**. Their sources, as listed there, are TISCO A36 plate data and ASM MatWeb 6061-T6. The repo notes that the Poisson ratios are representative or estimated.
- The handbook column is from the [Olympus/Evident NDT table of material sound velocities](https://www.olympus-ims.com/en/ndt-tutorials/thickness-gage/appendices-velocities/), which calls them "typical" values that can vary.
- The simulation will use the repo values, so the check should use the **bold** c. The aluminium difference (6,149 against 6,320, about 3%) comes from the estimated ν = 0.33; it is a reason to keep the check's tolerance on time above 3% if handbook values are ever compared.

### Numbers

**[calc]** σ = ρ·c·v/2 with the repo values. Times are for a 10 mm striker (δ = 10 mm); every time scales in proportion to δ.

| Material, impact speed | Interface speed u | Peak stress ρcv/2 | Strain u/c |
|---|---|---|---|
| Steel, 50 m/s | 25 m/s | **1.149 GPa** (handbook c: 1.156) | 0.0043 |
| Steel, 100 m/s | 50 m/s | **2.299 GPa** (handbook c: 2.312) | 0.0085 |
| Aluminium, 50 m/s | 25 m/s | **0.415 GPa** (handbook c: 0.427) | 0.0041 |
| Aluminium, 100 m/s | 50 m/s | **0.830 GPa** (handbook c: 0.853) | 0.0081 |

| Material | δ/c (waves reach back faces) | 2δ/c (equal plates: release waves meet at the interface) | 3δ/c (T = 2δ: spall plane at target mid-thickness) |
|---|---|---|---|
| Steel | 1.708 µs | **3.415 µs** | **5.123 µs** |
| Aluminium | 1.626 µs | **3.253 µs** | **4.879 µs** |

Times are measured from first contact, which the run already records (`firstContactTimes`) **[code]**. The times do not depend on impact speed; the stresses scale with it.

Where the spall plane is:

- Equal plates: at the impact interface, t = 2δ/c. Contact opens; no material crack.
- T = 2δ: δ from the target's back face (its middle), t = 3δ/c, tension ρcv/2 for about 2δ/c.

### The elastic limit, and why the check should use elastic plates

**[calc, formula recall]** In uniaxial strain, a von Mises metal starts to yield at the Hugoniot elastic limit σ_HEL = (1 − ν)/(1 − 2ν)·Y.

- Steel profile (Y = 250 MPa): σ_HEL ≈ 438 MPa. Both 1.15 and 2.30 GPa are far above it, so a plastic steel plate would not follow the elastic picture: an elastic precursor and a slower plastic wave form, and the numbers above no longer hold.
- Aluminium profile (Y = 276 MPa): σ_HEL ≈ 544 MPa. At 50 m/s (415 MPa) the plate stays elastic. At 100 m/s (830 MPa) it yields.

So the hand-calculation check should run with **elastic** plates (response Elastic), fracture on, and a cohesive strength set below the predicted tension. Real spall strengths of these metals, and the plastic case, belong to a later step.

### Suggested run setup (all choices, for Joey to approve before any run)

- Plates 100 mm wide (at least 10δ), so edge release waves, which also travel at c, cannot reach the middle before 3δ/c. The prediction is only valid on the middle of the plate.
- At least about 8 elements through the striker (the x7 mesh is about 1.3 mm, so δ = 10 mm). Put a row of horizontal element edges exactly at the predicted spall plane, because cracks can only open along element edges.
- Cohesive strength 0.5·ρcv/2 (absolute strength, which the code accepts from 10 kPa to 4 GPa **[code]**), so the crack must start at the meeting of the release waves.
- Negative control: the same T = 2δ run with strength 1.3·ρcv/2 must not crack. Without viscosity, ringing may push numerical tension above ρcv/2 and crack it anyway. That is a direct test of step 4.
- Equal-plate control: no crack anywhere, interface opens at 2δ/c.
- Tolerances to fix before running (my suggestion): spall plane within two element heights, crack time within 5%.

---

## Step 6. Volumetric locking in the triangles

### Why it might lock

**[recall]** Metal plastic flow keeps volume constant. A three-node triangle has one constant volume change, so in a mesh each triangle adds one incompressibility constraint. A 2D triangle mesh has about two triangles per node and two displacement unknowns per node, so the constraints can use up almost all the freedom and the mesh comes out far too stiff once it is fully plastic. Nagtegaal, Parks and Rice showed this and showed that some arrangements (four "crossed" triangles in each square) escape it: J. C. Nagtegaal, D. M. Parks and J. R. Rice, "On numerically accurate finite element solutions in the fully plastic range", Comput. Methods Appl. Mech. Eng. 4 (1974) 153–177 (title checked; journal, volume and pages from recall, the indexing page found had none).

**[code]** What Impact Lab uses:

- Structured blocks, default `aligned` pattern (`Mesh.rectangle` with diagonals alternating by (i + j) parity). This makes the four diagonals around every other node meet at that node, a "union jack" pattern. Whether union jack locks in plane-strain plasticity is **[recall, uncertain]**; it is not the crossed pattern of Nagtegaal et al.
- `staggered` pattern: shifted nodes with the shorter diagonal.
- Outline bodies (PR 6): unstructured Delaunay triangles, which are the usual worst case for locking.
- The plasticity is J2 with a Hencky law (`J2Plasticity.swift`). Its volume response is a separate term, Kirchhoff pressure `bulk * logJ`, which makes the averaged-pressure fix below easy to add.

### The test

A plane-strain flat-punch compression of a perfectly plastic block. It has a textbook limit load, and a locked mesh shows it as a load that keeps rising instead of levelling off.

- Block: width B = 6b or more, height H = 3b or more, bottom edge clamped (the existing "Clamp bottom edge" support **[code]**). These sizes are my margin; the slip-line field is about b to each side of the punch **[recall]**.
- Material: an elastic, perfectly plastic metal. The code accepts a flat hardening table (all flow stresses equal) **[code]**. Use a modest E/Y, for example 100, so the plastic zone forms early.
- Punch: the top-edge nodes over a central width b are driven down at a constant slow speed. Use a ramp, speed well below c, and report kinetic over plastic work to show it is quasi-static. This needs a prescribed-velocity boundary, which the Assembly tab does not have today. The legacy solver already moves grip nodes with work accounting (`guidePositions` and `guideVelocitiesAndWork` in `Physics.swift`) **[code]**, so the check is easiest as a new `ImpactCheck --locking` built on that path. Driving the nodes directly avoids contact penalty effects in the result. A heavy free punch does not work at metal strengths: its kinetic energy is thousands of times too small for the plastic work **[calc]**.
- Prediction: limit pressure p = (2 + π)·k ≈ 5.14·k, with k = Y/√3 for von Mises, so p ≈ 2.97·Y and load per metre of depth ≈ 2.97·Y·b. This is the Prandtl solution (rough punch) and Hill's (smooth punch); both give 2 + π **[recall]**. A place to check it: [Brown University EN0175 lecture notes on slip-line fields](https://www.brown.edu/Departments/Engineering/Courses/En175/Lecture%20Notes%202006/EN0175-25.pdf) (found by search, not read).
- Control: the same block compressed uniformly between smooth plates (top and bottom edges driven only vertically, one node pinned sideways). Here every triangle has the same constant strain, so even a locking mesh is exact. It must give 2k = 1.155·Y (plane-strain flow stress) **[recall, standard]**. If the control fails, the problem is the plasticity code, not locking.
- Meshes: `aligned` and an outline (Delaunay) mesh, each at two refinements.
- Reading it: a mesh that does not lock levels off at about 2.97·Y·b, coming down towards it as the mesh is refined. A locked mesh overshoots and keeps climbing with indentation, and its pressure field shows a checkerboard. A pass criterion to fix beforehand (my suggestion): plateau within 10% of (2 + π)k on the finer mesh, with the error falling on refinement.

### The fix if it locks: Bonet and Burton averaged nodal pressure

J. Bonet and A. J. Burton, "A simple averaged nodal pressure tetrahedral element for incompressible and nearly incompressible dynamic explicit applications", Commun. Numer. Methods Eng. 14 (1998) 437–449 **[source: reference list and method description in [Joldes, Wittek and Miller 2009](https://isml.ecm.uwa.edu.au/ISML/Publication/pdfs/2009juljoldesmillerCNMEnon.pdf)]**.

The method, in 2D:

1. Nodal areas: each triangle gives a third of its reference area A_e and of its current area J_e·A_e to each of its nodes, so node a has A_a and a_a.
2. Nodal area ratio J_a = a_a / A_a, and nodal pressure p_a = U′(J_a), where U is the volume energy (for this J2 law U = ½K(ln J)², so U′ = K ln J / J).
3. Element pressure: the average of its three nodal pressures, p̄_e = (p_a + p_b + p_c)/3.
4. Element volume stress: P_vol = p̄_e · cofactor(F_e). The shape-change (deviatoric) part stays per element.

This turns about one constraint per element into one per node, which is the counting argument for why it stops locking **[recall]**. Joldes et al. report that it is cheap, that it works much better than the plain element for nearly incompressible material, and that the averaged element's explicit stable step in 1D is twice the plain one's **[source, same paper]**. The current step bound is therefore still safe.

How it fits this code:

- **[code]** `J2Model.update` builds Kirchhoff stress τ from `pressure = bulk * logJ` plus the deviatoric part. Replace that volume term with J_e·p̄_e, passed in, and replace the volume energy ½K(ln J)² with the nodal sum Σ_a A_a·U(J_a). With that pairing the forces are exactly the derivative of the reported energy, so the energy check stays honest.
- `assembleElements` becomes two passes: one to get every J_e and the nodal areas, one for stresses. The averaging weights depend only on connectivity, so they are rebuilt only when cracks split nodes, like the stress recovery weights already are (`MaterialFracture.recoveryWeights`) **[code]**. Split nodes keep the average from reaching across an open crack.
- **Layers:** Joldes et al. point out that the standard average is ill-defined at nodes shared by materials with different bulk moduli, and they give a per-node fix **[source]**. For bonded layers (PR 5) the nodal average must be taken per material, so a metal layer's pressure is never mixed with a polymer layer's.
- Turn it on only for plastic bodies, behind a setting, so elastic runs and legacy replay stay unchanged.

Related alternatives, all **[recall]**: F-bar (de Souza Neto et al., 1996) and the averaged nodal deformation gradient element of Bonet, Marriott and Hassan (2001), which can bring spurious low-energy modes. Bonet–Burton is the simplest of these and is the one the plan names.

---

## Why fracture-on makes the three-point bend about 3.6× slower

The shipped "Three-Point Bend on Rollers" example (`docs/lab-examples/three-point-bend.json`) is elastic with no fracture. The numbers here assume fracture turned on for the bar with default settings (strength 0.03·E, energy 7 J/m², aligned mesh), which is what the old decision record says Joey's version did. If his settings differ, the split changes.

### 1. More time steps: about 2.5×, from the code's own formula

**[code]** The step is set once in `AssemblySimulation.init`: `dt = stepScale · 0.8 / √(largest ω²)`.

Without fracture, a body's ω² comes from `Simulation.squaredFrequency`: each node's material stiffness plus, on surface nodes only, a contact allowance (8 × the largest contact stiffness of every pair it can touch), divided by the node's full lumped mass.

With fracture on any body, three things change:

1. `interbodyStiffnessScale` becomes 2 for every contact pair in the scene, so every contact allowance doubles. The body also gets its own self-contact allowance.
2. That body's bound becomes `MaterialFracture.squaredFrequencyBound`, which adds the contact allowance and the crack-face stiffness to **every triangle corner**, interior ones too. The crack-face stiffness is max(30·E/altitude, 2·σ²/G) per face; `TimestepDiagnosis` says this outright ("at least 30·E/h … the main cost of fracture on stiff materials").
3. It divides by **one corner's mass** (ρA/3), not the node's full mass, because a crack may later leave a single corner on its own. On this mesh that is half the mass of the lightest surface node.

**[calc]** Copying those formulas into Python for the bar (132 × 12 cells, 3,168 triangles, E = 10 MPa, ρ = 1000, ν = 0, c = 100 m/s):

| | Stable step |
|---|---|
| Material alone | 4.57 µs |
| Fracture off (contact sets it) | 0.549 µs |
| Fracture on | 0.216 µs |
| Fracture on, without the crack-face term | 0.267 µs |

- Steps with fracture on ÷ off ≈ **2.54**.
- Of that, about 2.06× comes from the doubled contact penalty spread onto every corner at corner mass, and the crack-face stiffness takes it the rest of the way.
- The bar sets the step in both cases. The weight's own bound is about 50 times looser.
- The step is already set by contact, not by the material, even with fracture off (0.55 µs against 4.6 µs).

### 2. More work per step: about 1.4×, inferred

**[code]** Every step of a run with fracture also does:

- The crack check (`MaterialFracture.insert`): a quick scan of all 3,168 element stresses. If any is near the strength, a full pass over every interior face plus a stress recovery fit.
- Self-contact (`selfContact`): rebuilds the triangle contact tree state and searches it for the bar every step, from the very first step, even before any crack exists.
- Contact between pieces (`fractureContact`) instead of the plain body-to-body contact once any crack exists.
- The cohesive forces on every inserted face, once there are any.
- A kinetic-energy sum and the energy guard on every step (fracture-off runs skip it).

3.6 ÷ 2.54 ≈ 1.4, which fits these costs. The 1.4 is **inferred, not measured**. The parallel element code does not change the picture: the second-largest body here (the weight) is far below the 5,000 element-weight needed for two lanes **[code]**.

### 3. A reporting quirk found on the way

**[code]** The in-app sentence "Without fracture the step would be about …" (`TimestepDiagnosis.withoutFractureStep`) is computed with the contact allowance that already includes the 2× penalty. So it describes "fracture on, minus the crack faces", not "fracture off". For this bar it would say about 0.38 µs **[calc]**, while a real fracture-off run uses 0.55 µs. It is display-only and does not change any result, but it understates the cost of fracture by about 1.45×.

### How to confirm on the Mac (suggestion, not done)

`AssemblySimulation` already has a per-phase timer (`AssemblyWork`: drift, FEM, fracture, contact, integration, output), printed by `ImpactCheck --assembly-scaling` **[code]**. That check's fracture workload is the bending fracture example, not this scene. Adding a `bend` workload that runs the three-point bend with fracture on and off and prints dt, step counts and the phase split would turn this estimate into a measurement. If the 2× contact penalty turns out to matter, the decision record already lists it as a separate variable to revisit; nothing here proposes changing it.

---

## What this audit did not do

- No Swift was compiled or run. The 2.54× step ratio replicates the code's formulas in Python; it was not read from a run.
- No code, scene, plan doc or Drive document was changed. The only change is this file, on its own branch.
- The LS-DYNA formula and time-step expression, the plate-impact wave picture, the Hugoniot elastic limit, the Prandtl limit load, the locking counting argument, and the alternatives to Bonet–Burton are marked **[recall]** and should be checked before they are relied on.
