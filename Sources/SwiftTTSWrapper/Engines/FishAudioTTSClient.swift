import Foundation

/// Fish Audio TTS Client wrapping the Fish Audio API.
public final class FishAudioTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var model = "s2-pro"
    private var baseURL = "https://api.fish.audio"

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
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["FISH_AUDIO_API_KEY"]
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
        let processed = processText(text, options: options, engine: .fishaudio)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["FISH_AUDIO_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "FishAudioTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Fish Audio apiKey"])
        }

        guard let url = URL(string: "\(baseURL)/v1/tts") else {
            throw NSError(domain: "FishAudioTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let selectedModel = options?.extraOptions?["model"] as? String ?? model
        request.addValue(selectedModel, forHTTPHeaderField: "model")

        var body: [String: Any] = [
            "text": text
        ]
        if let selectedVoice = options?.voice, !selectedVoice.isEmpty {
            body["reference_id"] = selectedVoice
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "FishAudioTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        return data
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let processed = processText(text, options: options, engine: .fishaudio)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["FISH_AUDIO_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "FishAudioTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Fish Audio apiKey"])
        }

        guard let url = URL(string: "\(baseURL)/v1/tts") else {
            throw NSError(domain: "FishAudioTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let selectedModel = options?.extraOptions?["model"] as? String ?? model
        request.addValue(selectedModel, forHTTPHeaderField: "model")

        var body: [String: Any] = [
            "text": text
        ]
        if let selectedVoice = options?.voice, !selectedVoice.isEmpty {
            body["reference_id"] = selectedVoice
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "FishAudioTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
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
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["FISH_AUDIO_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            return []
        }

        guard let url = URL(string: "\(baseURL)/v1/model") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        // Response is a JSON list of models, each containing _id/id, title/name, gender, etc.
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return list.compactMap { dict -> UnifiedVoice? in
            guard let id = dict["_id"] as? String ?? dict["id"] as? String else {
                return nil
            }
            let type = dict["type"] as? String ?? dict["task"] as? String ?? ""
            guard type == "tts" else { return nil }

            let title = dict["title"] as? String ?? dict["name"] as? String ?? "Unknown"
            let genderStr = dict["gender"] as? String ?? ""
            let gender: UnifiedVoice.Gender = (genderStr.lowercased() == "female") ? .female : (genderStr.lowercased() == "male") ? .male : .unknown

            let langCodes: [UnifiedVoice.LanguageCode]
            if let languages = dict["languages"] as? [String] {
                langCodes = languages.map { lang in
                    UnifiedVoice.LanguageCode(bcp47: lang, iso639_3: String(lang.prefix(3)), display: lang)
                }
            } else {
                langCodes = [UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")]
            }

            return UnifiedVoice(id: id, name: title, gender: gender, provider: "fishaudio", languageCodes: langCodes)
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
