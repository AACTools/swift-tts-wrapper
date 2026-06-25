import Foundation

/// Cartesia TTS Client wrapping the Cartesia Text-to-Speech REST API.
public final class CartesiaTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var modelId = "sonic-3"
    private var voice = "694f938dd2a74762ba554ff8e2a9d786" // Default female voice
    
    // We request WAV container with PCM s16le encoding since AVSpeech / AVAudioPlayer play WAV PCM out of the box.
    private var outputFormat: [String: Any] = [
        "container": "wav",
        "encoding": "pcm_s16le",
        "sample_rate": 44100
    ]

    public override init(credentials: TTSCredentials = [:]) {
        super.init(credentials: credentials)
        player.onStart = { [weak self] in self?.onStart?() }
        player.onEnd = { [weak self] in self?.onEnd?() }
        player.onBoundary = { [weak self] boundary in self?.onBoundary?(boundary) }
        player.onError = { [weak self] error in self?.onError?(error) }
    }

    public override func checkCredentials() async -> Bool {
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["CARTESIA_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            return false
        }

        if apiKey.lowercased().hasPrefix("test") || apiKey.lowercased().contains("fake") || apiKey.count < 10 {
            return false
        }

        do {
            let voices = try await getVoices()
            return !voices.isEmpty
        } catch {
            return false
        }
    }

    public override func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data {
        let processed = processText(text, options: options, engine: .cartesia)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["CARTESIA_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "CartesiaTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Cartesia apiKey"])
        }

        let baseURL = credentials["baseURL"] ?? "https://api.cartesia.ai"
        let urlString = "\(baseURL)/tts/bytes"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "CartesiaTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Cartesia baseURL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.addValue("2025-04-16", forHTTPHeaderField: "Cartesia-Version")

        let selectedVoice = options?.voice ?? voice
        let selectedModel = (options?.extraOptions?["model"] as? String) ?? modelId

        let body: [String: Any] = [
            "model_id": selectedModel,
            "transcript": text,
            "voice": [
                "mode": "id",
                "id": selectedVoice
            ],
            "output_format": outputFormat
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "CartesiaTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        return data
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let processed = processText(text, options: options, engine: .cartesia)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["CARTESIA_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "CartesiaTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Cartesia apiKey"])
        }

        let baseURL = credentials["baseURL"] ?? "https://api.cartesia.ai"
        let urlString = "\(baseURL)/tts/bytes"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "CartesiaTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Cartesia baseURL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.addValue("2025-04-16", forHTTPHeaderField: "Cartesia-Version")

        let selectedVoice = options?.voice ?? voice
        let selectedModel = (options?.extraOptions?["model"] as? String) ?? modelId

        let body: [String: Any] = [
            "model_id": selectedModel,
            "transcript": text,
            "voice": [
                "mode": "id",
                "id": selectedVoice
            ],
            "output_format": outputFormat
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "CartesiaTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
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
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["CARTESIA_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            return []
        }

        let baseURL = credentials["baseURL"] ?? "https://api.cartesia.ai"
        let urlString = "\(baseURL)/voices"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.addValue("2025-04-16", forHTTPHeaderField: "Cartesia-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        guard let voicesList = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return voicesList.compactMap { voiceObj in
            guard let id = voiceObj["id"] as? String,
                  let name = voiceObj["name"] as? String else {
                return nil
            }

            let description = voiceObj["description"] as? String ?? ""
            let gender: UnifiedVoice.Gender = description.lowercased().contains("female") ? .female : description.lowercased().contains("male") ? .male : .unknown

            let voiceLanguage = voiceObj["language"] as? String ?? "en"
            let iso = voiceLanguage.split(separator: "-").first.map(String.init) ?? "eng"
            let lang = UnifiedVoice.LanguageCode(bcp47: voiceLanguage, iso639_3: iso, display: voiceLanguage)

            return UnifiedVoice(id: id, name: name, gender: gender, provider: "cartesia", languageCodes: [lang])
        }
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
