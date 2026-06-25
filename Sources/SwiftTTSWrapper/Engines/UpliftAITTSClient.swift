import Foundation

public final class UpliftAITTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var voice = "v_8eelc901"
    private var outputFormat = "MP3_22050_128"
    private var baseURL = "https://api.upliftai.org/v1/synthesis"

    public static let voices = [
        UnifiedVoice(id: "v_8eelc901", name: "Info/Education", gender: .unknown, provider: "upliftai", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "ur-PK", iso639_3: "urd", display: "Urdu (Pakistan)")
        ]),
        UnifiedVoice(id: "v_30s70t3a", name: "Nostalgic News", gender: .unknown, provider: "upliftai", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "ur-PK", iso639_3: "urd", display: "Urdu (Pakistan)")
        ]),
        UnifiedVoice(id: "v_yypgzenx", name: "Dada Jee", gender: .unknown, provider: "upliftai", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "ur-PK", iso639_3: "urd", display: "Urdu (Pakistan)")
        ]),
        UnifiedVoice(id: "v_kwmp7zxt", name: "Gen Z (beta)", gender: .unknown, provider: "upliftai", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "ur-PK", iso639_3: "urd", display: "Urdu (Pakistan)")
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
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["UPLIFTAI_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            return false
        }
        if apiKey.lowercased().hasPrefix("test") || apiKey.lowercased().contains("fake") || apiKey.count < 10 {
            return false
        }
        return true
    }

    public override func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data {
        let processed = processText(text, options: options, engine: .upliftai)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["UPLIFTAI_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "UpliftAITTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing UpliftAI apiKey"])
        }

        guard let url = URL(string: "\(baseURL)/text-to-speech/stream") else {
            throw NSError(domain: "UpliftAITTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let selectedVoice = options?.voice ?? voice
        let selectedFormat = options?.extraOptions?["outputFormat"] as? String ?? outputFormat

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "voiceId": selectedVoice,
            "text": text,
            "outputFormat": selectedFormat
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "UpliftAITTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        return data
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let processed = processText(text, options: options, engine: .upliftai)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["UPLIFTAI_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "UpliftAITTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing UpliftAI apiKey"])
        }

        guard let url = URL(string: "\(baseURL)/text-to-speech/stream") else {
            throw NSError(domain: "UpliftAITTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let selectedVoice = options?.voice ?? voice
        let selectedFormat = options?.extraOptions?["outputFormat"] as? String ?? outputFormat

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "voiceId": selectedVoice,
            "text": text,
            "outputFormat": selectedFormat
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "UpliftAITTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
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
        return UpliftAITTSClient.voices
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
