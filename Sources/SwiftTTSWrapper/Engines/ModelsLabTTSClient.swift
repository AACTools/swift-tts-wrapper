import Foundation

/// ModelsLab TTS Client wrapping the ModelsLab API.
public final class ModelsLabTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var voice = "madison"
    private var language = "american english"
    private var speed: Double = 1.0
    private var emotion = false
    private var baseURL = "https://modelslab.com/api/v6/voice/text_to_speech"

    public static let voices = [
        UnifiedVoice(id: "madison", name: "Madison", gender: .female, provider: "modelslab", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "tara", name: "Tara", gender: .female, provider: "modelslab", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "leah", name: "Leah", gender: .female, provider: "modelslab", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "jess", name: "Jess", gender: .female, provider: "modelslab", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "mia", name: "Mia", gender: .female, provider: "modelslab", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "zoe", name: "Zoe", gender: .female, provider: "modelslab", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "leo", name: "Leo", gender: .male, provider: "modelslab", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "dan", name: "Dan", gender: .male, provider: "modelslab", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "zac", name: "Zac", gender: .male, provider: "modelslab", languageCodes: [
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
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["MODELSLAB_API_KEY"]
        return key != nil && !key!.isEmpty
    }

    public override func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data {
        let processed = processText(text, options: options, engine: .modelslab)
        let text = processed.text

        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["MODELSLAB_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "ModelsLabTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing ModelsLab apiKey"])
        }

        guard let url = URL(string: baseURL) else {
            throw NSError(domain: "ModelsLabTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let selectedVoice = options?.voice ?? voice
        let selectedLang = options?.extraOptions?["language"] as? String ?? language
        let selectedSpeed = options?.extraOptions?["speed"] as? Double ?? speed
        let selectedEmotion = options?.extraOptions?["emotion"] as? Bool ?? emotion

        let body: [String: Any] = [
            "key": apiKey,
            "prompt": text,
            "language": selectedLang,
            "voice_id": selectedVoice,
            "speed": selectedSpeed,
            "emotion": selectedEmotion
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "ModelsLabTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            throw NSError(domain: "ModelsLabTTSClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Malformed ModelsLab response"])
        }

        if status == "error" {
            let msg = json["message"] as? String ?? "Unknown error"
            throw NSError(domain: "ModelsLabTTSClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "ModelsLab error: \(msg)"])
        }

        var audioUrlStr: String?

        if status == "success" {
            if let output = json["output"] as? [String], !output.isEmpty {
                audioUrlStr = output[0]
            }
        } else if status == "processing" {
            let fetchUrlStr = json["fetch_result"] as? String ?? json["link"] as? String
            guard let pollUrlStr = fetchUrlStr, !pollUrlStr.isEmpty else {
                throw NSError(domain: "ModelsLabTTSClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Processing status returned no poll URL"])
            }
            audioUrlStr = try await poll(pollUrlStr: pollUrlStr, apiKey: apiKey)
        }

        guard let targetUrlStr = audioUrlStr, let downloadUrl = URL(string: targetUrlStr) else {
            throw NSError(domain: "ModelsLabTTSClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve output audio URL"])
        }

        let (audioData, downloadResponse) = try await URLSession.shared.data(from: downloadUrl)
        if let httpDownload = downloadResponse as? HTTPURLResponse, httpDownload.statusCode != 200 {
            throw NSError(domain: "ModelsLabTTSClient", code: httpDownload.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to download audio from \(targetUrlStr)"])
        }

        return audioData
    }

    private func poll(pollUrlStr: String, apiKey: String) async throws -> String {
        guard let pollUrl = URL(string: pollUrlStr) else {
            throw NSError(domain: "ModelsLabTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid polling URL: \(pollUrlStr)"])
        }

        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            var request = URLRequest(url: pollUrl)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["key": apiKey])

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    if status == "success", let output = json["output"] as? [String], !output.isEmpty {
                        return output[0]
                    }
                    if status == "error" {
                        let msg = json["message"] as? String ?? "Unknown polling error"
                        throw NSError(domain: "ModelsLabTTSClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "ModelsLab polling error: \(msg)"])
                    }
                }
            } catch {
                if (error as NSError).domain == "ModelsLabTTSClient" {
                    throw error
                }
                // Silently continue polling on network hiccups
            }
        }

        throw NSError(domain: "ModelsLabTTSClient", code: 408, userInfo: [NSLocalizedDescriptionKey: "ModelsLab generation timed out after 20 attempts"])
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let processed = processText(text, options: options, engine: .modelslab)
        let text = processed.text

        let audioData = try await synthToBytes(text, options: options)
        return AsyncThrowingStream { continuation in
            continuation.yield(audioData)
            continuation.finish()
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
        return ModelsLabTTSClient.voices
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
