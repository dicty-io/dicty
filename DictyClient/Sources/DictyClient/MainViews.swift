import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Views
struct SidebarButton: View {
    let title: String
    let systemImage: String
    var iconColor: Color = .appAccent
    @Binding var selection: Int
    let targetSelection: Int
    var hasBadge: Bool = false
    var badgeCount: Int? = nil
    var badgeTooltip: String? = nil
    
    @AppStorage("appAccentColor") private var appAccentColor: String = "olive"
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    
    var body: some View {
        let isSelected = selection == targetSelection
        
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .appAccent : .secondary)
                .frame(width: 20, alignment: .center)
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .primary)
                .lineLimit(1)
            Spacer()
            if let count = badgeCount, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Capsule())
                    .help(badgeTooltip ?? "")
            } else if hasBadge {
                Circle()
                    .fill(Color.appAccent)
                    .frame(width: 7, height: 7)
                    .help(badgeTooltip ?? "")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .help((hasBadge || badgeCount != nil) ? (badgeTooltip ?? "An update is available") : "")
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.appAccent.opacity(0.18) : (isHovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        .onTapGesture {
            selection = targetSelection
        }
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hover
            }
        }
    }
}

struct PreferencesSettingsView: View {
    @EnvironmentObject var engineClient: EngineClient
    @AppStorage("appAccentColor") private var appAccentColor: String = "olive"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsPageHeader(title: "General", description: "Appearance, Dock, startup and privacy.", helpTopic: .preferences)
                AppearanceView()
                Divider()
                DockAndStartupSettingsView()
                Divider()
                DictationWorkflowPreferencesView().environmentObject(engineClient)
                Divider()
                SoundsSettingsView()
                Divider()
                HistoryRetentionSettingsView().environmentObject(engineClient)
                Divider()
                DiagnosticsExportView().environmentObject(engineClient)
                Divider()
                ClearCacheSettingsView().environmentObject(engineClient)
                Divider()
                AdvancedPreferencesSettingsView()
                Divider()
                OnboardingHelpPreferencesView().environmentObject(engineClient)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(.appAccent)
    }
}

struct DictationWorkflowPreferencesView: View {
    @EnvironmentObject var engineClient: EngineClient
    @AppStorage("appAccentColor") private var appAccentColor: String = "olive"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dictation & Playback")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            
            VStack(alignment: .leading, spacing: 16) {
                // Auto-Paste Dictation
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Paste Dictation")
                            .font(.system(.headline, design: .rounded))
                        Text("Automatically types the transcribed text directly into your frontmost application.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $engineClient.autoPaste)
                        .labelsHidden()
                        .toggleStyle(.appAccent)
                        .controlSize(.small)
                }
                
                // Restore Clipboard After Paste
                if engineClient.autoPaste {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore Clipboard After Paste")
                                .font(.system(.headline, design: .rounded))
                            Text("Keeps your previously copied links, snippets, and images on the clipboard after dictating.")
                                .font(.caption)
                                .foregroundColor(.dictySecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $engineClient.restoreClipboardAfterPaste)
                            .labelsHidden()
                            .toggleStyle(.appAccent)
                            .controlSize(.small)
                    }
                }
                
                Divider()
                
                // Incognito Mode
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Incognito Mode")
                                .font(.system(.headline, design: .rounded))
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.dictySecondary)
                        }
                        Text("When enabled, speech is processed in RAM and scrubbed immediately. Transcripts are typed directly and excluded from history.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $engineClient.isIncognitoMode)
                        .labelsHidden()
                        .toggleStyle(.appAccent)
                        .controlSize(.small)
                }
                
                Divider()
                
                // Email Sender Name
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Email Sender Name")
                                .font(.system(.headline, design: .rounded))
                            InfoSign(text: "Your name used in email sign-offs when reformatting speech with Email style, replacing generic placeholders like [Your Name].")
                        }
                        Text("Used in email signatures (e.g. 'Best regards, \(engineClient.authorName.isEmpty ? "Bruce Wayne" : engineClient.authorName)')")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    TextField("Bruce Wayne", text: Binding(
                        get: { engineClient.authorName },
                        set: { engineClient.updateAuthorName($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                }
                
                Divider()
                
                // Recording Activation Style (Hold-to-Talk vs Toggle)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Activation Style")
                                .font(.system(.headline, design: .rounded))
                            InfoSign(text: "Choose whether to hold the shortcut key while speaking (Push-to-Talk) or press once to start and press again to finish.")
                        }
                        Text(engineClient.hotkeyBehavior == "hold" 
                             ? "Push-to-Talk: Hold shortcut to speak, release when finished." 
                             : "Toggle: Press shortcut once to start, press again to stop.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    Picker("", selection: $engineClient.hotkeyBehavior) {
                        Text("Hold to Talk (Default)").tag("hold")
                        Text("Toggle (Press / Press)").tag("toggle")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190)
                    .onChange(of: engineClient.hotkeyBehavior) { oldValue, newValue in
                        engineClient.setupGlobalMonitor()
                    }
                }
                
                Divider()
                
                // Media Playback When Recording
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Playback when recording")
                                    .font(.system(.headline, design: .rounded))
                                InfoSign(text: "Choose how background music or third-party media playback is handled while voice recording.")
                            }
                            Text("Control media players (Apple Music, Spotify, browsers) during active dictation.")
                                .font(.caption)
                                .foregroundColor(.dictySecondary)
                        }
                        
                        Spacer()
                        
                        Picker("", selection: $engineClient.pauseMediaOnRecord) {
                            Text("Pause (Default)").tag("pause")
                            Text("Keep Playing").tag("keep_playing")
                            Text("Always Pause").tag("always")
                            Text("Lower Volume").tag("lower")
                            Text("Mute").tag("mute")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 170)
                    }
                    
                    if engineClient.pauseMediaOnRecord == "pause" || engineClient.pauseMediaOnRecord == "always" || engineClient.pauseMediaOnRecord == "auto" {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Resume Media After Recording")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                Text("Automatically unpauses background music once your dictation finishes.")
                                    .font(.caption)
                                    .foregroundColor(.dictySecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $engineClient.resumeMediaAfterRecord)
                                .labelsHidden()
                                .toggleStyle(.appAccent)
                                .controlSize(.small)
                        }
                        .padding(.top, 4)
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
    }
}

struct HistoryRetentionSettingsView: View {
    @EnvironmentObject var engineClient: EngineClient
    @AppStorage("appAccentColor") private var appAccentColor: String = "olive"
    @State private var isCleaningUp = false
    @State private var cleanupSuccess = false
    @State private var showConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("History Retention & Privacy")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            
            VStack(alignment: .leading, spacing: 16) {
                // Retention Window Picker
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Retention Window")
                            .font(.system(.headline, design: .rounded))
                        Text("Automatically prune transcription history records older than this window.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { engineClient.historyRetentionPeriod },
                        set: { newPeriod in
                            engineClient.saveRetentionSettings(period: newPeriod, scrubAudio: engineClient.scrubAudioImmediately)
                        }
                    )) {
                        Text("Forever (Default)").tag("forever")
                        Text("30 Days").tag("30d")
                        Text("7 Days").tag("7d")
                        Text("24 Hours").tag("24h")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
                
                Divider()
                
                // Scrub Audio Toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scrub Raw Audio Immediately")
                            .font(.system(.headline, design: .rounded))
                        Text("Deletes WAV voice recordings as soon as transcription finishes to save disk space while keeping text notes.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { engineClient.scrubAudioImmediately },
                        set: { newValue in
                            engineClient.saveRetentionSettings(period: engineClient.historyRetentionPeriod, scrubAudio: newValue)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.appAccent)
                    .controlSize(.small)
                }
                
                Divider()
                
                // Manual Cleanup Button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manual Retention Cleanup")
                            .font(.system(.headline, design: .rounded))
                        Text("Trigger an immediate cleanup run against your configured retention policy.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    Button(action: {
                        showConfirmation = true
                    }) {
                        HStack(spacing: 6) {
                            if isCleaningUp {
                                ProgressView().controlSize(.small)
                            } else if cleanupSuccess {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.appAccent)
                            } else {
                                Image(systemName: "trash.circle")
                            }
                            Text(cleanupSuccess ? "Cleaned Up" : "Clean Up Now")
                        }
                    }
                    .buttonStyle(.flatSecondary)
                    .disabled(isCleaningUp)
                    .confirmationDialog(
                        "Run Retention Cleanup?",
                        isPresented: $showConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Clean Up Now", role: .destructive) {
                            isCleaningUp = true
                            cleanupSuccess = false
                            engineClient.triggerHistoryCleanup()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                isCleaningUp = false
                                cleanupSuccess = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    cleanupSuccess = false
                                }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete records older than your configured retention window (\(engineClient.historyRetentionPeriod)). This action cannot be undone.")
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
    }
}

struct DiagnosticsExportView: View {
    @EnvironmentObject var engineClient: EngineClient
    @State private var isExporting = false
    @State private var exportSuccess = false
    @State private var exportError = false
    @State private var shareAnonymousUsage = false
    
    private static let telemetrySettingsURL = EngineEndpoint.shared.url("/telemetry/settings")
    
    static func fetchShareAnonymousUsage() async -> Bool {
        guard let (data, _) = try? await EngineEndpoint.shared.session.data(from: telemetrySettingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return TelemetryClient.shared.isEnabled
        }
        let enabled = json["share_anonymous_usage"] as? Bool ?? false
        TelemetryClient.shared.isEnabled = enabled
        return enabled
    }
    
    static func setShareAnonymousUsage(_ enabled: Bool) async {
        TelemetryClient.shared.isEnabled = enabled
        var req = URLRequest(url: telemetrySettingsURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["share_anonymous_usage": enabled])
        _ = try? await EngineEndpoint.shared.session.data(for: req)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.appAccent)
                
                Text("Performance Telemetry & Diagnostics Export")
                    .font(.headline)
            }
            
            Text("Package system logs and local performance telemetry (RTF, speaking WPM, engine latency, active model) into a single .zip file to share with developers or analyze performance.")
                .font(.subheadline)
                .foregroundColor(.dictySecondary)
            
            Toggle(isOn: Binding(
                get: { shareAnonymousUsage },
                set: { newValue in
                    shareAnonymousUsage = newValue
                    Task { await Self.setShareAnonymousUsage(newValue) }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share anonymous usage statistics")
                        .font(.system(size: 13, weight: .medium))
                    Text("Off by default. Sends feature-usage and performance events with a random install ID. Never sends transcripts, audio, your email, or app names.")
                        .font(.system(size: 11))
                        .foregroundColor(.dictySecondary)
                }
            }
            .toggleStyle(.appAccent)
            .task { shareAnonymousUsage = await Self.fetchShareAnonymousUsage() }
            
            HStack(spacing: 12) {
                Button(action: {
                    isExporting = true
                    exportSuccess = false
                    exportError = false
                    Task {
                        let success = await engineClient.exportDiagnosticsPackage()
                        await MainActor.run {
                            isExporting = false
                            if success {
                                exportSuccess = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { exportSuccess = false }
                            } else {
                                exportError = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { exportError = false }
                            }
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(isExporting ? "Generating Report..." : "Export Diagnostic Report (.zip)")
                    }
                }
                .buttonStyle(.flatPrimary)
                .disabled(isExporting)
                
                if exportSuccess {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.appAccent)
                        Text("Exported & Opened in Finder!")
                            .font(.caption)
                            .foregroundColor(.appAccent)
                    }
                }
                
                if exportError {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Export Failed. Make sure Engine is active.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

struct ClearCacheSettingsView: View {
    @EnvironmentObject var engineClient: EngineClient
    @State private var showClearConfirmation = false
    @State private var showSuccessBanner = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.red)
                
                Text("Storage & Cache Management")
                    .font(.headline)
            }
            
            Text("Permanently delete all stored voice transcription records, temporary audio recordings, and local cache. This frees up disk space and resets your transcription history.")
                .font(.subheadline)
                .foregroundColor(.dictySecondary)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 12) {
                Button(role: .destructive, action: {
                    showClearConfirmation = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Clear All Cache")
                    }
                }
                .buttonStyle(.flatPrimary(color: .red))
                
                if showSuccessBanner {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.appAccent)
                        Text("Cache cleared successfully!")
                            .font(.caption)
                            .foregroundColor(.appAccent)
                    }
                }
            }
        }
        .alert("Clear All Cache", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive) {
                engineClient.clearHistory()
                withAnimation {
                    showSuccessBanner = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    showSuccessBanner = false
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to permanently delete all transcription history and audio recordings? This action cannot be undone.")
        }
    }
}

// MARK: - Advanced Preferences
struct AdvancedPreferencesSettingsView: View {
    @AppStorage("showAllModelVariants") private var showAllModelVariants = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.appAccent)
                
                Text("Advanced")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show all model variants")
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                        Text("Display separate English-only and multilingual model rows in the Models library for manual control.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $showAllModelVariants)
                        .labelsHidden()
                        .toggleStyle(.appAccent)
                        .controlSize(.small)
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

// MARK: - Onboarding & Help Preferences
struct OnboardingHelpPreferencesView: View {
    @EnvironmentObject var engineClient: EngineClient
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Help & Onboarding")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replay Setup")
                            .font(.system(.headline, design: .rounded))
                        Text("Replay setup: test your mic, pick a model and check permissions again.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    Button("Replay setup") {
                        WindowManager.openOnboardingWindow(engineClient: engineClient)
                    }
                    .buttonStyle(.bordered)
                }
                
                Divider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Help Guide")
                            .font(.system(.headline, design: .rounded))
                        Text("Open help guide: explore shortcuts, models and troubleshooting.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    Button("Open help guide") {
                        WindowManager.openHelpWindow(initialTopic: .preferences)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

// MARK: - macOS Toolbar-style Settings Switcher
struct SettingsToolbarSwitcher: View {
    @Binding var selection: Int
    
    struct TabItem: Identifiable {
        var id: Int { tag }
        let tag: Int
        let label: String
        let icon: String
    }
    
    private let tabs: [TabItem] = [
        TabItem(tag: 6, label: "General", icon: "gearshape"),
        TabItem(tag: 4, label: "Shortcuts", icon: "keyboard"),
        TabItem(tag: 16, label: "Account", icon: "person.crop.circle"),
        TabItem(tag: 11, label: "AI Providers", icon: "key"),
        TabItem(tag: 21, label: "Integrations", icon: "puzzlepiece.extension"),
        TabItem(tag: 15, label: "Sync & Backup", icon: "arrow.triangle.2.circlepath.icloud"),
        TabItem(tag: 14, label: "Updates", icon: "arrow.down.circle")
    ]
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs) { tab in
                let isSelected = selection == tab.tag
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = tab.tag
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                            .frame(height: 18)
                        
                        Text(tab.label)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundColor(isSelected ? .appAccent : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minWidth: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.appAccent.opacity(0.15) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}

// MARK: - Consolidated Settings Hub
struct SettingsHubView: View {
    @EnvironmentObject var engineClient: EngineClient
    @EnvironmentObject var updateChecker: UpdateChecker
    @AppStorage("settingsSubTabSelection") private var subTab: Int = 6
    
    var body: some View {
        VStack(spacing: 0) {
            // macOS toolbar-style navigation bar
            HStack(spacing: 8) {
                SettingsToolbarSwitcher(selection: $subTab)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider()
            
            // Sub-page container
            ZStack(alignment: .topLeading) {
                if subTab == 6 {
                    PreferencesSettingsView()
                } else if subTab == 4 {
                    ShortcutsView()
                } else if subTab == 16 {
                    AccountSettingsView()
                } else if subTab == 11 {
                    APISettingsView()
                } else if subTab == 21 {
                    IntegrationsSettingsView()
                } else if subTab == 15 {
                    SyncSettingsView()
                } else if subTab == 14 {
                    CheckForUpdatesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var engineClient: EngineClient
    @EnvironmentObject var updateChecker: UpdateChecker
    @AppStorage("settingsTabSelection") private var selection = 0
    @State private var visitedPages: Set<Int> = []
    static let keepAlivePages: Set<Int> = [2, 3, 18]
    
    @ViewBuilder
    private func keepAlive<Content: View>(_ page: Int, @ViewBuilder _ content: () -> Content) -> some View {
        if visitedPages.contains(page) || selection == page {
            content()
                .opacity(selection == page ? 1 : 0)
                .allowsHitTesting(selection == page)
                .accessibilityHidden(selection != page)
        }
    }
    @AppStorage("appTheme") private var appTheme: String = "Dark"
    @AppStorage("appAccentColor") private var appAccentColor: String = "olive"
    @Environment(\.colorScheme) var colorScheme
    @State private var animateGradient = false
    
    var themeScheme: ColorScheme? {
        if appTheme == "Light" { return .light }
        if appTheme == "Dark" { return .dark }
        return nil
    }
    
    var currentTopicForSelection: FeatureHelpTopic {
        switch selection {
        case 0, 2: return .models
        case 1: return .modes
        case 3: return .history
        case 4: return .shortcuts
        case 5, 19, 22: return .vocabulary
        case 6, 11, 14, 15, 16, 21: return .preferences
        case 7: return .transcribe
        case 8, 9, 10, 12, 17: return .projects
        case 20: return .models
        default: return .models
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 2) {
                        SidebarButton(title: "Home", systemImage: "house", selection: $selection, targetSelection: 0)
                        SidebarButton(title: "Modes", systemImage: "slider.horizontal.3", selection: $selection, targetSelection: 1)
                        SidebarButton(title: "Words", systemImage: "character.book.closed", selection: $selection, targetSelection: 22)
                        SidebarButton(title: "History", systemImage: "clock", selection: $selection, targetSelection: 3)
                        SidebarButton(title: "Insights", systemImage: "chart.xyaxis.line", selection: $selection, targetSelection: 20)
                        
                        SidebarSectionHeader(title: "Tools")
                        SidebarButton(title: "Transcribe file", systemImage: "waveform.and.mic", selection: $selection, targetSelection: 7)
                        SidebarButton(title: "Text to Voice", systemImage: "speaker.wave.2.fill", selection: $selection, targetSelection: 18)
                        SidebarButton(
                            title: "Projects",
                            systemImage: "folder",
                            selection: $selection,
                            targetSelection: 8,
                            hasBadge: !engineClient.stagedThoughts.isEmpty,
                            badgeCount: engineClient.stagedThoughts.isEmpty ? nil : engineClient.stagedThoughts.count,
                            badgeTooltip: "\(engineClient.stagedThoughts.count) item\(engineClient.stagedThoughts.count == 1 ? "" : "s") waiting"
                        )
                        
                        SidebarSectionHeader(title: "Library")
                        SidebarButton(title: "Models", systemImage: "square.grid.2x2", selection: $selection, targetSelection: 2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .padding(.top, 8)
                
                Divider()
                
                // Pinned Bottom Section
                VStack(spacing: 2) {
                    SidebarButton(
                        title: "Settings",
                        systemImage: "gearshape",
                        selection: Binding(
                            get: { [4, 6, 11, 14, 15, 16, 21].contains(selection) ? 6 : selection },
                            set: { selection = $0 }
                        ),
                        targetSelection: 6,
                        hasBadge: updateChecker.updateAvailable,
                        badgeTooltip: "An update is available (Settings → Updates)"
                    )
                    
                    SidebarButton(title: "Help", systemImage: "questionmark.circle", selection: $selection, targetSelection: 99)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(width: 210)
            .layoutPriority(1)
            
            Divider()
            
            ZStack(alignment: .topLeading) {
                // Heavy pages (measured 100-200 ms to build) stay mounted after first visit and are
                // only hidden, so switching back is instant. Light pages are rebuilt as before.
                keepAlive(2) { ModelsLibraryView() }
                keepAlive(3) { HistoryContainerView() }
                keepAlive(18) { TextToVoiceSettingsView() }
                
                if Self.keepAlivePages.contains(selection) { EmptyView() }
                else if selection == 0 { HomeView() }
                else if selection == 1 { ModesView() }
                else if [4, 6, 11, 14, 15, 16].contains(selection) { SettingsHubView() }
                else if selection == 22 || selection == 5 || selection == 19 { WordsView() }
                else if selection == 7 { TranscribeFileView() }
                else if selection == 8 || selection == 12 || selection == 17 { ProjectsView() }
                else if selection == 9 { KnowledgeBaseSettingsView() }
                else if selection == 10 { PendingUpdatesView() }
                else if selection == 13 { UpdatesHistoryView() }
                else if selection == 20 { InsightsView() }
                else if selection == 99 { FeatureHelpEmbeddedView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: selection) { oldValue, newValue in
                if Self.keepAlivePages.contains(oldValue) { visitedPages.insert(oldValue) }
                if Self.keepAlivePages.contains(newValue) { visitedPages.insert(newValue) }
                // Kept-alive pages don't get onAppear again: refresh their data on revisit
                if newValue == 3 { engineClient.fetchHistory() }
                if newValue == 2 { engineClient.fetchModels() }
                // Removed pages redirect to their new home.
                switch newValue {
                case 5: UserDefaults.standard.set("vocabulary", forKey: "wordsTabSelection"); selection = 22
                case 19: UserDefaults.standard.set("snippets", forKey: "wordsTabSelection"); selection = 22
                case 12, 17: selection = 8
                default: break
                }
                // If a subtab was targeted directly from outside (e.g. notifications/links), sync subTab
                if [4, 6, 11, 14, 15, 16, 21].contains(newValue) {
                    UserDefaults.standard.set(newValue, forKey: "settingsSubTabSelection")
                }
            }
            #if DEBUG
            .onChange(of: selection) { _, newValue in
                // Time until the next main-runloop turn after the new page was built and committed
                let t0 = CFAbsoluteTimeGetCurrent()
                DispatchQueue.main.async {
                    print(String(format: "⏱️ [UI] Switch to page %d: %.0f ms", newValue, (CFAbsoluteTimeGetCurrent() - t0) * 1000))
                }
            }
            #endif
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                FeatureHelpButton(topic: currentTopicForSelection)
            }
        }
        .background(
            ZStack {
                Color.clear
                
                // Uniform frosted tint to preserve contrast and NSVisualEffectView glass feel without busy color blobs
                if colorScheme == .dark {
                    Color.black.opacity(0.35)
                } else {
                    Color.white.opacity(0.4)
                }
            }
            .ignoresSafeArea()
        )
        .frame(minWidth: 760, minHeight: 500)
        .tint(.appAccent)
        .accentColor(.appAccent)
        .onAppear {
            animateGradient.toggle()
            engineClient.fetchModels()
            engineClient.fetchHistory()
            engineClient.fetchDevices()
            engineClient.fetchStats()
            // A saved selection may point at a page that no longer exists in the sidebar.
            switch selection {
            case 5: UserDefaults.standard.set("vocabulary", forKey: "wordsTabSelection"); selection = 22
            case 19: UserDefaults.standard.set("snippets", forKey: "wordsTabSelection"); selection = 22
            case 12, 17: selection = 8
            default: break
            }
        }
        .onChange(of: appTheme) { _, newValue in
            if newValue == "Light" {
                NSApp.appearance = NSAppearance(named: .aqua)
            } else if newValue == "Dark" {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            } else {
                NSApp.appearance = nil
            }
        }
    }
}
