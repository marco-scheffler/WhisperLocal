import Foundation

/// Strips known Whisper hallucinations from a transcript.
///
/// Even after trailing-silence trimming, Whisper occasionally emits a stock
/// "outro" phrase. There are two categories:
///
/// - **Always junk** — subtitle credits ("Untertitel der Amara.org-Community",
///   "Thanks for watching") that never occur in real dictation. Removed
///   wherever they appear at the end, even if they are the whole transcript.
/// - **Trailing junk** — polite sign-offs ("Vielen Dank", "Thank you") that
///   *can* be real speech. Removed only when they trail other content, so a
///   deliberate standalone "Vielen Dank." is preserved.
enum HallucinationFilter {
    /// Subtitle/credit boilerplate — removed unconditionally at the tail.
    private static let alwaysJunk: Set<String> = [
        "untertitel der amara.org-community",
        "untertitelung des zdf, 2020",
        "untertitelung des zdf für funk, 2017",
        "untertitel im auftrag des zdf, 2017",
        "untertitel im auftrag des zdf, 2018",
        "untertitel im auftrag des zdf, 2019",
        "untertitel im auftrag des zdf, 2020",
        "untertitel im auftrag des zdf, 2021",
        "copyright wdr 2020",
        "copyright wdr 2021",
        "subtitles by the amara.org community",
        "thanks for watching",
        "thanks for watching!",
        "thank you for watching",
        "please subscribe",
        "like and subscribe",
    ]

    /// Polite sign-offs — removed only when they trail other content.
    private static let trailingJunk: Set<String> = [
        "vielen dank",
        "vielen dank fürs zuschauen",
        "vielen dank für's zuschauen",
        "danke fürs zuschauen",
        "danke für's zuschauen",
        "untertitel",
        "thank you",
        "thanks",
    ]

    static func strip(_ text: String) -> String {
        var sentences = splitSentences(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !sentences.isEmpty else { return "" }

        var changed = true
        while changed && !sentences.isEmpty {
            changed = false
            let last = normalize(sentences[sentences.count - 1])
            if alwaysJunk.contains(last) {
                sentences.removeLast()
                changed = true
            } else if trailingJunk.contains(last) && sentences.count > 1 {
                sentences.removeLast()
                changed = true
            }
        }

        return sentences.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    /// Splits into sentence-like chunks, keeping each chunk's trailing
    /// punctuation attached so rejoining reproduces the original spacing.
    /// A `.`/`!`/`?`/`…` only ends a sentence when the next character is
    /// whitespace or the end of the string — so "Amara.org" stays intact.
    private static func splitSentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            let isTerminator = ch == "." || ch == "!" || ch == "?" || ch == "…"
            let nextIsBreak = i + 1 >= chars.count || chars[i + 1].isWhitespace
            if isTerminator && nextIsBreak {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { result.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .!?…\"'\n\t"))
    }
}
