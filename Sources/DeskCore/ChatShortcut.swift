import Foundation

public enum ChatShortcut: Equatable {
    case website(URL)
    case folder(URL)
    case reveal(URL)

    public static func destination(_ url: URL, home: String = NSHomeDirectory()) -> Self? {
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            guard let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
            return .website(url)
        }
        let prefix = "herdrdesk-path:"
        guard url.absoluteString.hasPrefix(prefix),
              let path = url.absoluteString.dropFirst(prefix.count).removingPercentEncoding,
              path.utf8.count <= 4096, !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              path.hasPrefix("~/") || (path.hasPrefix("/") && !path.hasPrefix("//")) else { return nil }
        let expanded = path.hasPrefix("~/") ? home + String(path.dropFirst()) : path
        if let target = localItem(expanded) { return target }

        // A copied file reference may include its editor line and column.
        let file = expanded.replacingOccurrences(of: #":[0-9]+(?::[0-9]+)?$"#, with: "", options: .regularExpression)
        return file == expanded ? nil : localItem(file)
    }

    private static func localItem(_ path: String) -> Self? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard let info = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isPackageKey, .isSymbolicLinkKey]) else { return nil }
        if info.isSymbolicLink == true || info.isPackage == true { return .reveal(url) }
        if info.isDirectory == true { return .folder(url) }
        if info.isRegularFile == true { return .reveal(url) }
        return nil
    }
}
