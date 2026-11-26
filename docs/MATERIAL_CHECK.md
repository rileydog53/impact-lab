# Material check: the 13 Library materials against published sources

Checked 2026-11-26 against `main` after PR 36. Read-only: no code or value was changed. Every number below was read on the linked page.

The five values, in the app's words and the code's units:

| App word | Property | Stored as |
|---|---|---|
| Stiffness | Young's modulus | GPa |
| Squish sideways | Poisson's ratio | ratio |
| Density | density | kg/m³ |
| Bends-for-good strength | yield strength for metals; for springs-back materials the code stores a listed breaking strength in the same slot | MPa |
| Crack resistance | fracture energy G | J/m², from G = K²(1 − ν²)/E with the Library's own E and ν |

## Summary

- **65 values checked** (13 materials × 5).
- **3 flagged** as more than 20% off: 304 stainless crack resistance, carbon fibre breaking strength, rubber stiffness. Each is explained in its material's section.
- **The carbon fibre and rubber flags depend on which sources are compared.**
  - Carbon fibre is compared against aerospace prepregs, though the Library entry is a commercial grade, and commercial sources sit near 600 MPa.
  - Rubber is compared against two generic tables that repeat the same unsourced range. Against the two rubber-specific sources it lands exactly at the 20% line.
- **4 near the edge** (15–20% off, not flagged): A36 squish sideways, A36 bends-for-good strength (against typical values), PVB breaking strength, rubber stiffness (against rubber-specific sources).
- **7 crack resistance values are not stored** (copper, brass, carbon fibre, polycarbonate, PVB, rubber, oak). The app gives these a typed starting value of 1000 J/m² when cracking is switched on.
- **No source found** for 2 of those 7: annealed copper (no valid test value exists, only estimates) and cartridge brass. PVB has just one source.
- **Every stored value has at least two sources.** The weakest is oak's squish sideways: one oak-specific source plus a generic hardwood figure.

### How the flag works

1. For each value I took the two sources whose numbers are closest to each other. A range counts as its midpoint.
2. The Library value is compared with the average of those two.
3. A flag is a flag only. The average is **not** a suggested replacement. Where sources disagree, the grade, temper, test method and load time are noted, along with which one the Library entry seems to mean.
4. Grade and test method did not decide which sources were compared.
   - The pair was picked only by how close its numbers were, from every source read.
   - Grade, temper, test method and load time were noted beside each value afterward.
   - Where the closest pair is a different grade or method from the Library entry, the flag is marked source-dependent, and the grade-matched comparison is given beside it. That applies to carbon fibre and rubber.
   - Elsewhere the closest pair already matched the Library entry's basis. For example, A36's minimum yield was compared with minimum values, and PVB stiffness with values at the same 3 s load and 20 °C.

### Flagged

1. **304 stainless, crack resistance (231,800 J/m², from K 225 MPa·√m).**
   - Handbook tables give K 50–150 MPa·√m, which is about 11,000–103,000 J/m².
   - J-integral tests give about 300,000 J/m² or more. J-integral is the usual way to test steel this tough.
   - Against the two closest sources (Granta and MIT, both handbook tables) the Library is +637%. Against the J test it is −23%.
   - The sources split by test method, and the Library sits between the two camps.
2. **Carbon fibre fabric, breaking strength (600 MPa).**
   - Two aerospace prepreg fabrics (Hexcel 8552 AS4 plain weave and Toray T700/2510 plain weave) average 816 MPa, so the Library is −26%.
   - 600 matches ACP's "standard" fabric and the commercial-grade range on performancecomposites.com (345–621 MPa).
   - So the Library entry seems to mean a commercial or wet-layup grade, not aerospace prepreg.
   - **Source-dependent:** this flag compares a commercial grade with aerospace prepregs. Against the grade-matched commercial sources (ACP 600, and RS about 595 from its failure strain) it is not over 20%.
3. **Natural rubber, stiffness (3 MPa).**
   - Sources fall into two camps.
   - General property tables (Wikipedia Young's modulus, Engineering ToolBox, Brown University notes) all print "10–100 MPa" with no source and no grade. Against them the Library is −95%.
   - Unfilled vulcanised rubber sources give about 1–2 MPa (Nian & Suo 2 MPa; Treloar's data, about 1 MPa). NETZSCH gives a range of 1–5 MPa.
   - Against NETZSCH and Nian & Suo the Library is +20%, right at the line.
   - The 10–100 MPa tables look like they cover filled or hard compounds.
   - **Source-dependent:** the two tables behind this flag repeat the same unsourced range. Against the two rubber-specific sources the Library lands exactly at the 20% line.

### Biggest surprises

- **The rubber stiffness citation is wrong.** The Library credits "TSE Industries 1–5 MPa", but the TSE sheet has no stiffness value at all. The 1–5 MPa figure is on the NETZSCH page.
- **304 bends-for-good strength (200 MPa).** The cited Outokumpu sheet doesn't show 200. It gives 210 for hot-rolled and 230 for cold-rolled as EN minimums. This is not flagged: it is 6–13% off.
- **Ti-6Al-4V crack resistance.** The 90.3 MPa·√m behind it is the Library's own average of 91 and 89.5. Those are two literature values that NIST TN 2065 quotes (from Donachie and Salem). It is not a single number in that report. The Library's own titanium datasheet (AeroSpace Metals) says 75. Across sources, processing alone spans 40–107.
- **Two bad source pages found along the way. Neither was used.**
  - MakeItFrom lists cartridge brass at 8200 kg/m³. Every other source says about 8530.
  - Oklahoma State's FAPC-162 "white oak" row matches bur oak in the US Forest Products Lab table.
- **Oak's 51 MPa is a crushing strength,** not a breaking strength. Bending strength (MOR) is about 105 MPa. Pulling strength along the grain is about 78–87 MPa for other oaks; no white oak value was found.

---

## 1. Structural steel A36 (already in the Library before PR 36)

| Value | Library | Source 1 | Source 2 | Off | Status |
|---|---|---|---|---|---|
| Stiffness | 200 GPa | [Wikipedia ASTM A36](https://en.wikipedia.org/wiki/ASTM_A36) 200 | [OnlineMetals A36](https://www.onlinemetals.com/en/product-guide/alloy/a36) 199.9 | 0% | OK |
| Squish sideways | 0.30 | Wikipedia 0.26 | OnlineMetals 0.26 | +15% | Near edge |
| Density | 7850 | Wikipedia 7800 | OnlineMetals 7806 | +1% | OK |
| Bends-for-good | 250 MPa (spec minimum) | Wikipedia 250 (min) | [Xometry A36](https://www.xometry.com/resources/materials/a36-carbon-steel) 250 (min) | 0% | OK |
| Crack resistance | 89,180 J/m² (K 140) | [eFunda](https://www.efunda.com/formulae/solid_mechanics/fracture_mechanics/fm_lefm_Kc_Matl.cfm) K 140 "mild steel" | [MIT OCW 3.91 table](https://ocw.mit.edu/courses/3-91-mechanical-behavior-of-plastics-spring-2007/75de4a5cfaba0c00a5a72b25500b1149_props.pdf) K 140 "mild steel 1020" | 0% | OK, contested |

- **Squish sideways:** sources split. Wikipedia and OnlineMetals give 0.26. [MakeItFrom](https://www.makeitfrom.com/material-properties/ASTM-A36-SS400-S275-Structural-Carbon-Steel) and MIT give 0.29. [Engineering ToolBox](https://www.engineeringtoolbox.com/metals-poissons-ratio-d_1268.html) gives 0.30. The 0.26 pair and the 0.29 pair tie as "closest". Against 0.29 the Library is +3%.
- **Bends-for-good:** 250 is the specified minimum. Typical measured values are higher: MakeItFrom 290, OnlineMetals 329. Against those the Library is −19%.
- **Crack resistance:** both sources are generic "mild steel" tables, not A36. eFunda is the Library's own source. The [Ansys/Granta data booklet](https://ansys.synopsys.com/content/dam/amp/2021/august/webpage-requests/education-resources-dam-upload-batch-2/material-property-data-for-eng-materials-BOKENGEN21.pdf) gives low-carbon steel K 41–82, which is about 7,650–30,600 J/m². Mild steel at room temperature is too ductile for a strictly valid K_IC, so every value here is nominal.

## 2. Stainless steel 304, annealed (already in the Library)

| Value | Library | Source 1 | Source 2 | Off | Status |
|---|---|---|---|---|---|
| Stiffness | 200 GPa | [MakeItFrom 304 annealed](https://www.makeitfrom.com/material-properties/Annealed-304-Stainless-Steel) 200 | [Outokumpu Core datasheet](https://otke-cdn.outokumpu.com/-/media/files/products/core/outokumpu-core-range-datasheet.pdf) 200 | 0% | OK |
| Squish sideways | 0.29 | MakeItFrom 0.28 | MIT OCW table 0.28 | +4% | OK |
| Density | 7900 | Outokumpu 7900 | [Wikipedia 304L](https://en.wikipedia.org/wiki/304L) 7900 | 0% | OK |
| Bends-for-good | 200 MPa | Outokumpu 210 (EN min, hot-rolled) | [AeroSpace Metals 304](https://www.aerospacemetals.com/wp-content/uploads/2023/07/AISI-Type-304-Stainless-Steel.pdf) 215 (0.2% offset) | −6% | OK |
| Crack resistance | 231,800 J/m² (K 225) | Granta booklet K 62–150 (mid 106 → 51,450 J/m²) | MIT OCW K 50 (→ 11,450 J/m²) | +637% | **FLAG** |

- **Bends-for-good:** the Library's "EN minimum 200" isn't on the Outokumpu sheet. It shows 210 for hot-rolled sheet and plate and 230 for cold-rolled. MakeItFrom gives 230. Not checked: EN 10088-3 (bars), which may be where 200 comes from.
- **Crack resistance:** two methods give two different numbers.
  - The handbook K tables (Granta, MIT) are the two closest sources.
  - A J-integral test on 304 at room temperature ([ASTM STP 34525](https://store.astm.org/stp34525s.html), abstract) gives about 300,000 J/m² at crack start and about 750,000 J/m² at onset of stable growth.
  - An [Argonne report](https://publications.anl.gov/anlpubs/2003/06/47156.pdf), at 288 °C (not room temperature), says wrought austenitic stainless steels usually exceed 400,000 J/m².
  - The Library's 225 MPa·√m came from averaging 200 (chemeurope) with about 250 (the J test converted to K). That puts it between the two camps: −23% against the J test.

## 3. Aluminium 6061-T6 (already in the Library)

| Value | Library | Source 1 | Source 2 | Off | Status |
|---|---|---|---|---|---|
| Stiffness | 68.9 GPa | [MakeItFrom 6061-T6](https://www.makeitfrom.com/material-properties/6061-T6-Aluminum) 69 | [Wikipedia 6061](https://en.wikipedia.org/wiki/6061) 69 | 0% | OK |
| Squish sideways | 0.33 | [AeroSpace Metals 6061-T6](https://www.aerospacemetals.com/wp-content/uploads/2023/06/Aluminum-6061-T6-6061-T651.pdf) 0.33 | MakeItFrom 0.33 | 0% | OK |
| Density | 2700 | AeroSpace Metals 2700 | MakeItFrom 2700 | 0% | OK |
| Bends-for-good | 276 MPa | AeroSpace Metals 276 (typical) | [Matmatch 6061-T651](https://matmatch.com/materials/mitf351-aa-standards-grade-6061-t651) 276 | 0% | OK |
| Crack resistance | 10,877 J/m² (K 29) | AeroSpace Metals K 29 (T-L) | Matmatch K 29.1 (T-L, 24 °C) | 0% | OK |

- **Bends-for-good:** MakeItFrom and Wikipedia say 270 typical; the Wikipedia minimum is 240.
- **Crack resistance:** Granta gives 22–35 for aluminium alloys in general. Matmatch may be built on the same ASM data as AeroSpace Metals.

## 4. Copper C11000, annealed (already in the Library)

| Value | Library | Source 1 | Source 2 | Off | Status |
|---|---|---|---|---|---|
| Stiffness | 117 GPa | [Copper Development Association C11000](https://alloys.copper.org/alloy/C11000) 117.2 | [MakeItFrom C11000 OS050](https://www.makeitfrom.com/material-properties/Annealed-OS050-C11000-Copper) 120 | −1% | OK |
| Squish sideways | 0.33 | MakeItFrom 0.34 | MIT OCW table 0.35 | −4% | OK |
| Density | 8910 | Copper Development Association 8913 | Granta booklet 8900 | 0% | OK |
| Bends-for-good | 69 MPa | Copper Development Association 68.9 (0.5% extension) | MakeItFrom 69 | 0% | OK |
| Crack resistance | not stored | none valid | none valid | n/a | **No source** |

- **Squish sideways:** the Copper Development Association page gives none, and no source gives 0.33. Engineering ToolBox says 0.36.
- **Crack resistance:** no valid test value exists for annealed pure copper. It is too ductile for a standard test.
  - The closest is a [PMC paper](https://pmc.ncbi.nlm.nih.gov/articles/PMC3587345) on coarse-grained 99.97% copper. Its estimates are 88.5–273 MPa·√m, and the authors say they are not standard-compliant.
  - Granta gives 30–90 for copper alloys in general.
  - The Library's existing "unavailable" reason matches this.

## 5. Titanium Ti-6Al-4V, Grade 5 annealed (new in PR 36)

| Value | Library | Source 1 | Source 2 | Off | Status |
|---|---|---|---|---|---|
| Stiffness | 111 GPa | [AeroSpace Metals Grade 5](https://www.aerospacemetals.com/wp-content/uploads/2023/07/Titanium-Ti-6Al-4V-Grade-5-Annealed.pdf) 113.8 | [Smith Metal B348 bar](https://www.smithmetal.com/pdf/titanium/ti-6al-4v-grade-5.pdf) 114 | −3% | OK |
| Squish sideways | 0.341 | [Wikipedia Ti-6Al-4V](https://en.wikipedia.org/wiki/Ti-6Al-4V) 0.31–0.37 (mid 0.34) | AeroSpace Metals 0.342 | 0% | OK |
| Density | 4450 | AeroSpace Metals 4430 | Smith Metal 4420 | +1% | OK |
| Bends-for-good | 890 MPa | [voestalpine Grade 5](https://www.voestalpine.com/specialtymetals/eu/app/uploads/sites/251/2026/03/Titanium-Grade-5-Ti6Al4V.pdf) 830–1000 (mid 915) | Smith Metal 910 typical | −2% | OK |
| Crack resistance | 64,900 J/m² (K 90.3) | Donachie, via [NIST TN 2065](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.2065.pdf), K 91 | Salem 2008, via NIST TN 2065, K 78–101 (mid 89.5) | 0% | OK, wide spread |

- **Stiffness:** Wikipedia gives 104–113, MakeItFrom 110.
- **Bends-for-good:** minimums are about 827 (AMS 4928) and 828 (Smith Metal).
- **Crack resistance:**
  - The Library's own datasheet (AeroSpace Metals) gives 75. Against that one value alone the Library is +45%.
  - [Wikipedia's fracture toughness table](https://en.wikipedia.org/wiki/Fracture_toughness) gives 84–107 for titanium alloy.
  - NIST also lists 40–93 for other plates. Processing and orientation move it a lot.

## 6. Cartridge brass C26000 (70/30), annealed (new in PR 36)

| Value | Library | Source 1 | Source 2 | Off | Status |
|---|---|---|---|---|---|
| Stiffness | 110 GPa | [Copper Development Association C26000](https://alloys.copper.org/alloy/C26000) 110.3 | [MakeItFrom C26000 OS050](https://www.makeitfrom.com/material-properties/Annealed-OS050-C26000-Brass) 110 | 0% | OK |
| Squish sideways | 0.31 | [Austral Wright C26000](https://www.australwright.com.au/technical-data/alloys/copper-brass/c26000-70-30-brass/) 0.33 | [Engineers Edge](https://engineersedge.com/materials/poissons_ratio_metals_materials_chart_13160.htm) 0.331 (brass) | −6% | OK |
| Density | 8555 | Copper Development Association 8525 | [Concast C26000](https://www.concast.com/files/C26000.pdf) 8530 | 0% | OK |
| Bends-for-good | 107 MPa | Copper Development Association 110 (rod, 0.5% ext) | MakeItFrom 110 | −3% | OK |
| Crack resistance | not stored | not found | not found | n/a | **No source** |

- **Squish sideways:** the Library's 0.31 comes from MakeItFrom only. Matmatch (CuZn30) and Engineering ToolBox say 0.34.
- **Density:** MakeItFrom's 8200 is an outlier.
- **Bends-for-good:** the Copper Development Association flat-product value is 103.
- **Crack resistance:** looked in Wikipedia, the Copper Development Association, MakeItFrom, Austral Wright, Concast, Matmatch and two paper abstracts. Only impact-test (Charpy/Izod) energies were found, and those are not crack resistance.

## 7. Carbon fibre fabric (woven 0/90, epoxy) (new in PR 36)

| Value | Library | Source 1 | Source 2 | Off | Status |
|---|---|---|---|---|---|
| Stiffness | 70 GPa | [ACP Composites](https://acpcomposites.com/wp-content/uploads/2024/05/Mechanical-Properties-of-Carbon-Fiber-Composite-Materials.pdf) 70 | [RS Components carbon/epoxy sheet](https://assets.rs-online.com/v1699614257/Datasheets/94dbd134a6050eb5ac2e6e0ad5307516.pdf) 70 | 0% | OK |
| Squish sideways | 0.10 | ACP 0.10 | [Plymouth University woven CFRP](https://ecm-academics.plymouth.ac.uk/jsummerscales/MATS347/MATS347A2%20E-G-nu.htm) 0.08 | +11% | OK |
| Density | 1600 | ACP 1600 | RS 1600 | 0% | OK |
| Breaking strength | 600 MPa | [Hexcel 8552 AS4 plain weave](https://hexcel.com/wp-content/uploads/2025/12/HexPly_8552_eu_DataSheet1.pdf) 828 | [Toray T700/2510 plain weave](https://thyme.ornl.gov/CFCrush/materials/cmh17/wp3.3-033051-134.pdf) 803 | −26% | **FLAG** |
| Crack resistance | not stored | delamination G_IC 281 J/m² ([Frattura ed Integrità Strutturale 2014](https://doaj.org/article/026f59047e9140ad98be20036de0f597)) | delamination 140–571 J/m² ([NASA TP-2950](https://ntrs.nasa.gov/api/citations/19900000863/downloads/19900000863.pdf)) | n/a | Not stored, delamination only |

- **Stiffness:** Hexcel gives 68 and Toray gives about 56. The [Performance Composites design guide](https://performancecomposites.com/carbon-fiber-design-guide/) gives 55–69 for commercial grade. The "60–200 GPa laminate" wording you saw was not on the two Performance Composites pages I read.
- **Squish sideways:** Toray measured 0.042, so the value really is uncertain.
- **Density:** Toray measured 1501.
- **Breaking strength:**
  - 600 matches ACP's standard fabric.
  - It also matches RS, whose failure strain of 0.85% × 70 GPa works out to about 595 MPa (my calculation).
  - The aerospace prepregs run about 800.
  - Which grade the Library means: commercial, 50% fibre.
- **Crack resistance:** both values are for layers peeling apart, not for a crack cutting across the fabric. No across-the-fabric value was found.
- **Not checked by the app:** the fabric is stiff only along its fibres, and the app treats it as the same in every direction.

## 8. Window glass, soda-lime, annealed (new to the Library in PR 36)

| Value | Library | Source 1 | Source 2 | Off | Status |
|---|---|---|---|---|---|
| Stiffness | 72 GPa | [Pilkington ATS-129](https://www.pilkington.com/-/media/pilkington/site-content/usa/window-manufacturers/technical-bulletins/ats-129---properties-of-soda-lime-silica-float-glass.pdf) 72 | [Glass Association FM05-12](https://www.glass.org/sites/default/files/2023-07/FM05-12_2023_Physical_Mechanical_Properties_Typical_Soda_Lime_Float_Glass.pdf) 71.7 | 0% | OK |
| Squish sideways | 0.23 | Pilkington 0.22 | Glass Association 0.22 | +5% | OK |
| Density | 2500 | Pilkington 2500 | Glass Association 2500 | 0% | OK |
| Breaking strength | 41 MPa | Pilkington 41 (mean, 60 s load) | Glass Association 41 (mean, under 1 min) | 0% | OK |
| Crack resistance | 7.4 J/m² (K 0.75) | [MakeItFrom](https://makeitfrom.com/material-properties/Annealed-Soda-Lime-Glass) K 0.75 | [NIST glass S71d](https://srdata.nist.gov/CeramicDataPortal/Silicate/Glss71d) K 0.75 | 0% | OK |

- **Squish sideways:** the Library's own cited Pilkington says 0.22. MakeItFrom gives 0.23.
- **Breaking strength:** 41 is a bending (modulus of rupture) value for the glass surface. It is not an edge strength and not a direct pulling test.
- **Crack resistance:** NIST also lists a "fracture energy" of 3.86 J/m². That is most likely the surface energy, which is half of G. This is my reading; the page doesn't say.

## 9. Epoxy, unfilled cured resin (new in PR 36)

| Value | Library | Source 1 | Source 2 | Off | Status |
|---|---|---|---|---|---|
| Stiffness | 2.86 GPa | [Chong & Taylor 2013](https://link.springer.com/content/pdf/10.1007%2Fs10853-013-7481-8.pdf) 2.88 | [Carolan et al. 2016](https://spiral.imperial.ac.uk/bitstream/10044/1/32174/9/1-s2.0-S2452321616300130-main.pdf) 2.93 | −2% | OK |
| Squish sideways | 0.35 | [Master Bond](https://www.masterbond.com/node/3161) 0.29–0.34 | [Pandini & Pegoretti](https://pegoretti.dii.unitn.it/resources/Untitled-Folder/Papers/75-Pandini-Poisson-ratio-epoxies_PES-2008.pdf) 0.37–0.41 | −1% | OK, sources differ |
| Density | 1300 | [MakeItFrom Epoxy](https://www.makeitfrom.com/material-properties/Epoxy) 1300 | [Princeton MAE glossary](https://www.princeton.edu/~maelabs/mae324/glos324/epoxy.htm) 1300 | 0% | OK |
| Breaking strength | 63.5 MPa | MakeItFrom 67 | Princeton 60 | 0% | OK |
| Crack resistance | 150 J/m² | Chong & Taylor G_IC 96 (its text says 106) | Carolan et al. G_IC 173 | +12% | OK |

- **Stiffness:** MakeItFrom gives 2.4 and Princeton gives 4.
- **Squish sideways:** no mainstream page gives one. Epoxy's value creeps up with load time.
- **Breaking strength:** Engineering ToolBox gives a range of 26–85.
- **Crack resistance:**
  - Both papers come from the same Imperial College group as the Library's cited paper, so they are not fully independent.
  - Toughness depends on the hardener used.

## 10. Polycarbonate (new in PR 36)

| Value | Library | Source 1 | Source 2 | Off | Status |
|---|---|---|---|---|---|
| Stiffness | 2.4 GPa | [Makrolon GP sheet](https://www.aircraftspruce.com/catalog/pdf/lexandatasheet.pdf) 2.34 | [Omnexus](https://omnexus.specialchem.com/selection-guide/polycarbonate) 2.2–2.5 (mid 2.35) | +2% | OK |
| Squish sideways | 0.37 | Makrolon GP sheet 0.38 | [Tuffak](https://kmac-distribution.com/technical/tuffak_polycarbonate_technical_data.htm) 0.38 | −3% | OK |
| Density | 1205 | [Covestro Makrolon 2405](https://solutions.covestro.com/en/products/makrolon/makrolon-2405_00945088-00009643) 1200 | [Lexan 141](https://protolabs.com/media/hzhnbfyb/lexan-141.pdf) 1200 | 0% | OK |
| Strength (yield) | 65 MPa | Lexan 141 62.0 | Makrolon GP sheet 62.1 | +5% | OK |
| Crack resistance | not stored | [Key, Katz & Parker 1968](https://escholarship.org/content/qt6vv382fk/qt6vv382fk.pdf?t=p0wtff) K 3.6 (room temp) | [Uete & Caddell 1983](https://backend.production.deepblue-documents.lib.umich.edu/server/api/core/bitstreams/e1d560cf-5fb5-4436-9de9-60942057b9ab/content) K 3.06 (at −12 °C) | n/a | Not stored |

- **Stiffness:** Covestro gives 2.4, [Wikipedia](https://en.wikipedia.org/wiki/Polycarbonate) 2.0–2.4, Engineering ToolBox 2.6.
- **Squish sideways:** Wikipedia gives 0.37. This is the second source the Library was missing.
- **Strength:**
  - The yield values above use the same pulling speed, 50 mm/min. Covestro gives 65.
  - Breaking strength: Covestro 65, Makrolon GP 65.5, Lexan 68. Against breaking strength the Library is 0% off.
- **Crack resistance:**
  - These convert to about 4,700 and 3,400 J/m² with the Library's E and ν.
  - Only journal papers had a value. It changes a lot with thickness and loading speed, and the second value is not at room temperature.

## 11. Safety-glass plastic, PVB (new to the Library in PR 36)

| Value | Library | Source 1 | Source 2 | Off | Status |
|---|---|---|---|---|---|
| Stiffness | 33 MPa | [AGC Stratobel](https://www.agc-yourglass.com/sites/default/files/2022-10/Material%20Properties%20of%20PVB%200722_EN_0.pdf) 33 (3 s, 20 °C) | [Eastman Saflex Clear](https://saflex-vanceva.eastman.com/content/dam/saflex/product-pages/saflex-clear/ai-arch-4321_saflex_clear_product_bulletin.pdf) 42 (3 s, 20 °C) | −12% | OK |
| Squish sideways | 0.48 | AGC 0.5 | Saflex 0.5 | −4% | OK |
| Density | 1070 | AGC 1070 | Saflex 1070 | 0% | OK |
| Breaking strength | 20 MPa | Saflex 25 | [Zhang et al. 2015](https://core.ac.uk/download/195659926.pdf) 21.3–24.0 (slowest rate) | −16.1% (midpoint); −13.6% to −18.4% across Zhang's range | Near edge |
| Crack resistance | not stored | Saint-Gobain patent US 7,197,941: tearing 35,100 J/m² (0.38 mm film, 20 °C) | none | n/a | Not stored, one source |

- **Stiffness:**
  - The two sources are at the same load time and temperature.
  - At impact-like rates PVB is about 5–10× stiffer: Zhang et al. measured 184–320 MPa at 245–1360 per second.
  - The Library's 33 is a slow-load lower bound, as its own note says.
- **Squish sideways:** 0.48 is the app's limit.
- **Breaking strength:** the Library's original Trosifol source (">20 MPa") now sits behind a registration page, so it couldn't be re-read.
- **Crack resistance:** glass-to-PVB peel energy (258–660 J/m², [Butchart & Overend](https://www.gft.eng.cam.ac.uk/system/files/documents/butchart-delamination-in-fractured-laminated-glass.pdf)) is a different quantity.

## 12. Natural rubber, vulcanised (new in PR 36)

| Value | Library | Source 1 | Source 2 | Off | Status |
|---|---|---|---|---|---|
| Stiffness | 3 MPa | [Wikipedia Young's modulus](https://en.wikipedia.org/wiki/Young%27s_modulus) 10–100 (mid 55) | [Engineering ToolBox](https://www.engineeringtoolbox.com/young-modulus-d_417.html) 10–100 (mid 55) | −95% | **FLAG** |
| Squish sideways | 0.48 | [Wikipedia Poisson's ratio](https://en.wikipedia.org/wiki/Poisson%27s_ratio) 0.4999 | [Brown University notes](https://www.brown.edu/Departments/Engineering/Courses/En1750/Notes/Elasticity/Elasticity.htm) 0.49 | −3% | OK |
| Density | 930 | [Techniques de l'Ingénieur](https://www.techniques-ingenieur.fr/en/resources/article/ti100/natural-rubber-am8015/natural-rubber-properties-5) 930 | [TSE Industries sheet](https://www.tse-industries.com/wp-content/uploads/Rubber-Material-Properties-Natural-Rubber.pdf) 930 | 0% | OK |
| Breaking strength | 20 MPa | Techniques de l'Ingénieur "about 20 and more" (unfilled) | [KIPP](https://www.kippusa.com/en-us/nr) 10–30 (mid 20) | 0% | OK |
| Crack resistance | not stored | [Rivlin & Thomas 1953](https://www.imechanica.org/sites/default/files/1953%20Rupture%20of%20rubber%20characteristic%20energy%20for%20tearing.pdf) tearing about 13,000 J/m² (unfilled) | [Nian & Suo 2025](https://suo.seas.harvard.edu/resource/510pdf) about 10,000 J/m² (fatigue threshold about 40–50) | n/a | Not stored |

- **Stiffness:** the flag comes from general tables that print 10–100 MPa with no source and no grade (Brown University's notes print the same).
  - Rubber-specific sources are much lower: Nian & Suo 2 MPa, and [NETZSCH](https://analyzing-testing.netzsch.com/en/polymers-netzsch-com/elastomers/nr-natural-rubber) 1–5 MPa. Against these two the Library is +20%.
  - Treloar's data, as fitted in the [Abaqus documentation](https://abaqus-docs.mit.edu/2017/English/SIMACAEBMKRefMap/simabmk-c-rubberfit.htm), gives a shear stiffness of 0.32 MPa, which is about 1 MPa stiffness (my conversion).
  - The Library's "TSE 1–5 MPa" credit is wrong: the TSE sheet has no stiffness value.
- **Squish sideways:** 0.48 is the app's limit.
- **Breaking strength:** TSE gives 27.6 MPa, possibly for reinforced stock.

## 13. Oak, white oak along the grain (new in PR 36)

| Value | Library | Source 1 | Source 2 | Off | Status |
|---|---|---|---|---|---|
| Stiffness | 12.2 GPa | [Wood Handbook 2010, ch. 5](https://www.cedengineering.com/userfiles/S04-019%20-%20Wood%20as%20An%20Engineering%20Material%20-%20Mechanical%20Properties%20of%20Wood%20-%20US.pdf) 12.3 | [The Wood Database](https://www.wood-database.com/white-oak/) 12.15 | 0% | OK |
| Squish sideways | 0.369 | Wood Handbook 0.369 (L-R) | [MakeItFrom Hardwood](https://www.makeitfrom.com/material-properties/Hardwood) 0.37 (generic) | 0% | OK, weak second source |
| Density | 756 | The Wood Database 755 | [Carmona et al. 2020](https://bioresources.cnr.ncsu.edu/wp-content/uploads/2020/05/BioRes_15_3_4960_Carmona_SN_Phys_Mechan_Properties_Clear_Wood_Red_Oak_White_Oak_17125_.pdf) 756 | 0% | OK |
| Strength | 51 MPa (crushing) | Wood Handbook 51.3 | The Wood Database 50.8 | 0% | OK |
| Crack resistance | not stored | red oak K 0.61, G 297 J/m² ([Drvna industrija](https://hrcak.srce.hr/file/413537)) | oak 350–600 J/m² ([Luimes et al. 2018](https://link.springer.com/10.1007/s00226-018-1038-6)) | n/a | Not stored, no white oak value |

- **Stiffness:** [AHEC](https://americanhardwood.org/hi/node/21) gives 12.27 and Carmona 11.3. These are bending tests; the Wood Handbook notes that the true pulling stiffness is a little higher.
- **Squish sideways:** the second source isn't oak-specific. A study of 18 eastern hardwoods (Sliker & Yu 1993) averages 0.403.
- **Strength:**
  - 51 is a crushing strength.
  - Bending strength (MOR) is 105 (Wood Handbook) and 102.3 (The Wood Database).
  - Pulling strength along the grain is about 78 for a different oak ([Missouri S&T](https://web.mst.edu/jthomas/classes/2211/lessons/wood/property_comparison/index.html)) and 87.3 for sessile oak ([Büyüksarı 2018](https://bioresources.cnr.ncsu.edu/?p=12284)). No white oak value was found.
  - So the app's crack-start strength for oak would be about half what a bending or pulling test gives.
- **Crack resistance:** neither source is white oak. Values for oak run 0.29–1.2 MPa·√m depending on crack direction.

---

## Pages tried that gave nothing or refused

None of these were bypassed.

- **Refused:**
  - NIST copper monograph and a govinfo copper PDF (site error and proxy refusal)
  - MakeItFrom's natural rubber page (site error)
  - PMC table pages (a bot check, not worked)
  - Kuraray Trosifol PDFs (registration wall)
  - the 2021 Wood Handbook PDF (blocked to automated readers)
- **No numbers:** Sandia polymer page, the Wikipedia PVB page, and several paper abstracts.
