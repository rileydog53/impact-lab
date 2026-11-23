# FEM deformation limits for the copper wall benchmark

The finest FEM mesh inverted at 450 m/s with its nominal timestep. It completed at 750 m/s with a quarter timestep, while some triangles nearly collapsed and contact overlap exceeded 21%.

This study extends the [FEM–MPM comparison](MPM_PROTOTYPE.md) on the Apple M4. It uses the same 40 × 25 mm plane-strain copper block and represents a frictionless wall with two opposing blocks. Each block starts 0.25 mm from the symmetry plane. Speeds are per block. The 200 µs observation window starts at initialization. A completed run ends at the first accepted step at or after 200 µs.

The `ImpactCheck` comparison seeds the nodal velocities separately from a valid stationary scene. The workshop and scene documents still validate scene velocities against ±150 m/s per component. At 150 m/s and ×2, the study requires exact equality with the standard solver's accepted positions, velocities, energy totals and contact pairs at each step. It also requires the standard solver to reject the same scene at 150.001 m/s.

## Reproduce

```sh
swift build -c release
.build/release/ImpactCheck --mpm-compare fem-limits
```

The command emits one CSV row per case, including cases where the solver rejects a step. Run with `swift build --disable-sandbox -c release` inside an outer sandbox that prevents SwiftPM from starting its own manifest sandbox. The [M4 results](audit-evidence/fem-deformation-limits-m4.csv) were produced with Apple Swift 6.2.4 on macOS 27.0.1.

The suite compares ×2, ×4 and ×7 (96, 384 and 1,176 triangles per block), with nominal fixed timesteps of 76.89, 51.22 and 27.77 ns. It also runs ×4 at the ×7 nominal timestep to isolate mesh effects, and halves the timestep on ×4 and ×7. The additional ×7 tests use the nominal, half and quarter timesteps at 525 m/s. They also test quarter steps at 450, 600 and 750 m/s and an eighth step at 600 m/s. The solver has no adaptive timestep or retry in this test. It stops at the first rejected step.

## What the measurements mean

- Minimum $J$ is the signed current-to-reference area ratio. Minimum triangle quality is $4\sqrt{3} A / \sum_i \ell_i^2$, where $A$ is signed current area and the $\ell_i$ are current edge lengths. An equilateral element scores 1 and a collapsed element scores 0. Both minima cover both bodies and every accepted state. A rejected attempted drift is reconstructed from the last accepted state. Its signed $J$ and nonpositive-element count distinguish inversion from other causes in the solver's combined failure message.
- Energy error is the largest absolute deviation from initial energy, divided by initial energy. The ledger includes kinetic, elastic, contact and hardening energy, plus plastic dissipation. Linear momentum is normalized by total mass times initial speed and angular momentum by the same scale times the original block length. Mass error is fractional. Plastic dissipation in the CSV is per block. Peak equivalent plastic strain is the maximum in either block at the last accepted state and is reported as a fraction.
- Relative overlap is the maximum detected node penetration divided by the current length of the target edge. The intact contact solver also reports the sum of scalar penalty loads. Its time integral is unsigned. Contact episodes count transitions from zero to positive load with no noise threshold. Center separation detects whether the centers exchange sides. Local interpenetration can occur even when the centers stay on their original sides.
- Length is the left block's axial bounding span. The front span is the transverse distance between nodes within 2 mm of its most advanced point, matching the original comparison. At large deformation, this span can include widely separated material flowing sideways.

## Results

Of 31 cases, 21 reached 200 µs and 10 stopped at an inverted trial element. The table shows selected ×7 cases. Time is the last **accepted** state and the next attempted state is one timestep later. A dash indicates the case completed its observation window.

| Speed (m/s) | Step (ns) | Accepted through (µs) | Min. accepted $J$ | Min. quality | Min. rejected $J$ | Peak energy error | Peak relative overlap |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 150 | 27.77 | 200.00 | 0.944 | 0.1705 | — | 0.02794% | 3.80% |
| 300 | 27.77 | 200.00 | 0.888 | 0.01560 | — | 0.02511% | 8.14% |
| 450 | 27.77 | 130.16 | 0.410 | 0.003358 | −0.0854 | 16.43% | 12.74% |
| 450 | 13.89 | 200.00 | 0.827 | 0.004256 | — | 0.00842% | 12.76% |
| 450 | 6.94 | 200.00 | 0.829 | 0.004190 | — | 0.00162% | 12.84% |
| 525 | 27.77 | 65.70 | 0.227 | 0.001589 | −2.629 | 69.97% | 15.28% |
| 525 | 13.89 | 200.00 | 0.800 | 0.002341 | — | 0.00619% | 14.70% |
| 525 | 6.94 | 200.00 | 0.783 | 0.002171 | — | 0.00187% | 15.33% |
| 600 | 27.77 | 48.04 | 0.191 | 0.001509 | −2.550 | 76.35% | 17.41% |
| 600 | 13.89 | 150.64 | 0.240 | 0.0004063 | −2.179 | 40.80% | 17.77% |
| 600 | 6.94 | 200.00 | 0.758 | 0.001065 | — | 0.00342% | 17.30% |
| 600 | 3.47 | 200.00 | 0.763 | 0.001017 | — | 0.00074% | 17.12% |
| 750 | 6.94 | 200.00 | 0.685 | 0.0005978 | — | 0.00372% | 21.24% |

At the nominal timestep, all three meshes complete at 300 m/s and invert at 450 m/s. At the matched 27.77 ns timestep and 450 m/s, ×4 completes while ×7 inverts. At that timestep, further mesh refinement triggers inversion. On ×7, the tested completion boundary shifts from between 300 and 450 m/s at 27.77 ns to between 525 and 600 m/s at 13.89 ns. The 6.94 ns run reaches the full window at the highest tested speed of 750 m/s. Its inversion threshold is outside the sampled speeds for this geometry and duration.

Mass stays constant in every case. The normalized momentum and angular momentum errors stay below 2.2 × 10⁻¹⁵ and 2.6 × 10⁻¹⁶, respectively. At 300 m/s and 27.77 ns, the ×4 and ×7 front spans are 157.9 and 94.1 mm, respectively, while the energy errors are 0.0314% and 0.0251%. The width is mesh-sensitive even with good energy balance. At 450 m/s on ×7, halving the step from 13.89 to 6.94 ns reduces energy error about fivefold. The final length still changes from 7.16 to 8.83 mm and the front span changes from 292 to 251 mm. Measured contact overlap remains near 13%, and the count of positive-load episodes changes from 14 to 10. At 600 m/s on ×7, halving the timestep again changes the front span from 465 to 350 mm and leaves peak overlap near 17%. The bodies are still in contact at 200 µs in the 6.94 ns run, while the 3.47 ns run last records contact at 194.19 µs. Energy conservation coexists with distorted triangles and resolution-sensitive contact.

## Physical limitation

The existing C11000 profile uses an illustrative hardening table ending at 12% equivalent plastic strain and extends its final 225 MPa Kirchhoff flow stress as a constant plateau. Its response is independent of strain rate and temperature, with no copper damage or failure law. The completed 600 m/s ×7 runs reach peak equivalent plastic strains of 11.02 and 16.67, or 1,102% to 1,667%. The calculated flow and shape depend on that extrapolated model.

The next physical limitation is calibration of large-strain flow for the actual copper condition, including strain-rate dependence and heating from plastic work. Validate a rate- and temperature-dependent model against independent measurements of force history and deformed shape. Damage or failure needs its own measurements if the validation specimens show separation. Published copper experiments establish that rate sensitivity matters and motivate this calibration, with material grade and temper matched before using the data quantitatively. [Follansbee and Kocks, Acta Metallurgica (1988)](https://doi.org/10.1016/0001-6160(88)90030-2)
