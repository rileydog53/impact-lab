# Native evidence for tensile separation

The images capture the running Impact Lab window on the Apple M4. The app resolved the JSON scene with its production FEM integrator at the nominal 0.869 µs step. Window capture did not change the mesh, field data, simulation time, forces, or geometry. The comparison strip crops three of these screenshots and adds captions.

| Capture | Accepted solver time | Visible evidence |
|---|---:|---|
| [Material inspector](00-material.png) | 0.000 ms | 30 kPa tensile strength, 7 J/m² fracture energy, 1 MPa Young’s modulus, 950 kg/m³ density |
| [Initial setup](01-setup.png) | 0.000 ms | Intact meshed coupon, striker, deformable supports and receiver |
| [Principal stress](02-stress.png) | 5.800 ms | Early bending, Cauchy stress contours, and eight inserted faces |
| [Cohesive damage](03-damage.png) | 12.001 ms | Five failed faces, one connected piece, 14.444 mm of failed reference length |
| [Separation](04-separation.png) | 29.000 ms | Two pieces and 19 fully failed faces |
| [Receiver contact](06-receiver.png) | 67.141 ms | Two pieces and 96.09 N/m of recorded normal load at the receiver |
| [Final state](05-final.png) | 115.000 ms | Two pieces, 20 failed faces, 37.774 mm maximum gap among failed faces at this frame, and 0.919 J/m of fracture dissipation |

[Three-state comparison](comparison.png) · [Model and numerical checks](../../TENSILE_SEPARATION.md)
