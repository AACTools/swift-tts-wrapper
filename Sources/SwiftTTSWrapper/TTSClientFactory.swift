import Foundation

/// Supported TTS Engines.
public enum TTSEngine: String, CaseIterable {
    case system
    case openai
    case elevenlabs
    case azure
    case google
    case cartesia
    case playht
    case deepgram
    case fishaudio
    case hume
    case mistral
    case modelslab
    case murf
    case polly
    case resemble
    case unrealspeech
    case upliftai
    case watson
    case witai
    case xai
    case sherpaonnx

    /// The SpeechMarkdown platform string for this engine.
    public var speechMarkdownPlatform: String {
        switch self {
        case .azure: return "microsoft-azure"
        case .google: return "google-assistant"
        case .polly: return "amazon-polly"
        case .watson, .witai: return "ibm-watson"
        case .elevenlabs: return "elevenlabs"
        case .system: return "apple"
        default: return "w3c"
        }
    }
}

/// Factory class to dynamically instantiate TTS Clients.
public enum TTSClientFactory {
    /// Instantiates a TTSClient matching the chosen engine.
    /// - Parameters:
    ///   - engine: The chosen TTSEngine.
    ///   - credentials: Optional credentials payload for the engine (required by cloud engines).
    /// - Returns: A configured instance conforming to TTSClient.
    public static func create(engine: TTSEngine, credentials: TTSCredentials = [:]) -> TTSClient {
        switch engine {
        case .system:
            return SystemTTSClient(credentials: credentials)
        case .openai:
            return OpenAITTSClient(credentials: credentials)
        case .elevenlabs:
            return ElevenLabsTTSClient(credentials: credentials)
        case .azure:
            return AzureTTSClient(credentials: credentials)
        case .google:
            return GoogleTTSClient(credentials: credentials)
        case .cartesia:
            return CartesiaTTSClient(credentials: credentials)
        case .playht:
            return PlayHTTTSClient(credentials: credentials)
        case .deepgram:
            return DeepgramTTSClient(credentials: credentials)
        case .fishaudio:
            return FishAudioTTSClient(credentials: credentials)
        case .hume:
            return HumeTTSClient(credentials: credentials)
        case .mistral:
            return MistralTTSClient(credentials: credentials)
        case .modelslab:
            return ModelsLabTTSClient(credentials: credentials)
        case .murf:
            return MurfTTSClient(credentials: credentials)
        case .polly:
            return PollyTTSClient(credentials: credentials)
        case .resemble:
            return ResembleTTSClient(credentials: credentials)
        case .unrealspeech:
            return UnrealSpeechTTSClient(credentials: credentials)
        case .upliftai:
            return UpliftAITTSClient(credentials: credentials)
        case .watson:
            return WatsonTTSClient(credentials: credentials)
        case .witai:
            return WitAITTSClient(credentials: credentials)
        case .xai:
            return XAITTSClient(credentials: credentials)
        case .sherpaonnx:
            return SherpaOnnxTTSClient(credentials: credentials)
        }
    }
}
