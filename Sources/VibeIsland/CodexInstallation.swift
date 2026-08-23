import AppKit
import Foundation

/// Centralizes Codex discovery so distribution builds do not depend on one
/// user's home directory, shell configuration, or application display name.
enum CodexInstallation {
    static let applicationBundleIdentifier = "com.openai.codex"

    static func applicationURL() -> URL? {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: applicationBundleIdentifier
        )
    }

    static func executablePath(override: String? = nil) -> String? {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let override, !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }

        if let applicationURL = applicationURL() {
            candidates.append(applicationURL.appendingPathComponent("Contents/Resources/codex"))
            candidates.append(applicationURL.appendingPathComponent("Contents/MacOS/codex"))
        }

        let home = fileManager.homeDirectoryForCurrentUser
        candidates.append(home.appendingPathComponent(".local/bin/codex"))

        let pathEntries = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init) ?? []
        candidates.append(contentsOf: pathEntries.map {
            URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("codex")
        })

        // GUI applications receive a minimal PATH, so include the two standard
        // package-manager locations as portable fallbacks.
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/codex"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/codex"))

        var visited = Set<String>()
        return candidates.first { url in
            visited.insert(url.standardizedFileURL.path).inserted
                && fileManager.isExecutableFile(atPath: url.path)
        }?.path
    }
}

enum AppMetadata {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "development"
    }
}
