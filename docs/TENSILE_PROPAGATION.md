# Tensile crack propagation and fragment motion

The experimental tensile cohesive law now treats the two crack faces symmetrically and releases fully spent interfaces from the cohesive calculation. The bend coupon still shows strong mesh sensitivity in how much material detaches and how far it moves. The recovered traction criterion, tensile threshold, fracture energy per reference area, bulk elastic and Hencky–J2 updates, and geometric contact law retain their existing definitions.

## Cohesive kinematics

The frame tangent follows the mean of the two current face chords. The normal is perpendicular to that tangent. Reversing which triangle supplies the first face reverses the frame and gap together, so the local gap and work agree after reversing the order of the integration points. The frame rotation term in the force is distributed equally between the two faces. The original one-face frame assigned that term entirely to the first face and could give a different answer when the same triangles were enumerated in a different order.

Once both integration points finish softening, the seam retains its dissipation and separation readings and contributes no cohesive force to the assembly solver. The independent faces can rotate through orientations where their average chord vanishes. Geometric contact can still transmit compressive forces. The earlier symmetric-frame prototype still evaluated the average chord of spent seams and stopped when independently moving lips became nearly opposed. The completed implementation passed a half-turn test after release and finished both aligned runs that had stopped in the prototype.

A distorted two-triangle patch gave zero measured force and fracture-work change when the triangles were swapped. The unloading force-gradient residual was 3.44 × 10⁻⁸ N/m. A uniform opening patch dissipated 0.14000002 J/m against 0.14000000 J/m prescribed. The controlled release patch retained its dissipated work and returned zero cohesive force after the half-turn.

## Bounded bend study on Apple M4

The coupon, loading, supports, receiver, strength and toughness are from [the tensile separation scene](scene-examples/tensile-separation.json). Only the coupon mesh was varied. The common explicit step was 0.4346 µs, with one step halving on each formulation at ×3. The matched step here differs slightly from the one used in the original checkpoint study, which reported six final pieces for the original ×4 run. The present one-face ×4 control reached 2.04% peak overlap. The finish readings are from the first accepted step at or after 115 ms.

| Frame and control | First insertion (ms) | First detachment (ms) | Pieces at finish | Work (J/m) | Spent-face work (J/m) | Mass outside largest piece | Receiver ΔPy (N·s/m) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Original, aligned ×3 | 5.046 | 24.057 | 3 | 0.88111 | 0.49400 | 0.62% | −0.04882 |
| Original, aligned ×4 | 5.025 | 14.063 | 3 | 0.72481 | 0.46759 | 60.01% | −0.72980 |
| Original, ×3 half step | 5.046 | 24.297 | 4 | 0.89885 | 0.51513 | 0.82% | −0.04853 |
| Original, staggered ×3 | 5.147 | 100.259 | 3 | 0.67095 | 0.35533 | 39.20% | 0 |
| Original, ×3 adjacent-element stress | 5.004 | 12.337 | 4 | 0.90396 | 0.59098 | 41.15% | −0.10653 |
| Symmetric, aligned ×3 | 5.046 | 34.790 | 3 | 0.84749 | 0.46167 | 0.93% | −0.02369 |
| Symmetric, aligned ×4 | 5.025 | 23.844 | 4 | 0.78509 | 0.46759 | 61.28% | −0.02262 |
| Symmetric, ×3 half step | 5.046 | 22.770 | 3 | 0.92088 | 0.49400 | 0.62% | −0.03822 |

Both meshes begin insertion within 0.021 ms of each other. By 12 ms the symmetric ×3 and ×4 gauge displacements are 6.27 and 8.22 mm, with five and nine fully failed edges. At 30 ms the aligned ×4 coupon has separated into four pieces while the ×3 coupon is still connected. At the end the ×3 result has lost small chips and the ×4 result has released much larger pieces. The same material point below the striker reached peak downward displacements of 12.94 and 33.42 mm, respectively. Its displacement includes motion after detachment.

The ×3–×4 gap in final total fracture work fell by 60%, from 0.15630 to 0.06240 J/m. The gap in work on fully spent faces fell by 78%, from 0.02641 to 0.00591 J/m. Those faces consumed the prescribed toughness times their reference length. Partially spent faces contribute the rest of the work. Final receiver vertical momentum agreed within 0.00107 N·s/m at the common step, down from 0.68097 N·s/m in the original formulation. Receiver momentum is measured from mass times center velocity. The CSV also gives integrated scalar normal load between the coupon and receiver, which measures cumulative contact loading. The improvement at the common step did not establish timestep convergence. Halving the step at symmetric ×3 increased the work by 8.7% and the magnitude of receiver momentum by 61%. First detachment moved 12.02 ms earlier. The gauge peak changed by 0.28 mm and the separated mass stayed below 1%.

Changing the aligned ×3 mesh to the staggered mesh changed detachment by 76.2 ms and moved all its fracture work onto nonvertical edges. The staggered mesh changes vertex positions as well as the directions available to the crack. In the aligned ×3 case, switching from patch recovery to the mean of the adjacent elements changed detachment by 11.7 ms. Both controls had an insertion time near 5 ms. The stress rule decides which faces activate, while the edge network decides what paths are available, how much reference fracture area they cost, and whether failed faces join up before the loading changes. The recovery control also changed the stress used to seed the interfaces, so it measures the combined effect of trigger and seed. Step halving of the original aligned ×3 case changed detachment by only 0.24 ms in this pair, while its fragment count still changed.

The refined coupon began contact with the receiver at 54.261 ms and the coarser coupon at 84.653 ms. Both receiver hits used existing surfaces. The refined run also recorded contact involving a newly exposed face elsewhere in the assembly after detachment. The nominal-step ×3 demonstration separated and showed independent motion, with no receiver contact in the 115 ms window.

The new aligned pair completed without inversion or a cohesive stop. Both conserved whole-assembly linear momentum within 1.65 × 10⁻¹⁴ N·s/m, and the sum of the fragment masses matched the original coupon at the sampled times to within 10⁻¹² kg/m. Peak energy residuals were 0.025% and 0.107%, with peak relative overlaps of 1.31% and 1.53%. Those checks establish numerical accounting for these runs. The illustrative material properties still require experimental calibration.

A trial mesh with both diagonals represented in each cell added possible local routes and doubled the number of triangles per cell. The two crossed-mesh runs finished with a smaller fracture-work gap of 0.024 J/m and closer peak gauge displacements of 44.60 and 44.03 mm. Their separated mass fractions were 39.30% and 59.90%. The crossed ×3 case reached 2.59% peak relative overlap, above the existing 2% check for this example. The trial also changed the element density. It remains evidence about path restrictions and is excluded from the delivered mesh options.

## Reproduction and recommendation

```sh
swift build --disable-sandbox -c release
scene=docs/scene-examples/tensile-separation.json
.build/release/ImpactCheck --tensile-propagation "$scene" 3
.build/release/ImpactCheck --tensile-propagation "$scene" 4
.build/release/ImpactCheck --tensile-propagation "$scene" 3 half
.build/release/ImpactCheck --tensile-propagation "$scene" 3 left-frame
.build/release/ImpactCheck --tensile-propagation "$scene" 4 left-frame
.build/release/ImpactCheck --tensile-propagation "$scene" 3 left-frame half
.build/release/ImpactCheck --tensile-propagation "$scene" 3 left-frame staggered
.build/release/ImpactCheck --tensile-propagation "$scene" 3 left-frame --legacy-insertion
.build/release/ImpactCheck --tensile-separation
```

Keep the tensile law for research and for demonstrating calculated separation with continued fragment contact. Use mesh and step sensitivity when interpreting its outputs. For general-purpose prediction, the next development step is to let a crack advance in directions that can cut across the original triangles. A local conforming remesh around the tip would preserve explicit fragment faces for contact. It would need conservative transfer of mass and velocity, cohesive history and fracture area, followed by checks on work, displacement, separated mass and momentum transfer across orientations and steps. [Paulino et al., adaptive cohesive fracture](https://doi.org/10.1002/nme.2943)

[Native screenshots and measured histories](audit-evidence/tensile-propagation/README.md)
