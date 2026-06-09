import Foundation

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
}
