import Foundation
import ImpactPhysics

/// Keeps a body's or experiment's name in step with its material (Joseph, 2026-11-26: "Steel ball" kept its name
/// after he made it titanium). Only a name that contains the old material's word is changed, and only that word:
/// "Steel ball" becomes "Titanium ball"; a name he typed himself without a material word is left alone.
enum MaterialNaming {
    /// Words that mean each Library material inside a name, longest first so "Stainless steel" wins over "Steel".
    private static let words: [String: [String]] = [
        "structural-steel-a36": ["Steel"],
        "stainless-304-annealed": ["Stainless steel", "Stainless"],
        "aluminum-6061-t6": ["Aluminium", "Aluminum"],
        "copper-c11000-annealed": ["Copper"],
        "titanium-ti6al4v-annealed": ["Titanium"],
        "brass-c26000-annealed": ["Brass"],
        "carbon-fibre-epoxy-fabric": ["Carbon-fibre", "Carbon fibre", "Carbon-fiber", "Carbon fiber", "Carbon"],
        "soda-lime-glass": ["Window glass", "Glass"],
        "pvb-interlayer": ["Safety-glass plastic", "PVB"],
        "epoxy-bulk": ["Epoxy"],
        "polycarbonate": ["Polycarbonate"],
        "natural-rubber": ["Rubber"],
        "oak-along-grain": ["Oak wood", "Oak", "Wood"],
    ]

    /// The short word used for a material in a name.
    static func word(for provenance: MaterialProvenance) -> String {
        let key = provenance.referenceID ?? provenance.id
        if let first = words[key]?.first { return first }
        // A material the user made: the first word or two of its own name.
        return provenance.name.split(separator: " ").prefix(2).joined(separator: " ")
    }

    /// `name` with the old material's word swapped for the new one's, or `name` unchanged when it has no such word.
    static func renamed(_ name: String, from old: MaterialProvenance?, to new: MaterialProvenance?) -> String {
        guard let old, let new else { return name }
        let oldKey = old.referenceID ?? old.id
        let newKey = new.referenceID ?? new.id
        guard oldKey != newKey, let candidates = words[oldKey] else { return name }
        let replacement = word(for: new)
        for candidate in candidates {
            guard let range = wholeWord(candidate, in: name) else { continue }
            let found = name[range]
            let fitted = found.first?.isLowercase == true ? replacement.lowercased() : replacement
            return String(name.replacingCharacters(in: range, with: fitted).prefix(48))
        }
        return name
    }

    private static func wholeWord(_ word: String, in text: String) -> Range<String.Index>? {
        var start = text.startIndex
        while let range = text.range(of: word, options: .caseInsensitive, range: start..<text.endIndex) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if !(before?.isLetter ?? false) && !(after?.isLetter ?? false) { return range }
            start = range.upperBound
        }
        return nil
    }
}

extension MaterialProvenance {
    /// A copy of a Library material's label that the user may change: the numbers stay the same, the source stays
    /// attached as "the original", and the app calls it "your version" (Joseph, 2026-11-26: switching to typed
    /// numbers used to throw away the preset's origin, and preset numbers were then called his own).
    func editableCopy() -> MaterialProvenance {
        if isCustom { return self }
        let base = MaterialProfile.libraryProfile(for: self)?.plainName ?? name
        return editableCopy(named: String((base + ", my numbers").prefix(64)))
    }
}
