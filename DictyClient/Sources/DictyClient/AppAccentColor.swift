import SwiftUI
import AppKit

extension Notification.Name {
    static let dictyAccentColorDidChange = Notification.Name("dictyAccentColorDidChange")
}

/// Curated modern pastel palette for Dicty.
enum AppAccentColor: String, CaseIterable, Identifiable {
    case olive = "olive"
    case black = "black"
    case slate = "slate"
    case lavender = "lavender"
    case terracotta = "terracotta"
    case ocean = "ocean"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .olive: return "Olive"
        case .black: return "Obsidian"
        case .slate: return "Slate"
        case .lavender: return "Lavender"
        case .terracotta: return "Terracotta"
        case .ocean: return "Ocean"
        }
    }
    
    /// Swatch color representation for the Settings palette picker.
    func swatchColor(isDark: Bool) -> Color {
        switch self {
        case .olive:
            return isDark ? Color(red: 135/255.0, green: 185/255.0, blue: 150/255.0)
                          : Color(red: 65/255.0, green: 95/255.0, blue: 75/255.0)
        case .black:
            return isDark ? Color(white: 0.92) : Color(white: 0.12)
        case .slate:
            return isDark ? Color(red: 148/255.0, green: 163/255.0, blue: 184/255.0)
                          : Color(red: 71/255.0, green: 85/255.0, blue: 105/255.0)
        case .lavender:
            return isDark ? Color(red: 184/255.0, green: 161/255.0, blue: 217/255.0)
                          : Color(red: 124/255.0, green: 91/255.0, blue: 166/255.0)
        case .terracotta:
            return isDark ? Color(red: 226/255.0, green: 149/255.0, blue: 120/255.0)
                          : Color(red: 182/255.0, green: 98/255.0, blue: 54/255.0)
        case .ocean:
            return isDark ? Color(red: 127/255.0, green: 177/255.0, blue: 196/255.0)
                          : Color(red: 61/255.0, green: 115/255.0, blue: 135/255.0)
        }
    }
    
    /// Contrast-safe text / icon color when displayed over the selected accent background.
    func selectedForeground(isDark: Bool) -> Color {
        if self == .black && isDark {
            return Color.black
        }
        return Color.white
    }
    
    /// Dynamic NSColor that adapts to system Light / Dark mode.
    var color: Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            switch self {
            case .olive:
                return isDark
                    ? NSColor(red: 135/255.0, green: 185/255.0, blue: 150/255.0, alpha: 1.0)
                    : NSColor(red: 65/255.0, green: 95/255.0, blue: 75/255.0, alpha: 1.0)
            case .black:
                return isDark
                    ? NSColor(red: 244/255.0, green: 244/255.0, blue: 245/255.0, alpha: 1.0)
                    : NSColor(red: 24/255.0, green: 24/255.0, blue: 27/255.0, alpha: 1.0)
            case .slate:
                return isDark
                    ? NSColor(red: 148/255.0, green: 163/255.0, blue: 184/255.0, alpha: 1.0)
                    : NSColor(red: 71/255.0, green: 85/255.0, blue: 105/255.0, alpha: 1.0)
            case .lavender:
                return isDark
                    ? NSColor(red: 184/255.0, green: 161/255.0, blue: 217/255.0, alpha: 1.0)
                    : NSColor(red: 124/255.0, green: 91/255.0, blue: 166/255.0, alpha: 1.0)
            case .terracotta:
                return isDark
                    ? NSColor(red: 226/255.0, green: 149/255.0, blue: 120/255.0, alpha: 1.0)
                    : NSColor(red: 182/255.0, green: 98/255.0, blue: 54/255.0, alpha: 1.0)
            case .ocean:
                return isDark
                    ? NSColor(red: 127/255.0, green: 177/255.0, blue: 196/255.0, alpha: 1.0)
                    : NSColor(red: 61/255.0, green: 115/255.0, blue: 135/255.0, alpha: 1.0)
            }
        }))
    }
    
    /// Resolves the current user-selected accent preset from UserDefaults.
    static var current: AppAccentColor {
        let key = UserDefaults.standard.string(forKey: "appAccentColor") ?? "olive"
        return AppAccentColor(rawValue: key) ?? .olive
    }
}

extension ToggleStyle where Self == SwitchToggleStyle {
    /// Native macOS switch toggle tinted with the user-selected AppAccent color.
    static var appAccent: SwitchToggleStyle {
        SwitchToggleStyle(tint: .appAccent)
    }
}

extension Color {
    /// Global dynamic accent color reflecting the user's choice in Preferences.
    static var appAccent: Color {
        AppAccentColor.current.color
    }
    
    /// Vibrant pastel lilac / violet with crisp contrast on both dark and light modes.
    static let tagViolet = Color(NSColor(name: nil, dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            // High-luminance pastel lilac for dark mode (#C4B5FD)
            return NSColor(red: 196/255.0, green: 181/255.0, blue: 253/255.0, alpha: 1.0)
        } else {
            // Crisp refined violet on light backgrounds (#6D28D9)
            return NSColor(red: 109/255.0, green: 40/255.0, blue: 217/255.0, alpha: 1.0)
        }
    }))
    
    /// Subtle translucent background for violet badges
    static let tagVioletBackground = Color(NSColor(name: nil, dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 139/255.0, green: 92/255.0, blue: 246/255.0, alpha: 0.22)
        } else {
            return NSColor(red: 109/255.0, green: 40/255.0, blue: 217/255.0, alpha: 0.12)
        }
    }))
}
