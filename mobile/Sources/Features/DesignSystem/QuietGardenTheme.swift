import SwiftUI

enum QuietGardenTheme {
  static let accent = Color(red: 0.16, green: 0.42, blue: 0.27)
  static let paper = Color(light: .init(white: 0.97, alpha: 1), dark: .init(white: 0.08, alpha: 1))
  static let raised = Color(light: .white, dark: .init(white: 0.13, alpha: 1))
  static let subtle = Color.secondary.opacity(0.10)
  static let success = Color(light: .init(red: 0.10, green: 0.40, blue: 0.20, alpha: 1),
                             dark: .init(red: 0.35, green: 0.78, blue: 0.46, alpha: 1))
  static let warning = Color(light: .init(red: 0.65, green: 0.38, blue: 0.04, alpha: 1),
                             dark: .init(red: 0.94, green: 0.68, blue: 0.25, alpha: 1))
  static let danger = Color(light: .init(red: 0.68, green: 0.16, blue: 0.16, alpha: 1),
                            dark: .init(red: 0.95, green: 0.40, blue: 0.38, alpha: 1))
  static let spacingXS: CGFloat = 6
  static let spacingS: CGFloat = 10
  static let spacingM: CGFloat = 16
  static let spacingL: CGFloat = 24
  static let spacingXL: CGFloat = 36
  static let rowRadius: CGFloat = 16
  static let controlRadius: CGFloat = 12
  static let minimumTarget: CGFloat = 44

  static func animation(reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88)
  }
}

extension Color {
  fileprivate init(light: NSColor, dark: NSColor) {
    #if os(macOS)
    self.init(nsColor: NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
    #else
    self.init(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    #endif
  }
}

#if os(iOS)
import UIKit
private extension UIColor {
  convenience init(_ color: NSColor) {
    self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
  }
}
private struct NSColor {
  let red: CGFloat
  let green: CGFloat
  let blue: CGFloat
  let alpha: CGFloat
  static let white = NSColor(white: 1, alpha: 1)
  init(white: CGFloat, alpha: CGFloat) { red = white; green = white; blue = white; self.alpha = alpha }
  init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
  }
}
#else
import AppKit
#endif

enum UIAccessibility {
  static let root = "root.workspace"
  static let modelLibrary = "model.library"
  static let chatList = "chat.messages"
  static let chatComposer = "chat.composer"
  static let send = "chat.send"
  static let stop = "chat.stop"
  static let reasoning = "chat.reasoning"
  static let metrics = "chat.metrics"
  static let activity = "agent.activity"
  static let approvalAllow = "approval.allowOnce"
  static let approvalDeny = "approval.deny"
  static let photoPicker = "attachment.photos"
  static let cameraPicker = "attachment.camera"
  static let filePicker = "attachment.files"
  static let attachmentPreview = "attachment.preview"
  static let removeAttachment = "attachment.remove"
  static let detailPolicy = "attachment.detail"
  static let attachmentError = "attachment.error"
  static let settings = "settings.localPrivacy"
}
