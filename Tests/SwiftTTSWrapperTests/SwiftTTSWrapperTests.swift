import XCTest
@testable import SwiftTTSWrapper

final class SwiftTTSWrapperTests: XCTestCase {
    
    func testFactoryInstantiations() {
        let system = TTSClientFactory.create(engine: .system)
        XCTAssertTrue(system is SystemTTSClient)
        
        let openai = TTSClientFactory.create(engine: .openai)
        XCTAssertTrue(openai is OpenAITTSClient)
        
        let eleven = TTSClientFactory.create(engine: .elevenlabs)
        XCTAssertTrue(eleven is ElevenLabsTTSClient)
        
        let azure = TTSClientFactory.create(engine: .azure)
        XCTAssertTrue(azure is AzureTTSClient)
        
        let google = TTSClientFactory.create(engine: .google)
        XCTAssertTrue(google is GoogleTTSClient)

        let cartesia = TTSClientFactory.create(engine: .cartesia)
        XCTAssertTrue(cartesia is CartesiaTTSClient)

        let playht = TTSClientFactory.create(engine: .playht)
        XCTAssertTrue(playht is PlayHTTTSClient)

        let deepgram = TTSClientFactory.create(engine: .deepgram)
        XCTAssertTrue(deepgram is DeepgramTTSClient)

        let fishaudio = TTSClientFactory.create(engine: .fishaudio)
        XCTAssertTrue(fishaudio is FishAudioTTSClient)

        let hume = TTSClientFactory.create(engine: .hume)
        XCTAssertTrue(hume is HumeTTSClient)

        let mistral = TTSClientFactory.create(engine: .mistral)
        XCTAssertTrue(mistral is MistralTTSClient)

        let modelslab = TTSClientFactory.create(engine: .modelslab)
        XCTAssertTrue(modelslab is ModelsLabTTSClient)

        let murf = TTSClientFactory.create(engine: .murf)
        XCTAssertTrue(murf is MurfTTSClient)

        let polly = TTSClientFactory.create(engine: .polly)
        XCTAssertTrue(polly is PollyTTSClient)

        let resemble = TTSClientFactory.create(engine: .resemble)
        XCTAssertTrue(resemble is ResembleTTSClient)

        let unrealspeech = TTSClientFactory.create(engine: .unrealspeech)
        XCTAssertTrue(unrealspeech is UnrealSpeechTTSClient)

        let upliftai = TTSClientFactory.create(engine: .upliftai)
        XCTAssertTrue(upliftai is UpliftAITTSClient)

        let watson = TTSClientFactory.create(engine: .watson)
        XCTAssertTrue(watson is WatsonTTSClient)

        let witai = TTSClientFactory.create(engine: .witai)
        XCTAssertTrue(witai is WitAITTSClient)

        let xai = TTSClientFactory.create(engine: .xai)
        XCTAssertTrue(xai is XAITTSClient)

        let sherpaonnx = TTSClientFactory.create(engine: .sherpaonnx)
        XCTAssertTrue(sherpaonnx is SherpaOnnxTTSClient)
    }
    
    func testWordTimingEstimator() {
        let text = "Hello world, this is a test!"
        let boundaries = WordTimingEstimator.estimate(text: text)
        
        XCTAssertEqual(boundaries.count, 6)
        XCTAssertEqual(boundaries[0].text, "Hello")
        XCTAssertEqual(boundaries[1].text, "world,")
        XCTAssertGreaterThan(boundaries[0].duration, 0)
        XCTAssertEqual(boundaries[0].offset, 0)
        XCTAssertGreaterThan(boundaries[1].offset, 0)
    }
    
    func testSystemVoices() async throws {
        let system = TTSClientFactory.create(engine: .system)
        let voices = try await system.getVoices()
        
        XCTAssertFalse(voices.isEmpty)
        if let firstVoice = voices.first {
            XCTAssertEqual(firstVoice.provider, "system")
            XCTAssertFalse(firstVoice.id.isEmpty)
            XCTAssertFalse(firstVoice.name.isEmpty)
        }
    }
    
    func testCredentialChecking() async {
        let openai = TTSClientFactory.create(engine: .openai, credentials: ["apiKey": ""])
        let check1 = await openai.checkCredentials()
        XCTAssertFalse(check1)
        
        let openaiWithFake = TTSClientFactory.create(engine: .openai, credentials: ["apiKey": "fake-key-for-testing-purposes"])
        let check2 = await openaiWithFake.checkCredentials()
        XCTAssertFalse(check2)

        let cartesia = TTSClientFactory.create(engine: .cartesia, credentials: ["apiKey": "fake-key-for-testing-purposes"])
        let check3 = await cartesia.checkCredentials()
        XCTAssertFalse(check3)

        let playht = TTSClientFactory.create(engine: .playht, credentials: ["apiKey": "fake-key", "userId": "fake-user"])
        let check4 = await playht.checkCredentials()
        XCTAssertFalse(check4)
    }

    func testNewEngineCredentialChecking() async {
        let deepgram = TTSClientFactory.create(engine: .deepgram, credentials: ["apiKey": ""])
        let d1 = await deepgram.checkCredentials()
        XCTAssertFalse(d1)

        let fishaudio = TTSClientFactory.create(engine: .fishaudio, credentials: ["apiKey": "test-fake-key"])
        let d2 = await fishaudio.checkCredentials()
        XCTAssertFalse(d2)

        let hume = TTSClientFactory.create(engine: .hume, credentials: ["apiKey": "fakekey123"])
        let d3 = await hume.checkCredentials()
        XCTAssertFalse(d3)

        let mistral = TTSClientFactory.create(engine: .mistral, credentials: ["apiKey": ""])
        let d4 = await mistral.checkCredentials()
        XCTAssertFalse(d4)

        let modelslab = TTSClientFactory.create(engine: .modelslab, credentials: ["apiKey": ""])
        let d5 = await modelslab.checkCredentials()
        XCTAssertFalse(d5)

        let murf = TTSClientFactory.create(engine: .murf, credentials: ["apiKey": "testfake123"])
        let d6 = await murf.checkCredentials()
        XCTAssertFalse(d6)

        let polly = TTSClientFactory.create(engine: .polly, credentials: [:])
        let d7 = await polly.checkCredentials()
        XCTAssertFalse(d7)

        let resemble = TTSClientFactory.create(engine: .resemble, credentials: ["apiKey": ""])
        let d8 = await resemble.checkCredentials()
        XCTAssertFalse(d8)

        let unrealspeech = TTSClientFactory.create(engine: .unrealspeech, credentials: ["apiKey": ""])
        let d9 = await unrealspeech.checkCredentials()
        XCTAssertFalse(d9)

        let upliftai = TTSClientFactory.create(engine: .upliftai, credentials: ["apiKey": ""])
        let d10 = await upliftai.checkCredentials()
        XCTAssertFalse(d10)

        let watson = TTSClientFactory.create(engine: .watson, credentials: [:])
        let d11 = await watson.checkCredentials()
        XCTAssertFalse(d11)

        let witai = TTSClientFactory.create(engine: .witai, credentials: ["token": ""])
        let d12 = await witai.checkCredentials()
        XCTAssertFalse(d12)

        let xai = TTSClientFactory.create(engine: .xai, credentials: ["apiKey": ""])
        let d13 = await xai.checkCredentials()
        XCTAssertFalse(d13)
    }

    func testStaticVoiceLists() async throws {
        let deepgramVoices = try await TTSClientFactory.create(engine: .deepgram).getVoices()
        XCTAssertFalse(deepgramVoices.isEmpty)
        XCTAssertEqual(deepgramVoices.first?.provider, "deepgram")

        let humeVoices = try await TTSClientFactory.create(engine: .hume).getVoices()
        XCTAssertFalse(humeVoices.isEmpty)
        XCTAssertEqual(humeVoices.first?.provider, "hume")

        let mistralVoices = try await TTSClientFactory.create(engine: .mistral).getVoices()
        XCTAssertFalse(mistralVoices.isEmpty)
        XCTAssertEqual(mistralVoices.first?.provider, "mistral")

        let modelslabVoices = try await TTSClientFactory.create(engine: .modelslab).getVoices()
        XCTAssertFalse(modelslabVoices.isEmpty)
        XCTAssertEqual(modelslabVoices.first?.provider, "modelslab")

        let murfVoices = try await TTSClientFactory.create(engine: .murf).getVoices()
        XCTAssertFalse(murfVoices.isEmpty)
        XCTAssertEqual(murfVoices.first?.provider, "murf")

        let unrealspeechVoices = try await TTSClientFactory.create(engine: .unrealspeech).getVoices()
        XCTAssertFalse(unrealspeechVoices.isEmpty)
        XCTAssertEqual(unrealspeechVoices.first?.provider, "unrealspeech")

        let upliftaiVoices = try await TTSClientFactory.create(engine: .upliftai).getVoices()
        XCTAssertFalse(upliftaiVoices.isEmpty)
        XCTAssertEqual(upliftaiVoices.first?.provider, "upliftai")

        let xaiVoices = try await TTSClientFactory.create(engine: .xai).getVoices()
        XCTAssertFalse(xaiVoices.isEmpty)
        XCTAssertEqual(xaiVoices.first?.provider, "xai")
    }

    func testWatsonFallbackVoices() async throws {
        let watson = TTSClientFactory.create(engine: .watson) as! WatsonTTSClient
        let voices = try await watson.getVoices()
        XCTAssertFalse(voices.isEmpty)
        XCTAssertTrue(voices.allSatisfy { $0.provider == "watson" })
    }

    func testPollyFallbackVoices() async throws {
        let polly = TTSClientFactory.create(engine: .polly) as! PollyTTSClient
        let voices = try await polly.getVoices()
        XCTAssertFalse(voices.isEmpty)
        XCTAssertTrue(voices.allSatisfy { $0.provider == "polly" })
    }

    func testAllEnginesRegistered() {
        let allCases = TTSEngine.allCases
        XCTAssertEqual(allCases.count, 21)
        for engine in allCases {
            let client = TTSClientFactory.create(engine: engine)
            XCTAssertNotNil(client, "Failed to create client for engine: \(engine.rawValue)")
        }
    }

    func testSherpaOnnxModelsCatalog() async throws {
        let models = SherpaOnnxModelsCatalog.loadBundled()
        XCTAssertNotNil(models)
        XCTAssertFalse(models!.isEmpty)

        XCTAssertNotNil(models!["kokoro-en-en-19"])
        XCTAssertEqual(models!["kokoro-en-en-19"]?.resolvedModelType, .kokoro)
        XCTAssertEqual(models!["kokoro-en-en-19"]?.sampleRate, 24000)

        XCTAssertNotNil(models!["piper-en-amy-medium"])
        XCTAssertEqual(models!["piper-en-amy-medium"]?.resolvedModelType, .vits)
    }

    func testSherpaOnnxVoiceListing() async throws {
        let client = TTSClientFactory.create(engine: .sherpaonnx) as! SherpaOnnxTTSClient
        let voices = try await client.getVoices()
        XCTAssertFalse(voices.isEmpty)
        XCTAssertTrue(voices.contains { $0.provider == "sherpaonnx" })
    }

    func testSherpaOnnxStubEngineThrows() async {
        let stub = SherpaOnnxStubEngine()
        XCTAssertFalse(stub.isInitialized)
        do {
            _ = try stub.generate(text: "test", speakerId: 0, speed: 1.0)
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(true)
        }
    }

    func testSherpaOnnxAudioConverter() {
        let samples: [Float] = [0.0, 0.5, -0.5, 1.0, -1.0]
        let wav = SherpaOnnxAudioConverter.floatSamplesToWav(samples, sampleRate: 22050)

        XCTAssertTrue(wav.count > 44)
        let riff = String(data: wav.subdata(in: 0..<4), encoding: .ascii)
        XCTAssertEqual(riff, "RIFF")
        let wave = String(data: wav.subdata(in: 8..<12), encoding: .ascii)
        XCTAssertEqual(wave, "WAVE")
    }

    func testSherpaOnnxModelTypes() {
        guard let models = SherpaOnnxModelsCatalog.loadBundled() else {
            XCTFail("Failed to load models")
            return
        }

        let modelTypes = Set(models.values.map { $0.resolvedModelType })
        XCTAssertTrue(modelTypes.contains(.vits))
        XCTAssertTrue(modelTypes.contains(.kokoro))
        XCTAssertTrue(modelTypes.contains(.matcha))
        XCTAssertTrue(modelTypes.contains(.mms))
    }

    func testSherpaOnnxCustomEngine() async throws {
        class MockEngine: SherpaOnnxNativeEngine {
            var isInitialized = true
            func initialize(modelPath: String, tokensPath: String, voiceDir: String, modelType: SherpaOnnxModelType, dataDir: String, lexiconPath: String, voicesPath: String, vocoderPath: String, dictDir: String) throws {}
            func generate(text: String, speakerId: Int32, speed: Float) throws -> SherpaOnnxAudioResult {
                return SherpaOnnxAudioResult(samples: [0.0, 0.5, 0.0], sampleRate: 22050)
            }
        }

        let mockEngine = MockEngine()
        let client = SherpaOnnxTTSClient(engine: mockEngine)

        guard let models = SherpaOnnxModelsCatalog.loadBundled(),
              let _ = models.first else {
            XCTFail("No models available")
            return
        }

        let voices = try await client.getVoices()
        XCTAssertFalse(voices.isEmpty)
    }

    func testPollySpeechMarkParsing() {
        let polly = TTSClientFactory.create(engine: .polly) as! PollyTTSClient
        let ndjson = """
        {"time": 0, "type": "word", "start": 0, "end": 5, "value": "Hello"}
        {"time": 400, "type": "word", "start": 6, "end": 11, "value": "world"}
        """
        let boundaries = polly.parseSpeechMarks(ndjson)
        
        XCTAssertEqual(boundaries.count, 2)
        XCTAssertEqual(boundaries[0].text, "Hello")
        XCTAssertEqual(boundaries[0].offset, 0)
        XCTAssertEqual(boundaries[0].duration, 400)
        
        XCTAssertEqual(boundaries[1].text, "world")
        XCTAssertEqual(boundaries[1].offset, 400)
        XCTAssertGreaterThan(boundaries[1].duration, 0)
    }

    func testGoogleSSMLAndTimepoints() {
        let google = TTSClientFactory.create(engine: .google) as! GoogleTTSClient
        
        // Test SSML marked generation
        let text = "Hello world"
        let (ssml, words) = google.addWordTimingMarks(to: text)
        XCTAssertEqual(ssml, "<speak><mark name=\"0\"/>Hello <mark name=\"1\"/>world</speak>")
        XCTAssertEqual(words, ["Hello", "world"])
        
        // Test tag stripping in helper
        let ssmlInput = "<speak>Hello world</speak>"
        let (ssmlFromSSML, wordsFromSSML) = google.addWordTimingMarks(to: ssmlInput)
        XCTAssertEqual(ssmlFromSSML, "<speak><mark name=\"0\"/>Hello <mark name=\"1\"/>world</speak>")
        XCTAssertEqual(wordsFromSSML, ["Hello", "world"])
        
        // Test parsing timepoints
        let timepointsList: [[String: Any]] = [
            ["markName": "0", "timeSeconds": 0.125],
            ["markName": "1", "timeSeconds": 0.450]
        ]
        let boundaries = google.parseTimepoints(timepointsList, words: words)
        
        XCTAssertEqual(boundaries.count, 2)
        XCTAssertEqual(boundaries[0].text, "Hello")
        XCTAssertEqual(boundaries[0].offset, 125)
        XCTAssertEqual(boundaries[0].duration, 325) // 450 - 125
        
        XCTAssertEqual(boundaries[1].text, "world")
        XCTAssertEqual(boundaries[1].offset, 450)
        XCTAssertGreaterThan(boundaries[1].duration, 0)
    }

    func testElevenLabsAlignmentParsing() {
        let eleven = TTSClientFactory.create(engine: .elevenlabs) as! ElevenLabsTTSClient
        let text = "Hello world testing"
        let startTimes: [Double] = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8]
        let endTimes: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9]
        
        let boundaries = eleven.convertAlignmentToWordBoundaries(text: text, startTimes: startTimes, endTimes: endTimes)
        
        XCTAssertEqual(boundaries.count, 3)
        XCTAssertEqual(boundaries[0].text, "Hello")
        XCTAssertEqual(boundaries[0].offset, 0)
        XCTAssertEqual(boundaries[0].duration, 500)
        
        XCTAssertEqual(boundaries[1].text, "world")
        XCTAssertEqual(boundaries[1].offset, 600)
        XCTAssertEqual(boundaries[1].duration, 500)
        
        XCTAssertEqual(boundaries[2].text, "testing")
        XCTAssertEqual(boundaries[2].offset, 1200)
        XCTAssertEqual(boundaries[2].duration, 700)
    }

    func testAWSSigV4Signer() {
        var request = URLRequest(url: URL(string: "https://polly.us-east-1.amazonaws.com/v1/speech")!)
        let body = "{\"OutputFormat\":\"mp3\",\"Text\":\"Hello\"}".data(using: .utf8)!
        let date = Date(timeIntervalSince1970: 1600000000) // Deterministic date
        
        AWSSigV4Signer.sign(
            request: &request,
            body: body,
            region: "us-east-1",
            accessKeyId: "test-access-key-id",
            secretAccessKey: "test-secret-access-key",
            currentDate: date
        )
        
        XCTAssertEqual(request.value(forHTTPHeaderField: "Host"), "polly.us-east-1.amazonaws.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Amz-Date"), "20200913T122640Z")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        
        let authHeader = request.value(forHTTPHeaderField: "Authorization")
        XCTAssertNotNil(authHeader)
        XCTAssertTrue(authHeader!.contains("AWS4-HMAC-SHA256 Credential=test-access-key-id/20200913/us-east-1/polly/aws4_request"))
        XCTAssertTrue(authHeader!.contains("SignedHeaders=content-type;host;x-amz-date"))
    }

    func testSystemTTSClientISOMapping() {
        XCTAssertEqual(SystemTTSClient.iso639_3(from: "en-US"), "eng")
        XCTAssertEqual(SystemTTSClient.iso639_3(from: "es-ES"), "spa")
        XCTAssertEqual(SystemTTSClient.iso639_3(from: "zh-CN"), "zho")
        XCTAssertEqual(SystemTTSClient.iso639_3(from: "fr-FR"), "fra")
        XCTAssertEqual(SystemTTSClient.iso639_3(from: "unknown-lang"), "unknown")
    }
}

