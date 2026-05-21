import Foundation

public final class WitAITTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var voice = "Colin"
    private var apiVersion = "20240601"
    private var baseURL = "https://api.wit.ai"

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

    private var token: String? {
        credentials["token"] ?? ProcessInfo.processInfo.environment["WITAI_TOKEN"]
    }

    private func acceptHeader(for format: String?) -> String {
        switch format {
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "pcm": return "audio/raw"
        default: return "audio/raw"
        }
    }

    public override func checkCredentials() async -> Bool {
        guard let token = token, !token.isEmpty else {
            return false
        }
        if token.lowercased().hasPrefix("test") || token.lowercased().contains("fake") || token.count < 10 {
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
        guard let token = token, !token.isEmpty else {
            throw NSError(domain: "WitAITTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Wit.ai token"])
        }

        let selectedVoice = options?.voice ?? voice
        let format = options?.extraOptions?["format"] as? String

        guard let url = URL(string: "\(baseURL)/synthesize?v=\(apiVersion)") else {
            throw NSError(domain: "WitAITTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue(acceptHeader(for: format), forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "q": text,
            "voice": selectedVoice,
            "style": "default"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "WitAITTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        return data
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        guard let token = token, !token.isEmpty else {
            throw NSError(domain: "WitAITTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Wit.ai token"])
        }

        let selectedVoice = options?.voice ?? voice
        let format = options?.extraOptions?["format"] as? String

        guard let url = URL(string: "\(baseURL)/synthesize?v=\(apiVersion)") else {
            throw NSError(domain: "WitAITTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue(acceptHeader(for: format), forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "q": text,
            "voice": selectedVoice,
            "style": "default"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "WitAITTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
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
        guard let token = token, !token.isEmpty else {
            return []
        }

        guard let url = URL(string: "\(baseURL)/voices?v=\(apiVersion)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        guard let voicesDict = try JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]] else {
            return []
        }

        var unifiedVoices: [UnifiedVoice] = []
        for (localeKey, voiceList) in voicesDict {
            let locale = localeKey.replacingOccurrences(of: "_", with: "-")
            for voiceEntry in voiceList {
                guard let name = voiceEntry["name"] as? String else { continue }
                let displayName = name.contains("$") ? name.split(separator: "$").last.map(String.init) ?? name : name
                let genderStr = voiceEntry["gender"] as? String ?? ""
                let gender: UnifiedVoice.Gender = (genderStr == "female") ? .female : (genderStr == "male") ? .male : .unknown
                let langPart = locale.split(separator: "-").first.map(String.init) ?? "en"

                unifiedVoices.append(UnifiedVoice(
                    id: name,
                    name: displayName,
                    gender: gender,
                    provider: "witai",
                    languageCodes: [
                        UnifiedVoice.LanguageCode(bcp47: locale, iso639_3: langPart, display: "\(langPart.uppercased()) (\(locale))")
                    ]
                ))
            }
        }

        return unifiedVoices
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
