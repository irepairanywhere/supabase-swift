import Foundation

/// Encodes float PCM samples as a 16-bit little-endian WAV file, the format every
/// transcription API accepts.
public enum WAVEncoder {
  public static func encode16BitPCM(samples: [Float], sampleRate: Int, channels: Int = 1) -> Data {
    let bitsPerSample = 16
    let blockAlign = channels * bitsPerSample / 8
    let byteRate = sampleRate * blockAlign
    let dataSize = samples.count * 2

    var data = Data(capacity: 44 + dataSize)
    data.append(ascii: "RIFF")
    data.append(uint32: UInt32(36 + dataSize))
    data.append(ascii: "WAVE")
    data.append(ascii: "fmt ")
    data.append(uint32: 16)
    data.append(uint16: 1) // PCM
    data.append(uint16: UInt16(channels))
    data.append(uint32: UInt32(sampleRate))
    data.append(uint32: UInt32(byteRate))
    data.append(uint16: UInt16(blockAlign))
    data.append(uint16: UInt16(bitsPerSample))
    data.append(ascii: "data")
    data.append(uint32: UInt32(dataSize))

    var pcm = [Int16](repeating: 0, count: samples.count)
    for (i, s) in samples.enumerated() {
      let clamped = max(-1, min(1, s))
      pcm[i] = Int16(clamped * Float(Int16.max))
    }
    pcm.withUnsafeBufferPointer { buffer in
      data.append(buffer)
    }
    return data
  }
}

extension Data {
  mutating func append(ascii string: String) {
    append(contentsOf: Array(string.utf8))
  }

  mutating func append(uint32 value: UInt32) {
    var v = value.littleEndian
    Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
  }

  mutating func append(uint16 value: UInt16) {
    var v = value.littleEndian
    Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
  }
}
