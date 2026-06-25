import Foundation

public final class SherpaOnnxTTSClient: AbstractTTSClient, @unchecked Sendable {
    private let player = AudioPlayer()
    private var modelId: String?
    private var modelManager: SherpaOnnxModelManager
    private var engine: SherpaOnnxNativeEngine
    private var models: [String: SherpaOnnxModelEntry] = [:]
    private var customBaseDir: String?

    public override init(credentials: TTSCredentials = [:]) {
        self.engine = SherpaOnnxStubEngine()
        if let customDir = credentials["modelPath"] {
            self.customBaseDir = customDir
            self.modelManager = SherpaOnnxModelManager(baseDir: URL(fileURLWithPath: customDir))
        } else {
            self.modelManager = SherpaOnnxModelManager()
        }
        super.init(credentials: credentials)
        self.modelId = credentials["modelId"]

        player.onStart = { [weak self] in self?.onStart?() }
        player.onEnd = { [weak self] in self?.onEnd?() }
        player.onBoundary = { [weak self] boundary in self?.onBoundary?(boundary) }
        player.onError = { [weak self] error in self?.onError?(error) }
    }

    public convenience init(engine: SherpaOnnxNativeEngine, credentials: TTSCredentials = [:]) {
        self.init(credentials: credentials)
        self.engine = engine
    }

    public override func checkCredentials() async -> Bool {
        do {
            models = try await SherpaOnnxModelsCatalog.load(credentials: credentials)
            return !models.isEmpty
        } catch {
            return false
        }
    }

    public override func synthToBytes(_ text: String, options: SpeakOptions?) async throws -> Data {
        let processed = processText(text, options: options, engine: .sherpaonnx)
        let text = processed.text

        let selectedModelId = options?.voice ?? modelId ?? "kokoro-en-en-19"

        try await ensureModelReady(selectedModelId)

        guard engine.isInitialized else {
            throw NSError(domain: "SherpaOnnxTTSClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Native TTS engine not initialized. Provide a SherpaOnnxNativeEngine via init(engine:credentials:)"])
        }

        let plainText = stripSSML(text)
        let speakerId = options?.extraOptions?["speakerId"] as? Int32 ?? 0
        let speed = options?.extraOptions?["speed"] as? Float ?? 1.0

        let result = try engine.generate(text: plainText, speakerId: speakerId, speed: speed)
        return SherpaOnnxAudioConverter.floatSamplesToWav(result.samples, sampleRate: result.sampleRate)
    }

    public override func synthToBytestream(_ text: String, options: SpeakOptions?) async throws -> AsyncThrowingStream<Data, Error> {
        let processed = processText(text, options: options, engine: .sherpaonnx)
        let text = processed.text

        let selectedModelId = options?.voice ?? modelId ?? "kokoro-en-en-19"

        try await ensureModelReady(selectedModelId)

        guard engine.isInitialized else {
            throw NSError(domain: "SherpaOnnxTTSClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Native TTS engine not initialized"])
        }

        let plainText = stripSSML(text)
        let speakerId = options?.extraOptions?["speakerId"] as? Int32 ?? 0
        let speed = options?.extraOptions?["speed"] as? Float ?? 1.0

        let result = try engine.generate(text: plainText, speakerId: speakerId, speed: speed)
        let wavData = SherpaOnnxAudioConverter.floatSamplesToWav(result.samples, sampleRate: result.sampleRate)

        return AsyncThrowingStream { continuation in
            let chunkSize = 4096
            var offset = 0
            while offset < wavData.count {
                let end = min(offset + chunkSize, wavData.count)
                let chunk = wavData.subdata(in: offset..<end)
                continuation.yield(chunk)
                offset = end
            }
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
        if models.isEmpty {
            models = try await SherpaOnnxModelsCatalog.load(credentials: credentials)
        }
        return SherpaOnnxModelsCatalog.toUnifiedVoices(models)
    }

    public override func pause() { player.pause() }
    public override func resume() { player.resume() }
    public override func stop() { player.stop() }

    public func setVoice(_ voiceId: String) async throws {
        try await ensureModelReady(voiceId)
        self.modelId = voiceId
    }

    public func availableModelIds() -> [String] {
        return models.keys.sorted()
    }

    public func downloadModel(_ modelId: String) async throws {
        if models.isEmpty {
            models = try await SherpaOnnxModelsCatalog.load(credentials: credentials)
        }
        guard let entry = models[modelId] else {
            throw NSError(domain: "SherpaOnnxTTSClient", code: 404, userInfo: [NSLocalizedDescriptionKey: "Model \(modelId) not found in catalog"])
        }
        try await modelManager.downloadAndExtract(entry: entry)
    }

    public func isModelDownloaded(_ modelId: String) -> Bool {
        return modelManager.isModelDownloaded(modelId: modelId)
    }

    private func ensureModelReady(_ modelId: String) async throws {
        if models.isEmpty {
            models = try await SherpaOnnxModelsCatalog.load(credentials: credentials)
        }

        if !modelManager.isModelDownloaded(modelId: modelId) {
            guard let entry = models[modelId] else {
                throw NSError(domain: "SherpaOnnxTTSClient", code: 404, userInfo: [NSLocalizedDescriptionKey: "Model \(modelId) not found in catalog"])
            }
            try await modelManager.downloadAndExtract(entry: entry)
        }

        if !engine.isInitialized {
            let paths = modelManager.resolveModelPaths(modelId: modelId)
            let modelType = models[modelId]?.resolvedModelType ?? .vits

            if modelType == .matcha && paths.vocoderPath.isEmpty {
                let vocoderPath = try await modelManager.ensureVocoder()
                try engine.initialize(
                    modelPath: paths.modelPath,
                    tokensPath: paths.tokensPath,
                    voiceDir: paths.voiceDir,
                    modelType: modelType,
                    dataDir: paths.dataDir,
                    lexiconPath: paths.lexiconPath,
                    voicesPath: paths.voicesPath,
                    vocoderPath: vocoderPath,
                    dictDir: paths.dictDir
                )
            } else {
                try engine.initialize(
                    modelPath: paths.modelPath,
                    tokensPath: paths.tokensPath,
                    voiceDir: paths.voiceDir,
                    modelType: modelType,
                    dataDir: paths.dataDir,
                    lexiconPath: paths.lexiconPath,
                    voicesPath: paths.voicesPath,
                    vocoderPath: paths.vocoderPath,
                    dictDir: paths.dictDir
                )
            }
        }
    }

    private func stripSSML(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<speak") || trimmed.hasPrefix("<?xml") {
            return trimmed.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        return text
    }
}
