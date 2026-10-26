import SwiftUI
import AppKit

struct ResilientVocabularyItem: Codable {
    var id: String?
    var word: String
    var replacement: String
}

struct ResilientPromptItem: Codable {
    var key: String
    var value: String?
    var active_value: String?
    var default_value: String?
    var description: String?
    var is_custom: Bool?
    
    var resolvedValue: String {
        return active_value ?? value ?? default_value ?? ""
    }
}

struct DictyConfig: Codable {
    // Cross-Platform Metadata
    var app: String?
    var version: String?
    var exported_at: String?

    // Core AI
    var vocabulary: [ResilientVocabularyItem]
    var prompts: [ResilientPromptItem]
    
    // Preferences (supports macOS camelCase & Windows snake_case)
    var activeMode: String?
    var active_mode: String?
    var dictationFormatStyle: String?
    var dictation_format_style: String?
    var dictationLLMModel: String?
    var dictation_llm_model: String?
    var hotkeyKeyCode: Int?

    var hotkeyModifiers: Int?
    var hotkeyBehavior: String?
    var ttsHotkeyKeyCode: Int?
    var ttsHotkeyModifiers: Int?
    var ttsRequireDoubleTap: Bool?
    var autoPaste: Bool?
    var restoreClipboardAfterPaste: Bool?
    var isIncognitoMode: Bool?
    var pauseMediaOnRecord: String?
    var resumeMediaAfterRecord: Bool?
    var transcriptionLanguage: String?
    var keepModelInMemory: Bool?
    var favoriteModelsString: String?
    var favorite_models: String?
    var statsPeriod: String?
    var appTheme: String?
    var appAccentColor: String?
    var showInDock: Bool?
    var dockIconTheme: String?
    var hasSeenOnboarding: Bool?
    
    // Fallback dict for Windows Tauri localStorage
    var localStorageBackup: [String: String?]?
    
    // Sounds
    var startSoundType: String?
    var startSoundName: String?
    var startSoundPath: String?
    var stopSoundType: String?
    var stopSoundName: String?
    var stopSoundPath: String?
    
    // Integrations
    var llmProvider: String?
    var llmBaseUrl: String?
    var llmModel: String?
    var confluenceUrl: String?
    var confluenceSpace: String?
    var confluenceUser: String?
    var confluencePageTitle: String?
    var targetSystem: String?
    var obsidianPath: String?
    var gitProvider: String?
    var selectedGitHubRepo: String?
    var gitlabHost: String?
    var selectedGitLabRepo: String?
    var selectedBitbucketRepo: String?
    var notionPageId: String?
    
    // Secrets
    var llmApiKey: String?
    var openaiApiKey: String?
    var confluenceToken: String?
    var githubToken: String?
    var gitlabToken: String?
    var bitbucketToken: String?
    var linearApiToken: String?
    var notionApiKey: String?
}

@MainActor
class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var isExporting = false
    @Published var isImporting = false
    @Published var importError: String? = nil
    
    func exportConfig(engineClient: EngineClient, includeAPIKeys: Bool) {
        isExporting = true
        
        Task {
            engineClient.fetchVocabulary()
            engineClient.fetchPrompts()
            // Wait for data to load
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            await MainActor.run {
                defer { self.isExporting = false }
                let defaults = UserDefaults.standard
                
                var config = DictyConfig(
                    app: "Dicty",
                    version: "1.0.0",
                    exported_at: ISO8601DateFormatter().string(from: Date()),
                    vocabulary: engineClient.vocabulary.map { ResilientVocabularyItem(id: $0.id, word: $0.word, replacement: $0.replacement) },
                    prompts: engineClient.prompts.map { ResilientPromptItem(key: $0.key, value: $0.active_value, active_value: $0.active_value, default_value: $0.default_value, description: $0.description, is_custom: $0.is_custom) },
                    
                    activeMode: defaults.string(forKey: "activeMode"),
                    active_mode: defaults.string(forKey: "activeMode"),
                    dictationFormatStyle: defaults.string(forKey: "dictationFormatStyle"),
                    dictation_format_style: defaults.string(forKey: "dictationFormatStyle"),
                    dictationLLMModel: defaults.string(forKey: "dictationLLMModel"),
                    dictation_llm_model: defaults.string(forKey: "dictationLLMModel"),
                    hotkeyKeyCode: defaults.object(forKey: "hotkeyKeyCode") as? Int,

                    hotkeyModifiers: defaults.object(forKey: "hotkeyModifiers") as? Int,
                    hotkeyBehavior: defaults.string(forKey: "hotkeyBehavior"),
                    ttsHotkeyKeyCode: defaults.object(forKey: "ttsHotkeyKeyCode") as? Int,
                    ttsHotkeyModifiers: defaults.object(forKey: "ttsHotkeyModifiers") as? Int,
                    ttsRequireDoubleTap: defaults.object(forKey: "ttsRequireDoubleTap") as? Bool,
                    autoPaste: defaults.object(forKey: "autoPaste") as? Bool,
                    restoreClipboardAfterPaste: defaults.object(forKey: "restoreClipboardAfterPaste") as? Bool,
                    isIncognitoMode: defaults.object(forKey: "isIncognitoMode") as? Bool,
                    pauseMediaOnRecord: defaults.string(forKey: "pauseMediaOnRecord"),
                    resumeMediaAfterRecord: defaults.object(forKey: "resumeMediaAfterRecord") as? Bool,
                    transcriptionLanguage: defaults.string(forKey: "transcriptionLanguage"),
                    keepModelInMemory: defaults.object(forKey: "keepModelInMemory") as? Bool,
                    favoriteModelsString: defaults.string(forKey: "favoriteModels"),
                    favorite_models: defaults.string(forKey: "favoriteModels"),
                    statsPeriod: defaults.string(forKey: "statsPeriod"),
                    appTheme: defaults.string(forKey: "appTheme"),
                    appAccentColor: defaults.string(forKey: "appAccentColor"),
                    showInDock: defaults.object(forKey: "showInDock") as? Bool,
                    dockIconTheme: defaults.string(forKey: "dockIconTheme"),
                    hasSeenOnboarding: defaults.object(forKey: "hasSeenOnboarding") as? Bool,
                    
                    localStorageBackup: [
                        "active_mode": defaults.string(forKey: "activeMode"),
                        "dictation_format_style": defaults.string(forKey: "dictationFormatStyle"),
                        "favorite_models": defaults.string(forKey: "favoriteModels")
                    ],
                    
                    startSoundType: defaults.string(forKey: "startSoundType"),
                    startSoundName: defaults.string(forKey: "startSoundName"),
                    startSoundPath: defaults.string(forKey: "startSoundPath"),
                    stopSoundType: defaults.string(forKey: "stopSoundType"),
                    stopSoundName: defaults.string(forKey: "stopSoundName"),
                    stopSoundPath: defaults.string(forKey: "stopSoundPath"),
                    
                    llmProvider: defaults.string(forKey: "llmProvider"),
                    llmBaseUrl: defaults.string(forKey: "llmBaseUrl"),
                    llmModel: defaults.string(forKey: "llmModel"),
                    confluenceUrl: defaults.string(forKey: "confluenceUrl"),
                    confluenceSpace: defaults.string(forKey: "confluenceSpace"),
                    confluenceUser: defaults.string(forKey: "confluenceUser"),
                    confluencePageTitle: defaults.string(forKey: "confluencePageTitle"),
                    targetSystem: defaults.string(forKey: "targetSystem"),
                    obsidianPath: defaults.string(forKey: "obsidianPath"),
                    gitProvider: defaults.string(forKey: "gitProvider"),
                    selectedGitHubRepo: defaults.string(forKey: "selectedGitHubRepo"),
                    gitlabHost: defaults.string(forKey: "gitlabHost"),
                    selectedGitLabRepo: defaults.string(forKey: "selectedGitLabRepo"),
                    selectedBitbucketRepo: defaults.string(forKey: "selectedBitbucketRepo"),
                    notionPageId: defaults.string(forKey: "notionPageId")
                )
                
                if includeAPIKeys {
                    config.llmApiKey = SecretsManager.readSecret(forKey: "llmApiKey")
                    config.openaiApiKey = SecretsManager.readSecret(forKey: "openaiApiKey")
                    config.confluenceToken = SecretsManager.readSecret(forKey: "confluenceToken")
                    config.githubToken = SecretsManager.readSecret(forKey: "githubToken")
                    config.gitlabToken = SecretsManager.readSecret(forKey: "gitlabToken")
                    config.bitbucketToken = SecretsManager.readSecret(forKey: "bitbucketToken")
                    config.linearApiToken = SecretsManager.readSecret(forKey: "linearApiToken")
                    config.notionApiKey = defaults.string(forKey: "notionApiKey")
                }
                
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let data = try encoder.encode(config)
                    
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.json]
                    panel.nameFieldStringValue = "dicty_setup.json"
                    panel.title = "Export Dicty Setup"
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        try data.write(to: url)
                    }
                } catch {
                    print("Export error: \(error)")
                }
            }
        }
    }
    
    func importConfig(engineClient: EngineClient, url: URL, merge: Bool) {
        isImporting = true
        defer { isImporting = false }
        
        do {
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(DictyConfig.self, from: data)
            
            let defaults = UserDefaults.standard
            
            // Restore Preferences
            let activeMode = config.activeMode ?? config.active_mode ?? config.localStorageBackup?["active_mode"] ?? nil
            if let v = activeMode { defaults.set(v, forKey: "activeMode") }
            let dictationFormatStyle = config.dictationFormatStyle ?? config.dictation_format_style ?? config.localStorageBackup?["dictation_format_style"] ?? nil
            if let v = dictationFormatStyle { defaults.set(v, forKey: "dictationFormatStyle") }
            let dictationLLMModel = config.dictationLLMModel ?? config.dictation_llm_model ?? nil
            if let v = dictationLLMModel { defaults.set(v, forKey: "dictationLLMModel") }
            let favoriteModels = config.favoriteModelsString ?? config.favorite_models ?? config.localStorageBackup?["favorite_models"] ?? nil
            if let v = favoriteModels { defaults.set(v, forKey: "favoriteModels") }
            if let v = config.hotkeyKeyCode { defaults.set(v, forKey: "hotkeyKeyCode") }

            if let v = config.hotkeyModifiers { defaults.set(v, forKey: "hotkeyModifiers") }
            if let v = config.hotkeyBehavior { defaults.set(v, forKey: "hotkeyBehavior") }
            if let v = config.ttsHotkeyKeyCode { defaults.set(v, forKey: "ttsHotkeyKeyCode") }
            if let v = config.ttsHotkeyModifiers { defaults.set(v, forKey: "ttsHotkeyModifiers") }
            if let v = config.ttsRequireDoubleTap { defaults.set(v, forKey: "ttsRequireDoubleTap") }
            if let v = config.autoPaste { defaults.set(v, forKey: "autoPaste") }
            if let v = config.restoreClipboardAfterPaste { defaults.set(v, forKey: "restoreClipboardAfterPaste") }
            if let v = config.isIncognitoMode { defaults.set(v, forKey: "isIncognitoMode") }
            if let v = config.pauseMediaOnRecord { defaults.set(v, forKey: "pauseMediaOnRecord") }
            if let v = config.resumeMediaAfterRecord { defaults.set(v, forKey: "resumeMediaAfterRecord") }
            if let v = config.transcriptionLanguage { defaults.set(v, forKey: "transcriptionLanguage") }
            if let v = config.keepModelInMemory { defaults.set(v, forKey: "keepModelInMemory") }
            if let v = config.statsPeriod { defaults.set(v, forKey: "statsPeriod") }
            if let v = config.appTheme { defaults.set(v, forKey: "appTheme") }
            if let v = config.appAccentColor { defaults.set(v, forKey: "appAccentColor") }
            if let v = config.showInDock { defaults.set(v, forKey: "showInDock") }
            if let v = config.dockIconTheme { defaults.set(v, forKey: "dockIconTheme") }
            if let v = config.hasSeenOnboarding { defaults.set(v, forKey: "hasSeenOnboarding") }
            
            if let v = config.startSoundType { defaults.set(v, forKey: "startSoundType") }
            if let v = config.startSoundName { defaults.set(v, forKey: "startSoundName") }
            if let v = config.startSoundPath { defaults.set(v, forKey: "startSoundPath") }
            if let v = config.stopSoundType { defaults.set(v, forKey: "stopSoundType") }
            if let v = config.stopSoundName { defaults.set(v, forKey: "stopSoundName") }
            if let v = config.stopSoundPath { defaults.set(v, forKey: "stopSoundPath") }
            
            if let v = config.llmProvider { defaults.set(v, forKey: "llmProvider") }
            if let v = config.llmBaseUrl { defaults.set(v, forKey: "llmBaseUrl") }
            if let v = config.llmModel { defaults.set(v, forKey: "llmModel") }
            if let v = config.confluenceUrl { defaults.set(v, forKey: "confluenceUrl") }
            if let v = config.confluenceSpace { defaults.set(v, forKey: "confluenceSpace") }
            if let v = config.confluenceUser { defaults.set(v, forKey: "confluenceUser") }
            if let v = config.confluencePageTitle { defaults.set(v, forKey: "confluencePageTitle") }
            if let v = config.targetSystem { defaults.set(v, forKey: "targetSystem") }
            if let v = config.obsidianPath { defaults.set(v, forKey: "obsidianPath") }
            if let v = config.gitProvider { defaults.set(v, forKey: "gitProvider") }
            if let v = config.selectedGitHubRepo { defaults.set(v, forKey: "selectedGitHubRepo") }
            if let v = config.gitlabHost { defaults.set(v, forKey: "gitlabHost") }
            if let v = config.selectedGitLabRepo { defaults.set(v, forKey: "selectedGitLabRepo") }
            if let v = config.selectedBitbucketRepo { defaults.set(v, forKey: "selectedBitbucketRepo") }
            if let v = config.notionPageId { defaults.set(v, forKey: "notionPageId") }
            
            // Restore Secrets
            if let v = config.llmApiKey { SecretsManager.saveSecret(v, forKey: "llmApiKey") }
            if let v = config.openaiApiKey { SecretsManager.saveSecret(v, forKey: "openaiApiKey") }
            if let v = config.confluenceToken { SecretsManager.saveSecret(v, forKey: "confluenceToken") }
            if let v = config.githubToken { SecretsManager.saveSecret(v, forKey: "githubToken") }
            if let v = config.gitlabToken { SecretsManager.saveSecret(v, forKey: "gitlabToken") }
            if let v = config.bitbucketToken { SecretsManager.saveSecret(v, forKey: "bitbucketToken") }
            if let v = config.linearApiToken { SecretsManager.saveSecret(v, forKey: "linearApiToken") }
            if let v = config.notionApiKey { defaults.set(v, forKey: "notionApiKey") }
            
            // Sync with engineClient immediately so UI updates
            if let v = config.activeMode { engineClient.activeMode = v }
            if let _ = config.appTheme {
                AppDelegate.applyTheme()
            }
            if let _ = config.showInDock {
                AppDelegate.applyActivationPolicy()
            }
            if let v = config.keepModelInMemory {
                engineClient.keepModelInMemory = v
                engineClient.updateMemoryMode()
            }
            if let v = config.hotkeyKeyCode {
                engineClient.hotkeyKeyCode = v
            }
            if let v = config.hotkeyModifiers {
                engineClient.hotkeyModifiers = v
            }
            if let v = config.hotkeyBehavior {
                engineClient.hotkeyBehavior = v
                engineClient.setupGlobalMonitor()
            }
            if let v = config.ttsHotkeyKeyCode { engineClient.ttsHotkeyKeyCode = v }
            if let v = config.ttsHotkeyModifiers { engineClient.ttsHotkeyModifiers = v }
            if let v = config.ttsRequireDoubleTap { engineClient.ttsRequireDoubleTap = v }
            engineClient.setupGlobalMonitor()
            if let v = config.isIncognitoMode { engineClient.isIncognitoMode = v }
            if let v = config.pauseMediaOnRecord { engineClient.pauseMediaOnRecord = v }
            if let v = config.resumeMediaAfterRecord { engineClient.resumeMediaAfterRecord = v }
            
            Task {
                // Update vocabulary
                if !merge {
                    for v in engineClient.vocabulary {
                        engineClient.deleteVocabulary(id: v.id)
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                
                var existingWords = Set<String>()
                if merge {
                    existingWords = Set(engineClient.vocabulary.map { "\($0.word.lowercased())|\($0.replacement)" })
                }
                
                for voc in config.vocabulary {
                    let key = "\(voc.word.lowercased())|\(voc.replacement)"
                    if !existingWords.contains(key) {
                        engineClient.addVocabulary(word: voc.word, replacement: voc.replacement)
                        existingWords.insert(key)
                    }
                }
                
                // Update prompts
                for p in config.prompts {
                    let val = p.resolvedValue
                    if !val.isEmpty {
                        engineClient.updatePrompt(key: p.key, value: val)
                    }
                }
                
                engineClient.fetchVocabulary()
                engineClient.fetchPrompts()
            }
            
        } catch {
            print("Import error: \(error)")
            importError = error.localizedDescription
        }
    }
}

struct SyncSettingsView: View {
    @EnvironmentObject var engineClient: EngineClient
    @StateObject private var configManager = ConfigManager.shared
    
    @State private var showImportAlert = false
    @State private var pendingImportUrl: URL? = nil
    @State private var includeAPIKeys = false
    
    @State private var isCloudSyncing = false
    @State private var cloudSyncSuccess = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Text("Sync & Backup")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    FeatureHelpButton(topic: .sync_backup)
                }
                
                Text("Sync your custom prompts and knowledge base settings to the cloud or export them locally.")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                if engineClient.isLoggedIn {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Cloud Sync")
                                .font(.headline)
                        }
                        Text("Keep your custom prompts and Librarian configuration synchronized across all your devices.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                isCloudSyncing = true
                                cloudSyncSuccess = false
                                Task {
                                    await engineClient.uploadSettingsToCloud()
                                    await engineClient.downloadSettingsFromCloud()
                                    await MainActor.run {
                                        isCloudSyncing = false
                                        cloudSyncSuccess = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { cloudSyncSuccess = false }
                                    }
                                }
                            }) {
                                HStack(spacing: 6) {
                                    if isCloudSyncing {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text(isCloudSyncing ? "Syncing..." : "Sync with Cloud Now")
                                }
                            }
                            .buttonStyle(.flatPrimary)
                            .disabled(isCloudSyncing)
                            
                            if cloudSyncSuccess {
                                Text("Sync Complete!")
                                    .foregroundColor(.appAccent)
                                    .font(.caption)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                }
                
                // Export Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export Setup")
                        .font(.headline)
                    Text("Saves your Preferences, Integrations, Vocabulary, and Custom Prompts into a configuration file.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Toggle("Include API Keys and Credentials", isOn: $includeAPIKeys)
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 4)
                        .help("Turn this on to also export your saved API Keys (OpenRouter, OpenAI, GitHub, Confluence). Be careful when sharing this file!")
                    
                    Button(action: {
                        configManager.exportConfig(engineClient: engineClient, includeAPIKeys: includeAPIKeys)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Configuration")
                        }
                    }
                    .buttonStyle(.flatPrimary)
                    .disabled(configManager.isExporting)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                
                // Import Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Import Setup")
                        .font(.headline)
                    Text("Restores your configuration from a previously exported file.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.json]
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        
                        if panel.runModal() == .OK, let url = panel.url {
                            pendingImportUrl = url
                            showImportAlert = true
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import Configuration")
                        }
                    }
                    .buttonStyle(.flatSecondary)
                    .disabled(configManager.isImporting)
                    
                    if let err = configManager.importError {
                        Text("Error: \(err)")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                
                Spacer()
            }
            .frame(maxWidth: 800, alignment: .leading)
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Sync & Backup")
        .alert("Import Options", isPresented: $showImportAlert) {
            Button("Merge (Keep existing vocabulary/prompts)") {
                if let url = pendingImportUrl {
                    configManager.importConfig(engineClient: engineClient, url: url, merge: true)
                }
            }
            Button("Overwrite (Delete existing vocabulary/prompts)", role: .destructive) {
                if let url = pendingImportUrl {
                    configManager.importConfig(engineClient: engineClient, url: url, merge: false)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingImportUrl = nil
            }
        } message: {
            Text("How would you like to import Vocabulary and Custom Prompts? Your app preferences will always be overwritten.")
        }
    }
}
