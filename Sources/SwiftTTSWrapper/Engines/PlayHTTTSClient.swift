import Foundation

/// PlayHT TTS Client wrapping the PlayHT API.
public final class PlayHTTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var voice = "s3://voice-cloning-zero-shot/d9ff78ba-d016-47f6-b0ef-dd630f59414e/female-cs/manifest.json"
    private var voiceEngine = "PlayHT2.0"
    private var outputFormat = "mp3"

    public override init(credentials: TTSCredentials = [:]) {
        super.init(credentials: credentials)
        player.onStart = { [weak self] in self?.onStart?() }
        player.onEnd = { [weak self] in self?.onEnd?() }
        player.onBoundary = { [weak self] boundary in self?.onBoundary?(boundary) }
        player.onError = { [weak self] error in self?.onError?(error) }
    }

    public override func checkCredentials() async -> Bool {
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["PLAYHT_API_KEY"]
        let user = credentials["userId"] ?? ProcessInfo.processInfo.environment["PLAYHT_USER_ID"]
        guard let apiKey = key, !apiKey.isEmpty, let userId = user, !userId.isEmpty else {
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
        let processed = processText(text, options: options, engine: .playht)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["PLAYHT_API_KEY"]
        let user = credentials["userId"] ?? ProcessInfo.processInfo.environment["PLAYHT_USER_ID"]
        guard let apiKey = key, !apiKey.isEmpty, let userId = user, !userId.isEmpty else {
            throw NSError(domain: "PlayHTTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing PlayHT apiKey or userId"])
        }

        let urlString = "https://api.play.ht/api/v2/tts/stream"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "PlayHTTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid PlayHT URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "content-type")
        request.addValue("audio/mpeg", forHTTPHeaderField: "accept")
        request.addValue(apiKey, forHTTPHeaderField: "AUTHORIZATION")
        request.addValue(userId, forHTTPHeaderField: "X-USER-ID")

        let selectedVoice = options?.voice ?? voice
        let selectedEngine = selectedVoice.hasPrefix("s3://") ? "PlayHT2.0" : "PlayHT1.0"

        let body: [String: Any] = [
            "text": text,
            "voice": selectedVoice,
            "output_format": outputFormat,
            "voice_engine": selectedEngine
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "PlayHTTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        return data
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let processed = processText(text, options: options, engine: .playht)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["PLAYHT_API_KEY"]
        let user = credentials["userId"] ?? ProcessInfo.processInfo.environment["PLAYHT_USER_ID"]
        guard let apiKey = key, !apiKey.isEmpty, let userId = user, !userId.isEmpty else {
            throw NSError(domain: "PlayHTTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing PlayHT apiKey or userId"])
        }

        let urlString = "https://api.play.ht/api/v2/tts/stream"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "PlayHTTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid PlayHT URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "content-type")
        request.addValue("audio/mpeg", forHTTPHeaderField: "accept")
        request.addValue(apiKey, forHTTPHeaderField: "AUTHORIZATION")
        request.addValue(userId, forHTTPHeaderField: "X-USER-ID")

        let selectedVoice = options?.voice ?? voice
        let selectedEngine = selectedVoice.hasPrefix("s3://") ? "PlayHT2.0" : "PlayHT1.0"

        let body: [String: Any] = [
            "text": text,
            "voice": selectedVoice,
            "output_format": outputFormat,
            "voice_engine": selectedEngine
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "PlayHTTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
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
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["PLAYHT_API_KEY"]
        let user = credentials["userId"] ?? ProcessInfo.processInfo.environment["PLAYHT_USER_ID"]
        guard let apiKey = key, !apiKey.isEmpty, let userId = user, !userId.isEmpty else {
            return []
        }

        // PlayHT voice lists come from two endpoints: standard voices and cloned voices.
        let standardVoices = try await fetchVoicesFromURL("https://api.play.ht/api/v2/voices", apiKey: apiKey, userId: userId)
        let clonedVoices = try await fetchVoicesFromURL("https://api.play.ht/api/v2/cloned-voices", apiKey: apiKey, userId: userId)

        var allVoices = [UnifiedVoice]()
        allVoices.append(contentsOf: standardVoices)
        allVoices.append(contentsOf: clonedVoices)
        return allVoices
    }

    private func fetchVoicesFromURL(_ urlString: String, apiKey: String, userId: String) async throws -> [UnifiedVoice] {
        guard let url = URL(string: urlString) else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "accept")
        request.addValue(apiKey, forHTTPHeaderField: "AUTHORIZATION")
        request.addValue(userId, forHTTPHeaderField: "X-USER-ID")

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

            let genderStr = voiceObj["gender"] as? String ?? ""
            let gender: UnifiedVoice.Gender = (genderStr.lowercased() == "female") ? .female : (genderStr.lowercased() == "male") ? .male : .unknown

            let languageCode = voiceObj["language_code"] as? String ?? "en-US"
            let languageName = voiceObj["language"] as? String ?? "English"
            let iso = languageCode.split(separator: "-").first.map(String.init) ?? "eng"

            let lang = UnifiedVoice.LanguageCode(bcp47: languageCode, iso639_3: iso, display: languageName)

            return UnifiedVoice(id: id, name: name, gender: gender, provider: "playht", languageCodes: [lang])
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
