#if canImport(Darwin)
import OpenAPIRuntime
import OpenAPIAsyncHTTPClient
import SpeechallAPITypes
import Foundation
import UsefulThings


public struct SpeechallClient: Sendable {
    public let baseUrl: URL
    public let apiKey: String
    public let timeoutInSeconds: TimeInterval
    
    private let client: SpeechallAPI.Client

    public init(baseUrl: URL = URL(string: "https://api.speechall.com/v1")!, apiKey: String, timeoutInSeconds: TimeInterval = 1200) {
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.timeoutInSeconds = timeoutInSeconds
        
        self.client = SpeechallAPI.Client(
           serverURL: URL(string: "https://api.speechall.com/v1")!,
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

        let response = try await client.transcribe(
            query: .init(
                model: modelId,
                language: language,
                output_format: .text,
                punctuation: true,
                initial_prompt: initialContext
            ),
            body: .audio__ast_(
                HTTPBody(
                    // UsefulThings library conforms FileHandle to AsyncSequence, so that we send it chunk by chunk without loading the entire file to memory
                    fileHandle,
                    length: length,
                    iterationBehavior: .single
                )
            )
        )
        let plainTextBody: HTTPBody = try response.ok.body.plainText
        // convert plainTextBody to String
        let buffer = try await plainTextBody.collect(upTo: 100 * 1024 * 1024, using: .init())
        return String(buffer: buffer)
    }

    /// Returns transcription in subtitle format (SRT or VTT)
    public func subtitlesFor(
        fileAt fileUrl: URL,
        as format: SubtitleFormat,
        withModel modelId: SpeechallAPITypes.Components.Schemas.TranscriptionModelIdentifier,
        inLanguage language: Components.Schemas.TranscriptLanguageCode = .auto
    ) async throws -> String {
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

        let outputFormat: Components.Schemas.TranscriptOutputFormat = format == .srt ? .srt : .vtt

        let response = try await client.transcribe(
            query: .init(
                model: modelId,
                language: language,
                output_format: outputFormat,
                punctuation: true
            ),
            body: .audio__ast_(
                HTTPBody(
                    fileHandle,
                    length: length,
                    iterationBehavior: .single
                )
            )
        )
        let plainTextBody: HTTPBody = try response.ok.body.plainText
        let buffer = try await plainTextBody.collect(upTo: 100 * 1024 * 1024, using: .init())
        return String(buffer: buffer)
    }

    /// Returns detailed transcription with word-level timestamps
    public func detailedTranscription(
        of fileUrl: URL,
        withModel modelId: SpeechallAPITypes.Components.Schemas.TranscriptionModelIdentifier,
        inLanguage language: Components.Schemas.TranscriptLanguageCode = .auto
    ) async throws -> Components.Schemas.TranscriptionDetailed {
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

        let response = try await client.transcribe(
            query: .init(
                model: modelId,
                language: language,
                output_format: .json,
                punctuation: true
            ),
            body: .audio__ast_(
                HTTPBody(
                    fileHandle,
                    length: length,
                    iterationBehavior: .single
                )
            )
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
#endif
