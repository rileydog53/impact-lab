#!/usr/bin/env python3
"""Generate an Impact Lab scene: a striker hitting a stack of plates.

Usage:  python3 generate_stack.py [plates] [speed_m_per_s] > stack.json
Then open stack.json in Impact Lab (Assembly → Open).
"""
import json
import sys

plates = int(sys.argv[1]) if len(sys.argv) > 1 else 4
speed = float(sys.argv[2]) if len(sys.argv) > 2 else 20.0
profiles = ["aluminum-6061-t6", "copper-c11000-annealed", "stainless-304-annealed", "structural-steel-a36"]
thickness, gap = 0.025, 0.0005          # metres

parts = []
for i in range(plates):
    parts.append({
        "name": f"Plate {i + 1}",
        "size": [thickness, 0.12],
        "center": [i * (thickness + gap), 0],
        "material": profiles[i % len(profiles)],
    })
parts.append({
    "name": "Striker", "shape": "round", "size": [0.03, 0.03],
    "center": [-(thickness / 2 + gap + 0.015), 0],
    "velocity": [speed, 0],
    "material": {"profile": "structural-steel-a36", "elasticOnly": True},
})
scene = {
    "description": f"{plates}-plate stack struck at {speed} m/s (generated)",
    "duration": 0.0006,
    "meshResolution": "fine",
    "parts": parts,
    "monitor": "Plate 1",
}
json.dump(scene, sys.stdout, indent=2)
print()
