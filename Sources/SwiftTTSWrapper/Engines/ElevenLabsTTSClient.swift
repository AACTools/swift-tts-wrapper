import Foundation

/// ElevenLabs TTS Client wrapping the ElevenLabs Text-to-Speech REST API.
public final class ElevenLabsTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var modelId = "eleven_multilingual_v2"
    private var outputFormat = "mp3_44100_128"
    private var cachedBoundaries: [WordBoundary] = []

    public override init(credentials: TTSCredentials = [:]) {
        super.init(credentials: credentials)
        player.onStart = { [weak self] in self?.onStart?() }
        player.onEnd = { [weak self] in self?.onEnd?() }
        player.onBoundary = { [weak self] boundary in self?.onBoundary?(boundary) }
        player.onError = { [weak self] error in self?.onError?(error) }
    }

    public override func checkCredentials() async -> Bool {
        let apiKey = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]
        guard let key = apiKey, !key.isEmpty else {
            return false
        }

        if key.lowercased().hasPrefix("test") || key.lowercased().contains("fake") || key.count < 10 {
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
        let apiKey = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]
        guard let key = apiKey, !key.isEmpty else {
            throw NSError(domain: "ElevenLabsTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing ElevenLabs API Key"])
        }

        let voiceId = options?.voice ?? credentials["voiceId"] ?? "21m00Tcm4TlvDq8ikWAM" // Rachel
        let baseURL = credentials["baseURL"] ?? "https://api.elevenlabs.io/v1"

        let useTimestamps = options?.useWordBoundary == true
        let endpoint = useTimestamps ? "/text-to-speech/\(voiceId)/with-timestamps" : "/text-to-speech/\(voiceId)"

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw NSError(domain: "ElevenLabsTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid ElevenLabs URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(key, forHTTPHeaderField: "xi-api-key")

        let selectedModel = options?.extraOptions?["modelId"] as? String ?? options?.extraOptions?["model"] as? String ?? modelId
        let selectedFormat = options?.extraOptions?["outputFormat"] as? String ?? outputFormat

        var voiceSettings: [String: Any] = [
            "stability": 0.5,
            "similarity_boost": 0.75,
            "use_speaker_boost": true
        ]

        if let rate = options?.rate {
            let speedMap: [SpeechRate: Float] = [
                .xSlow: 0.5, .slow: 0.75, .medium: 1.0, .fast: 1.25, .xFast: 1.5
            ]
            voiceSettings["speed"] = speedMap[rate] ?? 1.0
        }

        if let customSettings = options?.extraOptions?["voiceSettings"] as? [String: Any] {
            for (k, v) in customSettings {
                voiceSettings[k] = v
            }
        }

        let body: [String: Any] = [
            "text": text,
            "model_id": selectedModel,
            "voice_settings": voiceSettings
        ]

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "output_format", value: selectedFormat)]
        if let reqURL = components?.url {
            request.url = reqURL
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "ElevenLabsTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        if useTimestamps {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let audioBase64 = json["audio_base64"] as? String,
                  let audioData = Data(base64Encoded: audioBase64) else {
                throw NSError(domain: "ElevenLabsTTSClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse timestamped audio response"])
            }

            if let alignment = json["alignment"] as? [String: Any],
               let startTimes = alignment["character_start_times_seconds"] as? [Double],
               let endTimes = alignment["character_end_times_seconds"] as? [Double] {
                let boundaries = convertAlignmentToWordBoundaries(text: text, startTimes: startTimes, endTimes: endTimes)
                self.cachedBoundaries = boundaries
            }

            return audioData
        } else {
            self.cachedBoundaries = []
            return data
        }
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let useTimestamps = options?.useWordBoundary == true
        if useTimestamps {
            let data = try await synthToBytes(text, options: options)
            return AsyncThrowingStream { continuation in
                continuation.yield(data)
                continuation.finish()
            }
        }

        let apiKey = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]
        guard let key = apiKey, !key.isEmpty else {
            throw NSError(domain: "ElevenLabsTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing ElevenLabs API Key"])
        }

        let voiceId = options?.voice ?? credentials["voiceId"] ?? "21m00Tcm4TlvDq8ikWAM"
        let baseURL = credentials["baseURL"] ?? "https://api.elevenlabs.io/v1"
        let endpoint = "/text-to-speech/\(voiceId)/stream"

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw NSError(domain: "ElevenLabsTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid ElevenLabs URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(key, forHTTPHeaderField: "xi-api-key")

        let selectedModel = options?.extraOptions?["modelId"] as? String ?? options?.extraOptions?["model"] as? String ?? modelId
        let selectedFormat = options?.extraOptions?["outputFormat"] as? String ?? outputFormat

        var voiceSettings: [String: Any] = [
            "stability": 0.5,
            "similarity_boost": 0.75,
            "use_speaker_boost": true
        ]

        if let rate = options?.rate {
            let speedMap: [SpeechRate: Float] = [
                .xSlow: 0.5, .slow: 0.75, .medium: 1.0, .fast: 1.25, .xFast: 1.5
            ]
            voiceSettings["speed"] = speedMap[rate] ?? 1.0
        }

        if let customSettings = options?.extraOptions?["voiceSettings"] as? [String: Any] {
            for (k, v) in customSettings {
                voiceSettings[k] = v
            }
        }

        let body: [String: Any] = [
            "text": text,
            "model_id": selectedModel,
            "voice_settings": voiceSettings
        ]

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "output_format", value: selectedFormat)]
        if let reqURL = components?.url {
            request.url = reqURL
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "ElevenLabsTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
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

    internal func convertAlignmentToWordBoundaries(text: String, startTimes: [Double], endTimes: [Double]) -> [WordBoundary] {
        var wordBoundaries: [WordBoundary] = []
        let nsText = text as NSString
        let regex = try? NSRegularExpression(pattern: "\\S+")
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []

        for match in matches {
            let range = match.range
            let word = nsText.substring(with: range)

            let startCharIndex = range.location
            let endCharIndex = range.location + range.length - 1

            if startCharIndex < startTimes.count && endCharIndex < endTimes.count {
                let startTime = startTimes[startCharIndex]
                let endTime = endTimes[endCharIndex]

                wordBoundaries.append(WordBoundary(
                    text: word,
                    offset: Int(startTime * 1000),
                    duration: Int((endTime - startTime) * 1000)
                ))
            }
        }

        return wordBoundaries
    }

    public override func speak(_ input: SpeakInput, options: SpeakOptions?) async throws {
        stop()

        switch input {
        case .text(let text):
            let data = try await synthToBytes(text, options: options)
            let boundaries = options?.useWordBoundary == true ? cachedBoundaries : []
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
        let apiKey = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]
        guard let key = apiKey, !key.isEmpty else {
            return []
        }

        let baseURL = credentials["baseURL"] ?? "https://api.elevenlabs.io/v1"
        guard let url = URL(string: "\(baseURL)/voices") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(key, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voicesList = json["voices"] as? [[String: Any]] else {
            return []
        }

        return voicesList.compactMap { voice in
            guard let id = voice["voice_id"] as? String,
                  let name = voice["name"] as? String else {
                return nil
            }

            let labels = voice["labels"] as? [String: Any]
            let genderStr = labels?["gender"] as? String
            let gender: UnifiedVoice.Gender = (genderStr == "female") ? .female : (genderStr == "male") ? .male : .unknown

            let accent = labels?["accent"] as? String ?? "en-US"
            let iso = accent.split(separator: "-").first.map(String.init) ?? "eng"

            let lang = UnifiedVoice.LanguageCode(bcp47: accent, iso639_3: iso, display: accent)

            return UnifiedVoice(id: id, name: name, gender: gender, provider: "elevenlabs", languageCodes: [lang])
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
