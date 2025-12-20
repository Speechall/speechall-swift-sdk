# SpeechallAPI

A Swift SDK for the [Speechall](https://speechall.com) speech-to-text API. Transcribe audio and video files using multiple STT providers through a unified interface.

## Features

- **Simple, developer-friendly API** - Get transcriptions with just a few lines of code
- **Memory-efficient streaming** - Files are streamed directly from disk using `FileHandle`, never loaded entirely into memory
- **Video file support** - Pass video files (mp4, mov, m4v, avi) directly; audio is extracted automatically
- **Multiple output formats** - Plain text, SRT subtitles, VTT subtitles, or detailed JSON with timestamps
- **Type-safe** - Fully generated from OpenAPI spec with Swift OpenAPI Generator

## Requirements

- macOS 13+ / iOS 16+ / tvOS 16+ / watchOS 9+
- Swift 5.9+

## Installation

Add SpeechallAPI to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Speechall-SDK/speechall-swift-sdk", from: "0.0.1")
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "SpeechallAPI", package: "speechall-swift-sdk")
    ]
)
```

## Quick Start

```swift
import SpeechallAPI

// Initialize the client with your API key
let client = SpeechallClient(apiKey: "your-api-key")

// Transcribe an audio or video file to plain text
let transcription = try await client.transcribe(
    fileAt: URL(filePath: "/path/to/audio.mp3"),
    withModel: .cloudflare_period_whisper
)

print(transcription)
```

## Convenience Methods

The `SpeechallClient` provides three main methods for common transcription tasks:

### Plain Text Transcription

```swift
let text = try await client.transcribe(
    fileAt: audioUrl,
    withModel: .cloudflare_period_whisper,
    inLanguage: .en,  // Optional, defaults to .auto
    withInitialContext: "Technical discussion about Swift programming"  // Optional
)
```

### Subtitles (SRT or VTT)

```swift
// SRT format
let srtSubtitles = try await client.subtitlesFor(
    fileAt: videoUrl,
    as: .srt,
    withModel: .assemblyai_period_best,
    inLanguage: .auto
)

// VTT format
let vttSubtitles = try await client.subtitlesFor(
    fileAt: videoUrl,
    as: .vtt,
    withModel: .assemblyai_period_best
)
```

### Detailed Transcription with Timestamps

Get word-level or segment-level timestamps:

```swift
let detailed = try await client.detailedTranscription(
    of: audioUrl,
    withModel: .deepgram_period_nova_hyphen_2
)

print("Full text: \(detailed.text)")
print("Language: \(detailed.language ?? "unknown")")

// Access individual segments with timestamps
for segment in detailed.segments ?? [] {
    print("[\(segment.start ?? 0) - \(segment.end ?? 0)] \(segment.text ?? "")")
}

// Access individual words with timestamps
for word in detailed.words ?? [] {
    print("[\(word.start) - \(word.end)] \(word.word)")
}
```

## Available Models

The SDK supports a wide range of speech-to-text models from various providers:

| Provider | Model Identifiers |
|----------|------------------|
| OpenAI | `openai.whisper_1`, `openai.gpt_4o_transcribe`, `openai.gpt_4o_mini_transcribe` |
| Cloudflare | `cloudflare.whisper` |
| Deepgram | `deepgram.nova_2`, `deepgram.nova`, `deepgram.base`, `deepgram.whisper_large`, etc. |
| AssemblyAI | `assemblyai.best`, `assemblyai.nano` |
| Groq | `groq.whisper_large_v3`, `groq.whisper_large_v3_turbo`, `groq.distil_whisper_large_v3_en` |
| ElevenLabs | `elevenlabs.scribe_v1` |
| Gladia | `gladia.default` |
| Amazon | `amazon.transcribe` |
| RevAI | `revai.default` |
| And more... | |

Use autocomplete on `Components.Schemas.TranscriptionModelIdentifier` to see all available options.

## Advanced Usage: Full API Access

For advanced features like speaker diarization, custom vocabulary, text replacement rules, and more, you can use the fully-typed generated client directly:

```swift
import SpeechallAPI
import SpeechallAPITypes
import OpenAPIRuntime
import OpenAPIAsyncHTTPClient

// Create the low-level client
let client = SpeechallAPI.Client(
    serverURL: URL(string: "https://api.speechall.com/v1")!,
    transport: AsyncHTTPClientTransport(),
    middlewares: [AuthenticationMiddleware(apiKey: "your-api-key")]
)
```

### Speaker Diarization

Identify different speakers in the audio:

```swift
let audioData = try Data(contentsOf: audioUrl)
let response = try await client.transcribe(
    query: .init(
        model: .deepgram_period_nova_hyphen_2,
        language: .en,
        output_format: .json,
        diarization: true,
        speakers_expected: 2  // Optional hint
    ),
    body: .audio__ast_(HTTPBody(audioData))
)

if case .ok(let result) = response,
   case .json(let transcription) = result.body,
   case .TranscriptionDetailed(let detailed) = transcription {
    for segment in detailed.segments ?? [] {
        print("Speaker \(segment.speaker ?? "?"): \(segment.text ?? "")")
    }
}
```

### Custom Vocabulary

Improve recognition of specific terms:

```swift
let response = try await client.transcribe(
    query: .init(
        model: .assemblyai_period_best,
        custom_vocabulary: ["Speechall", "OpenAPI", "AsyncHTTPClient"]
    ),
    body: .audio__ast_(HTTPBody(audioData))
)
```

### Temperature Control

Adjust output randomness for supported models:

```swift
let response = try await client.transcribe(
    query: .init(
        model: .openai_period_whisper_hyphen_1,
        temperature: 0.2  // Lower = more deterministic
    ),
    body: .audio__ast_(HTTPBody(audioData))
)
```

### Transcribe from Remote URL

Transcribe audio hosted at a public URL without downloading it first:

```swift
let response = try await client.transcribeRemote(
    body: .json(.init(
        url: "https://example.com/audio.mp3",
        model: .cloudflare_period_whisper
    ))
)
```

### Text Replacement Rulesets

Create reusable text replacement rules for post-processing:

```swift
// Create a ruleset
let rulesetResponse = try await client.createReplacementRuleset(
    body: .json(.init(
        name: "Technical Terms",
        rules: [
            .init(_type: .exact, pattern: "swift", replacement: "Swift"),
            .init(_type: .regex, pattern: "\\bapi\\b", replacement: "API")
        ]
    ))
)

// Use the ruleset in transcription
if case .created(let created) = rulesetResponse,
   case .json(let ruleset) = created.body {
    let response = try await client.transcribe(
        query: .init(
            model: .cloudflare_period_whisper,
            ruleset_id: ruleset.id
        ),
        body: .audio__ast_(HTTPBody(audioData))
    )
}
```

### List Available Models

Discover all available models and their capabilities:

```swift
let modelsResponse = try await client.listSpeechToTextModels()

if case .ok(let result) = modelsResponse,
   case .json(let models) = result.body {
    for model in models {
        print("\(model.display_name) (\(model.id.rawValue))")
        print("  Diarization: \(model.diarization ?? false)")
        print("  Streamable: \(model.streamable ?? false)")
        print("  Languages: \(model.supported_languages?.joined(separator: ", ") ?? "N/A")")
    }
}
```

### OpenAI-Compatible Endpoint

Use the OpenAI-compatible endpoint for easy migration.  
Set the base URL to `https://api.speechall.com/v1/openai-compatible/audio/transcriptions` in your OpenAI client from whichever library you are using.

## Error Handling

The convenience methods throw descriptive errors:

```swift
do {
    let text = try await client.transcribe(fileAt: audioUrl, withModel: .cloudflare_period_whisper)
} catch TranscriptionError.invalidFile {
    print("File could not be read or is not a supported format")
} catch TranscriptionError.invalidResponse {
    print("Server returned an invalid response")
} catch TranscriptionError.apiError(let message, let code) {
    print("API error \(code): \(message)")
} catch TranscriptionError.networkError(let error) {
    print("Network error: \(error.localizedDescription)")
}
```

## Configuration

### Custom Base URL for Proxying

```swift
let client = SpeechallClient(
    baseUrl: URL(string: "https://custom-endpoint.example.com/v1")!,
    apiKey: "your-api-key"
)
```

### Request Timeout

The default timeout is 1200 seconds (20 minutes) to accommodate large files:

```swift
let client = SpeechallClient(
    apiKey: "your-api-key",
    timeoutInSeconds: 3600  // 1 hour
)
```

## License

See [LICENSE](LICENSE) for details.
