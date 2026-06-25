import Foundation

/// Murf AI TTS Client wrapping the Murf API.
public final class MurfTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var model = "GEN2"
    private var voice = "en-US-natalie"
    private var baseURL = "https://api.murf.ai/v1"

    public static let voices = [
        UnifiedVoice(id: "en-US-natalie", name: "Natalie", gender: .female, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "en-US-owen", name: "Owen", gender: .male, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "en-US-amira", name: "Amira", gender: .female, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "en-US-daniel", name: "Daniel", gender: .male, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "en-US-taylor", name: "Taylor", gender: .female, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "en-US-alex", name: "Alex", gender: .male, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "en-US-emily", name: "Emily", gender: .female, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "en-US-ben", name: "Ben", gender: .male, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "en-US-claire", name: "Claire", gender: .female, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "en-US-glen", name: "Glen", gender: .male, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "de-DE-detlef", name: "Detlef", gender: .male, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "de-DE", iso639_3: "deu", display: "German (Germany)")
        ]),
        UnifiedVoice(id: "es-ES-rosalyn", name: "Rosalyn", gender: .female, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "es-ES", iso639_3: "spa", display: "Spanish (Spain)")
        ]),
        UnifiedVoice(id: "fr-FR-henri", name: "Henri", gender: .male, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "fr-FR", iso639_3: "fra", display: "French (France)")
        ]),
        UnifiedVoice(id: "pt-BR-thomas", name: "Thomas", gender: .male, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "pt-BR", iso639_3: "por", display: "Portuguese (Brazil)")
        ]),
        UnifiedVoice(id: "it-IT-giulia", name: "Giulia", gender: .female, provider: "murf", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "it-IT", iso639_3: "ita", display: "Italian (Italy)")
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

    public override func checkCredentials() async -> Bool {
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["MURF_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            return false
        }
        if apiKey.lowercased().hasPrefix("test") || apiKey.lowercased().contains("fake") || apiKey.count < 10 {
            return false
        }
        return true
    }

    public override func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data {
        let processed = processText(text, options: options, engine: .murf)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["MURF_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "MurfTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Murf apiKey"])
        }

        let selectedVoice = options?.voice ?? voice
        let selectedModel = options?.extraOptions?["model"] as? String ?? model
        let isFalcon = selectedModel == "FALCON"

        let urlStr = isFalcon ? "\(baseURL)/speech/stream" : "\(baseURL)/speech/generate"
        guard let url = URL(string: urlStr) else {
            throw NSError(domain: "MurfTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "api-key")

        var body: [String: Any] = [
            "voiceId": selectedVoice,
            "text": text
        ]

        if isFalcon {
            body["model"] = "FALCON"
        } else {
            body["encodeAsBase64"] = true
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "MurfTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        if isFalcon {
            return data
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base64String = json["encodedAudio"] as? String,
              let audioData = Data(base64Encoded: base64String) else {
            throw NSError(domain: "MurfTTSClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response or encodedAudio"])
        }

        return audioData
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let processed = processText(text, options: options, engine: .murf)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["MURF_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "MurfTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Murf apiKey"])
        }

        guard let url = URL(string: "\(baseURL)/speech/stream") else {
            throw NSError(domain: "MurfTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "api-key")

        let selectedVoice = options?.voice ?? voice
        let selectedModel = options?.extraOptions?["model"] as? String ?? model

        let body: [String: Any] = [
            "voiceId": selectedVoice,
            "text": text,
            "model": selectedModel
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "MurfTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
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
        return MurfTTSClient.voices
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
