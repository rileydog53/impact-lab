# Volumetric locking check (layered target plan, step 6)

Date: 2026-11-25. Status: **numerical verification** of the existing element. No solver code changed. Not physical validation, not product acceptance.

## Question

Metal plastic flow keeps volume constant. A 3-node triangle has a single, constant volume change, so a mesh of them can become far too stiff once the metal is fully plastic ("volumetric locking", Nagtegaal, Parks and Rice 1974). Does that happen in Impact Lab's triangles?

## Short answer

**No for the structured blocks Impact Lab uses by default. Mild for outline (unstructured) bodies.**

- The default `aligned` block pattern behaves like the known non-locking "crossed" mesh, within about 4% at every depth, at both refinements, for E/Y = 100 and E/Y = 500.
- Outline bodies (Delaunay triangles from the PR 6 mesher) read up to 6% stiffer than the crossed mesh on the finer mesh and up to 12% stiffer on the coarse one. That is mild overstiffening that falls with refinement. It is not the runaway load of a locked mesh.
- A deliberately bad pattern (every diagonal the same way, which Impact Lab does not use) reads 12–23% stiffer and the gap grows with depth. So the test does detect locking when it is there.

The Bonet–Burton averaged-pressure fix is therefore **not needed now**. It is written up below as a ready proposal in case outline bodies of stiff metals are later used for quantitative plastic results.

## The test: `ImpactCheck --locking [quick] [E/Y]`

Default run is E/Y = 100, about 2 minutes on the M4 at low priority. `--locking 500` (more like steel) takes about 11 minutes. `quick` runs only the coarse meshes.

- **Material:** elastic, perfectly plastic J2, the production `J2Model` (Hencky law), ν = 0.3, no hardening.
- **Punch:** block 6b wide, 3b tall, bottom clamped. The top nodes over a central width b are driven down at a slow, smoothly ramped speed and held sideways (rough punch), to 0.22b. Pressure = punch load / b.
- **Prediction:** the plane-strain flat-punch limit pressure is (2 + π)k (Prandtl; Hill for a smooth punch), with k = Y/√3 for von Mises, so about 2.97·Y. Checked against the Brown University EN0175 slip-line lecture notes (via search excerpt: punch pressure (2 + π)k, about 3σY) and the Shield–Drucker limit-analysis bounds for the 2D flat punch, which close on (2 + π)k. Wikipedia's bearing-capacity article gives the same factor N_c = 2 + π for a cohesive (φ = 0) soil.
- **Meshes, each at b/h = 8 and 16:** `crossed` (four triangles per square, known non-locking, the reference), `uniform` (all diagonals one way, the negative control), `aligned` (production structured pattern, verified identical to `Mesh.bar`), `delaunay` (production outline mesher, 25° minimum angle).
- **Driver:** the check runs its own small explicit loop (lumped mass, central difference, no damping) so it needs no new boundary condition in the solver. Its force assembly is checked against `Simulation.internalForces` (agreement 2e-16).
- **Quasi-static:** kinetic energy stays below 2e-4 of the plastic work in every run.

### Controls

1. **Uniform compression between smooth plates** must give the plane-strain flow stress 2k = 1.155·Y, because every triangle then has the same strain and even a locking mesh is exact. Result: +0.6% (E/Y = 100), +0.4% (E/Y = 500). Gate: within 2%. Kept to 4% strain: past that, a perfectly plastic block between frictionless plates drifts into a non-uniform mode in an explicit run and the plate load stops equalling the element flow stress.
2. **Crossed mesh** must reach within 10% of (2 + π)k at depth 0.2b on the fine mesh. Result: 1.033 (E/Y = 100) and 1.036 (E/Y = 500).

Damping note: an earlier version used mass-proportional damping. It resisted the bulk flow itself and biased the compression control by 5%, so it was removed.

## Results

Pressure as a fraction of (2 + π)k at indentation depth d (fine mesh, b/h = 16):

| E/Y | mesh | d = 0.05b | 0.10b | 0.15b | 0.20b |
|---|---|---|---|---|---|
| 100 | crossed (reference) | 0.768 | 0.911 | 0.996 | 1.033 |
| 100 | aligned | 0.778 | 0.909 | 1.008 | 1.064 |
| 100 | delaunay | 0.793 | 0.943 | 1.008 | 1.041 |
| 100 | uniform | 0.811 | 0.977 | 1.071 | 1.121 |
| 500 | crossed (reference) | 0.939 | 0.982 | 1.010 | 1.036 |
| 500 | aligned | 0.941 | 0.991 | 1.048 | 1.079 |
| 500 | delaunay | 0.997 | 1.040 | 1.073 | 1.095 |
| 500 | uniform | 1.053 | 1.138 | 1.210 | 1.273 |

Excess over the crossed mesh at the same element size (worst depth):

| E/Y | mesh | b/h = 8 | b/h = 16 | verdict |
|---|---|---|---|---|
| 100 | aligned | +3.2% | +3.0% | no locking |
| 100 | delaunay | +7.3% | +3.6% | no locking |
| 100 | uniform | +14.2% | +8.5% | mild |
| 500 | aligned | +2.4% | +4.2% | no locking |
| 500 | delaunay | +11.6% | +6.2% | mild overstiffening |
| 500 | uniform | +33.5% | +22.9% | **locks** |

Verdict rule, fixed before the E/Y = 500 run: more than 10% above the crossed mesh on the fine mesh = locks; 5–10% = mild; under 5% = does not lock.

Full logs from these runs are in the PR description.

### Reading it

- The slow rise of every curve past (2 + π)k, the crossed mesh included, is not locking. It comes from finite deformation under a rough punch, the corner node at x = ±b/2 carrying part of the neighbouring element (the effective width is between b and b + h), and the slow elastic-plastic approach at finite E/Y. It falls with refinement (crossed at 0.2b: 1.070 → 1.033 at E/Y = 100).
- The "aligned" pattern alternates the diagonal direction cell by cell, so every other node has four diagonals meeting at it ("union jack"). It behaves like the crossed mesh here, which fits the counting argument that alternating patterns leave enough freedom for isochoric flow. **[hypothesis, consistent with the data]**
- The checkerboard index printed by the check (RMS pressure jump between neighbouring elements under the punch, relative to the pressure) is about 1 for every mesh, including crossed. It is dominated by the punch-corner singularity, so it does not separate the meshes and is reported only for information.
- Not tested: the `staggered` fracture pattern (jittered nodes, shorter diagonal). With square cells its tie-break falls back to one diagonal direction, so it may sit between aligned and uniform. Worth a run if staggered plastic metal blocks matter.

## Proposal if it is ever needed: Bonet–Burton averaged nodal pressure

J. Bonet and A. J. Burton, "A simple averaged nodal pressure tetrahedral element for incompressible and nearly incompressible dynamic explicit applications", Commun. Numer. Methods Eng. 14 (1998) 437–449. Method description and the multi-material caveat as in Joldes, Wittek and Miller (2009). Not implemented. This would be a production physics change and needs Joseph's approval.

In 2D:

1. Each triangle gives a third of its reference area A_e and current area J_e·A_e to each of its nodes, giving nodal areas A_a and a_a.
2. Nodal area ratio J_a = a_a / A_a, nodal pressure p_a = U′(J_a). For this J2 law U = ½K(ln J)², so U′ = K ln J / J.
3. Element pressure p̄_e = (p_a + p_b + p_c)/3.
4. In `J2Model.update`, replace the volume term `bulk * logJ` (Kirchhoff pressure) with J_e·p̄_e passed in, and replace the energy term ½K(ln J)² with the nodal sum Σ_a A_a·U(J_a), so the forces stay the exact derivative of the reported energy and the energy check stays honest.

Fit to the code:

- `assembleElements` becomes two passes (volumes, then stresses). The averaging weights depend only on connectivity, so rebuild them only when cracks split nodes, like `MaterialFracture.recoveryWeights`. Split nodes keep the average from reaching across an open crack.
- Bonded layers (PR 5): average per material at shared nodes, so a metal layer's pressure never mixes with a polymer layer's (the Joldes et al. caveat).
- Turn it on only for plastic outline bodies, behind a setting, so elastic runs and legacy replay stay bit-identical.
- Joldes et al. report that the averaged element's explicit stable step is not smaller than the plain one's, so the current step bound stays safe.
- Acceptance test: this check. Delaunay should then fall to within 5% of crossed at E/Y = 500, and uniform should stop locking.

Alternatives (**recall**): F-bar (de Souza Neto et al. 1996) and the averaged nodal deformation gradient element (Bonet, Marriott and Hassan 2001, which can show spurious low-energy modes).

## What changed in the repository

- `Sources/ImpactCheck/Locking.swift`: the check, plus `--locking probe`, a material-point plane-strain compression that reaches 2k.
- `Sources/ImpactCheck/main.swift`: the `--locking` flag.
- `Package.swift`: ImpactCheck now also depends on ImpactGeometry (for the Delaunay mesh). This only affects the check executable.
- No change under `Sources/ImpactPhysics`. Legacy replay is bit-identical (see PR).
