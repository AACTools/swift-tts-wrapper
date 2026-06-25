import Foundation
import SpeechMarkdown

/// Unified interface for all Text-to-Speech clients.
public protocol TTSClient: AnyObject {
    /// Associated credentials for cloud client engines.
    var credentials: TTSCredentials { get set }

    /// Event handler invoked when speech begins.
    var onStart: (() -> Void)? { get set }

    /// Event handler invoked when speech completes successfully.
    var onEnd: (() -> Void)? { get set }

    /// Event handler invoked when a word boundary is reached (supplying text and timing offsets).
    var onBoundary: ((WordBoundary) -> Void)? { get set }

    /// Event handler invoked when an error occurs during processing or playback.
    var onError: ((Error) -> Void)? { get set }

    /// Speaks the given input (text, audio file, raw bytes, or stream).
    func speak(_ input: SpeakInput, options: SpeakOptions?) async throws

    /// Speaks the given text string.
    func speak(_ text: String, options: SpeakOptions?) async throws

    /// Synthesizes text to raw audio bytes (typically MP3 or WAV).
    func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data

    /// Synthesizes text to a stream of audio chunks.
    func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error>

    /// Lists all unified voices available from this engine.
    func getVoices() async throws -> [UnifiedVoice]
    
    /// Pauses audio playback.
    func pause()
    
    /// Resumes audio playback.
    func resume()
    
    /// Stops audio playback and resets the player state.
    func stop()
    
    /// Validates whether the current credentials are correct.
    func checkCredentials() async -> Bool
}

/// Abstract base implementation that provides common helpers and properties.
open class AbstractTTSClient: NSObject, TTSClient, @unchecked Sendable {
    public var credentials: TTSCredentials

    public var onStart: (() -> Void)?
    public var onEnd: (() -> Void)?
    public var onBoundary: ((WordBoundary) -> Void)?
    public var onError: ((Error) -> Void)?

    public override init() {
        self.credentials = [:]
        super.init()
    }

    public init(credentials: TTSCredentials = [:]) {
        self.credentials = credentials
        super.init()
    }

    /// Speaks the given input. Must be overridden by subclasses.
    open func speak(_ input: SpeakInput, options: SpeakOptions?) async throws {
        preconditionFailure("speak(_:options:) must be overridden by subclass")
    }

    /// Speaks the given text string (overload helper).
    public func speak(_ text: String, options: SpeakOptions? = nil) async throws {
        try await speak(.text(text), options: options)
    }

    /// Synthesizes text to bytes. Must be overridden by subclasses.
    open func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data {
        preconditionFailure("synthToBytes(_:options:) must be overridden by subclass")
    }

    /// Synthesizes text to a stream of audio chunks. Defaults to a single-chunk stream of the entire synthesized bytes.
    open func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let bytes = try await synthToBytes(text, options: options)
        return AsyncThrowingStream { continuation in
            continuation.yield(bytes)
            continuation.finish()
        }
    }

    /// Lists available voices. Must be overridden by subclasses.
    open func getVoices() async throws -> [UnifiedVoice] {
        preconditionFailure("getVoices() must be overridden by subclass")
    }

    /// Pauses audio playback. Optional implementation.
    open func pause() {}

    /// Resumes audio playback. Optional implementation.
    open func resume() {}

    /// Stops audio playback. Optional implementation.
    open func stop() {}

    /// Validates credentials. Defaults to true for local/system engines.
    open func checkCredentials() async -> Bool {
        return true
    }

    public func constructProsodyTag(_ text: String, options: SpeakOptions?) -> String {
        var attrs: [String] = []
        if let rate = options?.rate, rate != .medium {
            attrs.append("rate=\"\(rate.rawValue)\"")
        }
        if let pitch = options?.pitch, pitch != .medium {
            attrs.append("pitch=\"\(pitch.rawValue)\"")
        }
        if let volume = options?.volume {
            let pct = Int(min(max(volume, 0), 1.0) * 100)
            if pct != 100 {
                attrs.append("volume=\"\(pct)\"")
            }
        }
        if attrs.isEmpty { return text }
        return "<prosody \(attrs.joined(separator: " "))>\(text)</prosody>"
    }

    // MARK: - SpeechMarkdown & SSML Helpers

    /// Result of processing input text through the markdown/SSML pipeline.
    public struct ProcessedText {
        /// The processed text (may be SSML or plain text)
        public let text: String
        /// Whether the processed text is SSML
        public let isSSML: Bool
    }

    private static let markdownParser = SpeechMarkdownParser()

    /// Detects whether the string looks like SpeechMarkdown.
    public static func looksLikeMarkdown(_ text: String) -> Bool {
        return markdownParser.isSpeechMarkdown(input: text)
    }

    /// Detects whether the string is already SSML (starts with `<speak`).
    public static func isSSML(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("<speak")
    }

    /// Converts SpeechMarkdown to SSML for the given platform.
    public static func convertMarkdownToSSML(_ text: String, platform: String) -> String? {
        return try? markdownParser.toSsml(input: text, platform: platform)
    }

    /// Converts SpeechMarkdown to plain text (strips all markup).
    public static func convertMarkdownToText(_ text: String) -> String? {
        return try? markdownParser.toText(input: text)
    }

    /// Strips all SSML tags and unescapes XML entities, returning plain text.
    public static func stripSSML(_ ssml: String) -> String {
        var result = ssml
        // Replace self-closing tags (break, mark, etc.) with space to avoid fusing words
        result = result.replacingOccurrences(of: #"<[^>/]+/>"#, with: " ", options: .regularExpression)
        // Remove all remaining opening/closing tags
        result = result.replacingOccurrences(of: #"</?[a-zA-Z][^>]*>"#, with: "", options: .regularExpression)
        // Unescape XML entities
        result = result.replacingOccurrences(of: "&amp;apos;", with: "'")
        result = result.replacingOccurrences(of: "&amp;quot;", with: "\"")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        // Collapse whitespace
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Processes input text through the SpeechMarkdown/SSML pipeline.
    ///
    /// Handles auto-detection of SpeechMarkdown, conversion to SSML (for SSML-capable engines)
    /// or plain text (for non-SSML engines), and raw SSML passthrough.
    ///
    /// - Parameters:
    ///   - text: The input text
    ///   - options: Speak options (may be nil)
    ///   - engine: The engine that will process the text
    /// - Returns: Processed text and whether it's SSML
    public func processText(_ text: String, options: SpeakOptions?, engine: TTSEngine) -> ProcessedText {
        // Raw SSML passthrough
        if options?.rawSSML == true {
            return ProcessedText(text: text, isSSML: true)
        }

        // Already SSML
        if Self.isSSML(text) {
            return ProcessedText(text: text, isSSML: true)
        }

        // SpeechMarkdown conversion (explicit or auto-detected)
        let shouldConvert = options?.useSpeechMarkdown == true || Self.looksLikeMarkdown(text)
        if shouldConvert {
            if engine.supportsSSML {
                if let ssml = Self.convertMarkdownToSSML(text, platform: engine.speechMarkdownPlatform) {
                    return ProcessedText(text: ssml, isSSML: true)
                }
            } else {
                if let plainText = Self.convertMarkdownToText(text) {
                    return ProcessedText(text: plainText, isSSML: false)
                }
            }
        }

        return ProcessedText(text: text, isSSML: false)
    }
}
