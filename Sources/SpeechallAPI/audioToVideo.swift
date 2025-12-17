#if canImport(Darwin)
import Foundation
import AVFoundation

/// Return audio file url in temporary folder
func extractAudioFileFromVideo(_ url: URL) async throws -> URL {

    let audioUrl = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("m4a")
    let asset = AVAsset(url: url)

    // Extract only audio
    let audioTrack = AVMutableComposition()
    guard
        let compositionAudioTrack = audioTrack.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
    else {
        throw NSError(domain: "AudioExtraction", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio track"])
    }

    // Get the audio track from the video
    guard let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
        throw NSError(domain: "AudioExtraction", code: -3, userInfo: [NSLocalizedDescriptionKey: "No audio track found in video"])
    }

    // Add the audio track to our composition
    try compositionAudioTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: try await asset.load(.duration)),
        of: sourceAudioTrack,
        at: .zero
    )

    // Create an export session with our composition
    guard
        let exportSession = AVAssetExportSession(
            asset: audioTrack,
            presetName: AVAssetExportPresetAppleM4A
        )
    else {
        throw NSError(domain: "AudioExtraction", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
    }

    // Configure export session
    exportSession.outputURL = audioUrl
    exportSession.outputFileType = .m4a
    exportSession.shouldOptimizeForNetworkUse = true

    // Perform the export
    await exportSession.export()

    if let error = exportSession.error {
        try? FileManager.default.removeItem(at: audioUrl)
        throw error
    }

    return audioUrl
}

#endif
