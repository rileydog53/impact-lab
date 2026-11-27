import AppKit
import SwiftUI

/// Finding saved experiments again (Joseph, 2026-11-26: he could not reopen his carbon-fibre panel, which had been
/// saved deep inside a temporary folder). The app remembers the last files opened or saved and can search the Mac
/// for every saved experiment, wherever it is.
enum SavedExperiments {
    static let recentKey = "recentExperiments"
    static let suffix = ".impact-assembly.json"
    static let recentLimit = 12

    /// A first save with nothing remembered goes here instead of wherever the system dialog last was.
    static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Impact Lab Experiments", isDirectory: true)
    }

    static func prepareDefaultFolder() -> URL {
        try? FileManager.default.createDirectory(at: defaultFolder, withIntermediateDirectories: true)
        return defaultFolder
    }

    static func recent(defaults: UserDefaults = .standard) -> [URL] {
        (defaults.stringArray(forKey: recentKey) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func remember(_ url: URL, defaults: UserDefaults = .standard) {
        var paths = defaults.stringArray(forKey: recentKey) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        defaults.set(Array(paths.prefix(recentLimit)), forKey: recentKey)
    }

    /// Every saved experiment on this Mac that Spotlight knows about. Spotlight is asked rather than the app walking
    /// Desktop and Documents itself, so macOS does not stop to ask for folder access. Runs off the main thread.
    static func findAll() async -> [URL] {
        await Task.detached(priority: .userInitiated) {
            var found = Set<String>()
            let spotlight = Process()
            spotlight.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            spotlight.arguments = ["-name", suffix]
            let pipe = Pipe()
            spotlight.standardOutput = pipe
            spotlight.standardError = FileHandle.nullDevice
            if (try? spotlight.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                spotlight.waitUntilExit()
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where line.hasSuffix(suffix) {
                    found.insert(String(line))
                }
            }
            // Skip the app's own build folders and copies inside source checkouts' test fixtures.
            return found.filter { !$0.contains("/.build/") && !$0.contains("/.git/") }
                .map { URL(fileURLWithPath: $0) }
                .sorted { modified($0) > modified($1) }
        }.value
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    static func title(_ url: URL) -> String {
        let name = url.lastPathComponent
        return name.hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : url.deletingPathExtension().lastPathComponent
    }
}

/// The "Saved Experiments" window: recent files first, then everything the search finds, each with Open and
/// Show in Finder.
struct SavedExperimentsSheet: View {
    let open: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recent = SavedExperiments.recent()
    @State private var all: [URL]?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved experiments").font(.headline)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("New saves go to Documents › Impact Lab Experiments unless you pick another folder.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                Section("Opened or saved recently") {
                    if recent.isEmpty {
                        Text("None yet. Files you open or save from now on appear here.").foregroundStyle(.secondary)
                    }
                    ForEach(recent, id: \.self) { row($0) }
                }
                Section("All saved experiments on this Mac") {
                    if let all {
                        if all.isEmpty { Text("No saved experiments found.").foregroundStyle(.secondary) }
                        ForEach(all, id: \.self) { row($0) }
                    } else {
                        HStack { ProgressView().controlSize(.small); Text("Searching this Mac…").foregroundStyle(.secondary) }
                    }
                }
            }
            .listStyle(.inset)
        }
        .padding(16)
        .frame(width: 640, height: 480)
        .task { all = await SavedExperiments.findAll() }
    }

    private func row(_ url: URL) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(SavedExperiments.title(url)).lineLimit(1)
                Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                     + " · " + SavedExperiments.modified(url).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .controlSize(.small)
            Button("Open") { dismiss(); open(url) }
                .controlSize(.small).buttonStyle(.borderedProminent)
        }
    }
}
