import Foundation

/// Resemble AI TTS Client wrapping the Resemble API.
public final class ResembleTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var voiceId = "default"
    private var baseURL = "https://f.cluster.resemble.ai"

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
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["RESEMBLE_API_KEY"]
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
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["RESEMBLE_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "ResembleTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Resemble apiKey"])
        }

        guard let url = URL(string: "\(baseURL)/synthesize") else {
            throw NSError(domain: "ResembleTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "Authorization")

        let selectedVoice = options?.voice ?? voiceId

        let body: [String: Any] = [
            "voice_uuid": selectedVoice,
            "data": text
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "ResembleTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base64String = json["audio_content"] as? String,
              let audioData = Data(base64Encoded: base64String) else {
            throw NSError(domain: "ResembleTTSClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response or audio_content"])
        }

        return audioData
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["RESEMBLE_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "ResembleTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Resemble apiKey"])
        }

        guard let url = URL(string: "\(baseURL)/stream") else {
            throw NSError(domain: "ResembleTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "Authorization")

        let selectedVoice = options?.voice ?? voiceId

        let body: [String: Any] = [
            "voice_uuid": selectedVoice,
            "data": text
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "ResembleTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
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
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["RESEMBLE_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            return []
        }

        guard let url = URL(string: "\(baseURL)/v2/voices") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return list.compactMap { dict -> UnifiedVoice? in
            guard let id = dict["uuid"] as? String ?? dict["id"] as? String else {
                return nil
            }
            let name = dict["name"] as? String ?? id
            let genderStr = dict["gender"] as? String ?? ""
            let gender: UnifiedVoice.Gender = (genderStr.lowercased() == "female") ? .female : (genderStr.lowercased() == "male") ? .male : .unknown
            let lang = dict["language"] as? String ?? "en-US"

            return UnifiedVoice(
                id: id,
                name: name,
                gender: gender,
                provider: "resemble",
                languageCodes: [
                    UnifiedVoice.LanguageCode(bcp47: lang, iso639_3: String(lang.prefix(3)), display: lang)
                ]
            )
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
