import Foundation

/// Mistral AI TTS Client wrapping the Mistral API.
public final class MistralTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var model = "voxtral-mini-tts-2603"
    private var voice = "Amalthea"
    private var responseFormat = "mp3"
    private var baseURL = "https://api.mistral.ai/v1"

    public static let voices = [
        "Amalthea", "Achan", "Brave", "Contessa", "Daintree", "Eugora", "Fornax",
        "Griffin", "Hestia", "Irving", "Jasmine", "Kestra", "Lorentz", "Mara",
        "Nettle", "Orin", "Puck", "Quinn", "Rune", "Simbe", "Tertia", "Umbriel",
        "Vesta", "Wystan", "Xeno", "Yara", "Zephyr"
    ].map { name in
        UnifiedVoice(id: name, name: name, gender: .unknown, provider: "mistral", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ])
    }

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
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["MISTRAL_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            return false
        }
        if apiKey.lowercased().hasPrefix("test") || apiKey.lowercased().contains("fake") || apiKey.count < 10 {
            return false
        }
        guard let url = URL(string: "\(baseURL)/models") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }

    public override func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data {
        let processed = processText(text, options: options, engine: .mistral)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["MISTRAL_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "MistralTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Mistral apiKey"])
        }

        guard let url = URL(string: "\(baseURL)/audio/speech") else {
            throw NSError(domain: "MistralTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let selectedVoice = options?.voice ?? voice
        let selectedModel = options?.extraOptions?["model"] as? String ?? model
        let format = options?.extraOptions?["responseFormat"] as? String ?? responseFormat

        var body: [String: Any] = [
            "model": selectedModel,
            "input": text,
            "response_format": format
        ]
        if !selectedVoice.isEmpty {
            body["voice_id"] = selectedVoice
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "MistralTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base64String = json["audio_data"] as? String,
              let audioData = Data(base64Encoded: base64String) else {
            throw NSError(domain: "MistralTTSClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response or audio_data"])
        }

        return audioData
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let processed = processText(text, options: options, engine: .mistral)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["MISTRAL_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "MistralTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Mistral apiKey"])
        }

        guard let url = URL(string: "\(baseURL)/audio/speech") else {
            throw NSError(domain: "MistralTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")

        let selectedVoice = options?.voice ?? voice
        let selectedModel = options?.extraOptions?["model"] as? String ?? model
        let format = options?.extraOptions?["responseFormat"] as? String ?? responseFormat

        var body: [String: Any] = [
            "model": selectedModel,
            "input": text,
            "response_format": format,
            "stream": true
        ]
        if !selectedVoice.isEmpty {
            body["voice_id"] = selectedVoice
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "MistralTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var lineBuffer = ""
                    for try await byte in bytes {
                        guard let char = String(bytes: [byte], encoding: .ascii) else { continue }
                        lineBuffer.append(char)
                        if lineBuffer.hasSuffix("\n") {
                            let line = lineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                            lineBuffer = ""
                            if line.hasPrefix("data: ") {
                                let dataStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                                if dataStr != "[DONE]" && !dataStr.isEmpty {
                                    if let jsonData = dataStr.data(using: .utf8),
                                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                       json["type"] as? String == "speech.audio.delta",
                                       let base64 = json["audio_data"] as? String,
                                       let chunk = Data(base64Encoded: base64) {
                                        continuation.yield(chunk)
                                    }
                                }
                            }
                        }
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
        return MistralTTSClient.voices
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
