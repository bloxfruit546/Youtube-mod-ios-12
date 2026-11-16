import UIKit

extension Notification.Name {
    static let themeDidChange = Notification.Name("com.litetube5s.themeDidChange")
}

enum ThemeMode: String, Codable {
    case light
    case dark

    var displayName: String {
        switch self {
        case .light: return "Sáng (Light)"
        case .dark: return "Tối (Dark)"
        }
    }
}

struct ThemePalette {
    let background: UIColor
    let secondaryBackground: UIColor
    let elevatedBackground: UIColor
    let primaryText: UIColor
    let secondaryText: UIColor
    let separator: UIColor
    let accent: UIColor
    let badgeBackground: UIColor
    let badgeText: UIColor
    let barStyle: UIBarStyle
    let statusBarStyle: UIStatusBarStyle

    static let light = ThemePalette(
        background: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        secondaryBackground: UIColor(red: 0.949, green: 0.949, blue: 0.949, alpha: 1.0), // #F2F2F2
        elevatedBackground: UIColor(red: 0.976, green: 0.976, blue: 0.976, alpha: 1.0),
        primaryText: UIColor(red: 0.059, green: 0.059, blue: 0.059, alpha: 1.0), // #0F0F0F
        secondaryText: UIColor(red: 0.376, green: 0.376, blue: 0.376, alpha: 1.0), // #606060
        separator: UIColor(red: 0.898, green: 0.898, blue: 0.898, alpha: 1.0), // #E5E5E5
        accent: UIColor(red: 0.88, green: 0.09, blue: 0.09, alpha: 1.0),
        badgeBackground: UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1.0),
        badgeText: UIColor.white,
        barStyle: .default,
        statusBarStyle: .default
    )

    static let dark = ThemePalette(
        background: UIColor(red: 0.059, green: 0.059, blue: 0.059, alpha: 1.0), // #0F0F0F
        secondaryBackground: UIColor(red: 0.129, green: 0.129, blue: 0.129, alpha: 1.0), // #212121
        elevatedBackground: UIColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1.0),
        primaryText: UIColor(red: 0.945, green: 0.945, blue: 0.945, alpha: 1.0), // #F1F1F1
        secondaryText: UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0), // #AAAAAA
        separator: UIColor(red: 0.153, green: 0.153, blue: 0.153, alpha: 1.0), // #272727
        accent: UIColor(red: 1.0, green: 0.15, blue: 0.15, alpha: 1.0),
        badgeBackground: UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1.0),
        badgeText: UIColor.white,
        barStyle: .black,
        statusBarStyle: .lightContent
    )
}

final class ThemeManager {
    static let shared = ThemeManager()

    private let userDefaultsKey = "com.litetube5s.themeMode"

    private(set) var mode: ThemeMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: userDefaultsKey)
            NotificationCenter.default.post(name: .themeDidChange, object: self)
        }
    }

    var palette: ThemePalette {
        return mode == .dark ? .dark : .light
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
           let saved = ThemeMode(rawValue: raw) {
            self.mode = saved
        } else {
            self.mode = .dark
        }
    }

    func setMode(_ newMode: ThemeMode) {
        guard mode != newMode else { return }
        mode = newMode
    }

    func toggle() {
        setMode(mode == .dark ? .light : .dark)
    }
}
