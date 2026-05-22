import Foundation

public final class AzureTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var voice = "en-US-AriaNeural"
    private var outputFormat = "audio-16khz-128kbitrate-mono-mp3"
    private var cachedBoundaries: [WordBoundary] = []

    public override init(credentials: TTSCredentials = [:]) {
        super.init(credentials: credentials)
        player.onStart = { [weak self] in self?.onStart?() }
        player.onEnd = { [weak self] in self?.onEnd?() }
        player.onBoundary = { [weak self] boundary in self?.onBoundary?(boundary) }
        player.onError = { [weak self] error in self?.onError?(error) }
    }

    public override func checkCredentials() async -> Bool {
        let key = credentials["subscriptionKey"] ?? credentials["apiKey"] ?? ProcessInfo.processInfo.environment["AZURE_TTS_KEY"]
        guard let subscriptionKey = key, !subscriptionKey.isEmpty else {
            return false
        }

        if subscriptionKey.lowercased().hasPrefix("test") || subscriptionKey.lowercased().contains("fake") || subscriptionKey.count < 10 {
            return false
        }

        do {
            let voices = try await getVoices()
            return !voices.isEmpty
        } catch {
            return false
        }
    }

    private func buildSSML(_ text: String, options: SpeakOptions?) -> String {
        let selectedVoice = options?.voice ?? voice
        let langCode = String(selectedVoice.prefix(5))

        if options?.rawSSML == true {
            if let body = Self.extractSSMLBody(text) {
                return """
                <speak version='1.0' xml:lang='\(langCode)'>
                    <voice xml:lang='\(langCode)' name='\(selectedVoice)'>
                        \(body)
                    </voice>
                </speak>
                """
            }
            return text
        }

        var escapedText = text
        escapedText = escapedText.replacingOccurrences(of: "&", with: "&amp;")
        escapedText = escapedText.replacingOccurrences(of: "<", with: "&lt;")
        escapedText = escapedText.replacingOccurrences(of: ">", with: "&gt;")
        escapedText = escapedText.replacingOccurrences(of: "\"", with: "&amp;quot;")
        escapedText = escapedText.replacingOccurrences(of: "'", with: "&amp;apos;")

        return """
        <speak version='1.0' xml:lang='\(langCode)'>
            <voice xml:lang='\(langCode)' name='\(selectedVoice)'>
                \(escapedText)
            </voice>
        </speak>
        """
    }

    private static func extractSSMLBody(_ ssml: String) -> String? {
        guard let openRange = ssml.range(of: "<speak", options: .caseInsensitive) else { return nil }
        guard let tagEnd = ssml.range(of: ">", range: openRange.lowerBound..<ssml.endIndex) else { return nil }
        guard let closeRange = ssml.range(of: "</speak>", options: [.caseInsensitive, .backwards]) else { return nil }
        return String(ssml[tagEnd.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public override func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data {
        if options?.useWordBoundary == true {
            let result = try await synthViaWebSocket(text, options: options)
            cachedBoundaries = result.boundaries
            return result.audio
        }
        cachedBoundaries = []
        return try await synthViaREST(text, options: options)
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

    private func synthViaREST(_ text: String, options: SpeakOptions?) async throws -> Data {
        let key = credentials["subscriptionKey"] ?? credentials["apiKey"] ?? ProcessInfo.processInfo.environment["AZURE_TTS_KEY"]
        guard let subscriptionKey = key, !subscriptionKey.isEmpty else {
            throw NSError(domain: "AzureTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Azure subscriptionKey"])
        }

        let region = credentials["region"] ?? "eastus"
        let urlString = "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "AzureTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Azure region or URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(subscriptionKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.addValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.addValue(outputFormat, forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.addValue("SwiftTTSWrapper", forHTTPHeaderField: "User-Agent")

        let ssml = buildSSML(text, options: options)
        request.httpBody = ssml.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "AzureTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        return data
    }

    private struct WebSocketSynthResult {
        let audio: Data
        let boundaries: [WordBoundary]
    }

    private func synthViaWebSocket(_ text: String, options: SpeakOptions?) async throws -> WebSocketSynthResult {
        let key = credentials["subscriptionKey"] ?? credentials["apiKey"] ?? ProcessInfo.processInfo.environment["AZURE_TTS_KEY"]
        guard let subscriptionKey = key, !subscriptionKey.isEmpty else {
            throw NSError(domain: "AzureTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Azure subscriptionKey"])
        }

        let region = credentials["region"] ?? "eastus"
        let requestId = UUID().uuidString.lowercased()
        let wsURLStr = "wss://\(region).tts.speech.microsoft.com/cognitiveservices/websocket/v1?Ocp-Apim-Subscription-Key=\(subscriptionKey)"
        guard let wsURL = URL(string: wsURLStr) else {
            throw NSError(domain: "AzureTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Azure WebSocket URL"])
        }

        let request = URLRequest(url: wsURL)
        let webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask.resume()

        let selectedFormat = outputFormat
        let configHeaders = "X-RequestId:\(requestId)\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n"
        let configBody = #"{"context":{"synthesis":{"audio":{"metadataOptions":{"sentenceBoundaryEnabled":false,"wordBoundaryEnabled":true},"outputFormat":"\#(selectedFormat)"}}}}"#
        let configMessage = configHeaders + configBody

        try await webSocketTask.send(.string(configMessage))

        let ssml = buildSSML(text, options: options)
        let ssmlMessage = "X-RequestId:\(requestId)\r\nContent-Type:application/ssml+xml\r\nX-StreamId:\(requestId)\r\nPath:ssml\r\n\r\n\(ssml)"
        try await webSocketTask.send(.string(ssmlMessage))

        var audioData = Data()
        var boundaries: [WordBoundary] = []

        while true {
            let message = try await webSocketTask.receive()

            switch message {
            case .string(let textMessage):
                let path = Self.extractPath(from: textMessage)

                if path == "turn.end" {
                    webSocketTask.cancel(with: .normalClosure, reason: nil)
                    let computed = Self.computeDurations(boundaries)
                    return WebSocketSynthResult(audio: audioData, boundaries: computed)
                }

                if path == "audio.metadata" || path == "word-boundary" {
                    let body: String
                    if let sep = textMessage.range(of: "\r\n\r\n") {
                        body = String(textMessage[sep.upperBound...])
                    } else if let sep = textMessage.range(of: "\n\n") {
                        body = String(textMessage[sep.upperBound...])
                    } else {
                        body = textMessage
                    }
                    guard let jsonData = body.data(using: .utf8),
                          let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { break }

                    if let metadata = json["Metadata"] as? [[String: Any]] {
                        for item in metadata {
                            guard item["Type"] as? String == "WordBoundary",
                                  let data = item["Data"] as? [String: Any] else { continue }
                            let offsetTicks = data["Offset"] as? Int64 ?? 0
                            let durationTicks = data["Duration"] as? Int64 ?? 0
                            let word: String
                            if let textObj = data["text"] as? [String: Any] {
                                word = textObj["Text"] as? String ?? ""
                            } else if let textObj = data["Text"] as? [String: Any] {
                                word = textObj["Text"] as? String ?? ""
                            } else {
                                word = data["text"] as? String ?? ""
                            }
                            if !word.isEmpty {
                                boundaries.append(WordBoundary(
                                    text: word,
                                    offset: Int(offsetTicks / 10_000),
                                    duration: Int(durationTicks / 10_000)
                                ))
                            }
                        }
                    }
                }

            case .data(let binaryMessage):
                if binaryMessage.count > 2 {
                    let headerLength = Int(binaryMessage[0]) << 8 | Int(binaryMessage[1])
                    if binaryMessage.count > 2 + headerLength {
                        let audioStart = 2 + headerLength
                        audioData.append(binaryMessage[audioStart...])
                    }
                }

            @unknown default:
                break
            }
        }
    }

    private static func extractPath(from message: String) -> String {
        for line in message.components(separatedBy: "\r\n") {
            if line.hasPrefix("Path:") {
                return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private static func computeDurations(_ boundaries: [WordBoundary]) -> [WordBoundary] {
        guard boundaries.count > 1 else {
            return boundaries.map { WordBoundary(text: $0.text, offset: $0.offset, duration: max($0.duration, 500)) }
        }

        var result = boundaries
        for i in 0..<(result.count - 1) {
            if result[i].duration == 0 {
                result[i].duration = result[i + 1].offset - result[i].offset
            }
        }
        if result[result.count - 1].duration == 0 {
            result[result.count - 1].duration = 500
        }
        return result
    }

    public override func getVoices() async throws -> [UnifiedVoice] {
        let key = credentials["subscriptionKey"] ?? credentials["apiKey"] ?? ProcessInfo.processInfo.environment["AZURE_TTS_KEY"]
        guard let subscriptionKey = key, !subscriptionKey.isEmpty else {
            return []
        }

        let region = credentials["region"] ?? "eastus"
        let urlString = "https://\(region).tts.speech.microsoft.com/cognitiveservices/voices/list"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(subscriptionKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.addValue("SwiftTTSWrapper", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        guard let voicesList = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return voicesList.compactMap { voice in
            guard let name = voice["Name"] as? String,
                  let shortName = voice["ShortName"] as? String else {
                return nil
            }

            let genderStr = voice["Gender"] as? String
            let gender: UnifiedVoice.Gender = (genderStr?.lowercased() == "female") ? .female : (genderStr?.lowercased() == "male") ? .male : .unknown

            let locale = voice["Locale"] as? String ?? "en-US"
            let iso = locale.split(separator: "-").first.map(String.init) ?? "eng"

            let lang = UnifiedVoice.LanguageCode(bcp47: locale, iso639_3: iso, display: locale)

            return UnifiedVoice(id: shortName, name: name, gender: gender, provider: "azure", languageCodes: [lang])
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
