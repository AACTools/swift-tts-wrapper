import Foundation

public final class UnrealSpeechTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var voice = "Sierra"
    private var audioFormat = "mp3"
    private var baseURL = "https://api.v8.unrealspeech.com"

    public static let voices = [
        UnifiedVoice(id: "Sierra", name: "Sierra", gender: .female, provider: "unrealspeech", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "Dan", name: "Dan", gender: .male, provider: "unrealspeech", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "Will", name: "Will", gender: .male, provider: "unrealspeech", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "Scarlett", name: "Scarlett", gender: .female, provider: "unrealspeech", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "Liv", name: "Liv", gender: .female, provider: "unrealspeech", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "Amy", name: "Amy", gender: .female, provider: "unrealspeech", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "Eric", name: "Eric", gender: .male, provider: "unrealspeech", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "Brian", name: "Brian", gender: .male, provider: "unrealspeech", languageCodes: [
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

    public override func checkCredentials() async -> Bool {
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["UNREAL_SPEECH_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            return false
        }
        if apiKey.lowercased().hasPrefix("test") || apiKey.lowercased().contains("fake") || apiKey.count < 10 {
            return false
        }
        do {
            guard let url = URL(string: "\(baseURL)/speech") else { return false }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "Text": "test",
                "VoiceId": "Sierra",
                "AudioFormat": "mp3",
                "OutputFormat": "uri"
            ])
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode != 401
            }
            return false
        } catch {
            return false
        }
    }

    public override func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data {
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["UNREAL_SPEECH_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "UnrealSpeechTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Unreal Speech apiKey"])
        }

        guard let url = URL(string: "\(baseURL)/speech") else {
            throw NSError(domain: "UnrealSpeechTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let selectedVoice = options?.voice ?? voice
        let selectedFormat = options?.extraOptions?["audioFormat"] as? String ?? audioFormat

        var body: [String: Any] = [
            "Text": text,
            "VoiceId": selectedVoice,
            "AudioFormat": selectedFormat,
            "OutputFormat": "uri"
        ]
        if let providerOptions = options?.extraOptions?["providerOptions"] as? [String: Any] {
            body.merge(providerOptions) { _, new in new }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "UnrealSpeechTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outputUri = json["OutputUri"] as? String,
              let downloadUrl = URL(string: outputUri) else {
            throw NSError(domain: "UnrealSpeechTTSClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response or missing OutputUri"])
        }

        let (audioData, downloadResponse) = try await URLSession.shared.data(from: downloadUrl)
        if let httpDownload = downloadResponse as? HTTPURLResponse, httpDownload.statusCode != 200 {
            throw NSError(domain: "UnrealSpeechTTSClient", code: httpDownload.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to download audio from \(outputUri)"])
        }

        return audioData
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["UNREAL_SPEECH_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "UnrealSpeechTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Unreal Speech apiKey"])
        }

        guard let url = URL(string: "\(baseURL)/stream") else {
            throw NSError(domain: "UnrealSpeechTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let selectedVoice = options?.voice ?? voice
        let selectedFormat = options?.extraOptions?["audioFormat"] as? String ?? audioFormat

        var body: [String: Any] = [
            "Text": text,
            "VoiceId": selectedVoice,
            "AudioFormat": selectedFormat
        ]
        if let providerOptions = options?.extraOptions?["providerOptions"] as? [String: Any] {
            body.merge(providerOptions) { _, new in new }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "UnrealSpeechTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
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
            let boundaries = options?.useWordBoundary == true ? WordTimingEstimator.estimate(text: text) : []
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
        return UnrealSpeechTTSClient.voices
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
