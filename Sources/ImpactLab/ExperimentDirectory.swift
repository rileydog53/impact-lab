import AppKit

/// Remembers the folder the last experiment or export was opened from or saved to, so every file dialog
/// starts there instead of at the system default.
enum ExperimentDirectory {
    static let key = "lastExperimentDirectory"

    /// The remembered folder if it still exists, else the folder of the open file, else nil (system default).
    static func start(fallback: URL? = nil, defaults: UserDefaults = .standard) -> URL? {
        if let path = defaults.string(forKey: key) {
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return fallback
    }

    static func remember(_ file: URL, defaults: UserDefaults = .standard) {
        defaults.set(file.deletingLastPathComponent().path, forKey: key)
    }

    /// Runs an open or save panel that starts in the remembered folder and remembers the folder of the choice.
    /// Returns the chosen URL, or nil when the dialog was cancelled.
    @MainActor static func run(_ panel: NSSavePanel, fallback: URL? = nil) -> URL? {
        panel.directoryURL = start(fallback: fallback?.deletingLastPathComponent())
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        remember(url)
        return url
    }
}
