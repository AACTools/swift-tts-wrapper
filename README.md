# swift-tts-wrapper

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fwillwade%2Fswift-tts-wrapper%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/willwade/swift-tts-wrapper)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fwillwade%2Fswift-tts-wrapper%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/willwade/swift-tts-wrapper)

A native Swift package that provides a unified interface for working with local offline and cloud-based Text-to-Speech (TTS) services on iOS and macOS. Inspired by [js-tts-wrapper](https://github.com/willwade/js-tts-wrapper), it simplifies speech synthesis across multiple engines with a single consistent API.

## Features

- **Unified API**: A single protocol (`TTSClient`) with consistent methods for speech synthesis and playback control.
- **21 Engines**: System, 19 cloud REST APIs, and on-device sherpa-onnx (VITS/Kokoro/Matcha/MMS).
- **SpeechMarkdown Support**: Built-in [SpeechMarkdown](https://speechmarkdown.org) parsing via [speechmarkdown-rust](https://github.com/AACTools/speechmarkdown-rust) — write pronounceable, cross-platform speech markup with **auto-detection** (no manual toggle needed). Supports X-SAMPA/Praat/SIL/Branner → IPA phonetic notation.
- **Real-Time Streaming**: 16 cloud engines stream audio incrementally; system engine streams from synthesizer callbacks.
- **Word-Level Timing**: ElevenLabs, Azure, and System engines provide real word timestamps from the API; all others use a heuristic estimator.
- **On-Device TTS**: Optional sherpa-onnx integration for fully offline synthesis with 1300+ models.
- **macOS 13+ & iOS 16+**: Supports both platforms with `swift-tools-version: 5.9`.

## Installation

### Core Package

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/willwade/swift-tts-wrapper.git", from: "0.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: ["SwiftTTSWrapper"]),
]
```

> **Note:** The core package depends on [speechmarkdown-rust](https://github.com/AACTools/speechmarkdown-rust) for SpeechMarkdown support and [sherpa-onnx-spm](https://github.com/willwade/sherpa-onnx-spm) for on-device TTS. These binary XCFrameworks are downloaded automatically by SPM.

### With sherpa-onnx (on-device TTS)

Add both packages:

```swift
dependencies: [
    .package(url: "https://github.com/willwade/swift-tts-wrapper.git", from: "0.1.0"),
    .package(url: "https://github.com/willwade/sherpa-onnx-spm.git", from: "1.13.3"),
],
targets: [
    .target(name: "YourApp", dependencies: ["SwiftTTSWrapperSherpaOnnx"]),
]
```

## Supported Engines

### System & On-Device

| Engine ID | Client Class | Streaming | Word Events | Notes |
|-----------|-------------|-----------|-------------|-------|
| `system` | `SystemTTSClient` | Real (AVSpeechSynthesizer.write) | Real (delegate callbacks) | Offline, 44 languages |
| `sherpaonnx` | `SherpaOnnxTTSClient` | Chunked (generates fully then yields) | Estimated | On-device, 1300+ models |

### Cloud REST APIs

| Engine ID | Client Class | Streaming | Word Events | Audio Format |
|-----------|-------------|-----------|-------------|--------------|
| `elevenlabs` | `ElevenLabsTTSClient` | Real | **Real** (character alignment API) | MP3 |
| `openai` | `OpenAITTSClient` | Real | Estimated | MP3/Opus/AAC/FLAC/WAV |
| `cartesia` | `CartesiaTTSClient` | Real | Estimated | PCM WAV |
| `playht` | `PlayHTTTSClient` | Real | Estimated | MP3 |
| `deepgram` | `DeepgramTTSClient` | Real | Estimated | varies |
| `fishaudio` | `FishAudioTTSClient` | Real | Estimated | varies |
| `hume` | `HumeTTSClient` | Real | Estimated | varies |
| `mistral` | `MistralTTSClient` | Real (SSE) | Estimated | MP3 |
| `murf` | `MurfTTSClient` | Real | Estimated | MP3 |
| `polly` | `PollyTTSClient` | Real | Estimated | MP3/PCM/OGG |
| `resemble` | `ResembleTTSClient` | Real | Estimated | WAV/PCM |
| `unrealspeech` | `UnrealSpeechTTSClient` | Real | Estimated | MP3 |
| `upliftai` | `UpliftAITTSClient` | Real | Estimated | MP3 |
| `watson` | `WatsonTTSClient` | Real | Estimated | WAV |
| `witai` | `WitAITTSClient` | Real | Estimated | PCM/MP3/WAV |
| `xai` | `XAITTSClient` | Real | Estimated | varies |
| `azure` | `AzureTTSClient` | No (collects full response) | **Real** (WebSocket word-boundary events) | MP3 |
| `google` | `GoogleTTSClient` | No (collects full response) | **Real** (SSML mark timepoints) | MP3 |
| `modelslab` | `ModelsLabTTSClient` | Buffered (may poll) | Estimated | varies |

**Streaming**: "Real" = audio chunks arrive incrementally from the API. "Buffered" = full audio collected before yielding. "Chunked" = audio generated locally then split into chunks.

**Word Events**: "Real" = the API returns native word/character timestamps. "Estimated" = timing is approximated using `WordTimingEstimator` (assumes ~150 WPM, scaled by word length).

## Quick Start

### Instantiating a Client

```swift
import SwiftTTSWrapper

// System (offline, no credentials needed)
let client = TTSClientFactory.create(engine: .system)

// Cloud engine
let client = TTSClientFactory.create(
    engine: .elevenlabs,
    credentials: ["apiKey": "your-api-key"]
)

// sherpa-onnx (on-device)
let client = TTSClientFactory.create(engine: .sherpaonnx)
```

### Speech with Word Boundaries

```swift
let options = SpeakOptions(useWordBoundary: true)

client.onBoundary = { boundary in
    print("Word: \(boundary.text) at \(boundary.offset)ms")
}
client.onEnd = { print("Done") }

try await client.speak("Hello, world!", options: options)
```

### Direct Audio Generation

```swift
let audioBytes = try await client.synthToBytes("Generate audio data")
// Returns raw Data (MP3, WAV, etc. depending on engine)
```

### Rate, Pitch & Volume

Control speech rate, pitch, and volume via `SpeakOptions`. Engines that support SSML use `<prosody>` tags; others use their native parameters.

```swift
let options = SpeakOptions(
    rate: .fast,       // .xSlow, .slow, .medium, .fast, .xFast
    pitch: .high,      // .xLow, .low, .medium, .high, .xHigh
    volume: 0.7        // 0.0–1.0 (mapped per-engine)
)
try await client.speak("Hello, world!", options: options)
```

| Engine | Rate | Pitch | Volume | Mechanism |
|--------|------|-------|--------|-----------|
| System | ✅ | ✅ | ✅ | `AVSpeechUtterane` properties |
| Azure | ✅ | ✅ | ✅ | SSML `<prosody>` |
| Google | ✅ | ✅ | ✅ | SSML `<prosody>` (volume in dB) |
| Polly | ✅ | ✅ | ✅ | SSML `<prosody>` (auto-wraps) |
| Watson | ✅ | ✅ | ✅ | SSML `<prosody>` (volume in %) |
| ElevenLabs | ✅ | — | — | `voice_settings.speed` (0.5–1.5) |
| OpenAI | ✅ | — | — | `speed` JSON param |
| Others | — | — | — | Ignored silently |

### Voice Listing

```swift
let voices = try await client.getVoices()
for voice in voices {
    print("\(voice.name) - \(voice.languageCodes.first?.display ?? "")")
}
```

### SpeechMarkdown

All text inputs accept [SpeechMarkdown](https://speechmarkdown.org) syntax. SpeechMarkdown is **auto-detected** — no need to set any option. The pipeline converts it appropriately per engine:

- **SSML-capable engines** (system, azure, google, polly, watson): markdown → SSML → native SSML synthesis
- **Non-SSML engines** (openai, elevenlabs, cartesia, etc.): markdown → plain text → API

```swift
// Auto-detected — no options needed
try await client.speak("Hello (world)[emphasis:\"strong\"] [500ms] Goodbye.")
```

You can also force conversion with `useSpeechMarkdown: true`:

```swift
let options = SpeakOptions(useSpeechMarkdown: true)
try await client.speak("Hello (world)[rate:\"fast\"]", options: options)
```

#### Phonetic Notation (X-SAMPA → IPA)

Use `xsampa`, `praat`, `sil`, or `branner` modifiers to specify pronunciation. The library converts these to IPA and wraps them in SSML `<phoneme>` tags:

```swift
// Each word uses X-SAMPA phonetic input
let md = "(Dasher)[xsampa:\"daS@r\"] (is)[xsampa:\"Iz\"] (like)[xsampa:\"laIk\"]"

// SSML-capable engines produce:
// <speak><phoneme alphabet="ipa" ph="daʃər">Dasher</phoneme> ...</speak>

try await client.speak(md)  // auto-detected, no options needed
```

| Engine | `<phoneme>` Support | Notes |
|--------|---------------------|-------|
| System (AVSynth) | ✅ | Phonemes applied to audio; word boundary events unavailable with SSML input |
| Azure | ✅ | Full support via SSML |
| Polly | ✅ | Full support via SSML |
| Watson | ✅ | Full support via SSML |
| Google | ⚠️ | SpeechMarkdown library strips to plain text for Google platform |
| Others | — | Converted to plain text (no phoneme support) |

#### Direct SpeechMarkdown API

You can also use the `SpeechMarkdown` library directly:

```swift
import SpeechMarkdown

let parser = SpeechMarkdownParser()

// Check if text contains SpeechMarkdown
parser.isSpeechMarkdown(input: "Hello (world)[emphasis:\"strong\"]") // true

// Convert to platform-specific SSML
let ssml = try parser.toSsml(input: "Hello (world)[rate:\"fast\"]", platform: "microsoft-azure")

// Strip to plain text
let text = try parser.toText(input: "Hello (world)[emphasis:\"strong\"]") // "Hello world"
```

Supported platforms: `apple`, `microsoft-azure`, `google-assistant`, `amazon-polly`, `ibm-watson`, `elevenlabs`, `w3c`.

### sherpa-onnx On-Device

```swift
import SwiftTTSWrapperSherpaOnnx

// Download a model
let manager = SherpaOnnxModelManager()
let catalog = SherpaOnnxModelsCatalog.loadBundled()
let entry = catalog["piper-en-ryan-low"]!
try await manager.downloadAndExtract(entry: entry)

// Create engine
let engine = SherpaOnnxDefaultEngine()
let paths = manager.resolveModelPaths(modelId: "piper-en-ryan-low")
try engine.initialize(
    modelPath: paths.modelPath,
    tokensPath: paths.tokensPath,
    voiceDir: paths.voiceDir,
    modelType: .vits,
    dataDir: paths.dataDir,
    lexiconPath: paths.lexiconPath,
    voicesPath: paths.voicesPath,
    vocoderPath: paths.vocoderPath,
    dictDir: paths.dictDir
)

// Use with the client
let client = SherpaOnnxTTSClient(engine: engine)
try await client.speak("Hello from on-device TTS!")
```

## Structure

```
Sources/
├── SwiftTTSWrapper/
│   ├── Types.swift                    // Shared options, formats, voices, boundaries
│   ├── TTSClient.swift               // Unified protocol & abstract base client
│   ├── TTSClientFactory.swift        // Factory enum with all 21 engine cases
│   ├── Engines/
│   │   ├── SystemTTSClient.swift     // AVSpeechSynthesizer (offline, streaming)
│   │   ├── OpenAITTSClient.swift     // OpenAI REST API
│   │   ├── ElevenLabsTTSClient.swift // ElevenLabs REST API (real word timestamps)
│   │   ├── AzureTTSClient.swift      // Azure Cognitive Services
│   │   ├── GoogleTTSClient.swift     // Google Cloud TTS
│   │   ├── CartesiaTTSClient.swift   // Cartesia REST API
│   │   ├── PlayHTTTSClient.swift     // PlayHT REST API
│   │   ├── DeepgramTTSClient.swift   // Deepgram REST API
│   │   ├── FishAudioTTSClient.swift  // Fish Audio REST API
│   │   ├── HumeTTSClient.swift       // Hume REST API
│   │   ├── MistralTTSClient.swift    // Mistral SSE streaming
│   │   ├── ModelsLabTTSClient.swift  // ModelsLab REST API
│   │   ├── MurfTTSClient.swift       // Murf REST API
│   │   ├── PollyTTSClient.swift      // Amazon Polly (native SigV4, no AWS SDK)
│   │   ├── ResembleTTSClient.swift   // Resemble AI REST API
│   │   ├── UnrealSpeechTTSClient.swift
│   │   ├── UpliftAITTSClient.swift
│   │   ├── WatsonTTSClient.swift     // IBM Watson (IAM token refresh)
│   │   ├── WitAITTSClient.swift      // Wit.ai REST API
│   │   ├── XAITTSClient.swift        // xAI REST API
│   │   └── SherpaOnnxTTSClient.swift // On-device sherpa-onnx
│   ├── Utils/
│   │   ├── AudioPlayer.swift         // AVAudioPlayer with boundary timer
│   │   ├── WordTimingEstimator.swift // Heuristic timing for engines without API support
│   │   ├── SherpaOnnxEngine.swift    // Engine protocol, stub, WAV converter
│   │   ├── SherpaOnnxModels.swift    // Model catalog types & loader
│   │   └── SherpaOnnxModelManager.swift // Download/extract/cache models
│   └── Resources/
│       └── merged_models.json        // 1300+ sherpa-onnx model catalog
└── SwiftTTSWrapperSherpaOnnx/
    └── SherpaOnnxDefaultEngine.swift // Default engine calling C API directly
```

## Example App

The `Examples/SimpleTTS` directory contains a macOS SwiftUI demo with SpeechMarkdown editing, formatting toolbar, and multi-engine switching. It depends on sherpa-onnx-spm, which has a known SPM linking issue on macOS: `onnxruntime.a` lacks the `lib` prefix, so SPM won't auto-link it. Use the bundled build script:

```bash
# From repo root — creates the needed symlink and builds
./Examples/SimpleTTS/build.sh
```

Or manually after `swift build`:

```bash
cd Examples/SimpleTTS
ln -sf onnxruntime.a .build/arm64-apple-macosx/debug/libonnxruntime.a
swift build
```

## Swift Package Index Builds

This package depends on binary XCFrameworks ([sherpa-onnx-spm](https://github.com/willwade/sherpa-onnx-spm) and [speechmarkdown-rust](https://github.com/AACTools/speechmarkdown-rust)) that ship macOS and iOS slices only. The Swift Package Index builds on Linux, where these binary targets cannot be resolved, causing SPI to report "no compatibility". The package works fully on macOS 13+ and iOS 16+.

## Requirements

- Swift 5.9+
- macOS 13+ / iOS 16+
- Xcode 15+ (for XCTest runner)

## License

MIT
