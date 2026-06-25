import Foundation
import AVFoundation

public final class SystemTTSClient: AbstractTTSClient, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private var speechStartTime: CFTimeInterval = 0
    private var activePlayer: AudioPlayer?

    public override init(credentials: TTSCredentials = [:]) {
        super.init(credentials: credentials)
        synthesizer.delegate = self
    }

    public override func speak(_ input: SpeakInput, options: SpeakOptions?) async throws {
        stop()

        switch input {
        case .text(let text):
            let processed = processText(text, options: options, engine: .system)
            let utterance = makeUtterance(text: processed.text, isSSML: processed.isSSML, options: options)
            synthesizer.speak(utterance)

        case .file(let url):
            let player = AudioPlayer()
            player.onStart = onStart
            player.onEnd = onEnd
            player.onBoundary = onBoundary
            player.onError = onError
            activePlayer = player
            try player.play(url: url)

        case .bytes(let data):
            let player = AudioPlayer()
            player.onStart = onStart
            player.onEnd = onEnd
            player.onBoundary = onBoundary
            player.onError = onError
            activePlayer = player
            try player.play(data: data)

        case .stream(let stream):
            var data = Data()
            for try await chunk in stream {
                data.append(chunk)
            }
            try await speak(.bytes(data), options: options)
        }
    }

    public override func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data {
        let processed = processText(text, options: options, engine: .system)
        let utterance = makeUtterance(text: processed.text, isSSML: processed.isSSML, options: options)

        return try await withCheckedThrowingContinuation { continuation in
            var audioFile: AVAudioFile?
            var writeError: Error?
            var completed = false
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")

            synthesizer.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    if !completed {
                        completed = true
                        continuation.resume(throwing: writeError ?? NSError(domain: "SystemTTSClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate PCM buffer"]))
                    }
                    return
                }

                if pcmBuffer.frameLength == 0 {
                    if !completed {
                        completed = true
                        if let err = writeError {
                            continuation.resume(throwing: err)
                        } else {
                            do {
                                audioFile = nil
                                let data = try Data(contentsOf: fileURL)
                                try? FileManager.default.removeItem(at: fileURL)
                                continuation.resume(returning: data)
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                    return
                }

                if audioFile == nil {
                    do {
                        audioFile = try AVAudioFile(forWriting: fileURL, settings: pcmBuffer.format.settings)
                    } catch {
                        writeError = error
                    }
                }

                if let file = audioFile {
                    do {
                        try file.write(from: pcmBuffer)
                    } catch {
                        writeError = error
                    }
                }
            }
        }
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let processed = processText(text, options: options, engine: .system)
        let utterance = makeUtterance(text: processed.text, isSSML: processed.isSSML, options: options)

        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()

        let wroteHeader = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        wroteHeader.initialize(to: false)
        nonisolated(unsafe) let headerPtr = wroteHeader

        continuation.onTermination = { _ in
            headerPtr.deallocate()
        }

        synthesizer.write(utterance) { buffer in
            guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                continuation.finish()
                return
            }

            if pcmBuffer.frameLength == 0 {
                continuation.finish()
                return
            }

            let frameCount = Int(pcmBuffer.frameLength)
            guard let channelData = pcmBuffer.floatChannelData?[0] else {
                continuation.finish()
                return
            }

            var pcmData = Data(capacity: frameCount * 2)
            for i in 0..<frameCount {
                let sample = channelData[i]
                let intSample = Int16(max(-1.0, min(1.0, sample)) * 32767.0)
                pcmData.append(UInt8(intSample & 0xFF))
                pcmData.append(UInt8((intSample >> 8) & 0xFF))
            }

            if !headerPtr.pointee {
                headerPtr.pointee = true
                let header = Self.wavHeader(sampleRate: 22050, channels: 1, bitsPerSample: 16, dataChunkSize: 0x7FFF0000)
                continuation.yield(header)
            }

            continuation.yield(pcmData)
        }

        return stream
    }

    public override func getVoices() async throws -> [UnifiedVoice] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        return voices.map { voice in
            let bcpCode = voice.language
            let isoCode = Self.iso639_3(from: bcpCode)
            let lang = UnifiedVoice.LanguageCode(
                bcp47: bcpCode,
                iso639_3: isoCode,
                display: Locale.current.localizedString(forIdentifier: bcpCode) ?? bcpCode
            )

            let gender: UnifiedVoice.Gender
            switch voice.gender {
            case .male: gender = .male
            case .female: gender = .female
            case .unspecified: gender = .unknown
            @unknown default: gender = .unknown
            }

            return UnifiedVoice(
                id: voice.identifier,
                name: voice.name,
                gender: gender,
                provider: "system",
                languageCodes: [lang]
            )
        }
    }

    public override func pause() {
        if let p = activePlayer {
            p.pause()
        } else {
            synthesizer.pauseSpeaking(at: .immediate)
        }
    }

    public override func resume() {
        if let p = activePlayer {
            p.resume()
        } else {
            synthesizer.continueSpeaking()
        }
    }

    public override func stop() {
        activePlayer?.stop()
        activePlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        speechStartTime = CACurrentMediaTime()
        onStart?()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onEnd?()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onEnd?()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let elapsedMs = Int((CACurrentMediaTime() - speechStartTime) * 1000)
        guard let range = Range(characterRange, in: utterance.speechString) else { return }
        var word = String(utterance.speechString[range])
        // Strip any SSML tags from boundary text
        word = AbstractTTSClient.stripSSML(word)
        let estimatedDuration = characterRange.length * 80
        onBoundary?(WordBoundary(text: word, offset: elapsedMs, duration: estimatedDuration))
    }

    // MARK: - Private Helpers

    private func makeUtterance(text: String, isSSML: Bool, options: SpeakOptions?) -> AVSpeechUtterance {
        let utterance: AVSpeechUtterance
        if isSSML, let ssmlUtterance = AVSpeechUtterance(ssmlRepresentation: text) {
            utterance = ssmlUtterance
        } else {
            utterance = AVSpeechUtterance(string: text)
        }

        if let rate = options?.rate {
            utterance.rate = rate.rateValue
        } else {
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        }

        if let pitch = options?.pitch {
            utterance.pitchMultiplier = pitch.pitchValue
        }

        if let volume = options?.volume {
            utterance.volume = min(max(volume, 0.0), 1.0)
        }

        if let voiceId = options?.voice {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId)
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        return utterance
    }

    private static func wavHeader(sampleRate: Int32, channels: Int16, bitsPerSample: Int16, dataChunkSize: Int32) -> Data {
        var data = Data()
        let byteRate = sampleRate * Int32(channels) * Int32(bitsPerSample / 8)
        let blockAlign = Int16(channels * (bitsPerSample / 8))
        let totalSize = 36 + dataChunkSize

        data.append(contentsOf: "RIFF".utf8)
        appendLE(&data, Int32(totalSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        appendLE(&data, Int32(16))
        appendLE(&data, Int16(1))
        appendLE(&data, channels)
        appendLE(&data, sampleRate)
        appendLE(&data, byteRate)
        appendLE(&data, blockAlign)
        appendLE(&data, bitsPerSample)
        data.append(contentsOf: "data".utf8)
        appendLE(&data, dataChunkSize)

        return data
    }

    private static func appendLE(_ data: inout Data, _ value: Int32) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 4))
    }

    private static func appendLE(_ data: inout Data, _ value: Int16) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 2))
    }

    internal static func iso639_3(from bcp47: String) -> String {
        let mapping: [String: String] = [
            "af": "afr", "ar": "ara", "bg": "bul", "ca": "cat", "cs": "ces",
            "da": "dan", "de": "deu", "el": "ell", "en": "eng", "es": "spa",
            "fi": "fin", "fr": "fra", "gu": "guj", "he": "heb", "hi": "hin",
            "hr": "hrv", "hu": "hun", "id": "ind", "is": "isl", "it": "ita",
            "ja": "jpn", "kn": "kan", "ko": "kor", "lt": "lit", "lv": "lav",
            "ml": "mal", "mr": "mar", "ms": "msa", "nb": "nob", "nl": "nld",
            "no": "nor", "pa": "pan", "pl": "pol", "pt": "por", "ro": "ron",
            "ru": "rus", "si": "sin", "sk": "slk", "sl": "slv", "sv": "swe",
            "ta": "tam", "te": "tel", "th": "tha", "tr": "tur", "uk": "ukr",
            "ur": "urd", "vi": "vie", "yue": "yue", "zh": "zho"
        ]
        let langCode = bcp47.components(separatedBy: "-").first ?? bcp47
        return mapping[langCode] ?? langCode
    }
}
