import Foundation

/// AWS Polly TTS Client wrapping the Amazon Polly REST API.
public final class PollyTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var voice = "Joanna"
    private var engine = "standard"
    private var region = "us-east-1"
    private var format = "mp3"

    public static let fallbackVoices = [
        UnifiedVoice(id: "Joanna", name: "Joanna", gender: .female, provider: "polly", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "Kendra", name: "Kendra", gender: .female, provider: "polly", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "Matthew", name: "Matthew", gender: .male, provider: "polly", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ]),
        UnifiedVoice(id: "Ivy", name: "Ivy", gender: .female, provider: "polly", languageCodes: [
            UnifiedVoice.LanguageCode(bcp47: "en-US", iso639_3: "eng", display: "English (US)")
        ])
    ]

    public override init(credentials: TTSCredentials = [:]) {
        super.init(credentials: credentials)
        if let customRegion = credentials["region"] {
            self.region = customRegion
        }
        player.onStart = { [weak self] in self?.onStart?() }
        player.onEnd = { [weak self] in self?.onEnd?() }
        player.onBoundary = { [weak self] boundary in self?.onBoundary?(boundary) }
        player.onError = { [weak self] error in self?.onError?(error) }
    }

    public override func checkCredentials() async -> Bool {
        let accessKeyId = credentials["accessKeyId"] ?? ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"]
        let secretAccessKey = credentials["secretAccessKey"] ?? ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"]
        
        guard let keyId = accessKeyId, !keyId.isEmpty,
              let secretKey = secretAccessKey, !secretKey.isEmpty else {
            return false
        }
        
        if keyId.lowercased().contains("fake") || keyId.lowercased().contains("test") {
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
        let accessKeyId = credentials["accessKeyId"] ?? ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"]
        let secretAccessKey = credentials["secretAccessKey"] ?? ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"]
        
        guard let keyId = accessKeyId, !keyId.isEmpty,
              let secretKey = secretAccessKey, !secretKey.isEmpty else {
            throw NSError(domain: "PollyTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing AWS credentials"])
        }

        let pollyRegion = credentials["region"] ?? region
        guard let url = URL(string: "https://polly.\(pollyRegion).amazonaws.com/v1/speech") else {
            throw NSError(domain: "PollyTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let selectedVoice = options?.voice ?? voice
        let selectedEngine = options?.extraOptions?["engine"] as? String ?? engine
        let selectedFormat = options?.extraOptions?["format"] as? String ?? format

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        var outputFormat = "mp3"
        var sampleRate = "24000"
        
        if selectedFormat.lowercased() == "pcm" {
            outputFormat = "pcm"
            sampleRate = "16000"
        } else if selectedFormat.lowercased() == "ogg" {
            outputFormat = "ogg_vorbis"
            sampleRate = "24000"
        }

        let isSSML = text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<speak>")
        let textType = isSSML ? "ssml" : "text"

        let body: [String: Any] = [
            "OutputFormat": outputFormat,
            "SampleRate": sampleRate,
            "Text": text,
            "TextType": textType,
            "VoiceId": selectedVoice,
            "Engine": selectedEngine
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData

        AWSSigV4Signer.sign(
            request: &request,
            body: bodyData,
            region: pollyRegion,
            accessKeyId: keyId,
            secretAccessKey: secretKey
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "PollyTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        return data
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let accessKeyId = credentials["accessKeyId"] ?? ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"]
        let secretAccessKey = credentials["secretAccessKey"] ?? ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"]
        
        guard let keyId = accessKeyId, !keyId.isEmpty,
              let secretKey = secretAccessKey, !secretKey.isEmpty else {
            throw NSError(domain: "PollyTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing AWS credentials"])
        }

        let pollyRegion = credentials["region"] ?? region
        guard let url = URL(string: "https://polly.\(pollyRegion).amazonaws.com/v1/speech") else {
            throw NSError(domain: "PollyTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let selectedVoice = options?.voice ?? voice
        let selectedEngine = options?.extraOptions?["engine"] as? String ?? engine
        let selectedFormat = options?.extraOptions?["format"] as? String ?? format

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        var outputFormat = "mp3"
        var sampleRate = "24000"
        
        if selectedFormat.lowercased() == "pcm" {
            outputFormat = "pcm"
            sampleRate = "16000"
        } else if selectedFormat.lowercased() == "ogg" {
            outputFormat = "ogg_vorbis"
            sampleRate = "24000"
        }

        let isSSML = text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<speak>")
        let textType = isSSML ? "ssml" : "text"

        let body: [String: Any] = [
            "OutputFormat": outputFormat,
            "SampleRate": sampleRate,
            "Text": text,
            "TextType": textType,
            "VoiceId": selectedVoice,
            "Engine": selectedEngine
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData

        AWSSigV4Signer.sign(
            request: &request,
            body: bodyData,
            region: pollyRegion,
            accessKeyId: keyId,
            secretAccessKey: secretKey
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "PollyTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status: \(httpResponse.statusCode)"])
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
        let accessKeyId = credentials["accessKeyId"] ?? ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"]
        let secretAccessKey = credentials["secretAccessKey"] ?? ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"]
        
        guard let keyId = accessKeyId, !keyId.isEmpty,
              let secretKey = secretAccessKey, !secretKey.isEmpty else {
            return PollyTTSClient.fallbackVoices
        }

        let pollyRegion = credentials["region"] ?? region
        guard let url = URL(string: "https://polly.\(pollyRegion).amazonaws.com/v1/voices") else {
            return PollyTTSClient.fallbackVoices
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let bodyData = Data()
        AWSSigV4Signer.sign(
            request: &request,
            body: bodyData,
            region: pollyRegion,
            accessKeyId: keyId,
            secretAccessKey: secretKey
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return PollyTTSClient.fallbackVoices
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voicesList = json["Voices"] as? [[String: Any]] else {
            return PollyTTSClient.fallbackVoices
        }

        return voicesList.compactMap { dict -> UnifiedVoice? in
            guard let id = dict["Id"] as? String,
                  let name = dict["Name"] as? String else {
                return nil
            }
            let genderStr = dict["Gender"] as? String ?? ""
            let gender: UnifiedVoice.Gender = (genderStr == "Female") ? .female : (genderStr == "Male") ? .male : .unknown
            let langCode = dict["LanguageCode"] as? String ?? "en-US"
            let langName = dict["LanguageName"] as? String ?? "English"

            return UnifiedVoice(
                id: id,
                name: name,
                gender: gender,
                provider: "polly",
                languageCodes: [
                    UnifiedVoice.LanguageCode(bcp47: langCode, iso639_3: String(langCode.prefix(3)), display: langName)
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
