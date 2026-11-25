# Laminate material profiles (Layered Target Plan, step 7)

Written 25 November 2026 for three editable laminate presets: **coated metal**, **laminated glass on metal** and **composite panel**. It collects literature values for every layer and every bond, shows where sources disagreed and how that was settled, and ends with one JSON scene the app can open.

Nothing here was built or run. The JSON was checked against `docs/scene-format.schema.json` with one exception noted under [Known issues](#known-issues). Every value still needs a run on the Mac before it is trusted.

## How the values were picked

- Literature first; Wikipedia is accepted.
- Two sources within about 10% of each other count as agreeing, and the more specific source is used.
- When two sources conflict, a third is found and the two closest values are averaged. Each case is worked out under [Conflicts and how they were settled](#conflicts-and-how-they-were-settled).
- Every fracture toughness, fracture energy and interface value is **experimental**. In the JSON each one carries an `energySource` with `"status": "experimental"`, so the app shows its "Experimental, not validated" note next to it.
- Fracture energy for the app is the plane-strain energy release rate G = K²(1 − ν²)/E, the same conversion the app already uses for its metal profiles.
- Anything not found in a source is labelled **guess** or **stand-in**. Nothing is from memory.

## The three presets

The app allows up to three layers per block, laid along the block's local x axis.

| Preset | Layer 1 (left) | Bond 1 | Layer 2 | Bond 2 | Layer 3 | Struck face |
|---|---|---|---|---|---|---|
| Coated metal | Plasma-sprayed alumina coating | Thermal-spray bond | A36 steel | – | – | Left (coating) |
| Laminated glass on metal | Soda-lime glass | Glass–PVB adhesion | PVB interlayer | Structural epoxy | 6061-T6 aluminium | Left (glass) |
| Composite panel | 6061-T6 aluminium | Structural epoxy | Carbon-fibre/epoxy 0/90 fabric | – | – | Right (fabric skin) |

- The composite panel has the aluminium as its first layer because a body needs its own sourced fracture setting before its layers can crack or come apart, and no crack toughness for the fabric was found. The striker comes in from the right so the fabric is still the struck face.
- Real laminated glass is glass/PVB/glass. A fourth layer is not possible in one block, so this preset uses a single glass sheet over the PVB.
- The coating is drawn 20 mm thick (20% of the block), because the app's thinnest layer is 10% of the block. Real sprayed coatings are about 0.1–0.7 mm.

## Layer properties

Units: density kg/m³, modulus GPa, strengths MPa, toughness MPa·√m, fracture energy J/m². "n/a" means the material has no yield point in the usual sense (it breaks or stretches without a distinct yield).

### Soda-lime glass (annealed float)

| Property | Value used | Sources |
|---|---|---|
| Density | 2500 | Pilkington ATS-129: 2500. Wikipedia: 2530 (flat glass). MakeItFrom: 2400. All agree within 5%. |
| Young's modulus | 72 | Pilkington: 72. Wikipedia: 74. MakeItFrom: 71. Agree. |
| Poisson's ratio | 0.23 | Pilkington: 0.23. MakeItFrom: 0.23. |
| Yield strength | n/a | Brittle. |
| Tensile strength | 41 | Pilkington: mean modulus of rupture 41 MPa (60 s load, weathered glass). MakeItFrom: 41. Design stress is far lower (19 MPa, Pilkington). |
| Fracture toughness K_IC | 0.75 (experimental) | Wikipedia: 0.75 (flat glass). MakeItFrom: 0.75. |
| Fracture energy G | 7.4 (experimental) | From K, E and ν above. |

### PVB interlayer

| Property | Value used | Sources |
|---|---|---|
| Density | 1070 | AGC Stratobel datasheet: 1070 (23 °C, ASTM D792). Trosifol Clear (NBS Source listing): 1070. |
| Young's modulus | 0.033 (33 MPa) | AGC: 33 MPa for 3 s load at 20 °C (standard Stratobel PVB). Single source. |
| Poisson's ratio | 0.48 | AGC: 0.5. **Lowered to 0.48**, the app's upper limit. |
| Yield strength | n/a | Rubbery, no distinct yield. |
| Tensile strength | 20 (lower bound) | Trosifol Clear: >20 MPa (EN ISO 527); elongation at break >250%. Single source. |
| Fracture toughness | not found | PVB layers are set never to crack. |

PVB stiffness depends strongly on load time and temperature. AGC's own table runs from about 1 MPa (30 min, 40 °C) to about 1 GPa (3 s, 20 °C, stiff "Strong" grade). An impact lasts microseconds, so the real interlayer will be far stiffer than 33 MPa during impact. No high-rate value was found, so 33 MPa is the shortest-load sourced value, and it should be treated as a soft lower bound.

### Plasma-sprayed alumina coating

| Property | Value used | Sources |
|---|---|---|
| Density | 3510 (**guess**) | No coating density found. Derived: γ-alumina 3600 (McPherson 1991, phase density) × (1 − 2.5% porosity, Tillmann et al. 2019 medium powder). |
| Young's modulus | 38 | Conflict, settled below. Sprayed alumina is far softer than dense alumina (about 400 GPa, Wikipedia). |
| Poisson's ratio | 0.20 (**stand-in**) | Not measured in any source read. Neumann et al. 2020 assume 0.2 for flame-sprayed alumina. |
| Yield strength | n/a | Brittle. |
| Tensile strength | 83 (**stand-in**) | No plasma-sprayed tensile strength found. Uses the as-sprayed characteristic flexural strength of free-standing flame-sprayed alumina, 83.5 MPa (Neumann et al. 2020). Tensile strength is usually lower than flexural. |
| Fracture toughness K_IC | 0.92 (experimental, derived) | From G and E below. |
| Fracture energy G | 21.5 (experimental) | McPherson 1991: cohesive G_IC 16–27 J/m² by double cantilever beam; midpoint. |

The coating is stiffer in its own plane (about 88 GPa) than through its thickness (about 29 GPa) because of its layered splat structure (McPherson 1991). The app's materials are isotropic, so one through-thickness-like value is used, since the stress wave crosses the coating through its thickness.

### A36 structural steel (existing app profile `structural-steel-a36`)

| Property | Value used | Sources |
|---|---|---|
| Density | 7850 | App profile (TISCO A36 data): 7850. Wikipedia: 7800. Agree. |
| Young's modulus | 200 | App profile and Wikipedia: 200. |
| Poisson's ratio | 0.30 (profile) | App profile: 0.30, marked "representative" in the profile. Wikipedia: 0.26. See conflicts. |
| Yield strength | 250 | App profile and Wikipedia: 250 MPa minimum. |
| Tensile strength | 475 | Wikipedia: 400–550 MPa (ASTM A36); midpoint, as the app already uses. |
| Fracture toughness K_IC | 140 (experimental) | App's estimate: mild steel 140 MPa·√m in two tables that agree (MIT OCW, eFunda). Ductile steel has no strictly valid K_IC; this is an equivalent value. |
| Fracture energy G | 89,180 (experimental) | From K, E and ν = 0.30. |

### 6061-T6 aluminium (existing app profile `aluminum-6061-t6`)

| Property | Value used | Sources |
|---|---|---|
| Density | 2700 | App profile (ASM MatWeb): 2700. Wikipedia: 2700. |
| Young's modulus | 68.9 | App profile: 68.9. Wikipedia: 68–69. Agree. |
| Poisson's ratio | 0.33 | App profile and Wikipedia: 0.33. |
| Yield strength | 276 | App profile (MatWeb): 276. Wikipedia: 270 typical (240 minimum). Agree. |
| Tensile strength | 310 | App's estimate and Wikipedia: 310 MPa typical (290 minimum). |
| Fracture toughness K_IC | 29 (experimental) | App's estimate: 29 MPa·√m (aerospacemetals.com datasheet, ASM-derived). |
| Fracture energy G | 10,877 (experimental) | From K, E and ν. |

### Carbon-fibre/epoxy 0/90 fabric laminate

| Property | Value used | Sources |
|---|---|---|
| Density | 1600 | ACP Composites property table (2014): 1.6 g/cm³, standard-modulus fabric, 50% fibre volume. Single source. |
| Young's modulus | 70 | ACP: 70 GPa along either fibre direction. Single source. |
| Poisson's ratio | 0.10 | ACP: 0.1 in-plane. Single source. |
| Yield strength | n/a | Linear until failure (ACP: 0.85% strain to failure). |
| Tensile strength | 600 | ACP: 600 MPa (compressive 570). Single source. |
| Fracture toughness | not found | The skin is set never to crack. |

A woven fabric is stiff only along its fibres: loaded at ±45° the same fabric drops to 19 GPa and 120 MPa (ACP, page 2). The app treats it as isotropic at the fibre-direction values, which overstates its stiffness off-axis. Two other CFRP pages were tried: one hides its numbers behind a sign-up and one showed a bot check, which was left alone. A second source is still wanted for these values.

## Interface (bond) properties

The app's bond takes a strength in Pa and an energy in J/m².

| Bond | Strength used | Energy used | Sources |
|---|---|---|---|
| Thermal-spray coating to steel | 64 MPa | 12.5 J/m² (experimental) | Strength: conflict, settled below (ASTM C633 pull-off). Energy: McPherson 1991, adhesive (interface) G_IC 10–15 J/m² by double cantilever beam; midpoint. Single source for energy. |
| Glass to PVB | 20 MPa (**guess**) | 329 J/m² (experimental) | Energy: conflict, settled below. Strength: no glass–PVB interface strength found; set to the PVB tensile strength (>20 MPa, Trosifol) as an upper bound, since the bond cannot hold more than the interlayer itself. |
| Structural epoxy (PVB to aluminium, and aluminium to fabric) | 31 MPa | 466.5 J/m² (experimental) | Strength: 3M DP460 overlap shear on etched aluminium at 23 °C, 4500 psi (2004 datasheet) = 316 kgf/cm² (2020 datasheet) = 31.0 MPa. This is a shear value used for the bond's opening strength (**stand-in**); no tensile value was found in the datasheets. Energy: conflict, settled below. |

## Conflicts and how they were settled

1. **Sprayed alumina modulus.** The review (McPherson 1991) reports several measurements: 29 GPa through the thickness (strain gauges), 34–40 GPa (sonic resonance, Ault, midpoint 37), 39 GPa (Tucker), 31 GPa (resonance, Fargeot) and 60–90 GPa (beam bending). Taking the three through-thickness-type values 29, 37 and 39: the two closest are 37 and 39, average **38 GPa**. All of these come from one review, so they are not fully independent.
2. **Thermal-spray bond strength (ASTM C633).** 63 MPa for alumina on bearing steel with a nickel bond coat (Sheibanian et al. 2026) and 15 MPa for alumina on mild steel (Shivakumar et al. 2003) conflict. Third: 65.5 MPa for a YSZ/alumina top coat on cast iron, 300 µm (Nayak et al. 2021). The two closest are 63 and 65.5, average **64 MPa**. Both kept values used a bond coat; the 15 MPa value did not say. Nayak et al. also warn that glue soaking into a porous coating can raise C633 readings. A plain alumina coat without a bond coat may be much weaker; 15 MPa is a sensible low setting to try.
3. **Glass–PVB adhesion energy.** Butchart and Overend (2012) measured 258 J/m² at their faster rate and 660 J/m² at their slower rate, and list earlier work from 280 up to 1400 J/m². Using values from three different studies: 258 (Butchart, fast), 400 (Jagota, as cited there) and 605 (Seshadri, midpoint of 280–930, as cited there). The two closest are 258 and 400, average **329 J/m²**. Faster loading gave lower values in Butchart's tests, and impact is fast, so the lower end is the more relevant one.
4. **Structural epoxy fracture energy.** Values depend heavily on formulation: 200–300 J/m² for a silica-filled epoxy (Betamate 73455, midpoint 250), 683 J/m² for a general-purpose epoxy paste on aluminium (international round robin, tapered double cantilever beam, Blackman et al. 2003), 1000–1500 J/m² for a rubber-toughened epoxy (ESP 110, midpoint 1250), and 2500–5800 J/m² for a nano-toughened Henkel epoxy (UCD). Taking 250, 683 and 1250: the two closest are 250 and 683, average **466.5 J/m²**. The same round robin measured about 208 J/m² when the substrates were carbon-fibre composite, so the composite panel's bond may be weaker than this.
5. **A36 Poisson's ratio.** Wikipedia gives 0.26; the app's existing profile uses 0.30, labelled "representative". No third source was read, and the profile was left unchanged because this task does not edit the app. If the profile is ever revised, a third source is needed.

## Known issues

- `docs/scene-format.schema.json` caps `parts[].fracture.energy` at 50 J/m², but `docs/SCENE_FORMAT.md` and the app's own validation allow up to 1,000,000 J/m² whenever `strength` is given in pascals. The metal layers here (10,877 and 89,180 J/m²) pass the app's rules but fail the schema's cap. The JSON below passes the schema with that one cap lifted. The schema was not changed.
- The app's comment on `FractureEstimateSource.status` says it is always "estimated"; this file uses "experimental" because that was the requested label. The app shows its "Experimental, not validated" note for any value that has a source, whatever the status says.
- Gaps still open: a high-rate PVB modulus, a glass–PVB interface strength, a tensile (not shear) strength for structural epoxy, a measured Poisson's ratio, density and tensile strength for plasma-sprayed alumina, a second source for every carbon-fibre value, and a crack toughness for the fabric skin.

## JSON scene

Save this block as a `.json` file and open it in Impact Lab. It holds all three presets as separate blocks, one above the other, each with its own small elastic steel striker at 10 m/s. Layer thickness (`interfaceFraction`), striker speed and every value can be edited.

```json
{
  "description": "Impact Lab step 7 laminate presets: coated metal, laminated glass on metal and composite panel, each struck by a small elastic steel block at 10 m/s. Values and sources: docs/laminate-material-profiles.md. Thicknesses, speed and every value are meant to be edited.",
  "duration": 0.0004,
  "meshResolution": "fine",
  "parts": [
    {
      "name": "Coated metal",
      "size": [
        0.1,
        0.04
      ],
      "center": [
        0,
        0.1
      ],
      "description": "Plasma-sprayed alumina coating (struck face) on A36 steel. Coating drawn 20 mm thick; real coatings are about 0.1-0.7 mm.",
      "material": {
        "young": 38000000000.0,
        "density": 3510,
        "poisson": 0.2
      },
      "fracture": {
        "strength": 83000000.0,
        "energy": 21.5,
        "energySource": {
          "status": "experimental",
          "citation": "APS alumina cohesive G_IC 16-27 J/m2, midpoint (McPherson 1991, DCB). Strength is a flame-sprayed free-standing flexural value, 83 MPa (Neumann et al. 2020), used as a stand-in.",
          "url": "https://www.irsm.cas.cz/materialy/cs_content/1991/McPherson_CS_1991_0000.pdf",
          "caution": "Experimental coating value; strength is a stand-in from a related coating."
        }
      },
      "bondedLayer": {
        "interfaceFraction": 0.2,
        "material": {
          "profile": "structural-steel-a36",
          "elasticOnly": false
        },
        "fracture": {
          "strength": 475000000.0,
          "energy": 89180,
          "energySource": {
            "status": "experimental",
            "citation": "Mild steel K_IC 140 MPa sqrt(m) (MIT OCW, eFunda) and A36 UTS 400-550 MPa midpoint, as in the app's own A36 estimate; G = K^2(1-nu^2)/E.",
            "url": "https://www.efunda.com/formulae/solid_mechanics/fracture_mechanics/fm_lefm_Kc_Matl.cfm",
            "caution": "Handbook estimate; real toughness varies with heat, orientation and thickness."
          }
        },
        "bond": {
          "strength": 64000000.0,
          "energy": 12.5,
          "energySource": {
            "status": "experimental",
            "citation": "Thermal-spray bond: ASTM C633 strength 64 MPa (average of 63 MPa, Sheibanian et al. 2026, and 65.5 MPa, Nayak et al. 2021; 15 MPa outlier dropped). Interface G_IC 10-15 J/m2 midpoint (McPherson 1991, DCB).",
            "url": "https://iris.polito.it/retrieve/handle/11583/3007768/966768",
            "caution": "Experimental; C633 strength depends on bond coat and glue penetration."
          }
        }
      }
    },
    {
      "name": "Striker, coated metal",
      "size": [
        0.02,
        0.02
      ],
      "center": [
        -0.0605,
        0.1
      ],
      "velocity": [
        10,
        0
      ],
      "material": {
        "profile": "structural-steel-a36",
        "elasticOnly": true
      }
    },
    {
      "name": "Laminated glass on metal",
      "size": [
        0.1,
        0.04
      ],
      "center": [
        0,
        0
      ],
      "description": "Annealed soda-lime glass (struck face), PVB interlayer, then 6061-T6 aluminium bonded with structural epoxy.",
      "material": {
        "young": 72000000000.0,
        "density": 2500,
        "poisson": 0.23
      },
      "fracture": {
        "strength": 41000000.0,
        "energy": 7.4,
        "energySource": {
          "status": "experimental",
          "citation": "Soda-lime glass K_IC 0.75 MPa sqrt(m) (Wikipedia, MakeItFrom) and mean modulus of rupture 41 MPa (Pilkington ATS-129); G = K^2(1-nu^2)/E.",
          "url": "https://en.wikipedia.org/wiki/Soda%E2%80%93lime_glass",
          "caution": "Experimental; glass strength depends strongly on surface flaws."
        }
      },
      "bondedLayer": {
        "interfaceFraction": 0.4,
        "material": {
          "young": 33000000.0,
          "density": 1070,
          "poisson": 0.48
        },
        "bond": {
          "strength": 20000000.0,
          "energy": 329,
          "energySource": {
            "status": "experimental",
            "citation": "Glass-PVB adhesion energy 329 J/m2: average of the two closest of 258 J/m2 (Butchart and Overend 2012, fast TCT), 400 J/m2 (Jagota, cited there) and 605 J/m2 (Seshadri 280-930 midpoint, cited there). Strength set to PVB tensile strength >20 MPa (Trosifol Clear) as an upper bound.",
            "url": "https://www.gft.eng.cam.ac.uk/system/files/documents/butchart-delamination-in-fractured-laminated-glass.pdf",
            "caution": "Experimental; rate dependent. Bond strength is a guess capped at the interlayer's own strength."
          }
        },
        "third": {
          "interfaceFraction": 0.5,
          "material": {
            "profile": "aluminum-6061-t6",
            "elasticOnly": false
          },
          "fracture": {
            "strength": 310000000.0,
            "energy": 10877,
            "energySource": {
              "status": "experimental",
              "citation": "6061-T6 typical UTS 310 MPa and K_IC 29 MPa sqrt(m), as in the app's own 6061-T6 estimate (aerospacemetals.com datasheet); G = K^2(1-nu^2)/E.",
              "url": "https://www.aerospacemetals.com/wp-content/uploads/2023/06/Aluminum-6061-T6-6061-T651.pdf",
              "caution": "Handbook estimate; real toughness varies with heat, orientation and thickness."
            }
          },
          "bond": {
            "strength": 31000000.0,
            "energy": 466.5,
            "energySource": {
              "status": "experimental",
              "citation": "Structural epoxy: G_IC 466.5 J/m2, average of the two closest of 250 (Betamate 73455, Martiny et al. 2013), 683 (round robin TDCB on aluminium, Blackman et al. 2003) and 1250 J/m2 (ESP 110, Martiny et al. 2013). Strength 31 MPa is 3M DP460 overlap shear on etched aluminium.",
              "url": "https://core.ac.uk/download/77002118.pdf",
              "caution": "Experimental; epoxy toughness varies widely with formulation and bond thickness."
            }
          }
        }
      }
    },
    {
      "name": "Striker, laminated glass",
      "size": [
        0.02,
        0.02
      ],
      "center": [
        -0.0605,
        0.0
      ],
      "velocity": [
        10,
        0
      ],
      "material": {
        "profile": "structural-steel-a36",
        "elasticOnly": true
      }
    },
    {
      "name": "Composite panel",
      "size": [
        0.1,
        0.04
      ],
      "center": [
        0,
        -0.1
      ],
      "description": "6061-T6 aluminium backing (left) bonded with structural epoxy to a carbon-fibre/epoxy 0/90 fabric skin (right, struck face). The skin has no sourced crack toughness, so it does not crack.",
      "material": {
        "profile": "aluminum-6061-t6"
      },
      "fracture": {
        "strength": 310000000.0,
        "energy": 10877,
        "energySource": {
          "status": "experimental",
          "citation": "6061-T6 typical UTS 310 MPa and K_IC 29 MPa sqrt(m), as in the app's own 6061-T6 estimate; G = K^2(1-nu^2)/E.",
          "url": "https://www.aerospacemetals.com/wp-content/uploads/2023/06/Aluminum-6061-T6-6061-T651.pdf",
          "caution": "Handbook estimate; real toughness varies with heat, orientation and thickness."
        }
      },
      "bondedLayer": {
        "interfaceFraction": 0.7,
        "material": {
          "young": 70000000000.0,
          "density": 1600,
          "poisson": 0.1
        },
        "bond": {
          "strength": 31000000.0,
          "energy": 466.5,
          "energySource": {
            "status": "experimental",
            "citation": "Structural epoxy: G_IC 466.5 J/m2, average of the two closest of 250, 683 and 1250 J/m2 (Martiny et al. 2013; Blackman et al. 2003). Strength 31 MPa is 3M DP460 overlap shear on etched aluminium.",
            "url": "https://core.ac.uk/download/77002118.pdf",
            "caution": "Experimental; the same round robin measured about 208 J/m2 on carbon-fibre substrates."
          }
        }
      }
    },
    {
      "name": "Striker, composite panel",
      "size": [
        0.02,
        0.02
      ],
      "center": [
        0.0605,
        -0.1
      ],
      "velocity": [
        -10,
        0
      ],
      "material": {
        "profile": "structural-steel-a36",
        "elasticOnly": true
      }
    }
  ],
  "monitor": "Laminated glass on metal"
}
```

## Sources

- Pilkington North America, Technical Bulletin ATS-129, *Properties of Soda-Lime Silica Float Glass* (2013): https://www.pilkington.com/-/media/pilkington/site-content/usa/window-manufacturers/technical-bulletins/ats129propertiesofglass20130114.pdf
- Wikipedia, *Soda–lime glass*: https://en.wikipedia.org/wiki/Soda%E2%80%93lime_glass
- MakeItFrom, *Annealed Soda-Lime Glass*: https://www.makeitfrom.com/material-properties/Annealed-Soda-Lime-Glass
- AGC Glass Europe, *Material properties of PVB interlayers, Stratobel and Stratobel Strong* (2022): https://www.agc-yourglass.com/sites/default/files/2022-10/Material%20Properties%20of%20PVB%200722_EN_0.pdf
- Kuraray Trosifol Clear, manufacturer-verified NBS Source listing: https://source.thenbs.com/product/trosifol-clear/F3HDsixarxYA3mm7jxmp5
- Butchart and Overend, *Delamination in fractured laminated glass*, glasstec 2012: https://www.gft.eng.cam.ac.uk/system/files/documents/butchart-delamination-in-fractured-laminated-glass.pdf
- McPherson, *The structure and properties of plasma sprayed alumina coatings*, Silikáty 35 (1991) 273–282: https://www.irsm.cas.cz/materialy/cs_content/1991/McPherson_CS_1991_0000.pdf
- Tillmann, Khalil, Abdulgader, *Porosity characterization and its effect on thermal properties of APS-sprayed alumina coatings*, Coatings 9 (2019) 601: https://eldorado.tu-dortmund.de/bitstream/2003/38266/1/coatings-09-00601.pdf
- Neumann et al., *Statistical analysis of the flexural strength of free-standing flame-sprayed alumina coatings*, J. Therm. Spray Tech. (2020): https://link.springer.com/content/pdf/10.1007/s11666-020-01114-6.pdf
- Wikipedia, *Aluminium oxide*: https://en.wikipedia.org/wiki/Aluminium_oxide
- Sheibanian et al., *Effect of torch power and thickness on APS Al2O3 coatings on 100Cr6 bearing steel*, J. Manuf. Mater. Process. 10 (2026) 68: https://iris.polito.it/retrieve/handle/11583/3007768/966768
- Nayak, Krishnamurthy, Shailesh, *Development and adhesion strength of plasma-sprayed thermal barrier coating on the cast iron substrate*, IJIE 13 (2021) 47–59: https://core.ac.uk/download/480425212.pdf
- Shivakumar, Sadashivappa, Vrushabhendrappa, *Characteristic evaluation of mechanical properties of plasma sprayed ceramic coating*, ICME 2003: https://me.buet.ac.bd/public/old/icme/icme2003/Proceedings/PDF/ICME03-AM-12.pdf
- Martiny, Lani, Kinloch, Pardoen, *A maximum stress at a distance criterion for the prediction of crack propagation in adhesively-bonded joints*, Eng. Fract. Mech. 97 (2013): https://spiral.imperial.ac.uk/bitstream/10044/1/13842/2/Engineering%20Fracture%20Mechanics_97_2013.pdf
- Blackman, Kinloch, Paraschi, Teo, *Measuring the mode I adhesive fracture energy, G_IC, of structural adhesive joints: the results of an international round-robin*, Int. J. Adhes. Adhes. 23 (2003) 293–305: https://core.ac.uk/download/77002118.pdf
- UCD Centre for Adhesion and Adhesives, *Characterisation of traction-separation laws in structural adhesives*: https://www.ucd.ie/adhesion/research/characterisationoftraction-separationlawsinstructuraladhesives
- 3M, *Scotch-Weld Epoxy Adhesive DP460* technical data sheet (2004): https://dragonplate.com/Images/uploaded/PDFs/3m%20DP460NS_Data_Sheet.pdf and 3M do Brasil edition (2020): https://multimedia.3m.com/mws/media/1857254O/product-data-sheet-structural-adhesives-dp460ns-460-off-white.pdf
- ACP Composites, *Mechanical Properties of Carbon Fiber Composite Materials* (2014): https://acpcomposites.com/wp-content/uploads/2024/05/Mechanical-Properties-of-Carbon-Fiber-Composite-Materials.pdf
- Wikipedia, *A36 steel*: https://en.wikipedia.org/wiki/A36_steel
- Wikipedia, *6061 aluminium alloy*: https://en.wikipedia.org/wiki/6061_aluminium_alloy
- App's existing metal sources, kept as cited in `Sources/ImpactPhysics/MaterialProfile.swift` and `MaterialFractureEstimate.swift`: TISCO A36 plate data, ASM MatWeb 6061-T6, eFunda mild steel K_IC table (https://www.efunda.com/formulae/solid_mechanics/fracture_mechanics/fm_lefm_Kc_Matl.cfm), aerospacemetals.com 6061-T6 datasheet (https://www.aerospacemetals.com/wp-content/uploads/2023/06/Aluminum-6061-T6-6061-T651.pdf).
