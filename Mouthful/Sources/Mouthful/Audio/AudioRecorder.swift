import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError {
  case noInputDevice
  case engineFailed(String)

  var errorDescription: String? {
    switch self {
    case .noInputDevice: return "No microphone found. Connect one or pick an input in System Settings → Sound."
    case .engineFailed(let message): return "Could not start the microphone: \(message)"
    }
  }
}

/// Captures the default microphone and converts it on the fly to 16 kHz mono Float32,
/// the format every speech engine here expects.
final class AudioRecorder {
  static let targetSampleRate: Double = 16000

  /// RMS level of the latest chunk (0…1), delivered on the main thread.
  var onLevel: ((Float) -> Void)?

  private(set) var isRecording = false
  private var engine: AVAudioEngine?
  private var converter: AVAudioConverter?
  private let lock = NSLock()
  private var samples: [Float] = []

  var duration: TimeInterval {
    lock.lock(); defer { lock.unlock() }
    return Double(samples.count) / Self.targetSampleRate
  }

  func start() throws {
    guard !isRecording else { return }
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw AudioRecorderError.noInputDevice }
    guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.targetSampleRate,
                                           channels: 1, interleaved: false),
          let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
      throw AudioRecorderError.engineFailed("Unsupported microphone format")
    }
    self.converter = converter

    lock.lock()
    samples.removeAll(keepingCapacity: true)
    lock.unlock()

    let ratio = Self.targetSampleRate / inputFormat.sampleRate
    input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
      guard let self else { return }
      let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
      guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
      var consumed = false
      var conversionError: NSError?
      let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
        if consumed {
          outStatus.pointee = .noDataNow
          return nil
        }
        consumed = true
        outStatus.pointee = .haveData
        return buffer
      }
      guard status != .error, output.frameLength > 0, let channel = output.floatChannelData?[0] else { return }
      let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))

      self.lock.lock()
      self.samples.append(contentsOf: chunk)
      self.lock.unlock()

      if let onLevel = self.onLevel {
        var sum: Float = 0
        for sample in chunk { sum += sample * sample }
        let rms = sqrt(sum / Float(max(chunk.count, 1)))
        DispatchQueue.main.async { onLevel(rms) }
      }
    }

    engine.prepare()
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      throw AudioRecorderError.engineFailed(error.localizedDescription)
    }
    self.engine = engine
    isRecording = true
  }

  /// Stops capturing and returns everything recorded since `start()`.
  func stop() -> [Float] {
    guard isRecording, let engine else { return [] }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    self.engine = nil
    converter = nil
    isRecording = false
    lock.lock()
    let result = samples
    samples = []
    lock.unlock()
    return result
  }
}
