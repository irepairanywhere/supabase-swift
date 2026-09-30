import AppKit

enum Sounds {
  enum Kind { case start, stop, error }

  static func play(_ kind: Kind) {
    let name: String
    let volume: Float
    switch kind {
    case .start: name = "Tink"; volume = 0.35
    case .stop: name = "Pop"; volume = 0.35
    case .error: name = "Basso"; volume = 0.5
    }
    guard let sound = NSSound(named: NSSound.Name(name)) else { return }
    sound.volume = volume
    sound.play()
  }
}
