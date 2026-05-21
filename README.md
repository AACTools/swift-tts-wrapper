# swift-tts-wrapper

A native Swift package that provides a unified interface for working with local offline and cloud-based Text-to-Speech (TTS) services on iOS and macOS. Inspired by [js-tts-wrapper](file:///Users/willwade/GitHub/DasherProjects/js-tts-wrapper), it simplifies speech synthesis across multiple engines with a single consistent API.

## Features

- **Unified API**: A single protocol (`TTSClient`) with consistent methods for speech synthesis and playback control.
- **Local Offline TTS**: Fully wraps Apple's native `AVSpeechSynthesizer` with real-time delegate word boundary tracking.
- **Cloud Services**: Standard REST API clients for OpenAI, ElevenLabs, Microsoft Azure Cognitive Services, and Google Cloud TTS with no external dependencies.
- **Real-Time Word Timing**: Custom boundary tracking aligned to the audio player's playback position to fire word boundaries at the exact moment words are spoken.
- **Multi-Source Playback**: Support for speaking text, playing local file URLs, raw binary audio data buffer blocks, or raw async byte streams.

## Supported Engines

| Engine ID | Client Class | Environment | Provider |
|-----------|--------------|-------------|----------|
| `system` | `SystemTTSClient` | macOS, iOS | Apple native AVSpeechSynthesizer (offline) |
| `openai` | `OpenAITTSClient` | macOS, iOS | OpenAI REST API (`tts-1` / `tts-1-hd`) |
| `elevenlabs` | `ElevenLabsTTSClient` | macOS, iOS | ElevenLabs REST API |
| `azure` | `AzureTTSClient` | macOS, iOS | Microsoft Azure Cognitive Services |
| `google` | `GoogleTTSClient` | macOS, iOS | Google Cloud Text-to-Speech |

## Quick Start

### Instantiating a Client

You can use the factory pattern to create clients dynamically:

```swift
import SwiftTTSWrapper

// 1. Local offline synthesizer
let systemClient = TTSClientFactory.create(engine: .system)

// 2. Cloud-based OpenAI synthesizer
let credentials = ["apiKey": "sk-your-openai-api-key"]
let openaiClient = TTSClientFactory.create(engine: .openai, credentials: credentials)
```

### Synthesis & Speech Playback

To synthesize and speak text:

```swift
// Basic speech
try await client.speak("Hello, world!")

// Custom speech options
let options = SpeakOptions(
    rate: .slow,
    pitch: .medium,
    volume: 0.9,
    useWordBoundary: true
)

// Configure callbacks
client.onStart = {
    print("Speech started")
}
client.onBoundary = { boundary in
    print("Spoken word: \(boundary.text) at \(boundary.offset)ms")
}
client.onEnd = {
    print("Speech completed")
}

try await client.speak("Hello from swift-tts-wrapper!", options: options)
```

### Direct Byte Generation

To generate raw audio data bytes instead of playing back immediately:

```swift
let audioBytes = try await client.synthToBytes("Create audio bytes to save or transmit", options: options)
// Returns raw audio Data (MP3, WAV, etc. depending on format settings)
```

### Voice Management

```swift
// List available voices
let voices = try await client.getVoices()

for voice in voices {
    print("Voice Name: \(voice.name), Gender: \(voice.gender), Lang: \(voice.languageCodes.first?.display ?? "")")
}
```

## Structure

```
swift-tts-wrapper/
├── Package.swift
├── README.md
├── Sources/
│   └── SwiftTTSWrapper/
│       ├── Types.swift            // Shared options, formats, voices, and boundaries
│       ├── TTSClient.swift        // Unified protocol & abstract base client
│       ├── TTSClientFactory.swift  // Factory class helper
│       ├── Engines/
│       │   ├── SystemTTSClient.swift     // AVSpeechSynthesizer offline wrapper
│       │   ├── OpenAITTSClient.swift     // OpenAI REST API client
│       │   ├── ElevenLabsTTSClient.swift // ElevenLabs REST API client
│       │   ├── AzureTTSClient.swift      // Azure REST API client
│       │   └── GoogleTTSClient.swift     // Google Cloud REST API client
│       └── Utils/
│           ├── AudioPlayer.swift         // AVAudioPlayer wrap with boundary timer
│           └── WordTimingEstimator.swift // Timing algorithm for cloud responses
└── Tests/
    └── SwiftTTSWrapperTests/
        └── SwiftTTSWrapperTests.swift    // Unit tests
```
