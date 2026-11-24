# Impact Lab: plain-English guide

*Written 2026-11-24 as a documentation index. It summarizes older material and changes none of it. Where this guide and an older document disagree, the older document and the Google Doc decision record govern, and the disagreement should be reported.*

## What Impact Lab is

Impact Lab is Joseph's personal laboratory for mechanics and materials, running on a Mac. You build an experiment (shapes, materials, speeds, supports, gravity, springs), press Run, and the computer calculates what the physics says happens. It is not an animation: every picture comes from a calculation. It is non-violent by design (no weapons, no injury modelling).

## How it works, in one paragraph

Each object is cut into thousands of small triangles. The program applies Newton's laws to the triangles, step by tiny step (the "FEM", finite element method, solver). A metal can bend permanently (plasticity); an interface can crack (cohesive fracture); surfaces touch through "contact" rules. Everything is written in Swift. A second, experimental method (MPM, a particle method) exists as a side prototype. See [GLOSSARY.md](GLOSSARY.md).

## Where things stand (2026-11-24)

- **The app works and is accepted as an application.** Joseph accepted "Card 6" on 2026-11-24 for the consolidated laboratory recovery build. That acceptance covers the *application experience* only. It is **not** scientific validation of any material or fracture model.
- That build is merged into `main` (PR 1; the merge commit `f867f64` is on `main`).
- It can: assemble bodies and materials, fixed supports, gravity, spring connections with preload, runtime estimates and warnings, replay and compare runs, a scenario library, JSON scene files, a material library with sourced values.
- The "recovery phase" is over. Interface and geometry observations are a backlog beside the scientific roadmap.
- **Next suggested milestone (not approved):** fracture verification, i.e. proving the crack results do not depend on the mesh or time step.
- **Guiding direction (Joseph, 2026-11-24):** treat matter and its evolving state as the central idea, with FEM, MPM or others as interchangeable ways to compute it; reuse published methods and open-source tools within their licences. FEM is never discarded.

## Three kinds of "it works", never to be confused

1. **Numerical verification**: does the code solve its equations correctly (energy balance, convergence)?
2. **Physical validation**: do results match real experiments? Almost nothing here is validated this way yet.
3. **Personal acceptance**: Joseph judges the application usable.

## Map of this index

| File | What it is |
|---|---|
| [STATUS.md](STATUS.md) | Every finding, tagged verified / recorded / agent-reported / hypothesis |
| [DECISIONS.md](DECISIONS.md) | What Joseph approved, with dates, versus proposals still waiting |
| [GLOSSARY.md](GLOSSARY.md) | Toughness, strength, MPa, and the other terms |
| [WHERE_THINGS_LIVE.md](WHERE_THINGS_LIVE.md) | Which file or place holds what, and what exists only on the Mac |
| [archive-copies/](archive-copies/) | Labelled copies of Mac-only research files |
