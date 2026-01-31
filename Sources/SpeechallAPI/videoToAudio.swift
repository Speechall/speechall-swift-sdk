import Foundation

// MARK: - Platform-aware video file detection

private let _appleVideoExtensions = ["mp4", "mov", "m4v", "avi"]
private let _ffmpegVideoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "flv", "wmv"]

func isVideoFile(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    #if canImport(AVFoundation)
    return _appleVideoExtensions.contains(ext)
    #elseif canImport(FFmpeg)
    return _ffmpegVideoExtensions.contains(ext)
    #else
    // On unsupported platforms, still detect videos so extractAudioFileFromVideo
    // can throw a clear error rather than silently sending video data to the API.
    return _appleVideoExtensions.contains(ext)
    #endif
}

// MARK: - Apple platforms: AVFoundation

#if canImport(AVFoundation)
import AVFoundation

/// Return audio file url in temporary folder
public func extractAudioFileFromVideo(_ url: URL) async throws -> URL {

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

// MARK: - Linux: FFmpeg remux

#elseif canImport(FFmpeg)
import FFmpeg

/// Return audio file url in temporary folder using FFmpeg remux (stream copy)
public func extractAudioFileFromVideo(_ url: URL) async throws -> URL {
    let audioUrl = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("m4a")

    do {
        try ffmpegRemuxAudio(from: url.path, to: audioUrl.path)
    } catch {
        try? FileManager.default.removeItem(at: audioUrl)
        throw error
    }

    return audioUrl
}

/// Remux the audio track from a video file into an M4A container (stream copy, no re-encoding).
private func ffmpegRemuxAudio(from inputPath: String, to outputPath: String) throws {
    // --- Open input ---
    var inputFormatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
    try FFmpegError.check(avformat_open_input(&inputFormatCtx, inputPath, nil, nil))
    defer { avformat_close_input(&inputFormatCtx) }

    try FFmpegError.check(avformat_find_stream_info(inputFormatCtx, nil))

    // --- Find audio stream ---
    let audioStreamIndex = av_find_best_stream(
        inputFormatCtx,
        AVMEDIA_TYPE_AUDIO,
        -1,   // auto-select
        -1,   // no related stream
        nil,  // no decoder needed for remux
        0
    )
    guard audioStreamIndex >= 0 else {
        throw NSError(
            domain: "AudioExtraction",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "No audio track found in video"]
        )
    }

    let inputStream = inputFormatCtx!.pointee.streams[Int(audioStreamIndex)]!

    // --- Setup output ---
    var outputFormatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
    try FFmpegError.check(
        avformat_alloc_output_context2(&outputFormatCtx, nil, "ipod", outputPath)
    )
    defer {
        if let ctx = outputFormatCtx {
            if ctx.pointee.pb != nil {
                avio_closep(&ctx.pointee.pb)
            }
            avformat_free_context(ctx)
        }
    }

    // --- Add output audio stream ---
    guard let outputStream = avformat_new_stream(outputFormatCtx, nil) else {
        throw NSError(
            domain: "AudioExtraction",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Failed to create output audio stream"]
        )
    }

    try FFmpegError.check(
        avcodec_parameters_copy(outputStream.pointee.codecpar, inputStream.pointee.codecpar)
    )
    // Let the muxer choose the appropriate codec tag for the container
    outputStream.pointee.codecpar.pointee.codec_tag = 0

    // --- Open output file ---
    if (outputFormatCtx!.pointee.oformat.pointee.flags & AVFMT_NOFILE) == 0 {
        try FFmpegError.check(
            avio_open(&outputFormatCtx!.pointee.pb, outputPath, AVIO_FLAG_WRITE)
        )
    }

    // --- Write header ---
    try FFmpegError.check(avformat_write_header(outputFormatCtx, nil))

    // --- Copy audio packets ---
    var pkt: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
    guard pkt != nil else {
        throw NSError(
            domain: "AudioExtraction",
            code: -4,
            userInfo: [NSLocalizedDescriptionKey: "Failed to allocate packet"]
        )
    }
    defer { av_packet_free(&pkt) }

    while true {
        let readResult = av_read_frame(inputFormatCtx, pkt)
        if readResult == AVERROR_EOF {
            break
        }
        if readResult < 0 {
            try FFmpegError.check(readResult)
        }

        // Skip non-audio packets
        if pkt!.pointee.stream_index != audioStreamIndex {
            av_packet_unref(pkt)
            continue
        }

        // Remap to output stream index (always 0, since we only have one output stream)
        pkt!.pointee.stream_index = 0

        // Rescale timestamps from input to output time base
        av_packet_rescale_ts(pkt, inputStream.pointee.time_base, outputStream.pointee.time_base)
        pkt!.pointee.pos = -1

        // av_interleaved_write_frame takes ownership of the packet (unrefs it)
        try FFmpegError.check(av_interleaved_write_frame(outputFormatCtx, pkt))
    }

    // --- Write trailer ---
    try FFmpegError.check(av_write_trailer(outputFormatCtx))
}

// MARK: - Unsupported platform fallback

#else

public func extractAudioFileFromVideo(_ url: URL) async throws -> URL {
    throw NSError(
        domain: "AudioExtraction",
        code: -10,
        userInfo: [NSLocalizedDescriptionKey: "Audio extraction from video is not supported on this platform"]
    )
}

#endif
