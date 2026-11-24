import Foundation

/// Non-violent lab examples for supports, gravity and spring preload. The JSON here is
/// identical to docs/lab-examples (checked by ImpactCheck --lab-examples) and is read
/// through the same scene-file reader as any imported file.
public enum LabExample: String, CaseIterable, Sendable {
    case block_on_bench = "Block Resting on a Bench"
    case drop_test = "Drop Test on a Bench"
    case cantilever_sag = "Cantilever Sagging Under Its Weight"
    case three_point_bend = "Three-Point Bend on Rollers"
    case hanging_springs = "Hanging Springs, Unloaded vs Preloaded"

    public var fileName: String {
        switch self {
        case .block_on_bench: "block-on-bench.json"
        case .drop_test: "drop-test.json"
        case .cantilever_sag: "cantilever-sag.json"
        case .three_point_bend: "three-point-bend.json"
        case .hanging_springs: "hanging-springs.json"
        }
    }

    public var description: String { (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["description"] as? String ?? "" }

    public func scene() throws -> AssemblyScene { try AssemblyScene.document(Data(json.utf8)) }

    public var json: String {
        switch self {
        case .block_on_bench: #"""
{
  "description": "A rubber-like block set 0.5 mm above a fixed lab bench, with gravity on. It drops, settles and rocks gently on the bench. Check: the time-averaged bench reaction equals the block's weight (m·g per metre of depth). Elastic only.",
  "gravity": 9.80665,
  "duration": 0.25,
  "meshResolution": "fine",
  "parts": [
    { "name": "Lab bench", "size": [0.4, 0.03], "center": [0, -0.015], "support": "fixed",
      "material": { "young": 1e7, "density": 2500, "poisson": 0.2 } },
    { "name": "Block", "size": [0.06, 0.05], "center": [0, 0.0255],
      "material": { "young": 3e6, "density": 1100, "poisson": 0.25 } }
  ],
  "monitor": "Block"
}
"""#
        case .drop_test: #"""
{
  "description": "Drop test: a soft round body released from rest 40 mm above a fixed bench falls under gravity, lands and rebounds. Check before impact: the fall matches y0 - g t^2 / 2 and kinetic energy at landing equals m·g·h. The rebound height depends on contact penalty and mesh; treat it as illustrative.",
  "gravity": 9.80665,
  "duration": 0.2,
  "parts": [
    { "name": "Lab bench", "size": [0.3, 0.03], "center": [0, -0.015], "support": "fixed",
      "material": { "young": 1e7, "density": 2500, "poisson": 0.2 } },
    { "name": "Rubber ball", "shape": "round", "size": [0.04, 0.04], "center": [0, 0.06],
      "material": { "young": 2e6, "density": 1100, "poisson": 0.3 } }
  ],
  "monitor": "Rubber ball"
}
"""#
        case .cantilever_sag: #"""
{
  "description": "A shelf-like beam clamped at its left edge sags under its own weight. Beam theory (Timoshenko, uniform load) predicts a static tip deflection of 1.22 mm for these values; the time-averaged tip sag in the app is within about 2% (12 rows of triangles through the thickness). The tip swings between 0 and about twice the static value because gravity is applied suddenly and there is no damping.",
  "gravity": 9.80665,
  "duration": 0.3,
  "parts": [
    { "name": "Cantilever", "size": [0.15, 0.025], "center": [0, 0], "support": "clampLeft", "refinement": "x4",
      "material": { "young": 1e7, "density": 1000, "poisson": 0 } }
  ],
  "gauges": [ { "body": "Cantilever", "name": "Tip", "location": [0.07, 0] } ],
  "monitor": "Cantilever"
}
"""#
        case .three_point_bend: #"""
{
  "description": "Three-point bend: a bar rests on two fixed rollers 260 mm apart under gravity, and a small weight is lowered onto its midspan at 0.2 m/s. Self-weight sag alone is about 1.09 mm by beam theory (checked to within about 1%); the weight adds a central load. Elastic only, no fracture.",
  "gravity": 9.80665,
  "duration": 0.3,
  "parts": [
    { "name": "Bar", "size": [0.3, 0.025], "center": [0, 0], "refinement": "x4",
      "material": { "young": 1e7, "density": 1000, "poisson": 0 } },
    { "name": "Left roller", "shape": "round", "size": [0.025, 0.025], "center": [-0.13, -0.02501], "support": "fixed",
      "material": { "young": 1e7, "density": 2000, "poisson": 0.2 } },
    { "name": "Right roller", "shape": "round", "size": [0.025, 0.025], "center": [0.13, -0.02501], "support": "fixed",
      "material": { "young": 1e7, "density": 2000, "poisson": 0.2 } },
    { "name": "Weight", "size": [0.03, 0.03], "center": [0, 0.0285], "velocity": [0, -0.2],
      "material": { "young": 1e7, "density": 3000, "poisson": 0.25 } }
  ],
  "monitor": "Bar"
}
"""#
        case .hanging_springs: #"""
{
  "description": "Two equal blocks hang from a fixed ceiling on equal springs, with gravity on. The left spring starts unloaded, so its block drops and bounces about the equilibrium stretch m·g/k = 7.8 mm. The right spring is preloaded by exactly that stretch, so its block starts in equilibrium and stays almost still. Shows unloaded versus preloaded connections.",
  "gravity": 9.80665,
  "duration": 0.5,
  "parts": [
    { "name": "Ceiling", "size": [0.3, 0.03], "center": [0, 0.115], "support": "fixed",
      "material": { "young": 1e7, "density": 2500, "poisson": 0.2 } },
    { "name": "Unloaded side", "size": [0.04, 0.04], "center": [-0.07, 0],
      "material": { "young": 2e6, "density": 1000, "poisson": 0.2 } },
    { "name": "Preloaded side", "size": [0.04, 0.04], "center": [0.07, 0],
      "material": { "young": 2e6, "density": 1000, "poisson": 0.2 } }
  ],
  "connections": [
    { "first": "Ceiling", "second": "Unloaded side", "firstAnchor": [-0.4667, -1], "secondAnchor": [0, 1], "stiffness": 2000 },
    { "first": "Ceiling", "second": "Preloaded side", "firstAnchor": [0.4667, -1], "secondAnchor": [0, 1], "stiffness": 2000, "preload": 0.0078453 }
  ],
  "monitor": "Unloaded side"
}
"""#
        }
    }
}
