# Impact Lab scene files (JSON)

You can describe an experiment as a plain text file, by hand or with a script, then open it in Impact Lab. From there you can see it, change it in the workshop, run it, and save or export the revised version. The app's own saved files use this same format. There is only one scene format.

- **Open:** Assembly → **Open** (⌘O), or **⋯ → Import Scene JSON…**
- **Save the revised scene:** **Save** / **Save As…**, or **⋯ → Export Scene JSON Copy…**, which writes a copy and keeps the current file open.
- **Edit outside, then refresh:** **⋯ → Reload from Disk** (⇧⌘R) re-reads the open file, for example after a script rewrote it.
- **Quick reference inside the app:** **⋯ → Scene JSON Format…**
- **Formal schema:** [`scene-format.schema.json`](scene-format.schema.json) (JSON Schema 2020-12), for editors and generators.
- **Examples:** [`scene-examples/`](scene-examples/)

## The smallest useful scene

```json
{
  "parts": [
    { "name": "Target",  "size": [0.10, 0.03] },
    { "name": "Striker", "size": [0.03, 0.03], "center": [0.07, 0], "velocity": [-5, 0] }
  ]
}
```

Everything not written takes the workshop default: block shape, centre [0, 0], no rotation, at rest, a soft elastic material (E 1 MPa, 1,000 kg/m³, ν 0), standard mesh and 0.12 s of simulated time.

## Units and directions

SI throughout: **metres, seconds, m/s, pascals (Pa), kg/m³**. Angles are in **degrees**, counter-clockwise. x points right and y points up. `center` is the middle of a body. The model is 2-D plane strain, so energies and forces are per metre of depth.

## Scene settings

| Setting | Meaning | Default and limits |
|---|---|---|
| `parts` | The bodies (below) | up to 8 |
| `connections` | Springs and breakable links between bodies | up to 12 |
| `gauges` | Measurement points inside bodies | up to 8 |
| `duration` | Simulated time, s | 0.12; 0.0001–0.25 |
| `meshResolution` | Mesh for bodies without their own `refinement`: `standard` (≈9 mm), `fine` (4.5), `extraFine` (3), `x4`–`x7` (2.25–1.29 mm), or 1–7 | `standard` |
| `monitor` | Body shown in the motion plot | first body |
| `relativeTo` | Plot motion relative to this body | none |
| `groups` | Workshop selection groups: `[{"members": ["A", "B"]}]` | none |
| `bodyOrder` | Workshop list order (no physical effect) | file order |
| `description`, `$schema` | Free text and editor hints. Accepted, but not kept on save | — |

The timestep is not a setting. The solver chooses the largest stable step from the mesh and materials. Use a finer mesh to resolve more detail. The stiffest, smallest element sets the step for the whole scene, so a single metal body in a long scene of soft materials can make a run take minutes. Keep metal scenes to milliseconds, and soft-material scenes to tens of milliseconds.

## Body settings (`parts`)

| Setting | Meaning | Default and limits |
|---|---|---|
| `name` | Required, unique if other entries refer to it | 1–48 characters |
| `id` | Optional. A UUID, or readable text like `"striker"` used for references | generated |
| `shape` | `block`, `enclosure` (hollow box) or `round` (ellipse) | `block` |
| `size` | Required. `[width, height]`, or the two diameters of a round body, m | each 0.025–0.30 |
| `center` | `[x, y]`, m | `[0, 0]`; each −1 to 1 |
| `angle` | Rotation, degrees | 0; −360 to 360 |
| `velocity` | Initial uniform velocity `[vx, vy]`, m/s | `[0, 0]`; each −150 to 150 |
| `wall` | Enclosure wall thickness, m | 0.012; 0.005 to 0.4 × the smaller size |
| `refinement` | This body's own mesh level, same values as `meshResolution` | assembly mesh |
| `material` | See below | soft elastic |
| `plasticity` | Custom-material plasticity, see below | elastic |
| `fracture` | Illustrative cracking: `{ "strengthFraction": 0.03, "energy": 7 }` (energy in J/m²; optional `meshPattern` `aligned` or `staggered`) | off |
| `notch` | V-notch on a block's local bottom edge: `{ "depthFraction": 0.2, "widthFraction": 0.2, "centerFraction": 0 }` | none |
| `bondedLayer` | Permanently bonded second (and `third`) material along the block: `{ "interfaceFraction": 0.5, "material": …, "third": { "interfaceFraction": 0.75, "material": … } }` | none |

Bodies must start at least slightly apart. If two bodies overlap or touch, the scene still opens so you can fix it in the workshop, but **Calculate** explains the problem and stays disabled until you do.

## Materials

There are three ways to write a material:

```json
"material": "aluminum-6061-t6"
"material": { "profile": "structural-steel-a36", "elasticOnly": true }
"material": { "young": 3e9, "density": 1200, "poisson": 0.35 }
```

- **Reference profiles** come with their source, evidence notes and tabulated J2 plasticity. The four profiles are `structural-steel-a36`, `stainless-304-annealed`, `aluminum-6061-t6` and `copper-c11000-annealed`. `elasticOnly: true` keeps the elastic constants and turns off yielding.
- **Custom materials** take Young's modulus (0.5 MPa – 400 GPa), density (100 – 25,000 kg/m³) and Poisson's ratio (−0.9 – 0.48). For a custom material you can add:

```json
"plasticity": { "response": "Elastoplastic",
                "table": { "points": [[0, 2.0e8], [0.02, 2.4e8], [0.10, 3.0e8]] } }
```

Each table point is `[equivalent plastic strain, flow stress in Pa]`. Strains start at 0 and increase up to 1. Stresses never decrease. Without a table, `yieldFraction` (0.010–0.035 × E) and `hardeningFraction` (0.25–0.45 × E) give linear hardening.

Custom profiles you save in the app's Material Library live in the app's own library and cannot be named in a file. Assign one in the app, then **Save**: the file then holds its full values and provenance.

## Connections and gauges

```json
"connections": [
  { "first": "Block A", "second": "Block B", "kind": "breakable",
    "stiffness": 20000, "criticalExtension": 0.002, "span": 0.6 }
],
"gauges": [
  { "name": "Rear face", "body": "Plate", "location": [-0.9, 0], "usesBodyFractions": true }
]
```

- **Connections.** Anchors are in fractions of each body's half-size. The defaults are the right edge of `first` (`[1, 0]`) and the left edge of `second` (`[-1, 0]`). `stiffness` is in N/m² (shown as kN/m² in the app), from 500 to 250,000. A `breakable` link fails at `criticalExtension` (0.0005–0.04 m). `span` (0–1.9) spreads the link along the edge.
- **Gauges.** A gauge location is in the body's own unrotated frame: metres from its centre, or half-size fractions with `usesBodyFractions: true`. It must lie inside material.

Bodies are referred to by `name` (or `id`) everywhere: in `connections`, `gauges`, `monitor`, `relativeTo`, `groups` and `bodyOrder`.

## What the solver cannot represent, and so cannot be written

Impact Lab rejects these with an explanation instead of silently ignoring them:

| If you write… | Why it is rejected |
|---|---|
| `fixed`, `pinned`, `clamped`, `constraints`, `support` … | No fixed or clamped constraints exist. Every body is free. Model a support as a separate deformable body (heavier or larger to hold still), or join bodies with a connection. |
| `gravity`, `force`, `load`, `pressure` … | No applied loads or body forces. Motion comes from initial velocities, contact and connections. |
| `friction`, `restitution` | Contact is frictionless penalty contact. Rebound is computed, not prescribed. |
| `angularVelocity`, `spin` | Bodies start with one uniform velocity, without rotation. |
| `temperature`, `strainRate` | No thermal or rate-dependent material behavior. |
| `timestep`, `dt` | The stable step is computed automatically. |
| `mass` | Mass follows from size and density. |
| `fracture` on a metal profile | The crack model is illustrative and calibrated for no real metal. |
| anything misspelled | Reported with a suggestion, e.g. *`parts[1] "Ball".velocty: unknown setting; did you mean "velocity"?`* |

Values out of range are reported with their location, value and allowed range. For example: *`parts[0] "A".size[0] (width) is 0.01 m; allowed 0.025 m to 0.3 m.`* All problems in a file are listed together. [`scene-examples/invalid-example.json`](scene-examples/invalid-example.json) shows this.

## Saved files

**Save** and **Export** write the complete form. That form lists every setting, gives bodies UUID ids, and expands profiles into their constants, provenance and hardening table. It opens back unchanged, bit for bit, and is still ordinary JSON, so scripts can read and modify it. Hand-written short forms and saved complete forms can be mixed freely.

## Examples

| File | What it shows | Physical behavior to look for |
|---|---|---|
| `metal-plate-impact.json` | Profiles, a round striker, a backing block, gauges | The plate dents permanently. Swap the plate to copper and compare. |
| `layered-panel.json` | Three bonded materials in one block, gauges in each layer | The pulse partly reflects and partly transmits at each bond. |
| `linked-chain.json` | Rotated bodies, a spring and a breakable link, `relativeTo`, a group | The spring holds and the breakable link snaps (the app shows Failed links 5, because a link with `span` is spread over five strands). Raise `criticalExtension` to keep it intact. |
| `notched-beam-fracture.json` | Notch and illustrative fracture, supports | The beam cracks from the notch. Raise `fracture.energy` to toughen it. |
| `generated-stack.json` | Output of `generate_stack.py` | A steel ball drives into five plates of four different metals. |
| `invalid-example.json` | Deliberately broken | Shows how errors are explained. |

Generate your own:

```bash
python3 docs/scene-examples/generate_stack.py 6 30 > ~/Desktop/stack.json
```

`ImpactCheck --scene-documents` checks all of this. It confirms that every built-in scene reopens identically, that explanations appear exactly when the solver rejects a setting, that the specific error messages are correct, and that each example loads, runs with under 2% energy drift, and re-imports its own export identically.
