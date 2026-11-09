import Foundation

/// Looks up the newest published release on GitHub. Runs only when the user
/// picks "Check for Updates…", so the app never contacts GitHub on its own.
enum UpdateChecker {
    struct Release: Decodable, Sendable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }

        /// The tag without its leading "v", e.g. "0.1.3".
        var version: String {
            tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }
    }

    /// GitHub excludes drafts and pre-releases from `latest`.
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/marco-scheffler/WhisperLocal/releases/latest")!

    /// The running app's version, or `nil` outside an app bundle (`swift run`).
    static var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "GitHub answered with HTTP \(http.statusCode)."
            ])
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    /// Whether `candidate` is a later version than `current`. Compares the
    /// dot-separated numbers, so "0.1.10" is newer than "0.1.9" and "0.2" equals
    /// "0.2.0".
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = numbers(in: candidate)
        let rhs = numbers(in: current)
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func numbers(in version: String) -> [Int] {
        let trimmed = version.hasPrefix("v") ? version.dropFirst() : Substring(version)
        return trimmed.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
