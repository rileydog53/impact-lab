import Foundation

// Literature values for the materials added to the Library on 2026-11-25. Each number and its arithmetic
// (average of two sources that agree, or of the two closest of three) is in docs/library-materials.md.
// Units: GPa, kg/m³, MPa. Toughness values are experimental. Post-yield hardening of the new metals is
// illustrative: a straight line from yield to the tensile strength at 12% plastic strain, because no source
// gave a measured flow curve (the same convention as the existing metals' "illustrative" hardening).

enum TitaniumValues {
    static let young = 111.0, density = 4450.0, poisson = 0.341
    static let flow: [(Double, Double)] = [(0, 890), (0.12, 938)]
    static let sourceName = "Wikipedia Ti-6Al-4V; AeroSpace Metals Grade 5 annealed datasheet"
    static let url = "https://en.wikipedia.org/wiki/Ti-6Al-4V"
    static let evidence = "Weight, stiffness, squish and 890 MPa yield: average of Wikipedia and the AeroSpace Metals datasheet, which agree. Tensile strength 938 MPa. Hardening between them is illustrative."
}

enum BrassValues {
    static let young = 110.0, density = 8555.0, poisson = 0.31
    static let flow: [(Double, Double)] = [(0, 107), (0.12, 327)]
    static let sourceName = "Copper Development Association C26000; MakeItFrom C26000 OS050"
    static let url = "https://alloys.copper.org/alloy/C26000"
    static let evidence = "Annealed (OS050) yield 107 MPa and tensile strength 327 MPa from MakeItFrom and the CDA, which agree. Weight: average of the CDA 8530 and Wikipedia 8580 (MakeItFrom 8200 dropped). Squish sideways from one source. Hardening between yield and tensile strength is illustrative."
}

enum EpoxyValues {
    static let young = 2.86, density = 1300.0, poisson = 0.35, strength = 63.5
    static let sourceName = "MakeItFrom Epoxy; Princeton MAE 324 epoxy notes; PMC polymer tables"
    static let url = "https://www.makeitfrom.com/material-properties/Epoxy"
    static let evidence = "Unfilled cured resin. Stiffness: average of the two closest of five values (2.79 and 2.93 GPa). Breaking strength: average of 60 and 67 MPa (30 MPa outlier dropped). Varies a lot with hardener and cure. Brittle: no permanent bending."
    static let crackEnergy = 150.0
    static let crackURL = "https://spiral.imperial.ac.uk/bitstream/10044/1/32174/2/AJK.ECF.DC.pdf"
    static let crackCitation = "Bulk epoxy G_IC about 150 J/m²: average of 173 J/m² measured (Imperial College) and 130 J/m² from K_IC 0.65 MPa√m (one source). Strength 63.5 MPa as listed. See docs/library-materials.md."
}

enum PolycarbonateValues {
    static let young = 2.4, density = 1205.0, poisson = 0.37, strength = 65.0
    static let sourceName = "Covestro Makrolon 2405 datasheet; Wikipedia Polycarbonate"
    static let url = "https://en.wikipedia.org/wiki/Polycarbonate"
    static let evidence = "Weight, stiffness and 65 MPa strength agree between the Makrolon datasheet and Wikipedia. Squish sideways from one source. Real polycarbonate also bends for good past 65 MPa; here it springs back."
}

enum RubberValues {
    static let young = 0.003, density = 930.0, poisson = 0.48, strength = 20.0
    static let sourceName = "TSE Industries natural rubber properties; Wikipedia Young's modulus"
    static let url = "https://www.tse-industries.com/wp-content/uploads/Rubber-Material-Properties-Natural-Rubber.pdf"
    static let evidence = "Stiffness about 3 MPa, the middle of one source's 1-5 MPa; Wikipedia gives 10-100 MPa and no third source was found, so this is low confidence. Real rubber gets stiffer the more it is stretched. Squish sideways is really 0.4999; lowered to the app's limit 0.48."
}

enum OakValues {
    static let young = 12.2, density = 756.0, poisson = 0.369, strength = 51.0
    static let sourceName = "The Wood Database, White Oak; Carmona et al., BioResources 15 (2020)"
    static let url = "https://www.wood-database.com/white-oak/"
    static let evidence = "White oak at 12% moisture, along the grain. Stiffness from bending tests. Strength is the crushing strength along the grain (51 MPa); pulling strength along the grain was not found. Wood is much weaker and softer across the grain, which this app cannot show (its materials are the same in all directions)."
}
