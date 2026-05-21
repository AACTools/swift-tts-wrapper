import Foundation

public struct SherpaOnnxAudioResult: Sendable {
    public var samples: [Float]
    public var sampleRate: Int32

    public init(samples: [Float], sampleRate: Int32) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

public protocol SherpaOnnxNativeEngine: AnyObject {
    var isInitialized: Bool { get }

    func initialize(
        modelPath: String,
        tokensPath: String,
        voiceDir: String,
        modelType: SherpaOnnxModelType,
        dataDir: String,
        lexiconPath: String,
        voicesPath: String,
        vocoderPath: String,
        dictDir: String
    ) throws

    func generate(text: String, speakerId: Int32, speed: Float) throws -> SherpaOnnxAudioResult
}

public final class SherpaOnnxStubEngine: SherpaOnnxNativeEngine {
    public var isInitialized: Bool { false }

    public init() {}

    public func initialize(
        modelPath: String,
        tokensPath: String,
        voiceDir: String,
        modelType: SherpaOnnxModelType,
        dataDir: String,
        lexiconPath: String,
        voicesPath: String,
        vocoderPath: String,
        dictDir: String
    ) throws {
        throw NSError(
            domain: "SherpaOnnxStubEngine",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No native sherpa-onnx engine configured. Provide a SherpaOnnxNativeEngine implementation via SherpaOnnxTTSClient(engine:credentials:)"]
        )
    }

    public func generate(text: String, speakerId: Int32, speed: Float) throws -> SherpaOnnxAudioResult {
        throw NSError(
            domain: "SherpaOnnxStubEngine",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No native sherpa-onnx engine configured. Provide a SherpaOnnxNativeEngine implementation."]
        )
    }
}

public enum SherpaOnnxAudioConverter {
    public static func floatSamplesToWav(_ samples: [Float], sampleRate: Int32) -> Data {
        let numChannels: Int32 = 1
        let bitsPerSample: Int32 = 16
        let sampleCount = Int32(samples.count)
        let dataSize = sampleCount * numChannels * (bitsPerSample / 8)

        var data = Data(capacity: Int(44 + dataSize))

        data.append(contentsOf: "RIFF".utf8)
        appendInt32(&data, 36 + dataSize)
        data.append(contentsOf: "WAVE".utf8)

        data.append(contentsOf: "fmt ".utf8)
        appendInt32(&data, 16)
        appendInt16(&data, 1)
        appendInt16(&data, Int16(numChannels))
        appendInt32(&data, sampleRate)
        appendInt32(&data, sampleRate * numChannels * (bitsPerSample / 8))
        appendInt16(&data, Int16(numChannels * (bitsPerSample / 8)))
        appendInt16(&data, Int16(bitsPerSample))

        data.append(contentsOf: "data".utf8)
        appendInt32(&data, dataSize)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = clamped < 0 ? Int16(clamped * 32768.0) : Int16(clamped * 32767.0)
            var val = int16.littleEndian
            data.append(Data(bytes: &val, count: 2))
        }

        return data
    }

    private static func appendInt32(_ data: inout Data, _ value: Int32) {
        var val = value.littleEndian
        data.append(Data(bytes: &val, count: 4))
    }

    private static func appendInt16(_ data: inout Data, _ value: Int16) {
        var val = value.littleEndian
        data.append(Data(bytes: &val, count: 2))
    }
}
