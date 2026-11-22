# Version 0.6 · Assembly laboratory

Launch with `./launch.command`. The **Assembly** tab opens the enclosure example. Choose **New → New blank assembly** to start from an empty workspace. **Add body** creates a block or hollow rectangular enclosure. Drag an initial body to move it or enter its exact pose, dimensions, velocity and material in the inspector. The enclosure has a continuous deformable wall and a physical cavity. Add a separate block inside to use as a payload.

Select a body, then choose **Add link** and a destination. A spring takes tension and compression. A breakable link uses the existing bilinear cohesive law in tension. Local anchor coordinates run from −100% to +100% from one side of each body to the other. A cavity anchor snaps to the nearest material boundary. A nonzero band height distributes the connection stiffness across five anchors along local Y. Links start stress-free at their configured lengths. Stiffness is force per metre of depth per metre of extension.

Choose the tracked body and reference body in **Run settings**, then run, pause, or advance by **+1 ms**. Expand the energy readout for the force, balance, overlap and first-contact readings. Select a connection to inspect its current load, stored energy and fracture dissipation. Pin a reference before changing the setup to compare relative displacement, body kinetic energy, or stored connection energy at matching times. **Save** writes an assembly JSON. Earlier validated experiments are in **Verified presets**.

## Numerical scope

The assembly uses the existing explicit plane-strain FEM, J2 plasticity, cohesive law, and frictionless node-to-segment contact. It builds a candidate contact pair for each distinct body pair, then checks current bounds and boundaries at each timestep. Outer and inner boundaries both participate. Spring and cohesive forces act along their current chords and transfer to the deformable meshes through barycentric weights, with equal and opposite forces and conserved torque. All forces advance the same nodal state. The native kernels already covered the required geometries and interactions, so the release adds no external dependency.

The editor supports up to eight free bodies and twelve connections. Geometry is limited to blocks and uniform-wall rectangular enclosures. Contact is discrete and has no friction, self-contact, or continuous collision detection. Use a small initial clearance. Local loads and late recontacts can be mesh-sensitive. Breakage is limited to authored links. The model has no bulk cracking, arbitrary fragmentation, spall, melting, or explosive physics.

## Verification

Use `swift run --disable-sandbox -c release ImpactCheck --assembly` for the focused checks. Omit `--assembly` for earlier release regressions.

- In the 155 ms enclosure case, shell–facing contact is at **16.083 ms**, contact between obstacle layers at **22.319 ms**, and payload–cavity contact at **114.527 ms**. The payload moves **18.08 mm** relative to the shell, the shell yields, and all five obstacle links fail.
- Peak linear and angular momentum drift are **8.53 × 10⁻¹⁴ N·s/m** and **1.96 × 10⁻¹⁵ N·m·s/m** about the global origin. Peak energy error is **0.0031%** and peak overlap is **0.68%** of the contacted edge length. Integrated work across the breakable links and predicted fracture dissipation agree within **0.00001 J/m** of the predicted **0.078125 J/m**.
- Halving the timestep changes contact times, payload travel, and first spring crest by at most **0.26%**. Doubling mesh subdivisions at the same smaller timestep changes these quantities by at most **6.30%**, driven by late cavity contact. Peak link force is more sensitive, changing by **13.48%** with mesh refinement.
- The spring control reaches its first extension crest at **29.881 ms** versus **29.850 ms** for the lumped-mass prediction. A separate three-block relay transfers energy to a follower exclusively through a spring.
- The native smoke check constructs both assemblies from empty through the editor’s add and update actions, exercises timed playback and stepping, saves and reopens an identical trace, then shows a changed response after editing spring stiffness and opens the comparison sheet.
