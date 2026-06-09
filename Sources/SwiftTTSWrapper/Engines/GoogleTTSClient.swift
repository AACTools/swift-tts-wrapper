import Foundation

/// Google Cloud TTS Client wrapping the Google Cloud Text-to-Speech REST API.
public final class GoogleTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var voice = "en-US-Wavenet-D"
    private var audioEncoding = "MP3"
    private var cachedBoundaries: [WordBoundary] = []

    public override init(credentials: TTSCredentials = [:]) {
        super.init(credentials: credentials)
        player.onStart = { [weak self] in self?.onStart?() }
        player.onEnd = { [weak self] in self?.onEnd?() }
        player.onBoundary = { [weak self] boundary in self?.onBoundary?(boundary) }
        player.onError = { [weak self] error in self?.onError?(error) }
    }

    public override func checkCredentials() async -> Bool {
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["GOOGLE_TTS_KEY"]
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

    internal func addWordTimingMarks(to text: String) -> (ssml: String, words: [String]) {
        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.hasPrefix("<speak>") {
            cleanText = String(cleanText.dropFirst("<speak>".count))
        }
        if cleanText.hasSuffix("</speak>") {
            cleanText = String(cleanText.dropLast("</speak>".count))
        }
        
        var textWithoutTags = ""
        var inTag = false
        for char in cleanText {
            if char == "<" {
                inTag = true
            } else if char == ">" {
                inTag = false
            } else if !inTag {
                textWithoutTags.append(char)
            }
        }
        
        let words = textWithoutTags.split { $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
        var ssml = "<speak>"
        for (index, word) in words.enumerated() {
            if index > 0 {
                ssml += " "
            }
            ssml += "<mark name=\"\(index)\"/>\(word)"
        }
        ssml += "</speak>"
        return (ssml, words)
    }

    internal func parseTimepoints(_ timepointsList: [[String: Any]], words: [String]) -> [WordBoundary] {
        struct RawTimepoint {
            let index: Int
            let timeMs: Int
        }
        
        var rawTimepoints: [RawTimepoint] = []
        for tp in timepointsList {
            guard let markName = tp["markName"] as? String,
                  let index = Int(markName),
                  index >= 0 && index < words.count,
                  let timeSeconds = tp["timeSeconds"] as? Double else {
                continue
            }
            rawTimepoints.append(RawTimepoint(index: index, timeMs: Int(timeSeconds * 1000)))
        }
        
        rawTimepoints.sort { $0.timeMs < $1.timeMs }
        
        var boundaries: [WordBoundary] = []
        for i in 0..<rawTimepoints.count {
            let tp = rawTimepoints[i]
            let word = words[tp.index]
            let duration: Int
            if i < rawTimepoints.count - 1 {
                duration = rawTimepoints[i+1].timeMs - tp.timeMs
            } else {
                duration = max(50, word.count * 80)
            }
            boundaries.append(WordBoundary(text: word, offset: tp.timeMs, duration: duration))
        }
        
        return boundaries
    }

    public override func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data {
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["GOOGLE_TTS_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "GoogleTTSClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Google Cloud API Key"])
        }

        let useWordBoundary = options?.useWordBoundary == true
        let apiVersion = useWordBoundary ? "v1beta1" : "v1"
        let urlString = "https://texttospeech.googleapis.com/\(apiVersion)/text:synthesize?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GoogleTTSClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Google Cloud TTS URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let selectedVoice = options?.voice ?? voice
        let selectedLang = String(selectedVoice.prefix(5)) // e.g. "en-US"
        let selectedEncoding = options?.format?.rawValue.uppercased() ?? audioEncoding

        var inputPayload: [String: Any] = [:]
        var wordsList: [String] = []

        if useWordBoundary {
            let (markedSSML, words) = addWordTimingMarks(to: text)
            inputPayload["ssml"] = markedSSML
            wordsList = words
        } else if options?.rawSSML == true || text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<speak>") {
            inputPayload["ssml"] = text
        } else {
            inputPayload["text"] = text
        }

        var hasProsody = false
        var prosodyAttrs: [String] = []
        if let rate = options?.rate, rate != .medium {
            prosodyAttrs.append("rate=\"\(rate.rawValue)\"")
        }
        if let pitch = options?.pitch, pitch != .medium {
            prosodyAttrs.append("pitch=\"\(pitch.rawValue)\"")
        }
        if let volume = options?.volume {
            let pct = Int(min(max(volume, 0), 1.0) * 100)
            if pct != 100 {
                let db = (pct - 100) / 10
                prosodyAttrs.append("volume=\"\(db)dB\"")
            }
        }
        hasProsody = !prosodyAttrs.isEmpty

        if hasProsody && !useWordBoundary {
            if let ssmlStr = inputPayload["ssml"] as? String {
                if let bodyRange = ssmlStr.range(of: "<speak>"), let closeRange = ssmlStr.range(of: "</speak>", options: .backwards) {
                    let afterOpen = bodyRange.upperBound
                    let inner = String(ssmlStr[afterOpen..<closeRange.lowerBound])
                    inputPayload["ssml"] = "<speak><prosody \(prosodyAttrs.joined(separator: " "))>\(inner)</prosody></speak>"
                }
            } else if let textStr = inputPayload["text"] as? String {
                inputPayload["ssml"] = "<speak><prosody \(prosodyAttrs.joined(separator: " "))>\(textStr)</prosody></speak>"
                inputPayload.removeValue(forKey: "text")
            }
        }

        var body: [String: Any] = [
            "input": inputPayload,
            "voice": [
                "languageCode": selectedLang,
                "name": selectedVoice
            ],
            "audioConfig": [
                "audioEncoding": selectedEncoding
            ]
        ]

        if useWordBoundary {
            body["enableTimePointing"] = ["SSML_MARK"]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP status: \(httpResponse.statusCode)"
            throw NSError(domain: "GoogleTTSClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let audioContent = json["audioContent"] as? String,
              let audioData = Data(base64Encoded: audioContent) else {
            throw NSError(domain: "GoogleTTSClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Google audioContent"])
        }

        if useWordBoundary {
            if let timepointsList = json["timepoints"] as? [[String: Any]] {
                self.cachedBoundaries = parseTimepoints(timepointsList, words: wordsList)
            } else {
                self.cachedBoundaries = WordTimingEstimator.estimate(text: text)
            }
        } else {
            self.cachedBoundaries = []
        }

        return audioData
    }

    public override func speak(_ input: SpeakInput, options: SpeakOptions?) async throws {
        stop()

        switch input {
        case .text(let text):
            let data = try await synthToBytes(text, options: options)
            let boundaries: [WordBoundary]
            if options?.useWordBoundary == true {
                boundaries = cachedBoundaries.isEmpty ? WordTimingEstimator.estimate(text: text) : cachedBoundaries
            } else {
                boundaries = []
            }
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
        let key = credentials["apiKey"] ?? ProcessInfo.processInfo.environment["GOOGLE_TTS_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            return []
        }

        let urlString = "https://texttospeech.googleapis.com/v1/voices?key=\(apiKey)"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voicesList = json["voices"] as? [[String: Any]] else {
            return []
        }

        return voicesList.compactMap { voice in
            guard let name = voice["name"] as? String,
                  let languageCodes = voice["languageCodes"] as? [String] else {
                return nil
            }

            let genderStr = voice["ssmlGender"] as? String
            let gender: UnifiedVoice.Gender = (genderStr?.lowercased() == "female") ? .female : (genderStr?.lowercased() == "male") ? .male : .unknown

            let langs = languageCodes.map { code in
                let iso = code.split(separator: "-").first.map(String.init) ?? "eng"
                return UnifiedVoice.LanguageCode(bcp47: code, iso639_3: iso, display: code)
            }

            return UnifiedVoice(id: name, name: name, gender: gender, provider: "google", languageCodes: langs)
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
