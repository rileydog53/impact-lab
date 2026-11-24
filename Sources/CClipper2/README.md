# CClipper2

Vendored [Clipper2](https://github.com/AngusJohnson/Clipper2) by Angus Johnson, release `Clipper2_2.0.1`
(tag published 2025-12-19; source archive SHA-256 `2a3693aceab4aed3e39b743e038d87701acc53cf05ed7b2013aab3e0aec5287e`).
Licence: Boost Software License 1.0, checked in that release's `LICENSE` file and copied unchanged to `vendor/LICENSE`.
Only `CPP/Clipper2Lib/include/clipper2/*.h` and `src/clipper.engine.cpp`, `clipper.offset.cpp`, `clipper.rectclip.cpp`
are included, unmodified. `bridge.cpp` and `include/cclipper2.h` are Impact Lab's own C interface to it.

Used only by the geometry editor's Cut and Join (polygon boolean operations). It is not used by the mesher or the solver.
Approved by Joseph on 2026-11-24 (Google Doc section 28, decision 4).
