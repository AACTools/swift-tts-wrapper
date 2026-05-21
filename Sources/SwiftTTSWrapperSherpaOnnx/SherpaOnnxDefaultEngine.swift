import Foundation
import SwiftTTSWrapper
import SherpaOnnx

public final class SherpaOnnxDefaultEngine: SherpaOnnxNativeEngine, @unchecked Sendable {
    private var tts: OpaquePointer?
    private var _isInitialized = false

    public var isInitialized: Bool { _isInitialized }

    public init() {}

    deinit {
        if let tts {
            SherpaOnnxDestroyOfflineTts(tts)
        }
    }

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
        var modelConfig = SherpaOnnxOfflineTtsModelConfig()
        memset(&modelConfig, 0, MemoryLayout.size(ofValue: modelConfig))
        modelConfig.num_threads = 2
        modelConfig.debug = 0

        switch modelType {
        case .kokoro:
            let resolvedVoices = voicesPath.isEmpty ? voiceDir : voicesPath
            modelPath.withCString { model in
                resolvedVoices.withCString { voices in
                    tokensPath.withCString { tokens in
                        dataDir.withCString { data in
                            dictDir.withCString { dict in
                                lexiconPath.withCString { lexicon in
                                    modelConfig.kokoro = SherpaOnnxOfflineTtsKokoroModelConfig(
                                        model: model,
                                        voices: voices,
                                        tokens: tokens,
                                        data_dir: data,
                                        length_scale: 1.0,
                                        dict_dir: dict,
                                        lexicon: lexicon,
                                        lang: nil
                                    )
                                }
                            }
                        }
                    }
                }
            }

        case .matcha:
            modelPath.withCString { model in
                vocoderPath.withCString { voder in
                    lexiconPath.withCString { lexicon in
                        tokensPath.withCString { tokens in
                            dataDir.withCString { data in
                                dictDir.withCString { dict in
                                    modelConfig.matcha = SherpaOnnxOfflineTtsMatchaModelConfig(
                                        acoustic_model: model,
                                        vocoder: voder,
                                        lexicon: lexicon,
                                        tokens: tokens,
                                        data_dir: data,
                                        noise_scale: 0.667,
                                        length_scale: 1.0,
                                        dict_dir: dict
                                    )
                                }
                            }
                        }
                    }
                }
            }

        case .vits, .mms:
            modelPath.withCString { model in
                lexiconPath.withCString { lexicon in
                    tokensPath.withCString { tokens in
                        dataDir.withCString { data in
                            dictDir.withCString { dict in
                                modelConfig.vits = SherpaOnnxOfflineTtsVitsModelConfig(
                                    model: model,
                                    lexicon: lexicon,
                                    tokens: tokens,
                                    data_dir: data,
                                    noise_scale: 0.667,
                                    noise_scale_w: 0.8,
                                    length_scale: 1.0,
                                    dict_dir: dict
                                )
                            }
                        }
                    }
                }
            }
        }

        var config = SherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            rule_fsts: nil,
            max_num_sentences: 1,
            rule_fars: nil,
            silence_scale: 0.2
        )

        let ttsPtr = withUnsafePointer(to: &config) { ptr in
            SherpaOnnxCreateOfflineTts(ptr)
        }

        guard let ttsPtr else {
            throw NSError(
                domain: "SherpaOnnxDefaultEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create sherpa-onnx TTS engine"]
            )
        }

        self.tts = ttsPtr
        self._isInitialized = true
    }

    public func generate(text: String, speakerId: Int32, speed: Float) throws -> SherpaOnnxAudioResult {
        guard let tts else {
            throw NSError(
                domain: "SherpaOnnxDefaultEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Engine not initialized"]
            )
        }

        var genConfig = SherpaOnnxGenerationConfig()
        memset(&genConfig, 0, MemoryLayout.size(ofValue: genConfig))
        genConfig.speed = speed
        genConfig.sid = speakerId
        genConfig.silence_scale = 0.2

        let audioPtr = text.withCString { textPtr in
            withUnsafePointer(to: &genConfig) { cfgPtr in
                SherpaOnnxOfflineTtsGenerateWithConfig(tts, textPtr, cfgPtr, nil, nil)
            }
        }

        guard let audioPtr else {
            throw NSError(
                domain: "SherpaOnnxDefaultEngine",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to generate audio"]
            )
        }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audioPtr) }

        let audio = audioPtr.pointee
        let samples = Array(UnsafeBufferPointer(start: audio.samples, count: Int(audio.n)))

        return SherpaOnnxAudioResult(
            samples: samples,
            sampleRate: audio.sample_rate
        )
    }
}
