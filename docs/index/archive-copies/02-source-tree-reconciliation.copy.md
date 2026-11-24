> COPY made 2026-11-24 for preservation. Original: research/design-notes/02-source-tree-reconciliation.md on Joseph's Mac (untracked). The original wins if they differ.

# 2. Main-versus-research source-tree question

Method: read-only git (`merge-base`, `log`, `diff --stat`) in the existing checkout after `git fetch`. No checkout, merge, or branch switch was done. Status key as in note 1.

## What each tree contains [verified]
The four lines of work are **one linear chain, not divergent forks**.

```
main (local, 2593315 "WIP Card 5")           <- working checkout
  └─ +7 → origin/main (724e32b)              Card 5 accept, Card 6/7 (scenario library), JSON scene import/export,
  │                                          showcase scenes, bounded 2-D MPM prototype + FEM comparison
  └─ +1 → origin/fem-deformation-study (717f8dc)   FEM deformation-limits study; small hook in AssemblySimulation.swift
  └─ +2 → origin/material-separation (47ccaad)     experimental tensile cohesive initiation (MaterialFracture.swift,
                                                    AssemblyScene `tensileStrength`), symmetric crack kinematics
```
Checks: `main` is an ancestor of `origin/main`; `origin/main` of `fem-deformation-study`; `fem-deformation-study` of `material-separation` (all `merge-base --is-ancestor` true). `claude/fracture-audit` (1fd5e7f) is already an ancestor of local `main`. Local `main` is "behind 7", with 0 commits ahead.

Contents of the 7 commits on origin/main but not local main (Sources/ImpactPhysics): `SceneDocument.swift` (+607, forgiving JSON reader), `ScenarioLibrary.swift` (+453), `MPMPrototype.swift` (+221), small edits to `AssemblyScene.swift`. The research copy at `research/material-separation` is a separate clone with the same remote, tracking `origin/material-separation`, working tree clean.

Beyond those: `main..material-separation` changes 22 Sources files, +2924/−40; of these, ImpactPhysics edits to existing files are small (`AssemblyScene.swift` +17, `AssemblySimulation.swift` +24, `MaterialFracture.swift` +42).

## Local working-tree facts [verified]
- Tracked files in the working checkout are clean; only untracked files exist (audit scripts, `AGENTS.md`, `README.md`, `tests/`, `reports/`, `research/`, `docs/*.md` handoff files).
- None of the files changed on any branch collides with an untracked path, so a fast-forward would not overwrite untracked work.
- `research/` lives **inside** the main working directory as untracked nested clones/projects (`material-separation`, `beam-verification`, …).

## Recommendation [hypothesis, for Joseph's approval]
1. **Base future production work on `origin/main` (724e32b).** It is the latest commit that carries only already-reviewed, accepted work (Cards 5–7 and scene I/O). Local `main` should fast-forward to it when Joseph approves; nothing is lost, since main is a strict ancestor.
2. **Keep `fem-deformation-study` and `material-separation` as stacked research branches** on top of origin/main. They add no divergent history, so integrating later is a plain fast-forward or a clean cherry-pick. Specifically, the tensile-initiation commits (fc188ee, 47ccaad) are labelled experimental and change `MaterialFracture.swift`; they should land only after separate review, not by default.
3. **Reconcile in this order:** (a) fast-forward main to origin/main; (b) fast-forward to `fem-deformation-study` if its `comparisonVelocities` hook in `AssemblySimulation.init` is accepted (it is `package`-level and test-fixture oriented); (c) decide the tensile commits on their own merits; (d) retire the nested `research/material-separation` clone in favour of a git worktree of the same repo to avoid two copies with one remote.
4. **Flag:** `MPMPrototype.swift` is in the production `ImpactPhysics` target and shares `J2Model`. Any J2 ledger change (note 1) must update MPM tests too. [hypothesis] Consider whether prototype code belongs in a separate target.
5. **Note for design work:** the load/constraint refusals and the `assemblyVersion == 1` hard checks live in `SceneDocument.swift`, which exists only from origin/main on. Scene v2 work (note 3) should start from origin/main, not local main.

Does not need anything from Joseph to *investigate*; the fast-forward needs his approval (he asked for no merging).
