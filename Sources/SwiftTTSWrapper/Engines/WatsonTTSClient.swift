import Foundation

public final class WatsonTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var voice = "en-US_AllisonV3Voice"
    private var region = "us-east"
    private var instanceId = ""
    private var iamToken: String?

    public static let fallbackVoices = [
        UnifiedVoice(id: "en-US_AllisonV3Voice", name: "Allison", gender: .female, provider: "watson", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "en-US_LisaV3Voice", name: "Lisa", gender: .female, provider: "watson", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "en-US_MichaelV3Voice", name: "Michael", gender: .male, provider: "watson", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "en-GB_KateV3Voice", name: "Kate", gender: .female, provider: "watson", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-GB", iso639_3: "eng", display: "English (UK)")
        ]),
        UnifiedVoice(id: "es-ES_EnriqueV3Voice", name: "Enrique", gender: .male, provider: "watson", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "es-ES", iso639_3: "spa", display: "Spanish (Spain)")
        ]),
        UnifiedVoice(id: "fr-FR_ReneeV3Voice", name: "Renee", gender: .female, provider: "watson", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "fr-FR", iso639_3: "fra", display: "French (France)")
        ]),
        UnifiedVoice(id: "de-DE_BirgitV3Voice", name: "Birgit", gender: .female, provider: "watson", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "de-DE", iso639_3: "deu", display: "German (Germany)")
        ]),
        UnifiedVoice(id: "it-IT_FrancescaV3Voice", name: "Francesca", gender: .female, provider: "watson", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "it-IT", iso639_3: "ita", display: "Italian (Italy)")
        ]),
        UnifiedVoice(id: "ja-JP_EmiV3Voice", name: "Emi", gender: .female, provider: "watson", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "ja-JP", iso639_3: "jpn", display: "Japanese (Japan)")
        ]),
        UnifiedVoice(id: "pt-BR_IsabelaV3Voice", name: "Isabela", gender: .female, provider: "watson", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "pt-BR", iso639_3: "por", display: "Portuguese (Brazil)")
        ])
    ]

    public override init(credentials: TTSCredentials = [:]) {
        super.init(credentials: credentials)
        if let customRegion = credentials["region"] {
            self.region = customRegion
        }
        if let customInstance = credentials["instanceId"] {
            self.instanceId = customInstance
        }
        player.onStart = { [weak self] in self?.onStart?() }
        player.onEnd = { [weak self] in self?.onEnd?() }
        player.onBoundary = { [weak self] boundary in self?.onBoundary?(boundary) }
        player.onError = { [weak self] error in self?.onError?(error) }
    }

    private var apiKey: String? {
        credentials["apiKey"] ?? ProcessInfo.processInfo.environment["WATSON_API_KEY"]
    }

    private func refreshIAMToken() async throws {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw NSError(domain: "WatsonTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Watson apiKey"])
        }

        guard let url = URL(string: "https://iam.cloud.ibm.com/identity/token") else {
            throw NSError(domain: "WatsonTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid IAM URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = "apikey=\(apiKey)&grant_type=urn:ibm:params:oauth:grant-type:apikey"
        request.httpBody = params.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "WatsonTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to refresh IAM token"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw NSError(domain: "WatsonTTSClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid IAM token response"])
        }

        self.iamToken = token
    }

    public override func checkCredentials() async -> Bool {
        guard apiKey != nil, !region.isEmpty, !instanceId.isEmpty else {
            return false
        }
        if let key = apiKey, key.lowercased().hasPrefix("test") || key.lowercased().contains("fake") {
            return false
        }
        do {
            try await refreshIAMToken()
            let voices = try await getVoices()
            return !voices.isEmpty
        } catch {
            return false
        }
    }

    public override func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data {
        guard !region.isEmpty, !instanceId.isEmpty else {
            throw NSError(domain: "WatsonTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Watson region or instanceId"])
        }

        try await refreshIAMToken()

        guard let token = iamToken else {
            throw NSError(domain: "WatsonTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing IAM token"])
        }

        guard let url = URL(string: "https://api.\(region).text-to-speech.watson.cloud.ibm.com/instances/\(instanceId)/v1/synthesize") else {
            throw NSError(domain: "WatsonTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let selectedVoice = options?.voice ?? voice

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("audio/wav", forHTTPHeaderField: "Accept")

        // Process SpeechMarkdown/SSML pipeline
        let processed = processText(text, options: options, engine: .watson)

        var attrs: [String] = []
        if let rate = options?.rate, rate != .medium {
            attrs.append("rate=\"\(rate.rawValue)\"")
        }
        if let pitch = options?.pitch, pitch != .medium {
            attrs.append("pitch=\"\(pitch.rawValue)\"")
        }
        if let volume = options?.volume {
            let pct = Int(min(max(volume, 0), 1.0) * 100)
            if pct != 100 {
                attrs.append("volume=\"\(pct)%\"")
            }
        }

        let body: [String: Any]
        if processed.isSSML {
            body = [
                "text": processed.text,
                "voice": selectedVoice,
                "accept": "audio/wav"
            ]
        } else if attrs.isEmpty {
            body = [
                "text": processed.text,
                "voice": selectedVoice,
                "accept": "audio/wav"
            ]
        } else {
            let ssml = "<speak><prosody \(attrs.joined(separator: " "))>\(processed.text)</prosody></speak>"
            body = [
                "text": ssml,
                "voice": selectedVoice,
                "accept": "audio/wav"
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "WatsonTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        return data
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        guard !region.isEmpty, !instanceId.isEmpty else {
            throw NSError(domain: "WatsonTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Watson region or instanceId"])
        }

        try await refreshIAMToken()

        guard let token = iamToken else {
            throw NSError(domain: "WatsonTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing IAM token"])
        }

        guard let url = URL(string: "https://api.\(region).text-to-speech.watson.cloud.ibm.com/instances/\(instanceId)/v1/synthesize") else {
            throw NSError(domain: "WatsonTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let selectedVoice = options?.voice ?? voice

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("audio/wav", forHTTPHeaderField: "Accept")

        // Process SpeechMarkdown/SSML pipeline
        let processed = processText(text, options: options, engine: .watson)

        var attrs: [String] = []
        if let rate = options?.rate, rate != .medium {
            attrs.append("rate=\"\(rate.rawValue)\"")
        }
        if let pitch = options?.pitch, pitch != .medium {
            attrs.append("pitch=\"\(pitch.rawValue)\"")
        }
        if let volume = options?.volume {
            let pct = Int(min(max(volume, 0), 1.0) * 100)
            if pct != 100 {
                attrs.append("volume=\"\(pct)%\"")
            }
        }

        let body: [String: Any]
        if processed.isSSML {
            body = [
                "text": processed.text,
                "voice": selectedVoice,
                "accept": "audio/wav"
            ]
        } else if attrs.isEmpty {
            body = [
                "text": processed.text,
                "voice": selectedVoice,
                "accept": "audio/wav"
            ]
        } else {
            let ssml = "<speak><prosody \(attrs.joined(separator: " "))>\(processed.text)</prosody></speak>"
            body = [
                "text": ssml,
                "voice": selectedVoice,
                "accept": "audio/wav"
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "WatsonTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
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
        guard !region.isEmpty, !instanceId.isEmpty else {
            return WatsonTTSClient.fallbackVoices
        }

        if iamToken == nil {
            do {
                try await refreshIAMToken()
            } catch {
                return WatsonTTSClient.fallbackVoices
            }
        }

        guard let token = iamToken,
              let url = URL(string: "https://api.\(region).text-to-speech.watson.cloud.ibm.com/instances/\(instanceId)/v1/voices") else {
            return WatsonTTSClient.fallbackVoices
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return WatsonTTSClient.fallbackVoices
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voicesList = json["voices"] as? [[String: Any]] else {
            return WatsonTTSClient.fallbackVoices
        }

        return voicesList.compactMap { dict -> UnifiedVoice? in
            guard let name = dict["name"] as? String else { return nil }
            let genderStr = dict["gender"] as? String ?? ""
            let gender: UnifiedVoice.Gender = (genderStr == "female") ? .female : (genderStr == "male") ? .male : .unknown
            let language = dict["language"] as? String ?? "en-US"
            let description = dict["description"] as? String ?? language
            let displayName = name.contains("_") ? name.split(separator: "_").dropFirst().joined(separator: "_").replacingOccurrences(of: "V3Voice", with: "") : name

            return UnifiedVoice(
                id: name,
                name: displayName,
                gender: gender,
                provider: "watson",
                languageCodes: [
                    UnifiedVoice.LanguageCode(bcp47: language, iso639_3: String(language.split(separator: "-").first ?? "en"), display: description)
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
