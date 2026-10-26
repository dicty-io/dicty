import SwiftUI
import AppKit

/// A premium, retina-rendered country flag badge component that replaces standard emoji flags
/// with sharp, bordered, enameled vector flag iconography.
struct CountryFlagView: View {
    let countryCode: String
    var width: CGFloat = 19
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 3
    
    // In-memory NSImage cache to ensure zero latency during list scrolling
    private static var imageCache: [String: NSImage] = [:]
    private static let cacheLock = NSLock()
    
    init(_ identifier: String, width: CGFloat = 19, height: CGFloat = 14, cornerRadius: CGFloat = 3) {
        self.countryCode = CountryFlagView.normalizeCode(identifier)
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        Group {
            if countryCode == "all" || countryCode == "globe" {
                // Sleek global / all languages badge
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.primary.opacity(0.08))
                    
                    Image(systemName: "globe.europe.africa.fill")
                        .font(.system(size: height * 0.65, weight: .semibold))
                        .foregroundColor(.dictySecondary)
                }
                .frame(width: width, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 0.5)
            } else if let nsImage = Self.loadFlagImage(code: countryCode) {
                // High-fidelity country flag badge
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        // Top specular sheen for expensive tactile pin feel
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.primary.opacity(0.14), lineWidth: 0.75)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 1.2, x: 0, y: 0.6)
            } else {
                // Fallback icon
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.primary.opacity(0.06))
                    Text(countryCode.prefix(2).uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .frame(width: width, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
                )
            }
        }
    }
    
    // Normalizes diverse representations (emojis, accents, language tags, codes) to canonical ISO 3166-1 alpha-2
    static func normalizeCode(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        switch clean {
        // Emojis
        case "🇺🇸": return "us"
        case "🇬🇧": return "gb"
        case "🇩🇪": return "de"
        case "🇷🇺": return "ru"
        case "🇪🇸": return "es"
        case "🇺🇦": return "ua"
        case "🌐": return "all"
            
        // Accents / Country Codes
        case "us", "usa", "en-us": return "us"
        case "uk", "gb", "gbr", "en-gb": return "gb"
        case "de", "deu", "de-de": return "de"
        case "ru", "rus", "ru-ru": return "ru"
        case "es", "esp", "es-es": return "es"
        case "ua", "ukr", "uk-ua": return "ua"
            
        // Language keys
        case "all", "multilingual", "global": return "all"
        case "en": return "us"
            
        default:
            if clean.contains("us") { return "us" }
            if clean.contains("uk") || clean.contains("gb") { return "gb" }
            if clean.contains("de") { return "de" }
            if clean.contains("ru") { return "ru" }
            if clean.contains("es") { return "es" }
            if clean.contains("ua") { return "ua" }
            return clean
        }
    }
    
    private static func loadFlagImage(code: String) -> NSImage? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        if let cached = imageCache[code] {
            return cached
        }
        
        let resourceName = "flag_\(code)"
        
        // 1. Try safe resource loader (Contents/Resources or bundle)
        if let img = DictyResources.image(named: resourceName, extension: "png") {
            imageCache[code] = img
            return img
        }
        
        return nil
    }
}
