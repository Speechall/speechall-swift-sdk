func createWAVHeader(sampleRate: Int, channelCount: Int, bitsPerSample: Int, dataSize: Int) -> [UInt8] {
    let byteRate = sampleRate * channelCount * bitsPerSample / 8
    let blockAlign = channelCount * bitsPerSample / 8

    var header: [UInt8] = []

    // RIFF header
    header.append(contentsOf: "RIFF".utf8)
    header.append(contentsOf: UInt32(36 + dataSize).littleEndian.byteArray)  // Chunk size
    header.append(contentsOf: "WAVE".utf8)

    // fmt subchunk
    header.append(contentsOf: "fmt ".utf8)
    header.append(contentsOf: UInt32(16).littleEndian.byteArray)  // Subchunk size
    header.append(contentsOf: UInt16(3).littleEndian.byteArray)  // Audio format (3 = IEEE float)
    header.append(contentsOf: UInt16(channelCount).littleEndian.byteArray)
    header.append(contentsOf: UInt32(sampleRate).littleEndian.byteArray)
    header.append(contentsOf: UInt32(byteRate).littleEndian.byteArray)
    header.append(contentsOf: UInt16(blockAlign).littleEndian.byteArray)
    header.append(contentsOf: UInt16(bitsPerSample).littleEndian.byteArray)

    // data subchunk
    header.append(contentsOf: "data".utf8)
    header.append(contentsOf: UInt32(dataSize).littleEndian.byteArray)

    return header
}

extension FixedWidthInteger {
    var byteArray: [UInt8] {
        withUnsafeBytes(of: self.littleEndian) { Array($0) }
    }
}
