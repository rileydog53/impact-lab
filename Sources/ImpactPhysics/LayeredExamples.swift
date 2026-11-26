import Foundation

/// Layered target plan, step 7: editable starting scenes for ordinary bonded laminates, each struck by a steel ball as
/// in a ball-drop impact test. The copies in docs/layered-examples must match these byte for byte
/// (`ImpactCheck --layered-examples`). Values and sources: docs/laminate-material-profiles.md. Every toughness and
/// bond value is experimental. Generated from the JSON files; edit those and regenerate.
public enum LayeredExample: String, CaseIterable, Sendable {
    case coated_steel_plate = "Sprayed-Ceramic-Coated Steel Plate"
    case laminated_glass_on_aluminium = "Laminated Glass on Aluminium"
    case carbon_skin_aluminium_panel = "Carbon-Fibre-Skinned Aluminium Panel"
    case glass_on_titanium_glue = "Glass Glued on Titanium (crack or peel)"

    public var fileName: String {
        switch self {
        case .coated_steel_plate: "coated-steel-plate.json"
        case .laminated_glass_on_aluminium: "laminated-glass-on-aluminium.json"
        case .carbon_skin_aluminium_panel: "carbon-skin-aluminium-panel.json"
        case .glass_on_titanium_glue: "glass-on-titanium-glue.json"
        }
    }

    public var description: String { (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["description"] as? String ?? "" }

    public func scene() throws -> AssemblyScene { try AssemblyScene.document(Data(json.utf8)) }

    public var json: String {
        switch self {
        case .coated_steel_plate: #"""
{
  "description": "A steel plate with a plasma-sprayed alumina (ceramic) coating on its struck face, hit by a 20 mm steel ball at 20 m/s, as in a ball-drop impact test of a coated part. Watch for the first crack in the coating, the coating coming off the steel (delamination), and any crack that opens inside the material. The coating is drawn 1.8 mm thick, the app's thinnest layer (10% of the plate); real sprayed coatings are about 0.1-0.7 mm. Sprayed alumina is porous and far softer than solid alumina: E 38 GPa (McPherson 1991). Its density, Poisson ratio and 83 MPa strength are stand-ins from related coatings. Bond: ASTM C633 pull-off 64 MPa (with a bond coat; about 15 MPa without one). Values and their sources: docs/laminate-material-profiles.md. Every toughness and bond value is experimental. The app is 2D (plane strain), so the ball is really a long steel rod seen end on. Numerical results, not validation.",
  "duration": 0.0002,
  "meshResolution": "x4",
  "bulkViscosity": true,
  "monitor": "Coated steel plate",
  "parts": [
    {
      "name": "Coated steel plate",
      "size": [
        0.018,
        0.1
      ],
      "center": [
        0,
        0
      ],
      "material": {
        "young": 38000000000.0,
        "density": 3510,
        "poisson": 0.2
      },
      "fracture": {
        "strength": 83000000.0,
        "energy": 21.5,
        "energySource": {
          "status": "estimated",
          "citation": "Plasma-sprayed alumina cohesive G_IC 16-27 J/m², midpoint (McPherson 1991, double cantilever beam). Strength is the flexural strength of free-standing flame-sprayed alumina, 83 MPa (Neumann et al. 2020), a stand-in.",
          "url": "https://www.irsm.cas.cz/materialy/cs_content/1991/McPherson_CS_1991_0000.pdf",
          "caution": "Experimental coating value; the strength is a stand-in from a related coating."
        }
      },
      "bondedLayer": {
        "interfaceFraction": 0.1,
        "material": {
          "profile": "structural-steel-a36",
          "elasticOnly": false
        },
        "fracture": {
          "strength": 475000000.0,
          "energy": 89180,
          "energySource": {
            "status": "estimated",
            "citation": "Mild steel K_IC 140 MPa√m (MIT OCW, eFunda) and A36 tensile strength 400-550 MPa midpoint, as in the app's own A36 estimate; G = K²(1-ν²)/E.",
            "url": "https://www.efunda.com/formulae/solid_mechanics/fracture_mechanics/fm_lefm_Kc_Matl.cfm",
            "caution": "Handbook estimate; real toughness varies with heat, orientation and thickness."
          }
        },
        "bond": {
          "strength": 64000000.0,
          "energy": 12.5,
          "energySource": {
            "status": "estimated",
            "citation": "Thermal-spray bond: ASTM C633 strength 64 MPa (average of 63 MPa, Sheibanian et al. 2026, and 65.5 MPa, Nayak et al. 2021; 15 MPa dropped). Interface G_IC 10-15 J/m², midpoint (McPherson 1991).",
            "url": "https://iris.polito.it/retrieve/handle/11583/3007768/966768",
            "caution": "Experimental; C633 strength depends on the bond coat and glue penetration."
          }
        }
      }
    },
    {
      "name": "Steel ball",
      "shape": "round",
      "size": [
        0.02,
        0.02
      ],
      "center": [
        -0.0195,
        0
      ],
      "velocity": [
        20,
        0
      ],
      "material": {
        "profile": "structural-steel-a36",
        "elasticOnly": true
      }
    }
  ]
}
"""#
        case .laminated_glass_on_aluminium: #"""
{
  "description": "A 6 mm annealed soda-lime glass sheet laminated with PVB interlayer and bonded with structural epoxy to an aluminium plate, hit on the glass by a 20 mm steel ball at 20 m/s, as in a ball-drop test of a glass-faced panel. Materials, left to right: Window glass (Library: Pilkington ATS-129), Safety-glass plastic PVB (Library: AGC Stratobel data sheet) and Aluminium 6061-T6 (Library: MatWeb); the ball is Library steel (A36). Each layer's source is shown in the inspector under Material. The two glue lines (glass to PVB, PVB to aluminium with structural epoxy) carry their own sourced estimates under Glued-on layers. Watch for the first crack in the glass, the glass coming off the PVB (delamination), and any crack that opens inside the material. The PVB is drawn 1.6 mm thick (the app's thinnest layer; real sheets are 0.38-1.52 mm). Its stiffness, 33 MPa, is the shortest-load sourced value (3 s, 20 °C, AGC): PVB is much stiffer at impact speeds and no measured high-rate value was found, so this layer is too soft and its result is a lower bound. PVB has no sourced toughness, so it never cracks; the glass-PVB bond strength is a guess capped at PVB's own tensile strength. Values and their sources: docs/laminate-material-profiles.md. Every toughness and bond value is experimental. The app is 2D (plane strain), so the ball is really a long steel rod seen end on. Numerical results, not validation.",
  "duration": 0.0002,
  "meshResolution": "x4",
  "bulkViscosity": true,
  "monitor": "Laminated glass on aluminium",
  "parts": [
    {
      "name": "Laminated glass on aluminium",
      "size": [
        0.016,
        0.1
      ],
      "center": [
        0,
        0
      ],
      "material": {
        "profile": "soda-lime-glass",
        "elasticOnly": true
      },
      "fracture": {
        "strength": 41000000.0,
        "energy": 7.4,
        "energySource": {
          "status": "estimated",
          "citation": "Soda-lime glass K_IC 0.75 MPa√m (Wikipedia, MakeItFrom) and mean modulus of rupture 41 MPa (Pilkington ATS-129); G = K²(1-ν²)/E.",
          "url": "https://en.wikipedia.org/wiki/Soda%E2%80%93lime_glass",
          "caution": "Experimental; glass strength depends strongly on surface flaws."
        }
      },
      "bondedLayer": {
        "interfaceFraction": 0.375,
        "material": {
          "profile": "pvb-interlayer",
          "elasticOnly": true
        },
        "bond": {
          "strength": 20000000.0,
          "energy": 329,
          "energySource": {
            "status": "estimated",
            "citation": "Glass-PVB adhesion energy 329 J/m², average of the two closest of 258 (Butchart and Overend 2012, fast rate), 400 (Jagota, cited there) and 605 J/m² (Seshadri, cited there). Strength set to PVB's tensile strength, over 20 MPa (Trosifol Clear), as an upper bound.",
            "url": "https://www.gft.eng.cam.ac.uk/system/files/documents/butchart-delamination-in-fractured-laminated-glass.pdf",
            "caution": "Experimental and rate dependent; the bond strength is a guess."
          }
        },
        "third": {
          "interfaceFraction": 0.475,
          "material": {
            "profile": "aluminum-6061-t6",
            "elasticOnly": false
          },
          "fracture": {
            "strength": 310000000.0,
            "energy": 10877,
            "energySource": {
              "status": "estimated",
              "citation": "6061-T6 typical tensile strength 310 MPa and K_IC 29 MPa√m, as in the app's own 6061-T6 estimate (aerospacemetals.com datasheet); G = K²(1-ν²)/E.",
              "url": "https://www.aerospacemetals.com/wp-content/uploads/2023/06/Aluminum-6061-T6-6061-T651.pdf",
              "caution": "Handbook estimate; real toughness varies with heat, orientation and thickness."
            }
          },
          "bond": {
            "strength": 31000000.0,
            "energy": 466.5,
            "energySource": {
              "status": "estimated",
              "citation": "Structural epoxy G_IC 466.5 J/m², average of the two closest of 250 (Betamate 73455, Martiny et al. 2013), 683 (round-robin TDCB on aluminium, Blackman et al. 2003) and 1250 J/m² (ESP 110, Martiny et al. 2013). Strength 31 MPa is 3M DP460 overlap shear on etched aluminium, used as a stand-in for opening strength.",
              "url": "https://core.ac.uk/download/77002118.pdf",
              "caution": "Experimental; epoxy toughness varies widely with formulation and bond thickness."
            }
          }
        }
      }
    },
    {
      "name": "Steel ball",
      "shape": "round",
      "size": [
        0.02,
        0.02
      ],
      "center": [
        -0.0185,
        0
      ],
      "velocity": [
        20,
        0
      ],
      "material": {
        "profile": "structural-steel-a36",
        "elasticOnly": true
      }
    }
  ]
}
"""#
        case .carbon_skin_aluminium_panel: #"""
{
  "description": "An aluminium plate with a 2 mm carbon-fibre/epoxy fabric skin bonded on with structural epoxy, hit on the skin by a 20 mm steel ball at 20 m/s (the ball comes from the right), as in a ball-drop test of a composite-skinned panel. Watch for the skin coming off the aluminium (delamination) and any crack in the aluminium. No crack toughness was found for the carbon fabric, so the skin itself never cracks: only the bond and the aluminium can. The fabric is treated as isotropic at its fibre-direction stiffness (70 GPa, ACP Composites, single source), which overstates it off-axis. The same epoxy round robin measured about 208 J/m² on carbon-fibre substrates, so this bond may be weaker in reality. Values and their sources: docs/laminate-material-profiles.md. Every toughness and bond value is experimental. The app is 2D (plane strain), so the ball is really a long steel rod seen end on. Numerical results, not validation.",
  "duration": 0.0002,
  "meshResolution": "x4",
  "bulkViscosity": true,
  "monitor": "Carbon-skinned aluminium panel",
  "parts": [
    {
      "name": "Carbon-skinned aluminium panel",
      "size": [
        0.012,
        0.1
      ],
      "center": [
        0,
        0
      ],
      "material": {
        "profile": "aluminum-6061-t6"
      },
      "fracture": {
        "strength": 310000000.0,
        "energy": 10877,
        "energySource": {
          "status": "estimated",
          "citation": "6061-T6 typical tensile strength 310 MPa and K_IC 29 MPa√m, as in the app's own 6061-T6 estimate (aerospacemetals.com datasheet); G = K²(1-ν²)/E.",
          "url": "https://www.aerospacemetals.com/wp-content/uploads/2023/06/Aluminum-6061-T6-6061-T651.pdf",
          "caution": "Handbook estimate; real toughness varies with heat, orientation and thickness."
        }
      },
      "bondedLayer": {
        "interfaceFraction": 0.8333,
        "material": {
          "young": 70000000000.0,
          "density": 1600,
          "poisson": 0.1
        },
        "bond": {
          "strength": 31000000.0,
          "energy": 466.5,
          "energySource": {
            "status": "estimated",
            "citation": "Structural epoxy G_IC 466.5 J/m², average of the two closest of 250 (Betamate 73455, Martiny et al. 2013), 683 (round-robin TDCB on aluminium, Blackman et al. 2003) and 1250 J/m² (ESP 110, Martiny et al. 2013). Strength 31 MPa is 3M DP460 overlap shear on etched aluminium, used as a stand-in for opening strength.",
            "url": "https://core.ac.uk/download/77002118.pdf",
            "caution": "Experimental; epoxy toughness varies widely with formulation and bond thickness."
          }
        }
      }
    },
    {
      "name": "Steel ball",
      "shape": "round",
      "size": [
        0.02,
        0.02
      ],
      "center": [
        0.0165,
        0
      ],
      "velocity": [
        -20,
        0
      ],
      "material": {
        "profile": "structural-steel-a36",
        "elasticOnly": true
      }
    }
  ]
}
"""#
        case .glass_on_titanium_glue: #"""
{
  "description": "Fracture demonstration: a 6 mm window-glass sheet glued with structural epoxy to a 6 mm titanium plate, hit on the glass by a 20 mm steel ball at 20 m/s. Three different things can fail, each with its own settings: the glass can crack inside itself, the glue line can let go so the glass peels off the titanium (delamination), and the titanium can crack inside itself (it is far tougher than glass). Materials, left to right: Window glass (Library: Pilkington ATS-129) and Titanium Ti-6Al-4V (Library: Wikipedia and AeroSpace Metals); the ball is Library steel (A36). Glass crack numbers: 41 MPa and 7.4 J/m² (Pilkington; Wikipedia and MakeItFrom toughness). Titanium crack numbers: 938 MPa and 64918 J/m² (NIST TN 2065 and others, as in the Library's estimate). Glue: 31 MPa and 466.5 J/m², the structural-epoxy stand-ins also used in the laminated-glass example (3M DP460; Martiny et al. 2013, Blackman et al. 2003). Every toughness and glue value is experimental. The app is 2D (plane strain), so the ball is really a long steel rod seen end on. Numerical results, not validation.",
  "duration": 0.0002,
  "meshResolution": "x4",
  "bulkViscosity": true,
  "monitor": "Glass glued on titanium",
  "parts": [
    {
      "name": "Glass glued on titanium",
      "size": [
        0.012,
        0.1
      ],
      "center": [
        0,
        0
      ],
      "material": {
        "profile": "soda-lime-glass",
        "elasticOnly": true
      },
      "fracture": {
        "strength": 41000000.0,
        "energy": 7.4,
        "energySource": {
          "status": "estimated",
          "citation": "Soda-lime glass K_IC 0.75 MPa√m (Wikipedia, MakeItFrom) and mean modulus of rupture 41 MPa (Pilkington ATS-129); G = K²(1-ν²)/E.",
          "url": "https://en.wikipedia.org/wiki/Soda%E2%80%93lime_glass",
          "caution": "Experimental; glass strength depends strongly on surface flaws."
        }
      },
      "bondedLayer": {
        "interfaceFraction": 0.5,
        "material": {
          "profile": "titanium-ti6al4v-annealed",
          "elasticOnly": false
        },
        "fracture": {
          "strength": 938000000.0,
          "energy": 64918.2,
          "energySource": {
            "status": "estimated",
            "citation": "Ti-6Al-4V K_IC about 90.3 MPa√m: average of the two closest of 75 (AeroSpace Metals), 91 (NIST TN 2065, citing Donachie) and 89.5 (NIST, citing Salem 2008); tensile strength 938 MPa. G = K²(1-ν²)/E.",
            "url": "https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.2065.pdf",
            "caution": "Handbook estimate; real toughness varies with heat, orientation and thickness."
          }
        },
        "bond": {
          "strength": 31000000.0,
          "energy": 466.5,
          "energySource": {
            "status": "estimated",
            "citation": "Structural epoxy G_IC 466.5 J/m², average of the two closest of 250 (Betamate 73455, Martiny et al. 2013), 683 (round-robin TDCB on aluminium, Blackman et al. 2003) and 1250 J/m² (ESP 110, Martiny et al. 2013). Strength 31 MPa is 3M DP460 overlap shear, used as a stand-in for opening strength.",
            "url": "https://core.ac.uk/download/77002118.pdf",
            "caution": "Experimental; epoxy toughness varies widely with formulation and bond thickness; measured on aluminium, used here on titanium."
          }
        }
      }
    },
    {
      "name": "Steel ball",
      "shape": "round",
      "size": [
        0.02,
        0.02
      ],
      "center": [
        -0.0165,
        0
      ],
      "velocity": [
        20,
        0
      ],
      "material": {
        "profile": "structural-steel-a36",
        "elasticOnly": true
      }
    }
  ]
}
"""#
        }
    }
}
