# New materials: room-temperature literature values (research only)

Rule applied: two sources that roughly agree; if they conflict, a third, then average the two closest. Nothing invented; "not found" where nothing turned up. Fracture values marked "experimental". All sources opened 2026-11-25.
Source codes (S1, S2, ...) are listed at the bottom with URLs.

## 1. Titanium alloy Ti-6Al-4V (Grade 5, annealed)

| Property | Value used | Arithmetic / sources |
|---|---|---|
| Density | 4450 kg/m3 | S1 4429-4512 (mid 4470.5); S2 4430. Avg = (4470.5+4430)/2 = 4450 |
| Young's modulus | 111 GPa | S1 104-113 (mid 108.5); S2 113.8. Avg = 111.2 (S3 says 114, consistent) |
| Poisson ratio | 0.341 | S1 0.31-0.37 (mid 0.34); S2 0.342. Avg = 0.341 |
| Yield | 890 MPa | S1 880-920 (mid 900); S2 880. Avg = 890 |
| Tensile (UTS) | 938 MPa | S1 900-950 (mid 925); S2 950. Avg = 937.5 |
| True flow stress vs plastic strain | not found | No source opened gave a curve |
| K_IC (experimental) | about 90 MPa*sqrt(m) | Conflict: S2 75; S4 (NIST, citing Donachie) 91; S4 (citing Salem 2008, mill annealed) 78-101, mid 89.5. Two closest: 91 and 89.5. Avg = 90.3. Literature spread is wide (S4 also lists 43-93 for other plates; S5 gives 84-107) |

Caveat: toughness varies a lot with plate processing and orientation.

## 2. Cartridge brass C26000 (70/30), annealed (OS050 temper, about 0.050 mm grain)

| Property | Value used | Arithmetic / sources |
|---|---|---|
| Density | 8555 kg/m3 | Conflict: S6 8200 (outlier); S7 8530 (specific gravity 8.53); S8 rolled/drawn brass 8430-8730 (mid 8580). Two closest: 8530 and 8580. Avg = 8555 |
| Young's modulus | 110 GPa | S6 110; S7 16,000 ksi = 110.3. Avg = 110.2 |
| Poisson ratio | 0.31 | S6 only (second source not found) |
| Yield | 107 MPa | S6 OS050 110; S7 OS050 flat 15 ksi = 103.4. Avg = 106.7 |
| Tensile (UTS) | 327 MPa | S6 OS050 330; S7 OS050 flat 47 ksi = 324.1. Avg = 327 |
| True flow stress vs plastic strain | not found | |
| K_IC / G_IC | not found | |

Caveat: annealed brass is very soft; the finer OS025 temper is stronger (S6 350 UTS / 140 yield, S7 51 ksi / 19 ksi).

## 3. Bulk cured epoxy (unfilled bisphenol-A, DGEBA)

| Property | Value used | Arithmetic / sources |
|---|---|---|
| Density | 1300 kg/m3 | S9 1300; S10 1.3 Mg/m3 (1300); S11 table 1160 (outlier). Two closest: 1300 and 1300 |
| Young's modulus | 2.86 GPa | Conflict: S9 2.4; S12 2.789; S13 2.93; S10 4; S11 4.1. Two closest: 2.789 and 2.93. Avg = 2.86 |
| Poisson ratio | 0.35 | S11 0.35; S14 "about 0.35 in the glassy state" (from literature) |
| Yield | n/a (brittle) | Imperial paper gives compressive yield 94 MPa only (S13); not used |
| Tensile (UTS) | 63.5 MPa | Conflict: S9 67; S10 60; S12 76.1; S11 30 (outlier). Two closest: 60 and 67. Avg = 63.5 |
| G_IC (experimental) | about 150 J/m2 | S13 173 (measured, diluent-modified DGEBA anhydride cure). S14 cites K_IC 0.6-0.7 (DGEBA + dicyandiamide); at 0.65, G = K^2(1-nu^2)/E = 0.4225e12 x 0.8775 / 2.86e9 = 130 J/m2 (my derived conversion). Avg = (173+130)/2 = 151 |
| K_IC (experimental) | 0.6-0.7 MPa*sqrt(m) | S14 (quoting literature); one source |

Caveat: values depend on hardener and cure; amino-acid cures in S14 span K_IC 0.48-1.34.

## 4. Polycarbonate (general purpose)

| Property | Value used | Arithmetic / sources |
|---|---|---|
| Density | 1205 kg/m3 | S15 (Makrolon 2405) 1200; S16 Wikipedia 1200-1220 (mid 1210); S17 1200-1220. Avg of S15 and S16 = 1205 |
| Young's modulus | 2.4 GPa | S15 2400 (ISO 527); S17 2.2-2.5 (mid 2.35); S16 2.0-2.4 (mid 2.2). Two closest: 2400 and 2350. Avg = 2.375 (round 2.4) |
| Poisson ratio | 0.37 | S16 only (second source not found) |
| Yield | 65 MPa | S15 65.0; S17 61-69 (mid 65). Avg = 65 |
| Tensile (UTS) | 65 MPa | S16 55-75 (mid 65); S17 stress at break 55-77 (mid 66); S15 break 65. Two closest: 65 and 65 |
| K_IC / G_IC | not found | |

Caveat: ductile, so after yield it stretches and necks; strength drops at cold or notched conditions.

## 5. Natural rubber (vulcanised, gum)

| Property | Value used | Arithmetic / sources |
|---|---|---|
| Density | 930 kg/m3 | S18 0.93; S19 0.93; S20 0.91-0.93. Avg of first two = 930 |
| Young's modulus | about 3 MPa (low confidence) | Conflict, no third found: S20 1-5 MPa (mid 3); S21 Wikipedia "rubber, small strain" 10-100 MPa (0.01-0.1 GPa). Used S20 mid; flagged as unresolved |
| Poisson ratio | 0.4999 | S22 Wikipedia (rubber); second source not found |
| Yield | n/a (rubbery) | |
| Tensile (UTS) | about 20 MPa | S18 "of the order of 20 MPa and more" (unfilled); S23 3-29 MPa (mid 16) and S24 4-35 (mid 19.5); S19 4000+ psi = 27.6 (reinforced). Two closest: 20 and 19.5. Avg = 19.8 |
| Elongation at break | 100-1000 % | S23, S24 (wide); S19 500 % |
| K_IC / G_IC | not found | |

Caveat: stiffness depends strongly on strain (not a straight line) and gum rubber stretches several times its length.

## 6. Oak (white oak, Quercus alba), along the grain, 12 % moisture

| Property | Value used | Arithmetic / sources |
|---|---|---|
| Density | 756 kg/m3 | S25 (Wood Database) 755; S26 (BioResources, 12.5 % MC) 756; S27 (AHEC) 769; Wikipedia Wood table 680 (oven-dry basis, outlier). Two closest: 755 and 756. Avg = 755.5 |
| Young's modulus (bending, along grain) | 12.2 GPa | S25 12.15; S28 (Wood Handbook ch. 4 as hosted by CED) 12.3. Avg = 12.2 |
| Poisson ratio (L-R plane) | 0.369 | S28 only (also L-T 0.428); second source not found |
| Yield | n/a; crushing strength along grain 51 MPa | S25 50.8; S28 51.3. Avg = 51.05 |
| Tensile (UTS) along grain | not found | |
| K_IC / G_IC | not found | |

Caveat: wood is much weaker across the grain, and the 12 % figure is the average clear wood; knots and grain slope lower it. Note: S29 (OSU) lists white oak MOE 1,030,000 psi and red oak specific gravity 0.54; these contradict the Wood Handbook and were not used.

## Sources (all opened)

- S1 Wikipedia Ti-6Al-4V: https://en.wikipedia.org/wiki/Ti-6Al-4V
- S2 Aerospace Metals Ti-6Al-4V Grade 5 annealed datasheet: https://www.aerospacemetals.com/wp-content/uploads/2023/07/Titanium-Ti-6Al-4V-Grade-5-Annealed.pdf
- S3 Wikipedia Young's modulus: https://en.wikipedia.org/wiki/Young%27s_modulus
- S4 NIST Technical Note 2065 (Section 7.7.1, Table 10 K_IC literature): https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.2065.pdf
- S5 Wikipedia Fracture toughness: https://en.wikipedia.org/wiki/Fracture_toughness
- S6 MakeItFrom Annealed OS050 C26000 Brass: https://www.makeitfrom.com/material-properties/Annealed-OS050-C26000-Brass (OS025 page: https://www.makeitfrom.com/material-properties/Annealed-OS025-C26000-Brass)
- S7 Copper Development Association C26000: https://alloys.copper.org/alloy/C26000 (density/modulus also at https://www.concast.com/c26000.php)
- S8 Wikipedia Brass: https://en.wikipedia.org/wiki/Brass
- S9 MakeItFrom Epoxy: https://www.makeitfrom.com/material-properties/Epoxy
- S10 Princeton MAE epoxy glossary: https://swh.princeton.edu/~maelabs/mae324/glos324/epoxy.htm
- S11 Polymers 2021 table (epoxy 1.16 g/cm3, 4.1 GPa, nu 0.35, 30 MPa): https://pmc.ncbi.nlm.nih.gov/articles/PMC8659156/table/polymers-13-04116-t001
- S12 PMC table (epoxy resin tensile 2789 MPa, 76.1 MPa): https://pmc.ncbi.nlm.nih.gov/articles/PMC11461999/table/tbl3
- S13 Imperial College paper (G_IC 173 J/m2, E 2.93 GPa): https://spiral.imperial.ac.uk/bitstream/10044/1/32174/2/AJK.ECF.DC.pdf
- S14 Polymers 2023, 15, 385 (DGEBA with amino acids; K_IC, nu 0.35): https://epub.uni-bayreuth.de/7558/1/polymers-15-00385.pdf
- S15 Covestro Makrolon 2405 datasheet: https://quickparts.com/wp-content/uploads/2024/05/Makrolon-2405PC.pdf
- S16 Wikipedia Polycarbonate: https://en.wikipedia.org/wiki/Polycarbonate
- S17 Omnexus polycarbonate guide: https://omnexus.specialchem.com/selection-guide/polycarbonate
- S18 Techniques de l'Ingenieur natural rubber: https://techniques-ingenieur.fr/en/resources/article/ti100/natural-rubber-am8015/v1/natural-rubber-properties-5
- S19 TSE Industries natural rubber sheet: https://www.tse-industries.com/wp-content/uploads/Rubber-Material-Properties-Natural-Rubber.pdf
- S20 Netzsch NR: https://analyzing-testing.netzsch.com/en/polymers-netzsch-com/elastomers/nr-natural-rubber
- S21 Wikipedia Young's modulus (see S3)
- S22 Wikipedia Poisson's ratio: https://en.wikipedia.org/wiki/Poisson%27s_ratio
- S23 Miki Pulley vulcanized rubber: https://www.mikipulley.co.jp/en/resources/selection-calculation-guide-general-properties-vulcanized-rubber
- S24 Matmatch natural rubber: https://matmatch.com/materials/mbas118-natural-rubber-nr-
- S25 Wood Database white oak: https://www.wood-database.com/white-oak/
- S26 BioResources 15(3) red/white oak: https://bioresources.cnr.ncsu.edu/wp-content/uploads/2020/05/BioRes_15_3_4960_Carmona_SN_Phys_Mechan_Properties_Clear_Wood_Red_Oak_White_Oak_17125_.pdf
- S27 AHEC American white oak: https://americanhardwood.org/hi/node/21 (page layout garbled; labels inferred)
- S28 Wood Handbook ch. 4 (via CED Engineering): https://www.cedengineering.com/userfiles/S04-019 - Wood as An Engineering Material - Mechanical Properties of Wood - US.pdf
- S29 OSU fact sheet (not used, conflicts): https://pods.okstate.edu/fact-sheets/FAPC-162pod.pdf
