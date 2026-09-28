import UIKit

/// A rounded "key" that matches the look of the system keyboard closely enough.
final class KeyButton: UIButton {
  init(symbol: String?, title: String?, prominent: Bool = false) {
    super.init(frame: .zero)
    var config = UIButton.Configuration.filled()
    config.baseBackgroundColor = prominent ? .systemGray3 : .systemBackground
    config.baseForegroundColor = .label
    config.cornerStyle = .medium
    config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
    if let symbol {
      config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
      config.imagePadding = 6
    }
    if let title {
      config.title = title
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        outgoing.font = UIFont.systemFont(ofSize: 15)
        return outgoing
      }
    }
    configuration = config
    translatesAutoresizingMaskIntoConstraints = false
    heightAnchor.constraint(equalToConstant: 44).isActive = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// The keyboard layout: a status line, the mic (with command and undo beside it), and a bottom
/// row with globe, delete, space and return.
final class KeyboardView: UIView {
  let statusLabel = UILabel()
  let micButton = UIButton(type: .system)
  let commandButton = KeyButton(symbol: "sparkles", title: "Command")
  let undoButton = KeyButton(symbol: "arrow.uturn.backward", title: "Undo")
  let globeButton = KeyButton(symbol: "globe", title: nil, prominent: true)
  let deleteButton = KeyButton(symbol: "delete.left", title: nil, prominent: true)
  let spaceButton = KeyButton(symbol: nil, title: "space")
  let returnButton = KeyButton(symbol: nil, title: "return", prominent: true)

  private let micRing = UIView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    build()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private func build() {
    backgroundColor = UIColor.secondarySystemBackground

    statusLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
    statusLabel.textColor = .secondaryLabel
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 2
    statusLabel.lineBreakMode = .byTruncatingHead
    statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

    micRing.backgroundColor = UIColor.systemRed.withAlphaComponent(0.35)
    micRing.layer.cornerRadius = 40
    micRing.alpha = 0
    micRing.translatesAutoresizingMaskIntoConstraints = false

    micButton.backgroundColor = .systemBlue
    micButton.tintColor = .white
    micButton.layer.cornerRadius = 36
    micButton.translatesAutoresizingMaskIntoConstraints = false
    setRecording(false, command: false)

    let micContainer = UIView()
    micContainer.translatesAutoresizingMaskIntoConstraints = false
    micContainer.addSubview(micRing)
    micContainer.addSubview(micButton)
    NSLayoutConstraint.activate([
      micContainer.heightAnchor.constraint(equalToConstant: 84),
      micContainer.widthAnchor.constraint(equalToConstant: 110),
      micButton.widthAnchor.constraint(equalToConstant: 72),
      micButton.heightAnchor.constraint(equalToConstant: 72),
      micButton.centerXAnchor.constraint(equalTo: micContainer.centerXAnchor),
      micButton.centerYAnchor.constraint(equalTo: micContainer.centerYAnchor),
      micRing.widthAnchor.constraint(equalToConstant: 80),
      micRing.heightAnchor.constraint(equalToConstant: 80),
      micRing.centerXAnchor.constraint(equalTo: micButton.centerXAnchor),
      micRing.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
    ])

    let middleRow = UIStackView(arrangedSubviews: [commandButton, micContainer, undoButton])
    middleRow.axis = .horizontal
    middleRow.alignment = .center
    middleRow.distribution = .fill
    middleRow.spacing = 12
    commandButton.widthAnchor.constraint(equalTo: undoButton.widthAnchor).isActive = true

    let bottomRow = UIStackView(arrangedSubviews: [globeButton, deleteButton, spaceButton, returnButton])
    bottomRow.axis = .horizontal
    bottomRow.distribution = .fill
    bottomRow.spacing = 6
    NSLayoutConstraint.activate([
      globeButton.widthAnchor.constraint(equalToConstant: 52),
      deleteButton.widthAnchor.constraint(equalToConstant: 52),
      returnButton.widthAnchor.constraint(equalToConstant: 88),
    ])
    spaceButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let root = UIStackView(arrangedSubviews: [statusLabel, middleRow, bottomRow])
    root.axis = .vertical
    root.spacing = 8
    root.translatesAutoresizingMaskIntoConstraints = false
    addSubview(root)
    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      root.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
    ])
  }

  func setRecording(_ recording: Bool, command: Bool) {
    let symbol = recording ? "stop.fill" : "mic.fill"
    let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold))
    micButton.setImage(image, for: .normal)
    micButton.backgroundColor = recording ? (command ? .systemPurple : .systemRed) : .systemBlue
    micRing.backgroundColor = (command ? UIColor.systemPurple : UIColor.systemRed).withAlphaComponent(0.35)
    if !recording { setLevel(0) }
  }

  func setLevel(_ level: Float) {
    let scale = 1 + CGFloat(level) * 0.9
    micRing.transform = CGAffineTransform(scaleX: scale, y: scale)
    micRing.alpha = CGFloat(min(1, level * 1.5))
  }
}
