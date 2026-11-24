# Glossary (plain English)

| Term | Meaning |
|---|---|
| **Pa, MPa, GPa** | Units of pressure/stress. 1 Pa = 1 newton per square metre. MPa = a million Pa; GPa = a billion. A thumbtack tip is huge in Pa; atmospheric pressure is about 0.1 MPa. |
| **Stress** | Force spread over an area: how hard a material is being pushed or pulled inside. |
| **Strain** | Stretch as a fraction (0.01 = 1% longer). |
| **Young's modulus (E)** | Stiffness: stress needed per unit elastic strain. Steel about 200 GPa, aluminium about 69 GPa. |
| **Poisson's ratio** | How much a material gets thinner when stretched. |
| **Density** | Mass per volume (kg/m³). |
| **Elastic** | Springs back completely after the load is removed. |
| **Plastic / plasticity / yield** | Permanent bending. *Yield strength* is the stress where permanent deformation starts. |
| **Strength** (tensile strength) | The highest stress a material carries before it fails. Not the same as toughness. |
| **Toughness / fracture toughness / fracture energy** | How much energy it takes to grow a crack (J/m² of new crack surface). A strong material can be brittle (low toughness); a tough one resists cracking. In the app these values are experimental literature numbers, **not validated**. |
| **Hardening** | The material gets stronger as it is deformed plastically. Past initial yield, hardening curves here are mostly illustrative. |
| **J2 plasticity** | The standard textbook metal-plasticity model the solver uses. |
| **Cohesive interface** | A glue-like layer that opens and fails; how cracks are modelled here. |
| **Contact / penalty** | The rule stopping bodies passing through each other, like a very stiff spring. The spring stiffness is a numerical choice, so results must not depend on it. |
| **Impulse** | Force times time; the momentum handed over in a collision. The most robust contact result here. |
| **Raw peak force** | The highest instantaneous contact force. Found to be a numerical artifact; do not quote it. |
| **FEM** | Finite element method: the production solver, built on triangles (the mesh). |
| **MPM** | Material point method: an experimental particle-based method. Prototype only. |
| **Mesh / refinement / convergence** | Mesh = the triangles. Refinement = more, smaller triangles. Converged = answer stops changing as the mesh gets finer. |
| **CST** | Constant-strain triangle, the simplest FEM element. Known to be too stiff in bending on coarse meshes. |
| **Timestep (dt)** | Length of each calculation step. Stiffer or finer things force smaller steps and longer runs. |
| **Energy drift / conservation** | Whether energy adds up. Small drift (under 2% gate) shows the numerics are sound. |
| **Taylor-Quinney fraction** | Share of plastic work that becomes heat (typically around 0.9). Not yet used. |
| **Verified / validated** | Verified = solves its equations right. Validated = matches reality. See README. |
| **Card** | A numbered chunk of recovery work (Cards 1 to 7). |
| **ImpactCheck** | The command-line test program with named checks (gates). |
| **Replay fingerprint** | A hash showing two runs produced identical results. |
