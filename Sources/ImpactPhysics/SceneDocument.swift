import Foundation

/// Every reason a scene document could not be loaded, each with its location in the file.
public struct SceneDocumentError: LocalizedError, Equatable {
    public let issues: [String]

    public var errorDescription: String? {
        let shown = issues.prefix(12).map { "• " + $0 }.joined(separator: "\n")
        let more = issues.count > 12 ? "\n• …and \(issues.count - 12) more." : ""
        return "This scene cannot be loaded:\n" + shown + more
    }
}

/// Reads the native assembly file format, and also accepts hand-written or
/// generated scenes. Omitted settings take the workshop defaults, bodies may be
/// referred to by name, and reference materials may be named by profile id.
/// Complete files written by `save(to:)` pass through unchanged. Unknown
/// settings are rejected rather than ignored.
enum SceneDocument {
    typealias Object = [String: Any]

    /// Exact JSON values. Numbers stay Swift doubles end to end so a saved
    /// scene reopens bit-for-bit; JSONSerialization can perturb the last digit.
    enum Value: Codable {
        case null, bool(Bool), number(Double), string(String), array([Value]), object([String: Value])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Double.self) { self = .number(value) }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else if let value = try? container.decode([Value].self) { self = .array(value) }
            else { self = .object(try container.decode([String: Value].self)) }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .null: try container.encodeNil()
            case .bool(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            }
        }

        var any: Any {
            switch self {
            case .null: NSNull()
            case .bool(let value): value
            case .number(let value): value
            case .string(let value): value
            case .array(let value): value.map(\.any)
            case .object(let value): value.mapValues(\.any)
            }
        }

        init(_ any: Any) {
            switch any {
            case let value as Bool: self = .bool(value)
            case let value as Double: self = .number(value)
            case let value as Int: self = .number(Double(value))
            case let value as String: self = .string(value)
            case let value as [Any]: self = .array(value.map(Value.init))
            case let value as [String: Any]: self = .object(value.mapValues(Value.init))
            default: self = .null
            }
        }
    }

    static func anyJSON<T: Encodable>(_ value: T) -> Any? {
        (try? JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value)))?.any
    }

    /// The normalized scene data and any problems found while reading it.
    static func normalize(_ data: Data) throws -> (data: Data, issues: [String]) {
        let root: Any
        do { root = try JSONDecoder().decode(Value.self, from: data).any }
        catch { throw SceneDocumentError(issues: ["The file is not valid JSON: \(jsonReason(error))."]) }
        var reader = Reader()
        guard let scene = root as? Object else {
            throw SceneDocumentError(issues: ["The top level must be a JSON object { … } describing one scene."])
        }
        let normalized = reader.scene(scene)
        return (try JSONEncoder().encode(Value(normalized)), reader.issues)
    }

    private static func jsonReason(_ error: Error) -> String {
        var detail: String?
        if case DecodingError.dataCorrupted(let context) = error {
            detail = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String ?? context.debugDescription
        }
        return (detail.map { $0 + " — " } ?? "") + "check for missing or extra commas, quotes or brackets"
    }

    /// Edit distance, used to suggest the setting a typo probably meant.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(1, a.count) where !a.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in 1...max(1, b.count) where !b.isEmpty {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return a.isEmpty ? b.count : row[b.count]
    }

    /// Settings people often expect but the solver cannot represent.
    static let unsupported: [String: String] = {
        let constraint = "use support: \"fixed\" (a rigid, immovable bench or fixture) or \"clampLeft\", \"clampRight\", \"clampBottom\", \"clampTop\" (one edge held); pinned points and partial constraints are not supported"
        var map: [String: String] = [:]
        for key in ["fixed", "anchored", "pinned", "clamped", "constraint", "constraints", "boundaryCondition", "boundaryConditions", "static"] {
            map[key] = constraint
        }
        for key in ["bodyForce", "acceleration", "load", "loads", "force", "pressure"] {
            map[key] = "applied loads and body forces other than gravity are not supported; set the scene's gravity in m/s² (downward), or use initial velocities, contact and connections"
        }
        for key in ["restLength", "pretension", "prestress"] {
            map[key] = "use preload: the starting stretch in metres (positive stretched, negative compressed), springs only"
        }
        for key in ["friction", "frictionCoefficient", "restitution"] {
            map[key] = "contact is frictionless penalty contact; friction and restitution coefficients are not settable"
        }
        for key in ["angularVelocity", "spin", "omega", "rotationRate"] {
            map[key] = "initial rotation rates are not supported; each body starts with one uniform velocity [vx, vy]"
        }
        for key in ["temperature", "strainRate", "rateDependence", "thermal"] {
            map[key] = "temperature and strain-rate dependence are not supported"
        }
        for key in ["timestep", "dt", "timeStep", "stepSize"] {
            map[key] = "the timestep is chosen automatically for stability; set meshResolution or a body's refinement instead"
        }
        map["mass"] = "mass follows from size and density; set material.density"
        map["position"] = "use center: [x, y] in metres"
        map["rotation"] = "use angle, in degrees"
        map["width"] = "use size: [width, height] in metres"
        map["height"] = "use size: [width, height] in metres"
        map["radius"] = "round bodies use size: [diameter x, diameter y] in metres"
        map["diameter"] = "round bodies use size: [diameter x, diameter y] in metres"
        map["youngsModulus"] = "use material.young, in pascals"
        map["E"] = "use material.young, in pascals"
        map["yieldStress"] = "use a material profile or plasticity.table points (strain, stress in pascals)"
        map["failureStrain"] = "metal failure is not supported; illustrative cohesive fracture is set with fracture { strengthFraction, energy }"
        map["fractureToughness"] = "use fracture.energy (J/m²) on an elastic body without a metal profile"
        return map
    }()

    private struct Reader {
        var issues: [String] = []
        /// Part name or id string → canonical UUID string.
        var names: [String: String] = [:]
        var ambiguous: Set<String> = []

        mutating func fail(_ path: String, _ message: String) {
            issues.append("\(path): \(message)" + (message.hasSuffix("?") ? "" : "."))
        }

        mutating func keys(_ object: Object, _ path: String, allowed: Set<String>) {
            for key in object.keys.sorted() where !allowed.contains(key) {
                if let reason = SceneDocument.unsupported[key] { fail("\(path).\(key)", "not supported — \(reason)") }
                else {
                    let near = allowed.filter { $0 != "description" && $0 != "$schema" }
                        .map { ($0, SceneDocument.distance($0.lowercased(), key.lowercased())) }
                        .filter { $0.1 <= max(1, min(3, key.count / 3)) }.min { $0.1 < $1.1 }?.0
                    fail("\(path).\(key)", "unknown setting" + (near.map { "; did you mean \"\($0)\"?" } ?? ". Allowed here: \(allowed.sorted().joined(separator: ", "))"))
                }
            }
        }

        mutating func number(_ value: Any?, _ path: String) -> Double? {
            guard let value else { return nil }
            if !(value is Bool), let n = value as? Double, n.isFinite { return n }
            fail(path, "expected a number")
            return nil
        }

        mutating func point(_ value: Any?, _ path: String) -> [Double]? {
            guard let value else { return nil }
            if let pair = value as? [Any], pair.count == 2 {
                let x = number(pair[0], path + "[0]"), y = number(pair[1], path + "[1]")
                if let x, let y { return [x, y] }
                return nil
            }
            if let object = value as? Object, Set(object.keys) == ["x", "y"],
               let x = number(object["x"], path + ".x"), let y = number(object["y"], path + ".y") { return [x, y] }
            fail(path, "expected a pair of numbers [x, y]")
            return nil
        }

        mutating func string(_ value: Any?, _ path: String) -> String? {
            guard let value else { return nil }
            if let text = value as? String { return text }
            fail(path, "expected text in quotes")
            return nil
        }

        mutating func object(_ value: Any?, _ path: String) -> Object? {
            guard let value else { return nil }
            if let object = value as? Object { return object }
            fail(path, "expected an object { … }")
            return nil
        }

        mutating func array(_ value: Any?, _ path: String) -> [Any]? {
            guard let value else { return nil }
            if let array = value as? [Any] { return array }
            fail(path, "expected a list [ … ]")
            return nil
        }

        mutating func choice(_ value: Any?, _ path: String, _ options: [String: String]) -> String? {
            guard let text = string(value, path) else { return nil }
            let key = text.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
            if let match = options[key] { return match }
            fail(path, "\"\(text)\" is not one of: \(Set(options.values).sorted().joined(separator: ", "))")
            return nil
        }

        mutating func id(_ value: Any?, _ path: String) -> String {
            guard let value else { return UUID().uuidString }
            guard let text = string(value, path) else { return UUID().uuidString }
            return UUID(uuidString: text)?.uuidString ?? UUID().uuidString
        }

        /// Resolves a body reference written as a name or an id.
        mutating func reference(_ value: Any?, _ path: String) -> String? {
            guard let text = string(value, path) else { return nil }
            if ambiguous.contains(text) { fail(path, "more than one body is named \"\(text)\"; give bodies unique names"); return nil }
            if let id = names[text] { return id }
            fail(path, "no body named or with id \"\(text)\". Bodies: \(names.keys.filter { UUID(uuidString: $0) == nil }.sorted().joined(separator: ", "))")
            return nil
        }

        static let resolutions = ["standard": 1, "fine": 2, "extrafine": 3, "x4": 4, "x5": 5, "x6": 6, "x7": 7]

        mutating func resolution(_ value: Any?, _ path: String) -> Int? {
            guard let value else { return nil }
            if let text = value as? String {
                let key = text.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "×", with: "x")
                if let level = Self.resolutions[key] { return level }
            } else if !(value is Bool), let n = value as? Double, let level = Int(exactly: n), (1...7).contains(level) { return level }
            fail(path, "use 1–7 or one of \"standard\", \"fine\", \"extraFine\", \"x4\", \"x5\", \"x6\", \"x7\"")
            return nil
        }

        mutating func scene(_ scene: Object) -> Object {
            keys(scene, "scene", allowed: ["$schema", "description", "assemblyVersion", "parts", "connections", "duration", "monitor",
                                        "relativeTo", "gauges", "meshResolution", "bodyOrder", "groups", "gravity"])
            var out: Object = [:]
            if let version = scene["assemblyVersion"] {
                if number(version, "assemblyVersion") != 1 { fail("assemblyVersion", "only version 1 is supported") }
            }
            out["assemblyVersion"] = 1
            let parts = array(scene["parts"], "parts") ?? []
            // Collect ids and names first so connections can refer to later bodies.
            var partIDs: [String] = []
            for (index, raw) in parts.enumerated() {
                let object = raw as? Object ?? [:]
                let id = id(object["id"], "parts[\(index)].id")
                // A readable id such as "striker" becomes an alias for a generated UUID.
                if let text = object["id"] as? String, UUID(uuidString: text) == nil { names[text] = id }
                partIDs.append(id)
                names[id] = id
                if let name = object["name"] as? String {
                    if names[name] != nil && UUID(uuidString: name) == nil { ambiguous.insert(name) }
                    names[name] = id
                }
            }
            out["parts"] = parts.enumerated().map { index, raw in part(raw, index: index, id: partIDs[index]) }
            out["connections"] = (array(scene["connections"], "connections") ?? []).enumerated().map { connection($1, "connections[\($0)]") }
            out["duration"] = number(scene["duration"], "duration") ?? 0.12
            if let gravity = scene["gravity"] {
                if let flag = gravity as? Bool { out["gravity"] = flag ? AssemblyScene.standardGravity : nil }
                else { out["gravity"] = number(gravity, "gravity") }
            }
            if let monitor = scene["monitor"] { out["monitor"] = reference(monitor, "monitor") }
            if let relative = scene["relativeTo"] { out["relativeTo"] = reference(relative, "relativeTo") }
            if let gauges = array(scene["gauges"], "gauges") {
                out["gauges"] = gauges.enumerated().map { gauge($1, "gauges[\($0)]") }
            }
            if let mesh = scene["meshResolution"] { out["meshResolution"] = resolution(mesh, "meshResolution") }
            if let order = array(scene["bodyOrder"], "bodyOrder") {
                out["bodyOrder"] = order.enumerated().compactMap { reference($1, "bodyOrder[\($0)]") }
            }
            if let groups = array(scene["groups"], "groups") {
                out["groups"] = groups.enumerated().map { index, raw -> Object in
                    let path = "groups[\(index)]"
                    let group = object(raw, path) ?? [:]
                    keys(group, path, allowed: ["id", "members"])
                    let members = array(group["members"], path + ".members") ?? []
                    return ["id": id(group["id"], path + ".id"),
                            "members": members.enumerated().compactMap { reference($1, "\(path).members[\($0)]") }]
                }
            }
            return out
        }

        mutating func part(_ raw: Any, index: Int, id: String) -> Object {
            var path = "parts[\(index)]"
            guard let part = object(raw, path) else { return [:] }
            if let name = part["name"] as? String { path += " \"\(name)\"" }
            keys(part, path, allowed: ["id", "name", "shape", "center", "size", "wall", "angle", "velocity", "material",
                                       "plasticity", "fracture", "refinement", "notch", "bondedLayer", "support", "outline", "description"])
            var out: Object = ["id": id]
            if let name = string(part["name"], path + ".name") { out["name"] = name }
            else { fail(path + ".name", "every body needs a name"); out["name"] = "" }
            out["shape"] = part["shape"].map {
                choice($0, path + ".shape", ["block": "Block", "rectangle": "Block", "enclosure": "Enclosure",
                                             "hollow": "Enclosure", "roundbody": "Round body", "round": "Round body",
                                             "circle": "Round body", "ellipse": "Round body", "outline": "Outline",
                                             "polygon": "Outline"]) ?? "Block"
            } ?? (part["outline"] != nil ? "Outline" : "Block")
            out["center"] = point(part["center"], path + ".center") ?? [0, 0]
            var outlineSize: [Double]?
            if let raw = part["outline"] {
                let outlinePath = path + ".outline"
                if let outline = object(raw, outlinePath) {
                    keys(outline, outlinePath, allowed: ["outer", "holes", "meshSize"])
                    func ring(_ value: Any?, _ ringPath: String) -> [[Double]] {
                        (array(value, ringPath) ?? []).enumerated().compactMap { point($1, "\(ringPath)[\($0)]") }
                    }
                    if outline["outer"] == nil { fail(outlinePath + ".outer", "give the outer boundary as a list of [x, y] points in metres") }
                    let outer = ring(outline["outer"], outlinePath + ".outer")
                    let holes = (array(outline["holes"], outlinePath + ".holes") ?? []).enumerated().map { ring($1, "\(outlinePath).holes[\($0)]") }
                    var result: Object = ["outer": outer, "holes": holes]
                    if let size = outline["meshSize"] { result["meshSize"] = number(size, outlinePath + ".meshSize") }
                    out["outline"] = result
                    if let xs = outer.map(\.[0]) as [Double]?, let ys = outer.map(\.[1]) as [Double]?,
                       let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() {
                        outlineSize = [x1 - x0, y1 - y0]
                    }
                }
            }
            if part["size"] == nil && outlineSize == nil { fail(path + ".size", "give the body's size [width, height] in metres") }
            out["size"] = point(part["size"], path + ".size") ?? outlineSize ?? [0.06, 0.06]
            out["wall"] = number(part["wall"], path + ".wall") ?? 0.012
            out["angle"] = number(part["angle"], path + ".angle") ?? 0
            out["velocity"] = point(part["velocity"], path + ".velocity") ?? [0, 0]
            let (material, plasticity) = material(part["material"], path + ".material", allowPlastic: true)
            out["material"] = material
            if let explicit = part["plasticity"] {
                if plasticity != nil {
                    fail(path + ".plasticity", "the material profile already sets plasticity; use material.elasticOnly instead")
                } else {
                    out["plasticity"] = self.plasticity(explicit, path + ".plasticity")
                }
            } else {
                out["plasticity"] = plasticity ?? ["response": "Elastic", "yieldFraction": 0.016, "hardeningFraction": 0.32]
            }
            if let fracture = object(part["fracture"], path + ".fracture") {
                keys(fracture, path + ".fracture", allowed: ["strengthFraction", "strength", "energy", "energySource", "meshPattern"])
                var result: Object = ["strengthFraction": number(fracture["strengthFraction"], path + ".fracture.strengthFraction") ?? 0.030,
                                      "energy": number(fracture["energy"], path + ".fracture.energy") ?? 7.0]
                if let strength = fracture["strength"] {
                    if fracture["strengthFraction"] != nil {
                        fail(path + ".fracture", "give strength (Pa) or strengthFraction, not both")
                    }
                    if fracture["energy"] == nil {
                        fail(path + ".fracture.energy", "is required with strength: no default is assumed for real-unit fracture energy (J/m²)")
                    }
                    result["strength"] = number(strength, path + ".fracture.strength")
                }
                if let source = object(fracture["energySource"], path + ".fracture.energySource") {
                    keys(source, path + ".fracture.energySource", allowed: ["status", "citation", "url", "caution"])
                    result["energySource"] = source
                }
                if let pattern = fracture["meshPattern"] {
                    result["meshPattern"] = choice(pattern, path + ".fracture.meshPattern", ["aligned": "Aligned", "staggered": "Staggered"])
                }
                out["fracture"] = result
            }
            if let refinement = part["refinement"] { out["refinement"] = resolution(refinement, path + ".refinement") }
            if let support = part["support"] {
                out["support"] = choice(support, path + ".support", ["fixed": "Fixed support", "fixedsupport": "Fixed support",
                    "bench": "Fixed support", "ground": "Fixed support", "clampleft": "Clamp left edge", "clampleftedge": "Clamp left edge",
                    "clampright": "Clamp right edge", "clamprightedge": "Clamp right edge", "clampbottom": "Clamp bottom edge",
                    "clampbottomedge": "Clamp bottom edge", "clamptop": "Clamp top edge", "clamptopedge": "Clamp top edge"])
            }
            if let notch = object(part["notch"], path + ".notch") {
                keys(notch, path + ".notch", allowed: ["centerFraction", "widthFraction", "depthFraction"])
                out["notch"] = ["centerFraction": number(notch["centerFraction"], path + ".notch.centerFraction") ?? 0,
                                "widthFraction": number(notch["widthFraction"], path + ".notch.widthFraction") ?? 0.20,
                                "depthFraction": number(notch["depthFraction"], path + ".notch.depthFraction") ?? 0.20]
            }
            if let layer = object(part["bondedLayer"], path + ".bondedLayer") {
                let layerPath = path + ".bondedLayer"
                keys(layer, layerPath, allowed: ["interfaceFraction", "material", "third"])
                var result: Object = ["interfaceFraction": number(layer["interfaceFraction"], layerPath + ".interfaceFraction") ?? 0.5,
                                      "material": layer["material"] == nil
                                        ? ["young": 2e6, "density": 2000, "poisson": 0]
                                        : self.material(layer["material"], layerPath + ".material", allowPlastic: false).0]
                if let third = object(layer["third"], layerPath + ".third") {
                    keys(third, layerPath + ".third", allowed: ["interfaceFraction", "material"])
                    result["third"] = ["interfaceFraction": number(third["interfaceFraction"], layerPath + ".third.interfaceFraction") ?? 0.75,
                                       "material": self.material(third["material"], layerPath + ".third.material", allowPlastic: false).0]
                }
                out["bondedLayer"] = result
            }
            return out
        }

        /// Returns the material, plus plasticity when a reference profile was named.
        mutating func material(_ raw: Any?, _ path: String, allowPlastic: Bool) -> (Object, Object?) {
            let fallback: Object = ["young": 1e6, "density": 1000, "poisson": 0]
            guard let raw else { return (fallback, nil) }
            var profileID: String?
            var elasticOnly = !allowPlastic
            if let text = raw as? String { profileID = text }
            else if let object = object(raw, path) {
                if object["profile"] != nil {
                    keys(object, path, allowed: ["profile", "elasticOnly"])
                    profileID = string(object["profile"], path + ".profile")
                    if let flag = object["elasticOnly"] {
                        if let flag = flag as? Bool { elasticOnly = elasticOnly || flag }
                        else { fail(path + ".elasticOnly", "expected true or false") }
                    }
                } else {
                    keys(object, path, allowed: ["young", "density", "poisson", "provenance"])
                    var out = fallback
                    for key in ["young", "density", "poisson"] { if let value = number(object[key], "\(path).\(key)") { out[key] = value } }
                    if let provenance = object["provenance"] { out["provenance"] = provenance }
                    return (out, nil)
                }
            } else { return (fallback, nil) }
            guard let profileID else { return (fallback, nil) }
            let key = profileID.lowercased()
            guard let profile = MaterialProfile.references.first(where: { $0.id == key || $0.name.lowercased() == key }) else {
                fail(path, "unknown material profile \"\(profileID)\". Available: \(MaterialProfile.references.map(\.id).joined(separator: ", "))")
                return (fallback, nil)
            }
            var part = AssemblyPart("profile")
            profile.apply(to: &part, elasticOnly: elasticOnly)
            let material = SceneDocument.anyJSON(part.material) as? Object ?? fallback
            let plasticity = SceneDocument.anyJSON(part.plasticity) as? Object
            return (material, plasticity)
        }

        mutating func plasticity(_ raw: Any, _ path: String) -> Object {
            guard let settings = object(raw, path) else { return [:] }
            keys(settings, path, allowed: ["response", "yieldFraction", "hardeningFraction", "table"])
            var out: Object = [
                "response": settings["response"].map { choice($0, path + ".response", ["elastic": "Elastic", "elastoplastic": "Elastoplastic",
                                                                                     "plastic": "Elastoplastic", "j2": "Elastoplastic"]) ?? "Elastic" } ?? "Elastic",
                "yieldFraction": number(settings["yieldFraction"], path + ".yieldFraction") ?? 0.016,
                "hardeningFraction": number(settings["hardeningFraction"], path + ".hardeningFraction") ?? 0.32]
            if let table = object(settings["table"], path + ".table") {
                keys(table, path + ".table", allowed: ["points"])
                let points = (array(table["points"], path + ".table.points") ?? []).enumerated().map { index, raw -> Object in
                    let pointPath = "\(path).table.points[\(index)]"
                    if let pair = raw as? [Any], pair.count == 2 {
                        return ["strain": number(pair[0], pointPath + "[0]") ?? 0, "stress": number(pair[1], pointPath + "[1]") ?? 0]
                    }
                    let point = self.object(raw, pointPath) ?? [:]
                    keys(point, pointPath, allowed: ["strain", "stress"])
                    if point["strain"] == nil || point["stress"] == nil { fail(pointPath, "needs strain and stress (Pa)") }
                    return ["strain": number(point["strain"], pointPath + ".strain") ?? 0,
                            "stress": number(point["stress"], pointPath + ".stress") ?? 0]
                }
                out["table"] = ["points": points]
            }
            return out
        }

        mutating func connection(_ raw: Any, _ path: String) -> Object {
            guard let link = object(raw, path) else { return [:] }
            keys(link, path, allowed: ["id", "first", "second", "firstAnchor", "secondAnchor", "kind", "stiffness", "criticalExtension", "span", "preload"])
            if link["first"] == nil || link["second"] == nil { fail(path, "needs first and second body names") }
            var out: Object = ["id": id(link["id"], path + ".id")]
            out["first"] = reference(link["first"], path + ".first") ?? UUID().uuidString
            out["second"] = reference(link["second"], path + ".second") ?? UUID().uuidString
            out["firstAnchor"] = point(link["firstAnchor"], path + ".firstAnchor") ?? [1, 0]
            out["secondAnchor"] = point(link["secondAnchor"], path + ".secondAnchor") ?? [-1, 0]
            out["kind"] = link["kind"].map { choice($0, path + ".kind", ["spring": "Spring", "breakable": "Breakable", "cohesive": "Breakable"]) ?? "Spring" } ?? "Spring"
            out["stiffness"] = number(link["stiffness"], path + ".stiffness") ?? 12_000.0
            out["criticalExtension"] = number(link["criticalExtension"], path + ".criticalExtension") ?? 0.006
            out["span"] = number(link["span"], path + ".span") ?? 0
            if let preload = link["preload"] { out["preload"] = number(preload, path + ".preload") }
            return out
        }

        mutating func gauge(_ raw: Any, _ path: String) -> Object {
            guard let gauge = object(raw, path) else { return [:] }
            keys(gauge, path, allowed: ["id", "body", "name", "location", "usesBodyFractions"])
            var out: Object = ["id": id(gauge["id"], path + ".id")]
            if gauge["body"] == nil { fail(path + ".body", "name the body the gauge is attached to") }
            out["body"] = reference(gauge["body"], path + ".body") ?? UUID().uuidString
            out["name"] = string(gauge["name"], path + ".name") ?? "Gauge"
            if gauge["location"] == nil { fail(path + ".location", "give the gauge location [x, y]") }
            out["location"] = point(gauge["location"], path + ".location") ?? [0, 0]
            if let fractions = gauge["usesBodyFractions"] {
                if let flag = fractions as? Bool { out["usesBodyFractions"] = flag }
                else { fail(path + ".usesBodyFractions", "expected true or false") }
            }
            return out
        }
    }
}

extension AssemblyScene {
    /// Explains, in the file's own terms, each setting outside what the solver supports.
    public func issues() -> [String] {
        var result: [String] = []
        func range(_ value: Double, _ bounds: ClosedRange<Double>, _ path: String, _ unit: String = "") {
            guard !bounds.contains(value) else { return }
            let format = { (v: Double) in String(format: "%g", v) + unit }
            result.append("\(path) is \(format(value)); allowed \(format(bounds.lowerBound)) to \(format(bounds.upperBound)).")
        }
        func material(_ m: Material, _ path: String) {
            range(m.young, Material.assemblyYoungRange, path + ".young", " Pa")
            range(m.density, Material.assemblyDensityRange, path + ".density", " kg/m³")
            range(m.poisson, Material.assemblyPoissonRange, path + ".poisson")
            if let p = m.provenance, !p.isValid {
                result.append("\(path).provenance is incomplete. Use a profile name such as \"aluminum-6061-t6\", or remove provenance for a custom material.")
            }
        }
        if parts.count > Self.maximumParts { result.append("parts: \(parts.count) bodies; at most \(Self.maximumParts) are accepted (contact checks every pair, so the editor bounds the count).") }
        if connections.count > Self.maximumConnections {
            result.append("connections: \(connections.count); at most \(Self.maximumConnections) are supported.")
        }
        range(duration, Self.durationRange, "duration", " s")
        if let gravity { range(gravity, Self.gravityRange, "gravity", " m/s²") }
        if !parts.isEmpty && parts.allSatisfy({ $0.support?.isFixture == true }) {
            result.append("parts: every body is a fixed support, so nothing can move. Leave at least one body free.")
        }
        let ids = Set(parts.map(\.id))
        if ids.count != parts.count { result.append("parts: two bodies share the same id.") }
        for (i, part) in parts.enumerated() {
            let path = "parts[\(i)] \"\(part.name)\""
            if part.name.isEmpty || part.name.count > 48 { result.append("\(path).name must be 1–48 characters.") }
            let mesh = part.refinement ?? resolution
            range(part.size.x, part.widthRange(resolution: mesh), path + ".size[0] (width)", " m")
            range(part.size.y, part.sizeRange(resolution: mesh), path + ".size[1] (height)", " m")
            if let conflict = part.supportConflict { result.append("\(path).support: \(conflict)") }
            range(part.center.x, AssemblyPart.centerRange, path + ".center[0]", " m")
            range(part.center.y, AssemblyPart.centerRange, path + ".center[1]", " m")
            for issue in part.outlineIssues { result.append("\(path).outline: \(issue)") }
            range(part.angle, -360...360, path + ".angle", "°")
            range(part.velocity.x, AssemblyPart.velocityRange, path + ".velocity[0]", " m/s")
            range(part.velocity.y, AssemblyPart.velocityRange, path + ".velocity[1]", " m/s")
            if part.shape == .enclosure { range(part.wall, 0.005...max(0.005, 0.4 * min(part.size.x, part.size.y)), path + ".wall", " m") }
            material(part.material, path + ".material")
            range(part.plasticity.yieldFraction, ImpactPlasticity.yieldRange, path + ".plasticity.yieldFraction")
            range(part.plasticity.hardeningFraction, ImpactPlasticity.hardeningRange, path + ".plasticity.hardeningFraction")
            if let table = part.plasticity.table, !table.isValid {
                result.append("\(path).plasticity.table needs 2–32 points starting at strain 0, strains increasing up to 1, and stresses 1 Pa to 20 GPa that never decrease.")
            }
            if let fracture = part.fracture {
                if part.shape == .round { result.append("\(path).fracture is not available for round bodies.") }
                if part.shape == .outline { result.append("\(path).fracture is not available for outline bodies yet (crack paths on generated meshes are not yet verified).") }
                if part.material.provenance != nil && !fracture.usesAbsoluteStrength {
                    result.append("\(path).fracture: a metal profile needs fracture.strength in Pa and fracture.energy in J/m² (see the profile's sourced estimate); the fraction-of-E model cannot be combined with a metal profile.")
                }
                if let strength = fracture.strength {
                    range(strength, MaterialFractureSettings.absoluteStrengthRange, path + ".fracture.strength", " Pa")
                } else {
                    range(fracture.strengthFraction, MaterialFractureSettings.strengthRange, path + ".fracture.strengthFraction")
                }
                range(fracture.energy, fracture.activeEnergyRange, path + ".fracture.energy", " J/m²")
            }
            if let notch = part.notch {
                if part.shape != .block { result.append("\(path).notch is available for blocks only.") }
                range(notch.centerFraction, -0.30...0.30, path + ".notch.centerFraction")
                range(notch.widthFraction, 0.12...0.36, path + ".notch.widthFraction")
                range(notch.depthFraction, 0.02...0.45, path + ".notch.depthFraction")
            }
            if let layer = part.bondedLayer {
                let layerPath = path + ".bondedLayer"
                if part.shape != .block { result.append("\(layerPath) is available for blocks only.") }
                if part.fracture != nil || part.notch != nil {
                    result.append("\(layerPath) cannot be combined with fracture or a notch.")
                }
                if part.plasticity.response != .elastic { result.append("\(layerPath) requires an elastic body (bonded regions share nodes).") }
                let bounds = AssemblyPart.BondedLayer.minimumFraction...(1 - AssemblyPart.BondedLayer.minimumFraction)
                range(layer.interfaceFraction, bounds, layerPath + ".interfaceFraction")
                material(layer.material, layerPath + ".material")
                if let third = layer.third {
                    range(third.interfaceFraction, bounds, layerPath + ".third.interfaceFraction")
                    material(third.material, layerPath + ".third.material")
                    if third.interfaceFraction - layer.interfaceFraction < AssemblyPart.BondedLayer.minimumFraction - 1e-12 {
                        result.append("\(layerPath).third.interfaceFraction must be at least 0.1 beyond the first interface.")
                    }
                }
            }
        }
        let name = { (id: UUID) in self.parts.first { $0.id == id }.map { "\"\($0.name)\"" } ?? id.uuidString }
        for (i, link) in connections.enumerated() {
            let path = "connections[\(i)] (\(name(link.first)) → \(name(link.second)))"
            if link.first == link.second { result.append("\(path) joins a body to itself.") }
            if !ids.contains(link.first) || !ids.contains(link.second) { result.append("\(path) refers to a missing body.") }
            range(link.stiffness, 500...250_000, path + ".stiffness", " N/m per m")
            range(link.criticalExtension, 0.0005...0.04, path + ".criticalExtension", " m")
            range(link.span, 0...1.9, path + ".span")
            if let preload = link.preload {
                range(preload, AssemblyConnection.preloadRange, path + ".preload", " m")
                if preload != 0 && link.kind != .spring {
                    result.append("\(path).preload is available for springs only; a breakable link always starts unloaded.")
                }
            }
            for (label, anchor) in [("firstAnchor", link.firstAnchor), ("secondAnchor", link.secondAnchor)] {
                if !(-1...1).contains(anchor.x) || !(-1...1).contains(anchor.y) {
                    result.append("\(path).\(label) must use fractions of the half-size between −1 and 1.")
                } else if abs(anchor.y) + link.span / 2 > 1.000001 {
                    result.append("\(path).\(label): the span extends beyond the body edge.")
                }
            }
        }
        if Set(connections.map(\.id)).count != connections.count { result.append("connections: two connections share an id.") }
        let gauges = gauges ?? []
        if gauges.count > AssemblyGauge.limit { result.append("gauges: at most \(AssemblyGauge.limit) are supported.") }
        if Set(gauges.map(\.id)).count != gauges.count { result.append("gauges: two gauges share an id.") }
        for (i, gauge) in gauges.enumerated() {
            let path = "gauges[\(i)] \"\(gauge.name)\""
            if !ids.contains(gauge.body) { result.append("\(path).body refers to a missing body.") }
            if gauge.name.isEmpty || gauge.name.count > 48 { result.append("\(path).name must be 1–48 characters.") }
            if gauge.usesBodyFractions == true && max(abs(gauge.location.x), abs(gauge.location.y)) > 1 {
                result.append("\(path).location must be between −1 and 1 when usesBodyFractions is true.")
            }
        }
        if let monitor, !ids.contains(monitor) { result.append("monitor refers to a missing body.") }
        if let relativeTo {
            if !ids.contains(relativeTo) { result.append("relativeTo refers to a missing body.") }
            else if relativeTo == (monitor ?? parts.first?.id) { result.append("relativeTo must differ from the monitored body.") }
        }
        let order = bodyOrder ?? []
        if Set(order).count != order.count || !order.allSatisfy(ids.contains) {
            result.append("bodyOrder must list each existing body at most once.")
        }
        let groups = groups ?? []
        let members = groups.flatMap(\.members)
        if Set(groups.map(\.id)).count != groups.count || !groups.allSatisfy({ $0.members.count >= 2 })
            || Set(members).count != members.count || !members.allSatisfy(ids.contains) {
            result.append("groups: each group needs at least two existing bodies, and a body can be in one group only.")
        }
        return result
    }

    /// Decodes a native or hand-written scene and reports every problem found.
    public static func document(_ data: Data) throws -> Self {
        guard data.count <= 512 * 1024 else {
            throw SceneDocumentError(issues: ["The file is \(data.count / 1024) KB; scene files are limited to 512 KB."])
        }
        let (normalized, readIssues) = try SceneDocument.normalize(data)
        // Defaults stand in for unreadable values, so range problems are listed
        // together with structural ones instead of one round at a time.
        guard let scene = try? JSONDecoder().decode(Self.self, from: normalized) else {
            throw SceneDocumentError(issues: readIssues.isEmpty ? ["The scene structure could not be read."] : readIssues)
        }
        let issues = readIssues + scene.issues().filter { issue in
            !readIssues.contains { $0.contains("no body named") } || !issue.contains("missing body")
        }
        guard issues.isEmpty else { throw SceneDocumentError(issues: issues) }
        do { _ = try AssemblySimulation(scene) }
        catch AssemblyError.invalidSettings {
            throw SceneDocumentError(issues: ["The scene is outside the supported ranges."])
        }
        return scene
    }
}
