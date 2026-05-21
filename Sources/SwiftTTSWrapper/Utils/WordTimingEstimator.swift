import Foundation

/// Utility to estimate word boundaries based on average speaking rate and word lengths.
public enum WordTimingEstimator {
    /// Estimates word boundaries for a given text string.
    /// - Parameters:
    ///   - text: The text string to analyze.
    ///   - wordsPerMinute: The speaking rate in words per minute. Defaults to 150.
    /// - Returns: An array of estimated `WordBoundary` objects.
    public static func estimate(text: String, wordsPerMinute: Int = 150) -> [WordBoundary] {
        let words = text.split { $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }

        let msPerWord = (60.0 * 1000.0) / Double(wordsPerMinute)
        var wordBoundaries: [WordBoundary] = []
        var currentTimeMs = 0.0

        for word in words {
            // Apply length factor so longer words take proportionally more time.
            let lengthFactor = max(0.5, min(2.0, Double(word.count) / 5.0))
            let duration = msPerWord * lengthFactor

            wordBoundaries.append(WordBoundary(
                text: word,
                offset: Int(currentTimeMs),
                duration: Int(duration)
            ))

            currentTimeMs += duration
        }

        return wordBoundaries
    }
}
