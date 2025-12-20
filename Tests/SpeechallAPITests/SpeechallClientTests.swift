//
// https://github.com/atacan
// 18.12.25

import Testing
import SpeechallAPI
import SpeechallAPITypes
import UsefulThings
#if os(Linux)
@preconcurrency import struct Foundation.URL
#else
import struct Foundation.URL
#endif

struct SpeechallClientTests {
    let client: SpeechallClient = {
        let envFileUrl = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".env")
        guard let apiKey = UsefulThings.getEnvironmentVariable("API_KEY", from: envFileUrl) else {
            preconditionFailure("API_KEY not found in .env file")
        }
        return SpeechallClient(apiKey: apiKey)
    }()

    let sampleAudioUrl = URL(fileURLWithPath: "/Users/atacan/Developer/Repositories/Speechall-SDK/speechall-typescript-sdk/examples/sample-audio.wav")

    @Test func testTranscribe() async throws {
        let transcription = try await client.transcribe(
            fileAt: sampleAudioUrl,
            withModel: .cloudflare_period_whisper
        )

        #expect(!transcription.isEmpty, "Transcription should not be empty")
    }

    @Test func testSubtitlesForSRT() async throws {
        let subtitles = try await client.subtitlesFor(
            fileAt: sampleAudioUrl,
            as: .srt,
            withModel: .cloudflare_period_whisper
        )

        #expect(!subtitles.isEmpty, "Subtitles should not be empty")
        // SRT format contains timestamp arrows like "00:00:00,000 --> 00:00:01,000"
        #expect(subtitles.contains("-->"), "SRT should contain timestamp arrows")
    }

    @Test func testSubtitlesForVTT() async throws {
        let subtitles = try await client.subtitlesFor(
            fileAt: sampleAudioUrl,
            as: .vtt,
            withModel: .cloudflare_period_whisper
        )

        #expect(!subtitles.isEmpty, "Subtitles should not be empty")
        #expect(subtitles.contains("WEBVTT"), "VTT should contain WEBVTT header")
    }

    @Test func testDetailedTranscription() async throws {
        let detailed = try await client.detailedTranscription(
            of: sampleAudioUrl,
            withModel: .cloudflare_period_whisper
        )

        #expect(!detailed.id.isEmpty, "Transcription ID should not be empty")
        #expect(!detailed.text.isEmpty, "Transcription text should not be empty")
    }
}
