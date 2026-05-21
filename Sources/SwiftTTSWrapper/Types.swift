import Foundation

/// Options for customising the speech synthesis request.
public struct SpeakOptions {
    public var rate: SpeechRate?
    public var pitch: SpeechPitch?
    public var volume: Float? // Clamped 0.0 to 1.0
    public var voice: String?
    public var format: AudioFormat?
    public var useSpeechMarkdown: Bool
    public var useWordBoundary: Bool
    public var rawSSML: Bool
    public var extraOptions: [String: Any]?

    public init(
        rate: SpeechRate? = nil,
        pitch: SpeechPitch? = nil,
        volume: Float? = nil,
        voice: String? = nil,
        format: AudioFormat? = nil,
        useSpeechMarkdown: Bool = false,
        useWordBoundary: Bool = false,
        rawSSML: Bool = false,
        extraOptions: [String: Any]? = nil
    ) {
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
        self.voice = voice
        self.format = format
        self.useSpeechMarkdown = useSpeechMarkdown
        self.useWordBoundary = useWordBoundary
        self.rawSSML = rawSSML
        self.extraOptions = extraOptions
    }
}

/// Representation of speech speed.
public enum SpeechRate: String, Codable, CaseIterable {
    case xSlow = "x-slow"
    case slow = "slow"
    case medium = "medium"
    case fast = "fast"
    case xFast = "x-fast"

    public var rateValue: Float {
        switch self {
        case .xSlow: return 0.25
        case .slow: return 0.40
        case .medium: return 0.50
        case .fast: return 0.65
        case .xFast: return 0.80
        }
    }
}

/// Representation of speech pitch.
public enum SpeechPitch: String, Codable, CaseIterable {
    case xLow = "x-low"
    case low = "low"
    case medium = "medium"
    case high = "high"
    case xHigh = "x-high"

    public var pitchValue: Float {
        switch self {
        case .xLow: return 0.5
        case .low: return 0.8
        case .medium: return 1.0
        case .high: return 1.2
        case .xHigh: return 1.5
        }
    }
}

/// Unified audio formats supported by the client engines.
public enum AudioFormat: String, Codable {
    case mp3, wav, ogg, opus, aac, flac, pcm
}

/// Input source to be synthesized or played.
public enum SpeakInput {
    case text(String)
    case file(URL)
    case bytes(Data)
    case stream(AsyncThrowingStream<Data, Error>)
}

/// A standardized representation of voices across all engines.
public struct UnifiedVoice: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var gender: Gender
    public var provider: String
    public var languageCodes: [LanguageCode]

    public enum Gender: String, Codable {
        case male = "Male"
        case female = "Female"
        case unknown = "Unknown"
    }

    public struct LanguageCode: Codable, Equatable {
        public var bcp47: String
        public var iso639_3: String
        public var display: String

        public init(bcp47: String, iso639_3: String, display: String) {
            self.bcp47 = bcp47
            self.iso639_3 = iso639_3
            self.display = display
        }
    }

    public init(id: String, name: String, gender: Gender, provider: String, languageCodes: [LanguageCode]) {
        self.id = id
        self.name = name
        self.gender = gender
        self.provider = provider
        self.languageCodes = languageCodes
    }
}

/// Metadata mapping timing offset details for spoken words.
public struct WordBoundary: Codable, Equatable {
    public var text: String
    public var offset: Int // millisecond offset from speech start
    public var duration: Int // duration in milliseconds

    public init(text: String, offset: Int, duration: Int) {
        self.text = text
        self.offset = offset
        self.duration = duration
    }
}

/// Credentials payload structure for cloud endpoints.
public typealias TTSCredentials = [String: String]
