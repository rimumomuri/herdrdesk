import Foundation

/// The macOS alert sounds a user can pick for HerdrDesk notifications.
public enum SystemSounds {
    public static let folder = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)

    /// Sound names (file name without extension), sorted; hidden and non-sound files are skipped.
    public static func names(in folder: URL = folder) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return files.filter { !$0.hasPrefix(".") && ["aiff", "aif", "wav", "caf"].contains(($0 as NSString).pathExtension.lowercased()) }
            .map { ($0 as NSString).deletingPathExtension }.sorted()
    }

    /// Only a name from the listed sounds is played, so the page cannot ask for an arbitrary path.
    public static func allowed(_ name: String, in names: [String]) -> Bool { !name.isEmpty && names.contains(name) }
}
