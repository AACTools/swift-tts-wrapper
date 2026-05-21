import Foundation

/// OpenAI TTS Client wrapping the OpenAI Audio Speech REST API.
public final class OpenAITTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var model = "tts-1"
    private var voice = "alloy"
    private var responseFormat = "mp3"

    public override init(credentials: TTSCredentials = [:]) {
        super.init(credentials: credentials)
        player.onStart = { [weak self] in self?.onStart?() }
        player.onEnd = { [weak self] in self?.onEnd?() }
        player.onBoundary = { [weak self] boundary in self?.onBoundary?(boundary) }
        player.onError = { [weak self] error in self?.onError?(error) }
    }

    public override func checkCredentials() async -> Bool {
        let apiKey = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        guard let key = apiKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        // Fast fail for test/fake keys to avoid invalid HTTP requests during offline testing
        if key.lowercased().hasPrefix("test") || key.lowercased().contains("fake") || key.count < 24 {
            return false
        }

        let baseURL = credentials["baseURL"] ?? "https://api.openai.com/v1"
        guard let url = URL(string: "\(baseURL)/models") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

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
        let apiKey = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        guard let key = apiKey, !key.isEmpty else {
            throw NSError(domain: "OpenAITTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing OpenAI API Key"])
        }

        let baseURL = credentials["baseURL"] ?? "https://api.openai.com/v1"
        guard let url = URL(string: "\(baseURL)/audio/speech") else {
            throw NSError(domain: "OpenAITTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI baseURL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let selectedModel = options?.extraOptions?["model"] as? String ?? model
        let selectedVoice = options?.voice ?? voice
        let selectedFormat = options?.format?.rawValue ?? responseFormat

        // Map unified SpeechRate to OpenAI speed scale (0.25 to 4.0, 1.0 is default)
        var speed: Float = 1.0
        if let rate = options?.rate {
            switch rate {
            case .xSlow: speed = 0.5
            case .slow: speed = 0.75
            case .medium: speed = 1.0
            case .fast: speed = 1.25
            case .xFast: speed = 1.5
            }
        }

        let body: [String: Any] = [
            "model": selectedModel,
            "input": text,
            "voice": selectedVoice,
            "response_format": selectedFormat,
            "speed": speed
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "OpenAITTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        return data
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let apiKey = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        guard let key = apiKey, !key.isEmpty else {
            throw NSError(domain: "OpenAITTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing OpenAI API Key"])
        }

        let baseURL = credentials["baseURL"] ?? "https://api.openai.com/v1"
        guard let url = URL(string: "\(baseURL)/audio/speech") else {
            throw NSError(domain: "OpenAITTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI baseURL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let selectedModel = options?.extraOptions?["model"] as? String ?? model
        let selectedVoice = options?.voice ?? voice
        let selectedFormat = options?.format?.rawValue ?? responseFormat

        var speed: Float = 1.0
        if let rate = options?.rate {
            switch rate {
            case .xSlow: speed = 0.5
            case .slow: speed = 0.75
            case .medium: speed = 1.0
            case .fast: speed = 1.25
            case .xFast: speed = 1.5
            }
        }

        let body: [String: Any] = [
            "model": selectedModel,
            "input": text,
            "voice": selectedVoice,
            "response_format": selectedFormat,
            "speed": speed
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "OpenAITTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
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
        let rawVoices = [
            ("alloy", "Alloy", UnifiedVoice.Gender.unknown),
            ("ash", "Ash", .male),
            ("ballad", "Ballad", .male),
            ("coral", "Coral", .female),
            ("echo", "Echo", .male),
            ("fable", "Fable", .female),
            ("onyx", "Onyx", .male),
            ("nova", "Nova", .female),
            ("sage", "Sage", .male),
            ("shimmer", "Shimmer", .female)
        ]

        let lang = UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")

        return rawVoices.map { id, name, gender in
            UnifiedVoice(id: id, name: name, gender: gender, provider: "openai", languageCodes: [lang])
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
