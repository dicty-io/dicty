import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import ServiceManagement

// MARK: - Appearance

// A fixed secondary text color that is always readable on Dicty's animated background.
// Use this instead of .secondary or .gray in any Settings/Main views.
extension Color {
    static let dictySecondary = Color(NSColor(name: nil, dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(white: 1.0, alpha: 0.55)
        } else {
            return NSColor.black.withAlphaComponent(0.55)
        }
    }))

}

struct SettingsPageHeader: View {
    let title: String
    let description: String?
    let helpTopic: FeatureHelpTopic?
    
    init(title: String, description: String? = nil, helpTopic: FeatureHelpTopic? = nil) {
        self.title = title
        self.description = description
        self.helpTopic = helpTopic
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if let helpTopic = helpTopic {
                    FeatureHelpButton(topic: helpTopic)
                }
            }
            
            if let description = description {
                Text(description)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppearanceView: View {
    @AppStorage("appTheme") private var appTheme: String = "Dark"
    @AppStorage("appAccentColor") private var appAccentColor: String = "olive"
    @AppStorage("showModeLabel") private var showModeLabel: Bool = true
    @AppStorage("colorHex_dictation") private var colorHexDictation: String = "78B18D"
    @AppStorage("colorHex_librarian") private var colorHexLibrarian: String = "7E8CE0"
    @AppStorage("colorHex_meeting") private var colorHexMeeting: String = "EAA368"
    @AppStorage("colorHex_focused") private var colorHexFocused: String = "EB7575"
    
    @State private var dictationColor: Color = Color(hex: "78B18D")
    @State private var librarianColor: Color = Color(hex: "7E8CE0")
    @State private var meetingColor: Color = Color(hex: "EAA368")
    @State private var focusedColor: Color = Color(hex: "EB7575")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Appearance").font(.system(.title2, design: .rounded).weight(.semibold))
            
            HStack(spacing: 30) {
                ThemeCard(title: "Auto", isSelected: appTheme == "Auto") { appTheme = "Auto" }
                ThemeCard(title: "Light", isSelected: appTheme == "Light") { appTheme = "Light" }
                ThemeCard(title: "Dark", isSelected: appTheme == "Dark") { appTheme = "Dark" }
            }
            .padding(.top, 20)
            
            Text("Accent Color")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .padding(.top, 10)
            
            HStack(spacing: 16) {
                ForEach(AppAccentColor.allCases) { preset in
                    AccentColorSwatch(
                        preset: preset,
                        isSelected: appAccentColor == preset.rawValue
                    ) {
                        appAccentColor = preset.rawValue
                        NotificationCenter.default.post(name: .dictyAccentColorDidChange, object: nil)
                    }
                }
            }
            .padding(.vertical, 4)
            
            Divider()
                .padding(.vertical, 20)
                
                Text("Recording Overlay")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                
                Toggle("Show Active Mode Indicator", isOn: $showModeLabel)
                    .toggleStyle(.appAccent)
                    .controlSize(.small)
                
                if showModeLabel {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            Text("Dictation Mode Color")
                            ColorPicker("", selection: $dictationColor).labelsHidden()
                                .onChange(of: dictationColor) { _, newColor in
                                    if let hex = newColor.toHex() { colorHexDictation = hex }
                                }
                        }
                        GridRow {
                            Text("Librarian Mode Color")
                            ColorPicker("", selection: $librarianColor).labelsHidden()
                                .onChange(of: librarianColor) { _, newColor in
                                    if let hex = newColor.toHex() { colorHexLibrarian = hex }
                                }
                        }
                        GridRow {
                            Text("Meeting Mode Color")
                            ColorPicker("", selection: $meetingColor).labelsHidden()
                                .onChange(of: meetingColor) { _, newColor in
                                    if let hex = newColor.toHex() { colorHexMeeting = hex }
                                }
                        }
                        GridRow {
                            Text("Focused Meeting Color")
                            ColorPicker("", selection: $focusedColor).labelsHidden()
                                .onChange(of: focusedColor) { _, newColor in
                                    if let hex = newColor.toHex() { colorHexFocused = hex }
                                }
                        }
                    }
                    .padding(.top, 10)
                    
                    Button("Reset to Defaults") {
                        colorHexDictation = "78B18D"
                        colorHexLibrarian = "7E8CE0"
                        colorHexMeeting = "EAA368"
                        colorHexFocused = "EB7575"
                        dictationColor = Color(hex: "78B18D")
                        librarianColor = Color(hex: "7E8CE0")
                        meetingColor = Color(hex: "EAA368")
                        focusedColor = Color(hex: "EB7575")
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundColor(.dictySecondary)
                    .padding(.top, 6)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .task {
                // Migrate legacy harsh primary colors to contemporary pastel palette
                if colorHexDictation.uppercased() == "4CAF50" { colorHexDictation = "78B18D" }
                if colorHexLibrarian.uppercased() == "5856D6" { colorHexLibrarian = "7E8CE0" }
                if colorHexMeeting.uppercased() == "FF9500" { colorHexMeeting = "EAA368" }
                if colorHexFocused.uppercased() == "FF3B30" { colorHexFocused = "EB7575" }
                
                dictationColor = Color(hex: colorHexDictation)
                librarianColor = Color(hex: colorHexLibrarian)
                meetingColor = Color(hex: colorHexMeeting)
                focusedColor = Color(hex: colorHexFocused)
            }
    }
}

struct DockAndStartupSettingsView: View {
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage("dockIconTheme") private var dockIconTheme: String = "system"
    @Environment(\.colorScheme) var colorScheme
    @State private var launchOnStartup = false
    @State private var hasLoadedStartup = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dock & Startup")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            
            VStack(alignment: .leading, spacing: 16) {
                // Show Dicty in Dock
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Dicty in Dock")
                            .font(.system(.headline, design: .rounded))
                        Text("When disabled, Dicty will only appear in your top menu bar.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $showInDock)
                        .labelsHidden()
                        .toggleStyle(.appAccent)
                        .controlSize(.small)
                        .onChange(of: showInDock) { _, newValue in
                            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                            if newValue {
                                NSApp.activate(ignoringOtherApps: true)
                            }
                        }
                }
                
                if showInDock {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dock Icon Theme")
                                .font(.system(.headline, design: .rounded))
                            Text("Choose between system default, bright, or dark icon style.")
                                .font(.caption)
                                .foregroundColor(.dictySecondary)
                        }
                        Spacer()
                        Picker("", selection: $dockIconTheme) {
                            Text("System").tag("system")
                            Text("Bright").tag("bright")
                            Text("Dark").tag("dark")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                }
                
                Divider()
                
                // Launch Dicty on Startup
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch Dicty on Startup")
                            .font(.system(.headline, design: .rounded))
                        Text("Automatically open Dicty when your Mac boots up.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $launchOnStartup)
                        .labelsHidden()
                        .toggleStyle(.appAccent)
                        .controlSize(.small)
                        .onChange(of: launchOnStartup) { _, newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                print("Failed to toggle launch on startup: \(error)")
                                launchOnStartup = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: dockIconTheme) { _, newValue in
            updateDockIcon(theme: newValue)
        }
        .task {
            if !hasLoadedStartup {
                launchOnStartup = (SMAppService.mainApp.status == .enabled)
                hasLoadedStartup = true
            }
        }
    }
    
    private func updateDockIcon(theme: String) {
        let isDark: Bool
        if theme == "dark" {
            isDark = true
        } else if theme == "bright" {
            isDark = false
        } else {
            isDark = colorScheme == .dark
        }
        
        let imageName = isDark ? "Icon-macOS-Dark-1024" : "Icon-macOS-Default-1024"
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let path = DictyResources.path(forResource: imageName, ofType: "png"),
               let image = NSImage(contentsOfFile: path) {
                DispatchQueue.main.async {
                    NSApp.applicationIconImage = image
                }
            }
        }
    }
}

struct ThemeCard: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void
    
    @ViewBuilder
    var cardBackground: some View {
        if title == "Light" {
            Color.white.opacity(0.6)
        } else if title == "Dark" {
            Color.black.opacity(0.4)
        } else {
            HStack(spacing: 0) {
                Color.white.opacity(0.6)
                Color.black.opacity(0.4)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                cardBackground
                    .frame(width: 120, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.appAccent : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                    )
                
                // Mini fake UI
                VStack(spacing: 4) {
                    HStack {
                        Circle().fill(Color.primary.opacity(0.2)).frame(width: 6, height: 6)
                        Circle().fill(Color.primary.opacity(0.2)).frame(width: 6, height: 6)
                        Circle().fill(Color.primary.opacity(0.2)).frame(width: 6, height: 6)
                        Spacer()
                    }
                    .padding(8)
                    Spacer()
                }
                .frame(width: 120, height: 80)
            }
            .onTapGesture {
                withAnimation { action() }
            }
            
            Text(title)
                .font(.headline)
                .foregroundColor(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

struct SoundsSettingsView: View {
    @AppStorage("appAccentColor") private var appAccentColor: String = "olive"
    @AppStorage("startSoundType") private var startSoundType: String = "Built-in"
    @AppStorage("startSoundName") private var startSoundName: String = "Hero"
    @AppStorage("startSoundPath") private var startSoundPath: String = ""
    
    @AppStorage("stopSoundType") private var stopSoundType: String = "Built-in"
    @AppStorage("stopSoundName") private var stopSoundName: String = "Pop"
    @AppStorage("stopSoundPath") private var stopSoundPath: String = ""
    
    let builtInSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recording Sounds").font(.system(.title2, design: .rounded).weight(.semibold))
            
            soundConfigRow(title: "Start Recording", type: $startSoundType, name: $startSoundName, path: $startSoundPath)
            Divider()
            soundConfigRow(title: "Stop Recording", type: $stopSoundType, name: $stopSoundName, path: $stopSoundPath)
        }
        .padding(.top, 10)
    }
    
    @ViewBuilder
    private func soundConfigRow(title: String, type: Binding<String>, name: Binding<String>, path: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                
                Button(action: { playPreview(type: type.wrappedValue, name: name.wrappedValue, path: path.wrappedValue) }) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundColor(.appAccent)
                }
                .buttonStyle(.plain)
                .help("Preview sound")
            }
            
            HStack {
                Text("Source")
                    .frame(width: 60, alignment: .trailing)
                Picker("", selection: type) {
                    Text("Built-in").tag("Built-in")
                    Text("Custom Audio File").tag("Custom")
                    Text("None").tag("None")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 200)
            }
            
            if type.wrappedValue == "Built-in" {
                HStack {
                    Text("Sound")
                        .frame(width: 60, alignment: .trailing)
                    Picker("", selection: name) {
                        ForEach(builtInSounds, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
            } else if type.wrappedValue == "Custom" {
                HStack {
                    Text("File")
                        .frame(width: 60, alignment: .trailing)
                    Text(path.wrappedValue.isEmpty ? "No file selected" : (path.wrappedValue as NSString).lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.dictySecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 140, alignment: .leading)
                    
                    Button("Choose File...") {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canCreateDirectories = false
                        panel.allowedContentTypes = [.audio]
                        if panel.runModal() == .OK, let url = panel.url {
                            path.wrappedValue = url.path
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }
    
    private func playPreview(type: String, name: String, path: String) {
        if type == "Built-in" {
            NSSound(named: NSSound.Name(name))?.play()
        } else if type == "Custom", !path.isEmpty {
            NSSound(contentsOfFile: path, byReference: false)?.play()
        }
    }
}

// MARK: - Accent Color Swatch

struct AccentColorSwatch: View {
    let preset: AppAccentColor
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovering = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(preset.swatchColor(isDark: colorScheme == .dark))
                        .frame(width: 34, height: 34)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(preset == .black && colorScheme == .dark ? .black : .white)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.appAccent : (isHovering ? Color.primary.opacity(0.35) : Color.clear), lineWidth: 2)
                        .padding(-4)
                )
                
                Text(preset.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundColor(isSelected ? .primary : .dictySecondary)
            }
            .frame(width: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Minimalist Flat Button Styles

extension Color {
    static var dictyButtonPrimary: Color {
        Color.appAccent
    }
}

struct FlatPrimaryButtonStyle: ButtonStyle {
    var backgroundColor: Color = Color.dictyButtonPrimary
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appAccentColor") private var appAccentColor: String = "olive"
    
    func makeBody(configuration: Configuration) -> some View {
        let preset = AppAccentColor(rawValue: appAccentColor) ?? .olive
        let textColor = preset.selectedForeground(isDark: colorScheme == .dark)
        return configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isEnabled ? textColor : textColor.opacity(0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1.0) : 0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.12 : 0.06), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FlatSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isEnabled ? .primary : Color.primary.opacity(0.45))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(isEnabled ? (configuration.isPressed ? 0.04 : 0.08) : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.10 : 0.05), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == FlatPrimaryButtonStyle {
    static var flatPrimary: FlatPrimaryButtonStyle { FlatPrimaryButtonStyle() }
    static func flatPrimary(color: Color) -> FlatPrimaryButtonStyle { FlatPrimaryButtonStyle(backgroundColor: color) }
}

extension ButtonStyle where Self == FlatSecondaryButtonStyle {
    static var flatSecondary: FlatSecondaryButtonStyle { FlatSecondaryButtonStyle() }
}

