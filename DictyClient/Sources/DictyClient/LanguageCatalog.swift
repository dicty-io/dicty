import SwiftUI

/// Represents a language supported by Whisper with code, English name, and native name.
public struct LanguageItem: Identifiable, Hashable, Sendable {
    public let code: String
    public let englishName: String
    public let nativeName: String

    public var id: String { code }

    /// Formatted as "Deutsch (German)", or "English" if native and English match.
    public var displayName: String {
        if code == "auto" { return "Auto Detect" }
        if code == "none" { return "Off" }
        if nativeName.caseInsensitiveCompare(englishName) == .orderedSame {
            return englishName
        }
        return "\(nativeName) (\(englishName))"
    }

    public init(code: String, englishName: String, nativeName: String) {
        self.code = code
        self.englishName = englishName
        self.nativeName = nativeName
    }
}

/// Shared language catalog covering all 100 languages supported by OpenAI Whisper.
public enum LanguageCatalog {
    /// Complete catalog of Whisper languages, sorted A-Z by displayName.
    public static let allLanguages: [LanguageItem] = [
        LanguageItem(code: "af", englishName: "Afrikaans", nativeName: "Afrikaans"),
        LanguageItem(code: "sq", englishName: "Albanian", nativeName: "Shqip"),
        LanguageItem(code: "am", englishName: "Amharic", nativeName: "አማርኛ"),
        LanguageItem(code: "ar", englishName: "Arabic", nativeName: "العربية"),
        LanguageItem(code: "hy", englishName: "Armenian", nativeName: "Հայերեն"),
        LanguageItem(code: "as", englishName: "Assamese", nativeName: "অসমীয়া"),
        LanguageItem(code: "az", englishName: "Azerbaijani", nativeName: "Azərbaycan"),
        LanguageItem(code: "ba", englishName: "Bashkir", nativeName: "Башҡорт"),
        LanguageItem(code: "eu", englishName: "Basque", nativeName: "Euskara"),
        LanguageItem(code: "be", englishName: "Belarusian", nativeName: "Беларуская"),
        LanguageItem(code: "bn", englishName: "Bengali", nativeName: "বাংলা"),
        LanguageItem(code: "bs", englishName: "Bosnian", nativeName: "Bosanski"),
        LanguageItem(code: "br", englishName: "Breton", nativeName: "Brezhoneg"),
        LanguageItem(code: "bg", englishName: "Bulgarian", nativeName: "Български"),
        LanguageItem(code: "my", englishName: "Burmese", nativeName: "မြန်မာ"),
        LanguageItem(code: "yue", englishName: "Cantonese", nativeName: "廣東話"),
        LanguageItem(code: "ca", englishName: "Catalan", nativeName: "Català"),
        LanguageItem(code: "zh", englishName: "Chinese", nativeName: "中文"),
        LanguageItem(code: "hr", englishName: "Croatian", nativeName: "Hrvatski"),
        LanguageItem(code: "cs", englishName: "Czech", nativeName: "Čeština"),
        LanguageItem(code: "da", englishName: "Danish", nativeName: "Dansk"),
        LanguageItem(code: "nl", englishName: "Dutch", nativeName: "Nederlands"),
        LanguageItem(code: "en", englishName: "English", nativeName: "English"),
        LanguageItem(code: "et", englishName: "Estonian", nativeName: "Eesti"),
        LanguageItem(code: "fo", englishName: "Faroese", nativeName: "Føroyskt"),
        LanguageItem(code: "fi", englishName: "Finnish", nativeName: "Suomi"),
        LanguageItem(code: "fr", englishName: "French", nativeName: "Français"),
        LanguageItem(code: "gl", englishName: "Galician", nativeName: "Galego"),
        LanguageItem(code: "ka", englishName: "Georgian", nativeName: "ქართული"),
        LanguageItem(code: "de", englishName: "German", nativeName: "Deutsch"),
        LanguageItem(code: "el", englishName: "Greek", nativeName: "Ελληνικά"),
        LanguageItem(code: "gu", englishName: "Gujarati", nativeName: "ગુજરાતી"),
        LanguageItem(code: "ht", englishName: "Haitian Creole", nativeName: "Kreyòl Ayisyen"),
        LanguageItem(code: "ha", englishName: "Hausa", nativeName: "Hausa"),
        LanguageItem(code: "haw", englishName: "Hawaiian", nativeName: "ʻŌlelo Hawaiʻi"),
        LanguageItem(code: "he", englishName: "Hebrew", nativeName: "עברית"),
        LanguageItem(code: "hi", englishName: "Hindi", nativeName: "हिन्दी"),
        LanguageItem(code: "hu", englishName: "Hungarian", nativeName: "Magyar"),
        LanguageItem(code: "is", englishName: "Icelandic", nativeName: "Íslenska"),
        LanguageItem(code: "id", englishName: "Indonesian", nativeName: "Bahasa Indonesia"),
        LanguageItem(code: "it", englishName: "Italian", nativeName: "Italiano"),
        LanguageItem(code: "ja", englishName: "Japanese", nativeName: "日本語"),
        LanguageItem(code: "jw", englishName: "Javanese", nativeName: "Basa Jawa"),
        LanguageItem(code: "kn", englishName: "Kannada", nativeName: "ಕನ್ನಡ"),
        LanguageItem(code: "kk", englishName: "Kazakh", nativeName: "Қазақ Тілі"),
        LanguageItem(code: "km", englishName: "Khmer", nativeName: "ភាសាខ្មែរ"),
        LanguageItem(code: "ko", englishName: "Korean", nativeName: "한국어"),
        LanguageItem(code: "lo", englishName: "Lao", nativeName: "ພາສາລາວ"),
        LanguageItem(code: "la", englishName: "Latin", nativeName: "Latina"),
        LanguageItem(code: "lv", englishName: "Latvian", nativeName: "Latviešu"),
        LanguageItem(code: "ln", englishName: "Lingala", nativeName: "Lingála"),
        LanguageItem(code: "lt", englishName: "Lithuanian", nativeName: "Lietuvių"),
        LanguageItem(code: "lb", englishName: "Luxembourgish", nativeName: "Lëtzebuergesch"),
        LanguageItem(code: "mk", englishName: "Macedonian", nativeName: "Македонски"),
        LanguageItem(code: "mg", englishName: "Malagasy", nativeName: "Malagasy"),
        LanguageItem(code: "ms", englishName: "Malay", nativeName: "Bahasa Melayu"),
        LanguageItem(code: "ml", englishName: "Malayalam", nativeName: "മലയാളം"),
        LanguageItem(code: "mt", englishName: "Maltese", nativeName: "Malti"),
        LanguageItem(code: "mi", englishName: "Maori", nativeName: "Māori"),
        LanguageItem(code: "mr", englishName: "Marathi", nativeName: "मराठी"),
        LanguageItem(code: "mn", englishName: "Mongolian", nativeName: "Монгол"),
        LanguageItem(code: "ne", englishName: "Nepali", nativeName: "नेपाली"),
        LanguageItem(code: "no", englishName: "Norwegian", nativeName: "Norsk"),
        LanguageItem(code: "nn", englishName: "Nynorsk", nativeName: "Norsk Nynorsk"),
        LanguageItem(code: "oc", englishName: "Occitan", nativeName: "Occitan"),
        LanguageItem(code: "ps", englishName: "Pashto", nativeName: "پښتو"),
        LanguageItem(code: "fa", englishName: "Persian", nativeName: "فارسی"),
        LanguageItem(code: "pl", englishName: "Polish", nativeName: "Polski"),
        LanguageItem(code: "pt", englishName: "Portuguese", nativeName: "Português"),
        LanguageItem(code: "pa", englishName: "Punjabi", nativeName: "ਪੰਜਾਬੀ"),
        LanguageItem(code: "ro", englishName: "Romanian", nativeName: "Română"),
        LanguageItem(code: "ru", englishName: "Russian", nativeName: "Русский"),
        LanguageItem(code: "sa", englishName: "Sanskrit", nativeName: "संस्कृतम्"),
        LanguageItem(code: "sr", englishName: "Serbian", nativeName: "Српски"),
        LanguageItem(code: "sn", englishName: "Shona", nativeName: "Chishona"),
        LanguageItem(code: "sd", englishName: "Sindhi", nativeName: "سنڌي"),
        LanguageItem(code: "si", englishName: "Sinhala", nativeName: "සිංහල"),
        LanguageItem(code: "sk", englishName: "Slovak", nativeName: "Slovenčina"),
        LanguageItem(code: "sl", englishName: "Slovenian", nativeName: "Slovenščina"),
        LanguageItem(code: "so", englishName: "Somali", nativeName: "Soomaali"),
        LanguageItem(code: "es", englishName: "Spanish", nativeName: "Español"),
        LanguageItem(code: "su", englishName: "Sundanese", nativeName: "Basa Sunda"),
        LanguageItem(code: "sw", englishName: "Swahili", nativeName: "Kiswahili"),
        LanguageItem(code: "sv", englishName: "Swedish", nativeName: "Svenska"),
        LanguageItem(code: "tl", englishName: "Tagalog", nativeName: "Tagalog"),
        LanguageItem(code: "tg", englishName: "Tajik", nativeName: "Тоҷикӣ"),
        LanguageItem(code: "ta", englishName: "Tamil", nativeName: "தமிழ்"),
        LanguageItem(code: "tt", englishName: "Tatar", nativeName: "Татар"),
        LanguageItem(code: "te", englishName: "Telugu", nativeName: "తెలుగు"),
        LanguageItem(code: "th", englishName: "Thai", nativeName: "ไทย"),
        LanguageItem(code: "bo", englishName: "Tibetan", nativeName: "བོད་སྐད་"),
        LanguageItem(code: "tr", englishName: "Turkish", nativeName: "Türkçe"),
        LanguageItem(code: "tk", englishName: "Turkmen", nativeName: "Türkmen Dili"),
        LanguageItem(code: "uk", englishName: "Ukrainian", nativeName: "Українська"),
        LanguageItem(code: "ur", englishName: "Urdu", nativeName: "اردو"),
        LanguageItem(code: "uz", englishName: "Uzbek", nativeName: "Oʻzbek"),
        LanguageItem(code: "vi", englishName: "Vietnamese", nativeName: "Tiếng Việt"),
        LanguageItem(code: "cy", englishName: "Welsh", nativeName: "Cymraeg"),
        LanguageItem(code: "yi", englishName: "Yiddish", nativeName: "ייִדיש"),
        LanguageItem(code: "yo", englishName: "Yoruba", nativeName: "Èdè Yorùbá")
    ].sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

    /// System language item detected from device preferences.
    public static var systemLanguageItem: LanguageItem? {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        let code = preferred.components(separatedBy: CharacterSet(charactersIn: "-_")).first?.lowercased() ?? "en"
        return allLanguages.first { $0.code == code }
    }

    /// English language item.
    public static var englishItem: LanguageItem {
        allLanguages.first { $0.code == "en" } ?? LanguageItem(code: "en", englishName: "English", nativeName: "English")
    }

    /// Look up language item by Whisper code.
    public static func item(for code: String) -> LanguageItem? {
        let target = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allLanguages.first { $0.code == target }
    }

    /// Format display name for any code.
    public static func displayName(for code: String) -> String {
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.isEmpty || clean == "none" || clean == "off" {
            return "Off"
        }
        if clean == "auto" {
            return "Auto Detect"
        }
        return item(for: clean)?.displayName ?? clean.uppercased()
    }

    /// Record code into recently used list (max 3).
    public static func recordRecentlyUsed(code: String) {
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty, clean != "none", clean != "auto" else { return }
        var list = getRecentlyUsedCodes()
        list.removeAll { $0 == clean }
        list.insert(clean, at: 0)
        if list.count > 3 {
            list = Array(list.prefix(3))
        }
        UserDefaults.standard.set(list.joined(separator: ","), forKey: "recentlyUsedLanguages")
    }

    /// Retrieve recently used codes.
    public static func getRecentlyUsedCodes() -> [String] {
        let raw = UserDefaults.standard.string(forKey: "recentlyUsedLanguages") ?? ""
        return raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Retrieve recently used language items (up to 3).
    public static func recentlyUsedItems() -> [LanguageItem] {
        getRecentlyUsedCodes().compactMap { code in
            allLanguages.first { $0.code == code }
        }
    }
}

/// Searchable picker sheet for selecting spoken language or translation target.
public struct LanguagePickerSheet: View {
    public enum Mode {
        case spokenLanguage    // Includes "Auto Detect"
        case translationTarget // Includes "Off"
    }

    public let mode: Mode
    public let currentCode: String
    public let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""

    public init(mode: Mode, currentCode: String, initialSearchText: String = "", onSelect: @escaping (String) -> Void) {
        self.mode = mode
        self.currentCode = currentCode
        self._searchText = State(initialValue: initialSearchText)
        self.onSelect = onSelect
    }

    private var filteredLanguages: [LanguageItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LanguageCatalog.allLanguages
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return LanguageCatalog.allLanguages.filter { item in
            item.englishName.localizedCaseInsensitiveContains(query) ||
            item.nativeName.localizedCaseInsensitiveContains(query) ||
            item.code.localizedCaseInsensitiveContains(query) ||
            item.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    private var suggestedItems: [LanguageItem] {
        var items: [LanguageItem] = []
        if let sys = LanguageCatalog.systemLanguageItem, !items.contains(where: { $0.code == sys.code }) {
            items.append(sys)
        }
        let en = LanguageCatalog.englishItem
        if !items.contains(where: { $0.code == en.code }) {
            items.append(en)
        }
        for recent in LanguageCatalog.recentlyUsedItems() {
            if !items.contains(where: { $0.code == recent.code }) {
                items.append(recent)
            }
        }
        return items
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(mode == .spokenLanguage ? "Spoken Language" : "Translate to")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.appAccent)
                .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Search languages...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            Divider().opacity(0.4)

            // Language list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        // Special mode-specific default row
                        if mode == .translationTarget {
                            row(title: "Off — do not translate", code: "none", isSelected: currentCode == "none" || currentCode.isEmpty)
                        } else {
                            row(title: "Auto Detect (🌐)", code: "auto", isSelected: currentCode == "auto")
                        }

                        // SUGGESTED section
                        Text("SUGGESTED")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 2)

                        ForEach(suggestedItems) { item in
                            row(title: item.displayName, code: item.code, isSelected: currentCode == item.code)
                        }

                        Text("ALL LANGUAGES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                    }

                    ForEach(filteredLanguages) { item in
                        row(title: item.displayName, code: item.code, isSelected: currentCode == item.code)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 380, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func row(title: String, code: String, isSelected: Bool) -> some View {
        Button(action: {
            LanguageCatalog.recordRecentlyUsed(code: code)
            onSelect(code)
            dismiss()
        }) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .appAccent : .primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appAccent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.appAccent.opacity(0.08) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
