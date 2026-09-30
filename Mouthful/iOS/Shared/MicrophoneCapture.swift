import AVFoundation
import Foundation

enum MicrophoneCaptureError: LocalizedError {
  case noInput
  case engineFailed(String)

  var errorDescription: String? {
    switch self {
    case .noInput: return "No microphone input is available."
    case .engineFailed(let message): return "Could not start the microphone: \(message)"
    }
  }
}

/// Captures the microphone. Hands native buffers to a live recognizer and, when asked,
/// also accumulates 16 kHz mono samples for cloud transcription.
final class MicrophoneCapture {
  static let targetSampleRate: Double = 16000

  /// Called on the audio thread with buffers in the device's native format.
  var onNativeBuffer: ((AVAudioPCMBuffer) -> Void)?
  /// RMS level 0…1 of the latest buffer, delivered on the main thread.
  var onLevel: ((Float) -> Void)?
  var collectsSamples = false

  private(set) var isRunning = false
  private var engine: AVAudioEngine?
  private var converter: AVAudioConverter?
  private var targetFormat: AVAudioFormat?
  private let lock = NSLock()
  private var samples: [Float] = []

  func start() throws {
    guard !isRunning else { return }
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let nativeFormat = input.outputFormat(forBus: 0)
    guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else { throw MicrophoneCaptureError.noInput }

    if collectsSamples {
      guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.targetSampleRate,
                                       channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: nativeFormat, to: target) else {
        throw MicrophoneCaptureError.engineFailed("Unsupported microphone format")
      }
      self.converter = converter
      targetFormat = target
    }
    lock.lock()
    samples.removeAll(keepingCapacity: true)
    lock.unlock()

    let ratio = Self.targetSampleRate / nativeFormat.sampleRate
    input.installTap(onBus: 0, bufferSize: 2048, format: nativeFormat) { [weak self] buffer, _ in
      guard let self else { return }
      self.onNativeBuffer?(buffer)

      if let onLevel = self.onLevel, let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 {
        var sum: Float = 0
        let count = Int(buffer.frameLength)
        for i in 0..<count { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(count))
        DispatchQueue.main.async { onLevel(rms) }
      }

      guard self.collectsSamples, let converter = self.converter, let target = self.targetFormat else { return }
      let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
      guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
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
      guard status != .error, output.frameLength > 0, let converted = output.floatChannelData?[0] else { return }
      let chunk = Array(UnsafeBufferPointer(start: converted, count: Int(output.frameLength)))
      self.lock.lock()
      self.samples.append(contentsOf: chunk)
      self.lock.unlock()
    }

    engine.prepare()
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      throw MicrophoneCaptureError.engineFailed(error.localizedDescription)
    }
    self.engine = engine
    isRunning = true
  }

  /// Stops capturing and returns the collected 16 kHz samples (empty unless `collectsSamples`).
  func stop() -> [Float] {
    guard isRunning, let engine else { return [] }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    self.engine = nil
    converter = nil
    targetFormat = nil
    isRunning = false
    lock.lock()
    let result = samples
    samples = []
    lock.unlock()
    return result
  }
}
