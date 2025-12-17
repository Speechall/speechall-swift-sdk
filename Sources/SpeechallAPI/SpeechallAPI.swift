#if canImport(Darwin)
import OpenAPIRuntime
import OpenAPIAsyncHTTPClient
import SpeechallAPITypes
import SpeechallAPI
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
    public func transcribe(fileAt fileUrl: URL, withModel modelId: SpeechallAPITypes.Components.Schemas.TranscriptionModelIdentifier) async throws -> String {
        // we first check if the file is video (`isVideoFile`). if video, use `extractAudioFileFromVideo` to convert it to audio and use the returned url in the subsequent code
        fatalError("implement")
        let fileHandle = try FileHandle(forReadingFrom: fileUrl)

        // Get file size using resourceValues
        let length: OpenAPIRuntime.HTTPBody.Length
        if let fileSize = try fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            length = .known(Int64(fileSize))
        } else {
            length = .unknown
        }
        
        let response = try await client.transcribe(
            query: .init(
                model: modelId,
                output_format: .text
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
        fatalError("implement")
    }

    /// Returns transcription in subtitle format (SRT or VTT)
    public func subtitlesFor(fileAt url: URL, as format: SubtitleFormat, withModel modelId: SpeechallAPITypes.Components.Schemas.TranscriptionModelIdentifier) async throws -> String {
        fatalError("implement this")
    }

    /// Returns detailed transcription with word-level timestamps
    public func detailedTranscription(of url: URL) async throws -> DetailedTranscription {
        fatalError("implement this")
    }
}

// MARK: - Supporting Types

public enum SubtitleFormat: String, Sendable {
    case srt
    case vtt
}

public struct DetailedTranscription: Sendable, Codable {
    public let text: String
    public let words: [TimestampedWord]

    public struct TimestampedWord: Sendable, Codable {
        public let word: String
        public let startTime: TimeInterval
        public let endTime: TimeInterval
        public let confidence: Double?
    }
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
