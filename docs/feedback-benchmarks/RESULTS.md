# Plate-in-enclosure benchmark results

Joseph's scene from his testing (docs/FEEDBACK.md), rebuilt from the description: the carbon-skinned panel
preset clamped at the bottom, a hollow 60×40 mm box (5 mm wall) and a 40×20 mm plate inside it, both moving
at 20 m/s toward the panel, fine mesh, 0.4 ms run. Headless runs on Joseph's Mac, Release build of commit 8bc1de6.

| Scene | Materials | Result | Steps | Time on the Mac |
|---|---|---|---|---|
| plate-in-enclosure-as-built.json | Old soft demo material for the box and plate (1–4 MPa stiffness) | Stopped early: "Artificial bulk viscosity needs a shorter step here" | 21,595 | a few seconds |
| plate-in-enclosure-real.json | Steel plate, aluminium box (Library) | Finished all 0.4 ms, no "pushed into each other" stop | 293,137 | 71 s |

Real-material run, in order: box touches the panel at 0.050 ms; panel glue line starts to give at 0.053 ms;
first crack in the panel at 0.077 ms; plate reaches the inside of the box at 0.300 ms; first crack in the box
at 0.335 ms. Energy at the end (J per metre of depth): moving 879, permanent bending 491, cracking 107,
spring 171, damping 83. Total 1742.

What this shows: with real materials, his scene runs to the end, bodies touch, bend for good and crack. The
soft demo material, not the contact method, is what stopped the as-built scene here. The 5 m/s variants were
not run yet.
