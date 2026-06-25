import Foundation

/// Hume AI TTS Client wrapping the Hume API.
public final class HumeTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var model = "octave-2"
    private var voice = "ito"
    private var baseURL = "https://api.hume.ai/v0"

    public static let voices = [
        UnifiedVoice(id: "ito", name: "Ito", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "acantha", name: "Acantha", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "ant ai gonus", name: "Antigonos", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "ari", name: "Ari", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "brant", name: "Brant", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "daniel", name: "Daniel", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "fin", name: "Fin", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "hype", name: "Hype", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "kora", name: "Kora", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "mango", name: "Mango", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "marek", name: "Marek", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "ogma", name: "Ogma", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "sora", name: "Sora", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "terrence", name: "Terrence", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "vitor", name: "Vitor", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "zach", name: "Zach", gender: .unknown, provider: "hume", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ])
    ]

    public override init(credentials: TTSCredentials = [:]) {
        super.init(credentials: credentials)
        if let customBase = credentials["baseURL"] {
            self.baseURL = customBase
        }
        player.onStart = { [weak self] in self?.onStart?() }
        player.onEnd = { [weak self] in self?.onEnd?() }
        player.onBoundary = { [weak self] boundary in self?.onBoundary?(boundary) }
        player.onError = { [weak self] error in self?.onError?(error) }
    }

    private func resolveVersion(modelId: String) -> String? {
        if modelId == "octave-2" { return "2" }
        if modelId == "octave-1" { return "1" }
        return nil
    }

    public override func checkCredentials() async -> Bool {
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["HUME_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            return false
        }
        if apiKey.lowercased().hasPrefix("test") || apiKey.lowercased().contains("fake") || apiKey.count < 10 {
            return false
        }
        return true
    }

    public override func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data {
        let processed = processText(text, options: options, engine: .hume)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["HUME_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "HumeTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Hume apiKey"])
        }

        guard let url = URL(string: "\(baseURL)/tts/file") else {
            throw NSError(domain: "HumeTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-Hume-Api-Key")

        let selectedVoice = options?.voice ?? voice
        let selectedModel = options?.extraOptions?["model"] as? String ?? model
        
        var utterance: [String: Any] = ["text": text]
        if !selectedVoice.isEmpty {
            utterance["voice"] = ["name": selectedVoice, "provider": "HUME_AI"]
        }

        var body: [String: Any] = [
            "utterances": [utterance]
        ]
        if let version = resolveVersion(modelId: selectedModel) {
            body["version"] = version
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "HumeTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        return data
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let processed = processText(text, options: options, engine: .hume)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["HUME_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "HumeTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Hume apiKey"])
        }

        guard let url = URL(string: "\(baseURL)/tts/stream/file") else {
            throw NSError(domain: "HumeTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-Hume-Api-Key")

        let selectedVoice = options?.voice ?? voice
        let selectedModel = options?.extraOptions?["model"] as? String ?? model

        var utterance: [String: Any] = ["text": text]
        if !selectedVoice.isEmpty {
            utterance["voice"] = ["name": selectedVoice, "provider": "HUME_AI"]
        }

        var body: [String: Any] = [
            "utterances": [utterance]
        ]
        if let version = resolveVersion(modelId: selectedModel) {
            body["version"] = version
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "HumeTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 4096 {
                            continuation.yield(buffer)
                            buffer = Data()
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public override func speak(_ input: SpeakInput, options: SpeakOptions?) async throws {
        stop()

        switch input {
        case .text(let text):
            let data = try await synthToBytes(text, options: options)
            let plainText = AbstractTTSClient.looksLikeMarkdown(text) ? (AbstractTTSClient.convertMarkdownToText(text) ?? text) : text
            let boundaries = options?.useWordBoundary == true ? WordTimingEstimator.estimate(text: plainText) : []
            try player.play(data: data, boundaries: boundaries)

        case .file(let url):
            try player.play(url: url)

        case .bytes(let data):
            try player.play(data: data)

        case .stream(let stream):
            var data = Data()
            for try await chunk in stream {
                data.append(chunk)
            }
            try player.play(data: data)
        }
    }

    public override func getVoices() async throws -> [UnifiedVoice] {
        return HumeTTSClient.voices
    }

    public override func pause() {
        player.pause()
    }

    public override func resume() {
        player.resume()
    }

    public override func stop() {
        player.stop()
    }
}
