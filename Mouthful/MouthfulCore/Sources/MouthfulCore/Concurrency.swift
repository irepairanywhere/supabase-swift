import Foundation

/// Resumes a continuation at most once, from any thread. Handy when bridging delegate/callback
/// APIs that may report both a result and an error.
public final class OnceResumer<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<T, Error>?

  public init(_ continuation: CheckedContinuation<T, Error>) {
    self.continuation = continuation
  }

  public func succeed(_ value: T) {
    lock.lock()
    let c = continuation
    continuation = nil
    lock.unlock()
    c?.resume(returning: value)
  }

  public func fail(_ error: Error) {
    lock.lock()
    let c = continuation
    continuation = nil
    lock.unlock()
    c?.resume(throwing: error)
  }
}

public extension KeyedDecodingContainer {
  /// Decodes a value or falls back to `defaultValue` when the key is missing or malformed, so
  /// adding fields to a settings struct never wipes what users already saved.
  func decode<T: Decodable>(_ key: Key, default defaultValue: T) -> T {
    (try? decodeIfPresent(T.self, forKey: key)) ?? defaultValue
  }
}
