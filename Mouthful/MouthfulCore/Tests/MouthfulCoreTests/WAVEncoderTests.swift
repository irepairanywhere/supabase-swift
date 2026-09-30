import XCTest
@testable import MouthfulCore

final class WAVEncoderTests: XCTestCase {
  func testHeaderAndSize() {
    let samples: [Float] = [0, 0.5, -0.5, 1, -1, 2, -2]
    let data = WAVEncoder.encode16BitPCM(samples: samples, sampleRate: 16000)
    XCTAssertEqual(data.count, 44 + samples.count * 2)
    XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "RIFF")
    XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
    XCTAssertEqual(String(data: data[12..<16], encoding: .ascii), "fmt ")
    XCTAssertEqual(String(data: data[36..<40], encoding: .ascii), "data")

    func le32(_ offset: Int) -> UInt32 { data[offset..<offset + 4].reduce(0) { ($0 >> 8) | (UInt32($1) << 24) } }
    func le16(_ offset: Int) -> UInt16 { UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8) }
    XCTAssertEqual(le32(4), UInt32(36 + samples.count * 2))
    XCTAssertEqual(le16(20), 1) // PCM
    XCTAssertEqual(le16(22), 1) // mono
    XCTAssertEqual(le32(24), 16000)
    XCTAssertEqual(le32(28), 32000)
    XCTAssertEqual(le16(32), 2)
    XCTAssertEqual(le16(34), 16)
    XCTAssertEqual(le32(40), UInt32(samples.count * 2))

    // Samples are clamped to [-1, 1] and scaled to Int16.
    let first = Int16(bitPattern: le16(44))
    let second = Int16(bitPattern: le16(46))
    let overflow = Int16(bitPattern: le16(54))
    XCTAssertEqual(first, 0)
    XCTAssertEqual(second, Int16(0.5 * Float(Int16.max)))
    XCTAssertEqual(overflow, Int16.max)
  }
}
