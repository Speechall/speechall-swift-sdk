import OpenAPIRuntime
import OpenAPIAsyncHTTPClient
import SpeechallAPITypes
import Foundation
import UsefulThings


public struct SpeechallClient: Sendable {
    private let client: SpeechallAPI.Client

    public init(baseUrl: URL = URL(string: "https://api.speechall.com/v1")!, apiKey: String, timeoutInSeconds: TimeInterval = 1200) {
        self.client = SpeechallAPI.Client(
           serverURL: baseUrl,
           transport: AsyncHTTPClientTransport(
            configuration: .init(
                timeout: .seconds(
                    .init(
                        timeoutInSeconds
                    )
                )
            )
           ),
           middlewares: [AuthenticationMiddleware(apiKey: apiKey)]
        )
    }
}

extension SpeechallClient {
    /// Returns plain text transcription
    public func transcribe(
        fileAt fileUrl: URL,
        withModel modelId: SpeechallAPITypes.Components.Schemas.TranscriptionModelIdentifier,
        inLanguage language: Components.Schemas.TranscriptLanguageCode = .auto,
        withInitialContext initialContext: String? = nil
    ) async throws -> String {
        let body = try await prepareAudioBody(from: fileUrl)

        let response = try await client.transcribe(
            query: .init(
                model: modelId,
                language: language,
                output_format: .text,
                punctuation: true,
                initial_prompt: initialContext
            ),
            body: .audio__ast_(body)
        )
        return try await response.ok.body.plainText.toString()
    }

    /// Returns transcription in subtitle format (SRT or VTT)
    public func subtitlesFor(
        fileAt fileUrl: URL,
        as format: SubtitleFormat,
        withModel modelId: SpeechallAPITypes.Components.Schemas.TranscriptionModelIdentifier,
        inLanguage language: Components.Schemas.TranscriptLanguageCode = .auto
    ) async throws -> String {
        let body = try await prepareAudioBody(from: fileUrl)
        let outputFormat: Components.Schemas.TranscriptOutputFormat = format == .srt ? .srt : .vtt

        let response = try await client.transcribe(
            query: .init(
                model: modelId,
                language: language,
                output_format: outputFormat,
                punctuation: true
            ),
            body: .audio__ast_(body)
        )
        return try await response.ok.body.plainText.toString()
    }

    /// Returns detailed transcription with word-level timestamps
    public func detailedTranscription(
        of fileUrl: URL,
        withModel modelId: SpeechallAPITypes.Components.Schemas.TranscriptionModelIdentifier,
        inLanguage language: Components.Schemas.TranscriptLanguageCode = .auto
    ) async throws -> Components.Schemas.TranscriptionDetailed {
        let body = try await prepareAudioBody(from: fileUrl)

        let response = try await client.transcribe(
            query: .init(
                model: modelId,
                language: language,
                output_format: .json,
                punctuation: true
            ),
            body: .audio__ast_(body)
        )

        let transcriptionResponse = try response.ok.body.json
        switch transcriptionResponse {
        case .TranscriptionDetailed(let detailed):
            return detailed
        case .TranscriptionOnlyText:
            throw TranscriptionError.invalidResponse
        }
    }
}

// MARK: - HTTPBody Extensions

extension HTTPBody {
    func toString(maxBytes: Int = 100 * 1024 * 1024) async throws -> String {
        let buffer = try await collect(upTo: maxBytes, using: .init())
        return String(buffer: buffer)
    }
}

// MARK: - Private Helpers

extension SpeechallClient {
    private func prepareAudioBody(from fileUrl: URL) async throws -> HTTPBody {
        // Check if file is video and extract audio if needed
        let audioUrl: URL
        if isVideoFile(fileUrl) {
            audioUrl = try await extractAudioFileFromVideo(fileUrl)
        } else {
            audioUrl = fileUrl
        }

        let fileHandle = try FileHandle(forReadingFrom: audioUrl)

        // Get file size using resourceValues
        let length: OpenAPIRuntime.HTTPBody.Length
        if let fileSize = try audioUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            length = .known(Int64(fileSize))
        } else {
            length = .unknown
        }

        return HTTPBody(
            fileHandle,
            length: length,
            iterationBehavior: .single
        )
    }
}

// MARK: - Supporting Types

public enum SubtitleFormat: String, Sendable {
    case srt
    case vtt
}

// MARK: - Custom Errors

public enum TranscriptionError: Error, LocalizedError {
    case invalidFile
    case networkError(underlying: Error)
    case invalidResponse
    case apiError(message: String, code: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "The file could not be read or is not a supported format."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "The server returned an invalid response."
        case .apiError(let message, _):
            return message
        }
    }
}
