import SwiftUI
import AppKit
import UniformTypeIdentifiers
@preconcurrency import AVFoundation

struct CloudConfig {
    static var baseURL: String {
        return ProcessInfo.processInfo.environment["DICTY_CLOUD_URL"] ?? "https://dicty-backend.dicty-backend.workers.dev"
    }
}

// MARK: - Target App Context

struct TargetAppContext: Equatable {
    let name: String
    let bundleID: String

    init?(application: NSRunningApplication?) {
        guard let application else { return nil }
        self.init(name: application.localizedName ?? "", bundleID: application.bundleIdentifier ?? "")
    }

    init?(name: String, bundleID: String) {
        let cleanName = Self.sanitize(name)
        let cleanBundleID = Self.sanitize(bundleID)
        guard !cleanName.isEmpty || !cleanBundleID.isEmpty else { return nil }
        self.name = cleanName
        self.bundleID = cleanBundleID
    }

    var formFields: [(name: String, value: String)] {
        [
            ("target_app_name", name),
            ("target_app_bundle_id", bundleID)
        ]
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Engine Client
@MainActor
class EngineClient: ObservableObject {
    static let shared = EngineClient()
    
    @Published var isLoggedIn: Bool = false
    @Published var userEmail: String? = nil
    @Published var userId: Int? = nil
    @Published var isPro: Bool = false
    @Published var computeBalance: Int = 0
    @Published var subscriptionTier: String = "free"
    @Published var planExpiresAt: String? = nil
    private var authLoopbackTask: Task<Void, Never>? = nil
    
    // Check if the user has provided their own API keys
    var hasCustomAPIKey: Bool {
        let llm = SecretsManager.readSecret(forKey: "llmApiKey") ?? ""
        let openai = SecretsManager.readSecret(forKey: "openaiApiKey") ?? ""
        return !llm.isEmpty || !openai.isEmpty
    }
    
    // Whether the user can use Cloud LLMs
    var canUseCloud: Bool {
        return true
    }
    
    // The effective LLM provider: falls back to openrouter if dicty_cloud is selected without active Pro login / balance,
    // and automatically routes to dicty_cloud if the user is a Pro subscriber or has cloud credits without custom API keys.
    var effectiveLLMProvider: String {
        let provider = UserDefaults.standard.string(forKey: "llmProvider") ?? "openrouter"
        let hasCloudAccess = isLoggedIn && (isPro || computeBalance > 0)
        if provider == "dicty_cloud" && !hasCloudAccess {
            return "openrouter"
        }
        if provider == "openrouter" && hasCloudAccess && !hasCustomAPIKey {
            return "dicty_cloud"
        }
        return provider
    }
    @Published var offlineMode: Bool = false
    @Published var engineAuthFailed: Bool = false
    private var engineAuthObservers: [NSObjectProtocol] = []
    
    // MARK: - Transcribe File View State
    @Published var transcribeFileSelectedURL: URL? = nil
    @Published var transcribeFileTranscribedText: String = ""
    @Published var transcribeFileErrorMessage: String? = nil
    @Published var transcribeFileIsProcessing: Bool = false
    
    @AppStorage("activeMode") var activeMode: String = "dictation"
    @AppStorage("dictationFormatStyle") var dictationFormatStyle: String = "raw"
    @AppStorage("useVADStreaming") var useVADStreaming: Bool = false
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = 49 // Space
    @AppStorage("hotkeyModifiers") var hotkeyModifiers: Int = Int(NSEvent.ModifierFlags.option.rawValue)
    @AppStorage("hotkeyBehavior") var hotkeyBehavior: String = "hold" // "hold" (Push to Talk / Hold to speak) or "toggle"
    @Published var isHoldingToRecord: Bool = false
    private var recordingStartTime = Date()
    @AppStorage("pauseHotkeyKeyCode") var pauseHotkeyKeyCode: Int = 35 // P key
    @AppStorage("pauseHotkeyModifiers") var pauseHotkeyModifiers: Int = Int(NSEvent.ModifierFlags.option.rawValue) // ⌥P
    @AppStorage("pauseHotkeyBehavior") var pauseHotkeyBehavior: String = "toggle" // "toggle" or "hold"
    @Published var isHoldingToPause: Bool = false
    @AppStorage("switchModeHotkeyKeyCode") var switchModeHotkeyKeyCode: Int = 46 // M key
    @AppStorage("switchModeHotkeyModifiers") var switchModeHotkeyModifiers: Int = Int(NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.shift.rawValue)
    @AppStorage("switchModeHotkeyBehavior") var switchModeHotkeyBehavior: String = "toggle" // "toggle" or "hold"
    @Published var isHoldingToSwitchMode: Bool = false
    @AppStorage("ttsHotkeyKeyCode") var ttsHotkeyKeyCode: Int = 1 // S key
    @AppStorage("ttsHotkeyModifiers") var ttsHotkeyModifiers: Int = Int(NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.shift.rawValue) // ⌥⇧S
    @AppStorage("ttsHotkeyBehavior") var ttsHotkeyBehavior: String = "toggle" // "toggle" or "hold"
    @Published var isHoldingToTts: Bool = false
    @AppStorage("recordRequireDoubleTap") var recordRequireDoubleTap: Bool = false
    @AppStorage("pauseRequireDoubleTap") var pauseRequireDoubleTap: Bool = false
    @AppStorage("switchModeRequireDoubleTap") var switchModeRequireDoubleTap: Bool = false
    @AppStorage("ttsRequireDoubleTap") var ttsRequireDoubleTap: Bool = false
    @AppStorage("isIncognitoMode") var isIncognitoMode: Bool = false
    
    static func isSingleKeyShortcut(keyCode: Int, modifiers: Int) -> Bool {
        let standardModifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let mods = NSEvent.ModifierFlags(rawValue: UInt(modifiers)).intersection(standardModifierMask)
        let uKey = UInt16(keyCode)
        
        if isModifierKeyCode(uKey) {
            switch uKey {
            case 54, 55: return mods == .command
            case 58, 61: return mods == .option
            case 59, 62: return mods == .control
            case 56, 60: return mods == .shift
            case 57: return true // Caps Lock
            case 63: return mods.isEmpty
            default: return false
            }
        } else {
            return mods.isEmpty
        }
    }
    
    var isRecordSingleKey: Bool {
        Self.isSingleKeyShortcut(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }
    
    var isPauseSingleKey: Bool {
        Self.isSingleKeyShortcut(keyCode: pauseHotkeyKeyCode, modifiers: pauseHotkeyModifiers)
    }
    
    var isSwitchModeSingleKey: Bool {
        Self.isSingleKeyShortcut(keyCode: switchModeHotkeyKeyCode, modifiers: switchModeHotkeyModifiers)
    }
    
    var isTtsSingleKey: Bool {
        Self.isSingleKeyShortcut(keyCode: ttsHotkeyKeyCode, modifiers: ttsHotkeyModifiers)
    }
    
    func toggleIncognitoMode() {
        isIncognitoMode.toggle()
        if isIncognitoMode {
            NSSound(named: NSSound.Name("Tink"))?.play()
        } else {
            NSSound(named: NSSound.Name("Pop"))?.play()
        }
        print("[*] Incognito Mode: \(isIncognitoMode)")
    }
    
    func formatShortcutString(keyCode: Int, modifiers: Int) -> String {
        let uKey = UInt16(keyCode)
        if Self.isModifierKeyCode(uKey) {
            switch uKey {
            case 54: return "Right ⌘"
            case 55: return "Left ⌘"
            case 56: return "Left ⇧"
            case 57: return "Caps Lock"
            case 58: return "Left ⌥"
            case 59: return "Left ⌃"
            case 60: return "Right ⇧"
            case 61: return "Right ⌥"
            case 62: return "Right ⌃"
            case 63: return "Fn (Globe)"
            default: break
            }
        }
        
        var str = ""
        let mods = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if mods.contains(.control) { str += "⌃" }
        if mods.contains(.option) { str += "⌥" }
        if mods.contains(.shift) { str += "⇧" }
        if mods.contains(.command) { str += "⌘" }
        
        let keyMap: [Int: String] = [
            // Letters
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M",
            
            // Numbers
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            
            // Symbols / Punctuation
            50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\",
            41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 10: "§",
            
            // Whitespace / Control
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
            57: "Caps Lock",
            
            // Navigation & Editing
            114: "Help", 115: "Home", 116: "Page Up", 117: "Fwd Delete",
            119: "End", 121: "Page Down",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            
            // Function Keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
            79: "F18", 80: "F19", 90: "F20",
            
            // Keypad
            65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "Clear",
            75: "Keypad /", 76: "Keypad Enter", 78: "Keypad -", 81: "Keypad =",
            82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3",
            86: "Keypad 4", 87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7",
            91: "Keypad 8", 92: "Keypad 9"
        ]
        
        if let name = keyMap[keyCode] {
            str += name
        } else {
            str += "Key \(keyCode)"
        }
        return str.isEmpty ? "None" : str
    }
    
    var recordShortcutDisplay: String {
        let base = formatShortcutString(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
        if recordRequireDoubleTap && isRecordSingleKey {
            return "2× " + base
        }
        return base
    }
    
    var pauseShortcutDisplay: String {
        let base = formatShortcutString(keyCode: pauseHotkeyKeyCode, modifiers: pauseHotkeyModifiers)
        if pauseRequireDoubleTap && isPauseSingleKey {
            return "2× " + base
        }
        return base
    }
    
    var switchModeShortcutDisplay: String {
        let base = formatShortcutString(keyCode: switchModeHotkeyKeyCode, modifiers: switchModeHotkeyModifiers)
        if switchModeRequireDoubleTap && isSwitchModeSingleKey {
            return "2× " + base
        }
        return base
    }
    
    var ttsShortcutDisplay: String {
        let base = formatShortcutString(keyCode: ttsHotkeyKeyCode, modifiers: ttsHotkeyModifiers)
        if ttsRequireDoubleTap && isTtsSingleKey {
            return "2× " + base
        }
        return base
    }
    
    @AppStorage("autoPaste") var autoPaste: Bool = true
    @AppStorage("restoreClipboardAfterPaste") var restoreClipboardAfterPaste: Bool = false
    @AppStorage("pauseMediaOnRecord") var pauseMediaOnRecord: String = "pause"
    @AppStorage("resumeMediaAfterRecord") var resumeMediaAfterRecord: Bool = true
    @AppStorage("activeDeviceID") var activeDeviceID: Int = -1
    @AppStorage("transcriptionLanguage") var transcriptionLanguage: String = "auto"
    @AppStorage("translateToEnglish") var translateToEnglish: Bool = false
    @AppStorage("targetLanguage") var targetLanguage: String = "none"
    @AppStorage("enableAutoCompletion") var enableAutoCompletion: Bool = false
    @AppStorage("enableSelfCorrection") var enableSelfCorrection: Bool = false
    @AppStorage("selfCorrectionModel") var selfCorrectionModel: String = ""
    @AppStorage("translationMethod") var translationMethod: String = "built_in"
    @AppStorage("selectedTranslationModel") var selectedTranslationModel: String = ""
    @AppStorage("keepModelInMemory") var keepModelInMemory: Bool = true
    @AppStorage("favoriteModels") var favoriteModelsString: String = ""
    @AppStorage("authorName") var authorName: String = ""
    
    @Published var targetApp: NSRunningApplication?
    private static let eventSource = CGEventSource(stateID: .hidSystemState)
    private static var isAccessibilityTrusted: Bool = AXIsProcessTrusted()
    
    // MARK: - App Rules
    @Published var appRules: [AppRule] = []
    @Published var appRulesSettings: AppRulesSettings = AppRulesSettings()
    @Published var currentResolvedMode: String = ""
    @Published var currentResolvedReason: String = ""
    @Published var recordingOverrideMode: String? = nil
    @Published var manualOverrideActive: Bool = false
    @Published var pendingAppRuleSuggestion: AppRuleSuggestion? = nil
    
    var favoriteModels: Set<String> {
        Set(favoriteModelsString.split(separator: ",").map { String($0) })
    }
    
    func isFavorite(id: String) -> Bool {
        favoriteModels.contains(id)
    }
    
    func toggleFavorite(id: String) {
        var current = favoriteModels
        if current.contains(id) {
            current.remove(id)
        } else {
            current.insert(id)
        }
        favoriteModelsString = current.joined(separator: ",")
    }
    
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var isMicMuted = false
    @Published var isProcessing = false
    @Published var processingStatusMessage = "Processing..."
    @Published var activeModel = ""
    @Published var activeTextModel = ""
    @Published var models: [DictyModel] = []
    @Published var openRouterModels: [OpenRouterModelInfo] = []
    @Published var isLoadingOpenRouterModels: Bool = false
    @Published var history: [DictyHistory] = []
    private var lastHistoryPayloadHash: Int?
    @Published var historyRetentionPeriod: String = "forever"
    @Published var scrubAudioImmediately: Bool = false
    @Published var summarizingIds: Set<String> = []
    @Published var summarizationErrors: [String: String] = [:]
    @Published var reprocessingIds: Set<String> = []
    @Published var reprocessErrors: [String: String] = [:]
    @Published var devices: [DictyDevice] = []
    @Published var vocabulary: [DictyVocabulary] = []
    @Published var prompts: [DictyPromptInfo] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: Bool = false
    @Published var selectedQuantizations: [String: String] = [:]
    @Published var localLLMAddonStatus: LocalLLMAddonStatus? = nil
    
    func getSelectedQuality(for modelID: String) -> String {
        let q = selectedQuantizations[modelID] ?? "q5_0"
        // Q4 is no longer offered (not published upstream, can't be produced locally)
        return q.hasPrefix("q4") ? "q5_0" : q
    }
    
    @Published var avgSpeakingWpm: Int = 0
    @Published var avgEngineWpm: Int = 0
    @Published var totalWordsSpoken: Int = 0
    // Advanced performance metrics (stop -> paste latency per transcription)
    @Published var recentLatencyMetrics: [LatencyMetric] = []
    @Published var modelLatencyMetrics: [ModelLatencyMetric] = []
    @Published var snippets: [DictySnippet] = []
    @Published var correctionModelMetrics: [CorrectionModelMetric] = []
    @Published var formattingModelMetrics: [FormattingModelMetric] = []
    @Published var hardwareSummary: String = ""
    @Published var librarianUpdates: Int = 0
    @Published var stagedThoughts: [VoiceThought] = []
    @Published var isSynthesizingDocs: Bool = false
    
    @AppStorage("statsPeriod") var statsPeriod: String = "all" {
        didSet { fetchStats() }
    }
    
    @Published var isGeneratingArchitecture: Bool = false
    @Published var architectureGenMessage: String? = nil
    
    var audioRecorder = DictyAudioRecorder()
    let engineURL = EngineEndpoint.shared.baseURL.absoluteString
    var globalMonitor: Any?
    var flagsMonitor: Any?
    var localMonitor: Any?
    var localFlagsMonitor: Any?
    var progressTimer: Timer?
    private var lastAuthCheck: Date?
    
    init() {
        engineAuthObservers.append(
            NotificationCenter.default.addObserver(forName: .dictyEngineAuthFailed, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.engineAuthFailed = true
                }
            }
        )
        engineAuthObservers.append(
            NotificationCenter.default.addObserver(forName: .dictyEngineAuthRecovered, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.engineAuthFailed = false
                }
            }
        )
        if UserDefaults.standard.object(forKey: "hotkeyBehavior") == nil {
            hotkeyBehavior = "hold"
        }
        if UserDefaults.standard.object(forKey: "pauseHotkeyBehavior") == nil {
            pauseHotkeyBehavior = "toggle"
        }
        if UserDefaults.standard.object(forKey: "switchModeHotkeyBehavior") == nil {
            switchModeHotkeyBehavior = "toggle"
        }
        if UserDefaults.standard.object(forKey: "ttsHotkeyBehavior") == nil {
            ttsHotkeyBehavior = "toggle"
        }
        setupGlobalMonitor()
        fetchAuthStatus()
        fetchModels()
        fetchHistory()
        fetchRetentionSettings()
        fetchDevices()
        fetchVocabulary()
        fetchPrompts()
        fetchStats()
        fetchStagedThoughts()
        fetchAppRules()
        updateMemoryMode()
        
        // Auto-sync settings & vocabulary on startup if token exists (never crashes if offline)
        if let token = SecretsManager.readSecret(forKey: "dicty_jwt_token"), !token.isEmpty {
            Task {
                await self.downloadSettingsFromCloud()
            }
        }
        
        // Check for subscription changes when the app becomes active
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchAuthStatus()
            }
        }
        
        // Check periodically
        Timer.scheduledTimer(withTimeInterval: 3600.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                // Smart checking logic:
                // - Always check if not logged in or not Pro
                // - If Pro, only check if planExpiresAt is close (e.g. within 2 days)
                var shouldCheck = true
                if self.isLoggedIn && self.isPro, let expiresStr = self.planExpiresAt {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    
                    var expiresDate = formatter.date(from: expiresStr)
                    if expiresDate == nil {
                        formatter.formatOptions = [.withInternetDateTime]
                        expiresDate = formatter.date(from: expiresStr)
                    }
                    
                    if let expiresDate = expiresDate {
                        let timeUntilExpiration = expiresDate.timeIntervalSince(Date())
                        // If it expires more than 48 hours away, skip the periodic DB check
                        if timeUntilExpiration > 48 * 3600 {
                            shouldCheck = false
                        }
                    }
                }
                
                if shouldCheck {
                    self.fetchAuthStatus()
                }
            }
        }
        
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if self?.isDownloading == true {
                    self?.fetchDownloadProgress()
                }
            }
        }
    }
    
    /// Last recent-metrics limit requested by the UI, so paste-driven refreshes don't shrink the chart.
    private var lastRecentLimit = 10

    func fetchPerformanceMetrics(recentLimit: Int = 10) {
        lastRecentLimit = max(1, min(recentLimit, 500))
        Task {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            // EngineClient is observed by dozens of views: assigning a @Published value re-renders all of
            // them even if nothing changed, so only publish real changes (this runs on a 5 s poll).
            if let url = URL(string: engineURL + "/metrics/recent?limit=\(max(1, min(recentLimit, 500)))"),
               let (data, _) = try? await EngineEndpoint.shared.session.data(from: url),
               let res = try? decoder.decode(RecentLatencyResponse.self, from: data) {
                await MainActor.run { if self.recentLatencyMetrics != res.items { self.recentLatencyMetrics = res.items } }
            }
            if let url = URL(string: engineURL + "/metrics/models?period=\(statsPeriod)"),
               let (data, _) = try? await EngineEndpoint.shared.session.data(from: url),
               let res = try? decoder.decode(ModelLatencyResponse.self, from: data) {
                await MainActor.run { if self.modelLatencyMetrics != res.models { self.modelLatencyMetrics = res.models } }
            }
            if let url = URL(string: engineURL + "/metrics/corrections?period=\(statsPeriod)"),
               let (data, _) = try? await EngineEndpoint.shared.session.data(from: url),
               let res = try? decoder.decode(CorrectionModelResponse.self, from: data) {
                await MainActor.run { if self.correctionModelMetrics != res.models { self.correctionModelMetrics = res.models } }
            }
            if let url = URL(string: engineURL + "/metrics/formatting?period=\(statsPeriod)"),
               let (data, _) = try? await EngineEndpoint.shared.session.data(from: url),
               let res = try? decoder.decode(FormattingModelResponse.self, from: data) {
                await MainActor.run { if self.formattingModelMetrics != res.models { self.formattingModelMetrics = res.models } }
            }
            if hardwareSummary.isEmpty,
               let url = URL(string: engineURL + "/metrics/hardware"),
               let (data, _) = try? await EngineEndpoint.shared.session.data(from: url),
               let hw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var parts: [String] = []
                if let chip = hw["chip"] as? String, !chip.isEmpty { parts.append(chip) }
                if let mem = hw["memory_gb"] as? Int { parts.append("\(mem) GB RAM") }
                if let gpu = hw["gpu_accel"] as? String { parts.append(gpu) }
                if let os = hw["os"] as? String { parts.append(os) }
                let summary = parts.joined(separator: " · ")
                await MainActor.run { self.hardwareSummary = summary }
            }
        }
    }
    
    /// Reports the client-measured stop -> paste latency for a transcription back to the engine.
    func reportEndToEndLatency(metricsId: String?, since start: Date?, pasted: Bool) {
        guard let metricsId = metricsId, !metricsId.isEmpty, let start = start else { return }
        let ms = Date().timeIntervalSince(start) * 1000
        print(String(format: "⏱️ [CLIENT PASTE TIMING] Stop-to-%@: %.0f ms", pasted ? "Paste" : "Result", ms))
        Task {
            guard let url = URL(string: engineURL + "/metrics/\(metricsId)/latency") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["end_to_end_ms": ms, "pasted": pasted])
            EngineEndpoint.shared.authorize(&req)
            _ = try? await EngineEndpoint.shared.bareSession.data(for: req)
            self.fetchPerformanceMetrics(recentLimit: self.lastRecentLimit)
        }
    }
    
    func fetchStats() {
        Task {
            do {
                let url = URL(string: engineURL + "/stats?period=\(statsPeriod)")!
                let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DispatchQueue.main.async {
                        self.avgSpeakingWpm = json["avg_speaking_wpm"] as? Int ?? 0
                        self.avgEngineWpm = json["avg_engine_wpm"] as? Int ?? 0
                        self.totalWordsSpoken = json["total_words"] as? Int ?? 0
                        self.librarianUpdates = json["librarian_updates"] as? Int ?? 0
                    }
                }
            } catch {
                print("Error fetching stats: \(error)")
            }
        }
    }
    
    func fetchAuthStatus(force: Bool = false) {
        if !force, let lastCheck = lastAuthCheck, Date().timeIntervalSince(lastCheck) < 300 {
            // Skip auth check if checked within the last 5 minutes to prevent DB spam
            return
        }
        lastAuthCheck = Date()
        
        guard let token = SecretsManager.readSecret(forKey: "dicty_jwt_token"), !token.isEmpty else {
            DispatchQueue.main.async {
                self.isLoggedIn = false
                self.userEmail = nil
                self.isPro = false
                self.offlineMode = false
                if UserDefaults.standard.string(forKey: "llmProvider") == "dicty_cloud" {
                    UserDefaults.standard.set("openrouter", forKey: "llmProvider")
                }
            }
            return
        }
        
        guard let url = URL(string: "\(CloudConfig.baseURL)/auth/me") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        EngineEndpoint.shared.session.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                print("[!] Failed to fetch auth status (offline/network error): \(error)")
                // Load cached credentials for offline mode
                DispatchQueue.main.async {
                    let defaults = UserDefaults.standard
                    self.isLoggedIn = defaults.bool(forKey: "cachedIsLoggedIn")
                    self.userEmail = defaults.string(forKey: "cachedUserEmail")
                    let cachedUserId = defaults.integer(forKey: "cachedUserId")
                    self.userId = cachedUserId == 0 ? nil : cachedUserId
                    self.isPro = defaults.bool(forKey: "cachedIsPro")
                    self.offlineMode = true
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data {
                struct MeResponse: Codable {
                    let user: MeUser
                }
                struct MeUser: Codable {
                    let id: Int
                    let email: String
                    let isPro: Bool
                    let computeBalance: Int?
                    let subscriptionTier: String?
                    let planExpiresAt: String?
                }
                
                if let res = try? JSONDecoder().decode(MeResponse.self, from: data) {
                    DispatchQueue.main.async {
                        self.isLoggedIn = true
                        self.userId = res.user.id
                        self.userEmail = res.user.email
                        self.isPro = res.user.isPro
                        self.computeBalance = res.user.computeBalance ?? 0
                        self.subscriptionTier = res.user.subscriptionTier ?? "free"
                        self.planExpiresAt = res.user.planExpiresAt
                        self.offlineMode = false
                        
                        if !res.user.isPro && UserDefaults.standard.string(forKey: "llmProvider") == "dicty_cloud" {
                            UserDefaults.standard.set("openrouter", forKey: "llmProvider")
                        }
                        
                        // Cache for offline support
                        let defaults = UserDefaults.standard
                        defaults.set(true, forKey: "cachedIsLoggedIn")
                        defaults.set(res.user.id, forKey: "cachedUserId")
                        defaults.set(res.user.email, forKey: "cachedUserEmail")
                        defaults.set(res.user.isPro, forKey: "cachedIsPro")
                        if let expires = res.user.planExpiresAt {
                            defaults.set(expires, forKey: "cachedPlanExpiresAt")
                        }
                        
                        // Auto-sync settings and vocabulary for logged in users
                        Task {
                            await self.downloadSettingsFromCloud()
                        }
                    }
                }
            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                // Token is explicitly invalid or expired
                DispatchQueue.main.async {
                    SecretsManager.saveSecret("", forKey: "dicty_jwt_token")
                    self.isLoggedIn = false
                    self.userId = nil
                    self.userEmail = nil
                    self.isPro = false
                    self.planExpiresAt = nil
                    self.offlineMode = false
                    if UserDefaults.standard.string(forKey: "llmProvider") == "dicty_cloud" {
                        UserDefaults.standard.set("openrouter", forKey: "llmProvider")
                    }
                    
                    let defaults = UserDefaults.standard
                    defaults.removeObject(forKey: "cachedIsLoggedIn")
                    defaults.removeObject(forKey: "cachedUserId")
                    defaults.removeObject(forKey: "cachedUserEmail")
                    defaults.removeObject(forKey: "cachedIsPro")
                    defaults.removeObject(forKey: "cachedPlanExpiresAt")
                }
            } else {
                // Transient server error (500, 502, 503, etc.) or rate limit: preserve cached credentials
                print("[!] Server error during auth check (Status: \(String(describing: (response as? HTTPURLResponse)?.statusCode))). Preserving cached credentials.")
                DispatchQueue.main.async {
                    let defaults = UserDefaults.standard
                    self.isLoggedIn = defaults.bool(forKey: "cachedIsLoggedIn")
                    self.userEmail = defaults.string(forKey: "cachedUserEmail")
                    let cachedUserId = defaults.integer(forKey: "cachedUserId")
                    self.userId = cachedUserId == 0 ? nil : cachedUserId
                    self.isPro = defaults.bool(forKey: "cachedIsPro")
                    self.offlineMode = true
                }
            }
        }.resume()
    }
    
    func logoutAccount() {
        // Clear token from Keychain
        SecretsManager.saveSecret("", forKey: "dicty_jwt_token")
        
        // Clear cached credentials
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "cachedIsLoggedIn")
        defaults.removeObject(forKey: "cachedUserId")
        defaults.removeObject(forKey: "cachedUserEmail")
        defaults.removeObject(forKey: "cachedIsPro")
        defaults.removeObject(forKey: "cachedPlanExpiresAt")
        
        // Notify local python backend of logout
        if let url = URL(string: "\(engineURL)/auth/logout") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            EngineEndpoint.shared.session.dataTask(with: req).resume()
        }
        
        TelemetryClient.shared.track("user_logged_out")
        
        DispatchQueue.main.async {
            self.isLoggedIn = false
            self.userId = nil
            self.userEmail = nil
            self.isPro = false
            self.offlineMode = false
        }
    }
    
    func startOAuthLoopbackPolling() {
        stopOAuthLoopbackPolling()
        authLoopbackTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self, !self.isLoggedIn else { break }
                let url = EngineEndpoint.shared.url("/auth/pending_token")
                
                if let (data, _) = try? await EngineEndpoint.shared.session.data(from: url),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = json["token"] as? String,
                   !token.isEmpty {
                    self.stopOAuthLoopbackPolling()
                    self.handleOAuthToken(token)
                    break
                }
            }
        }
    }
    
    func stopOAuthLoopbackPolling() {
        authLoopbackTask?.cancel()
        authLoopbackTask = nil
    }
    
    func handleOAuthToken(_ token: String) {
        stopOAuthLoopbackPolling()
        SecretsManager.saveSecret(token, forKey: "dicty_jwt_token")
        lastAuthCheck = Date()
        
        guard let url = URL(string: "\(CloudConfig.baseURL)/auth/me") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        EngineEndpoint.shared.session.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                struct MeResponse: Codable {
                    let user: MeUser
                }
                struct MeUser: Codable {
                    let id: Int
                    let email: String
                    let isPro: Bool
                    let computeBalance: Int?
                    let subscriptionTier: String?
                    let planExpiresAt: String?
                }
                
                if let res = try? JSONDecoder().decode(MeResponse.self, from: data) {
                    DispatchQueue.main.async {
                        self.isLoggedIn = true
                        self.userId = res.user.id
                        self.userEmail = res.user.email
                        self.isPro = res.user.isPro
                        self.computeBalance = res.user.computeBalance ?? 0
                        self.subscriptionTier = res.user.subscriptionTier ?? "free"
                        self.planExpiresAt = res.user.planExpiresAt
                        self.offlineMode = false
                        
                        let defaults = UserDefaults.standard
                        defaults.set(true, forKey: "cachedIsLoggedIn")
                        defaults.set(res.user.id, forKey: "cachedUserId")
                        defaults.set(res.user.email, forKey: "cachedUserEmail")
                        defaults.set(res.user.isPro, forKey: "cachedIsPro")
                        if let expires = res.user.planExpiresAt {
                            defaults.set(expires, forKey: "cachedPlanExpiresAt")
                        }
                        
                        if res.user.isPro && !self.hasCustomAPIKey {
                            defaults.set("dicty_cloud", forKey: "llmProvider")
                        }
                        
                        // Auto-sync settings and vocabulary on login for logged in users
                        Task {
                            await self.downloadSettingsFromCloud()
                        }
                    }
                    
                    // Notify local backend engine of token
                    if let localTokenUrl = URL(string: "\(self.engineURL)/auth/token") {
                        var tReq = URLRequest(url: localTokenUrl)
                        tReq.httpMethod = "POST"
                        tReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        let tBody = ["token": token]
                        tReq.httpBody = try? JSONSerialization.data(withJSONObject: tBody)
                        EngineEndpoint.shared.session.dataTask(with: tReq).resume()
                    }
                    
                    TelemetryClient.shared.track("user_authenticated", properties: [
                        "is_pro": res.user.isPro
                    ])
                    // Trigger auto-download settings upon login
                    Task {
                        await self.downloadSettingsFromCloud()
                    }
                }
            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                SecretsManager.saveSecret("", forKey: "dicty_jwt_token")
            }
        }.resume()
    }
    
    // MARK: - Cloud Sync
    
    struct CloudSyncPayload: Codable {
        let customPrompts: [DictyPromptInfo]?
        let librarianConfig: LibrarianCloudConfig?
        let vocabulary: [DictyVocabulary]?
    }
    
    struct LibrarianCloudConfig: Codable {
        let targetSystem: String?
        let confluenceUrl: String?
        let confluenceSpace: String?
        let confluenceUser: String?
        let confluencePageTitle: String?
        let obsidianPath: String?
        let selectedGitHubRepo: String?
    }
    
    func uploadSettingsToCloud() async {
        guard let token = SecretsManager.readSecret(forKey: "dicty_jwt_token"), !token.isEmpty else { return }
        guard let url = URL(string: "\(CloudConfig.baseURL)/sync/settings") else { return }
        
        // Wait for latest prompts and vocabulary
        fetchPrompts()
        fetchVocabulary()
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        let defaults = UserDefaults.standard
        let libConfig = LibrarianCloudConfig(
            targetSystem: defaults.string(forKey: "targetSystem"),
            confluenceUrl: defaults.string(forKey: "confluenceUrl"),
            confluenceSpace: defaults.string(forKey: "confluenceSpace"),
            confluenceUser: defaults.string(forKey: "confluenceUser"),
            confluencePageTitle: defaults.string(forKey: "confluencePageTitle"),
            obsidianPath: defaults.string(forKey: "obsidianPath"),
            selectedGitHubRepo: defaults.string(forKey: "selectedGitHubRepo")
        )
        
        let payload = CloudSyncPayload(
            customPrompts: prompts,
            librarianConfig: libConfig,
            vocabulary: vocabulary
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8.0 // Resilient against offline / poor connections
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(payload)
        
        do {
            let (_, response) = try await EngineEndpoint.shared.session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("[*] Successfully uploaded settings & vocabulary to cloud.")
            }
        } catch {
            print("[-] Failed to upload settings (offline or unreachable): \(error.localizedDescription)")
        }
    }
    
    func downloadSettingsFromCloud() async {
        guard let token = SecretsManager.readSecret(forKey: "dicty_jwt_token"), !token.isEmpty else { return }
        guard let url = URL(string: "\(CloudConfig.baseURL)/sync/settings") else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0 // Resilient against offline / poor connections
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await EngineEndpoint.shared.session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                struct CloudSettingsResponse: Codable {
                    let customPrompts: [DictyPromptInfo]?
                    let librarianConfig: LibrarianCloudConfig?
                    let vocabulary: [DictyVocabulary]?
                }
                
                let res = try JSONDecoder().decode(CloudSettingsResponse.self, from: data)
                
                await MainActor.run {
                    let defaults = UserDefaults.standard
                    
                    // Restore Librarian config
                    if let lib = res.librarianConfig {
                        if let v = lib.targetSystem { defaults.set(v, forKey: "targetSystem") }
                        if let v = lib.confluenceUrl { defaults.set(v, forKey: "confluenceUrl") }
                        if let v = lib.confluenceSpace { defaults.set(v, forKey: "confluenceSpace") }
                        if let v = lib.confluenceUser { defaults.set(v, forKey: "confluenceUser") }
                        if let v = lib.confluencePageTitle { defaults.set(v, forKey: "confluencePageTitle") }
                        if let v = lib.obsidianPath { defaults.set(v, forKey: "obsidianPath") }
                        if let v = lib.selectedGitHubRepo { defaults.set(v, forKey: "selectedGitHubRepo") }
                    }
                    
                    // Restore Custom Prompts (pass autoSyncToCloud: false to avoid sync echoes)
                    if let cloudPrompts = res.customPrompts {
                        for p in cloudPrompts {
                            if p.is_custom {
                                updatePrompt(key: p.key, value: p.active_value, autoSyncToCloud: false)
                            }
                        }
                    }
                    
                    // Restore Vocabulary (pass autoSyncToCloud: false to avoid sync echoes)
                    if let cloudVocab = res.vocabulary {
                        let existingWords = Set(self.vocabulary.map { "\($0.word.lowercased())|\($0.replacement)" })
                        for v in cloudVocab {
                            let key = "\(v.word.lowercased())|\(v.replacement)"
                            if !existingWords.contains(key) {
                                addVocabulary(word: v.word, replacement: v.replacement, autoSyncToCloud: false)
                            }
                        }
                    }
                    
                    fetchPrompts()
                    fetchVocabulary()
                }
                print("[*] Successfully downloaded settings & vocabulary from cloud.")
            }
        } catch {
            print("[-] Cloud sync download skipped (offline or network error): \(error.localizedDescription)")
        }
    }
    
    /// Keychain keys for bring-your-own speech-to-text providers.
    static let sttProviderKeychainKeys: [(provider: String, keychainKey: String)] = [
        ("openai", "openaiApiKey"),
        ("deepgram", "deepgramApiKey"),
        ("groq", "groqApiKey"),
        ("elevenlabs", "elevenlabsApiKey"),
    ]
    
    /// Sends the user's own STT provider keys to the engine. Empty values clear a key.
    @discardableResult
    func pushSTTProviderKeys() async -> [String: Bool] {
        guard let url = URL(string: engineURL + "/settings/stt_keys") else { return [:] }
        var payload: [String: String] = [:]
        for entry in Self.sttProviderKeychainKeys {
            payload[entry.provider] = SecretsManager.readSecret(forKey: entry.keychainKey) ?? ""
        }
        // OpenRouter key (BYOK mode) is needed to transcribe phrases during recording
        payload["openrouter"] = SecretsManager.readSecret(forKey: "llmApiKey") ?? ""
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (data, _) = try? await EngineEndpoint.shared.session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let configured = json["configured"] as? [String: Bool] else { return [:] }
        return configured
    }
    
    func updateMemoryMode(retryCount: Int = 0) {
        Task {
            do {
                guard let url = URL(string: engineURL + "/settings/keep_model_loaded") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                let body = ["keep_loaded": keepModelInMemory]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let _ = try await EngineEndpoint.shared.session.data(for: request)
                // Engine is reachable: hand it the user's own speech-to-text keys (kept in engine memory only)
                await self.pushSTTProviderKeys()
            } catch {
                print("Failed to update memory mode (attempt \(retryCount + 1)): \(error)")
                if retryCount < 15 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    self.updateMemoryMode(retryCount: retryCount + 1)
                }
            }
        }
    }

    func updateAuthorName(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        authorName = clean
        UserDefaults.standard.set(clean, forKey: "authorName")
        Task {
            guard let url = URL(string: engineURL + "/settings/author_name") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["author_name": clean])
            _ = try? await EngineEndpoint.shared.session.data(for: req)
        }
    }
    
    func clearHistory() {
        Task {
            do {
                var request = URLRequest(url: URL(string: engineURL + "/history/clear")!)
                request.httpMethod = "DELETE"
                let (_, response) = try await EngineEndpoint.shared.session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    DispatchQueue.main.async {
                        self.history = []
                        self.fetchStats()
                    }
                }
            } catch {
                print("Error clearing history: \(error)")
            }
        }
    }

    func updateHistoryTags(recordId: String, tags: [String]) async {
        do {
            guard let url = URL(string: engineURL + "/history/\(recordId)/tags") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = ["tags": tags]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await EngineEndpoint.shared.session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                await MainActor.run {
                    if let idx = self.history.firstIndex(where: { $0.id == recordId }) {
                        self.history[idx].tags = tags
                    }
                }
            }
        } catch {
            print("Error updating history tags: \(error)")
        }
    }

    private var pauseModifierWasPressed = false
    private var targetModifierWasPressed = false
    private var switchModifierWasPressed = false
    private var ttsModifierWasPressed = false
    private var lastPauseToggleTime: Date = Date.distantPast
    private var modifierKeyDownTimes: [UInt16: TimeInterval] = [:]
    private var lastModifierTapTimes: [UInt16: TimeInterval] = [:]
    private var lastKeyTapTimes: [UInt16: TimeInterval] = [:]
    private var lastDoubleTapTriggerTime: TimeInterval = 0
    
    nonisolated static func isModifierKeyCode(_ code: UInt16) -> Bool {
        return (code >= 54 && code <= 63)
    }

    nonisolated static func isModifierDown(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case 63: // Fn / Globe
            return flags.contains(.function)
        case 55, 54: // Left / Right Command
            return flags.contains(.command)
        case 58, 61: // Left / Right Option
            return flags.contains(.option)
        case 59, 62: // Left / Right Control
            return flags.contains(.control)
        case 56, 60: // Left / Right Shift
            return flags.contains(.shift)
        case 57: // Caps Lock
            return flags.contains(.capsLock)
        default:
            return false
        }
    }

    @MainActor
    private func handleFlagsChanged(
        keyCode: UInt16,
        eventMods: NSEvent.ModifierFlags,
        pauseKey: UInt16,
        pauseModifiers: NSEvent.ModifierFlags,
        isPauseModifier: Bool,
        targetKey: UInt16,
        targetModifiers: NSEvent.ModifierFlags,
        isTargetModifier: Bool,
        switchKey: UInt16,
        switchModifiers: NSEvent.ModifierFlags,
        isSwitchModifier: Bool,
        ttsKey: UInt16,
        ttsModifiers: NSEvent.ModifierFlags,
        isTtsModifier: Bool
    ) {
        let standardModifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let cleanMods = eventMods.intersection(standardModifierMask)
        
        // 1. Check for Double-Tap Modifier Shortcut
        let now = ProcessInfo.processInfo.systemUptime
        let isDown = Self.isModifierDown(keyCode: keyCode, flags: eventMods)
        
        if isDown {
            if now - lastDoubleTapTriggerTime < 0.45 {
                return
            }
            modifierKeyDownTimes[keyCode] = now
            if let lastTap = lastModifierTapTimes[keyCode] {
                let elapsed = now - lastTap
                if elapsed < 0.38 {
                    if recordRequireDoubleTap && isTargetModifier && keyCode == targetKey {
                        lastDoubleTapTriggerTime = now
                        lastModifierTapTimes.removeAll()
                        modifierKeyDownTimes.removeAll()
                        toggleRecording()
                        return
                    } else if pauseRequireDoubleTap && isPauseModifier && keyCode == pauseKey {
                        lastDoubleTapTriggerTime = now
                        lastModifierTapTimes.removeAll()
                        modifierKeyDownTimes.removeAll()
                        if isRecording {
                            togglePauseRecording()
                        }
                        return
                    } else if switchModeRequireDoubleTap && isSwitchModifier && keyCode == switchKey {
                        lastDoubleTapTriggerTime = now
                        lastModifierTapTimes.removeAll()
                        modifierKeyDownTimes.removeAll()
                        ModeSwitcherHUDManager.shared.toggle(engineClient: self)
                        return
                    } else if ttsRequireDoubleTap && isTtsModifier && keyCode == ttsKey {
                        lastDoubleTapTriggerTime = now
                        lastModifierTapTimes.removeAll()
                        modifierKeyDownTimes.removeAll()
                        TTSManager.shared.speakSelection()
                        return
                    }
                }
            }
        } else {
            if let downTime = modifierKeyDownTimes[keyCode] {
                let holdDuration = now - downTime
                if holdDuration < 0.35 {
                    lastModifierTapTimes[keyCode] = now
                } else {
                    lastModifierTapTimes[keyCode] = nil
                }
                modifierKeyDownTimes[keyCode] = nil
            }
        }
        
        // 2. Standard single-press modifier handling (only if double-tap is NOT required)
        if isPauseModifier && keyCode == pauseKey && !pauseRequireDoubleTap {
            let isPressed = isDown && (pauseModifiers.isEmpty || cleanMods.contains(pauseModifiers))
            if pauseHotkeyBehavior == "hold" {
                if isPressed {
                    if isRecording && !isPaused {
                        isHoldingToPause = true
                        pauseRecording()
                    }
                } else {
                    if isHoldingToPause {
                        isHoldingToPause = false
                        if isRecording && isPaused {
                            resumeRecording()
                        }
                    }
                }
            } else {
                if isPressed && !pauseModifierWasPressed {
                    pauseModifierWasPressed = true
                    if isRecording {
                        togglePauseRecording()
                    }
                } else if !isPressed {
                    pauseModifierWasPressed = false
                }
            }
        }
        
        // Push-to-pause release detection when user releases the modifier of a combination hotkey
        if isHoldingToPause && !isPauseModifier && !pauseModifiers.isEmpty {
            let isModifierStillHeld = cleanMods.contains(pauseModifiers)
            if !isModifierStillHeld {
                isHoldingToPause = false
                if isRecording && isPaused {
                    resumeRecording()
                }
            }
        }
        
        // Push-to-talk release detection when user releases the modifier key (e.g. Option in ⌥Space)
        if isHoldingToRecord && !isTargetModifier && !targetModifiers.isEmpty {
            let isModifierStillHeld = cleanMods.contains(targetModifiers)
            if !isModifierStillHeld {
                stopRecording()
            }
        }
        
        if isTargetModifier && keyCode == targetKey && !recordRequireDoubleTap {
            let isPressed = isDown && (targetModifiers.isEmpty || cleanMods.contains(targetModifiers))
            if hotkeyBehavior == "toggle" {
                if isPressed && !targetModifierWasPressed {
                    targetModifierWasPressed = true
                    toggleRecording()
                } else if !isPressed {
                    targetModifierWasPressed = false
                }
            } else {
                // "hold" mode for modifier-only hotkey (e.g. Right Option by itself)
                if isPressed {
                    if !isRecording {
                        startRecording(isHoldTrigger: true)
                    }
                } else {
                    if isHoldingToRecord || isRecording {
                        stopRecording()
                    }
                }
            }
        }
        
        if isSwitchModifier && keyCode == switchKey && !switchModeRequireDoubleTap {
            let isPressed = isDown && (switchModifiers.isEmpty || cleanMods.contains(switchModifiers))
            if switchModeHotkeyBehavior == "hold" {
                if isPressed {
                    if !isHoldingToSwitchMode {
                        isHoldingToSwitchMode = true
                        ModeSwitcherHUDManager.shared.show(engineClient: self)
                    }
                } else {
                    if isHoldingToSwitchMode {
                        isHoldingToSwitchMode = false
                        ModeSwitcherHUDManager.shared.selectAndClose(engineClient: self)
                    }
                }
            } else {
                if isPressed && !switchModifierWasPressed {
                    switchModifierWasPressed = true
                    ModeSwitcherHUDManager.shared.toggle(engineClient: self)
                } else if !isPressed {
                    switchModifierWasPressed = false
                }
            }
        }
        
        if isHoldingToSwitchMode && !isSwitchModifier && !switchModifiers.isEmpty {
            let isModifierStillHeld = cleanMods.contains(switchModifiers)
            if !isModifierStillHeld {
                isHoldingToSwitchMode = false
                ModeSwitcherHUDManager.shared.selectAndClose(engineClient: self)
            }
        }
        
        if isTtsModifier && keyCode == ttsKey && !ttsRequireDoubleTap {
            let isPressed = isDown && (ttsModifiers.isEmpty || cleanMods.contains(ttsModifiers))
            if ttsHotkeyBehavior == "hold" {
                if isPressed {
                    if !isHoldingToTts {
                        isHoldingToTts = true
                        TTSManager.shared.speakSelection()
                    }
                } else {
                    if isHoldingToTts {
                        isHoldingToTts = false
                        TTSManager.shared.stop()
                    }
                }
            } else {
                if isPressed && !ttsModifierWasPressed {
                    ttsModifierWasPressed = true
                    TTSManager.shared.speakSelection()
                } else if !isPressed {
                    ttsModifierWasPressed = false
                }
            }
        }
        
        if isHoldingToTts && !isTtsModifier && !ttsModifiers.isEmpty {
            let isModifierStillHeld = cleanMods.contains(ttsModifiers)
            if !isModifierStillHeld {
                isHoldingToTts = false
                TTSManager.shared.stop()
            }
        }
    }

    @MainActor
    private func handleKeyEvent(
        keyCode: UInt16,
        eventType: NSEvent.EventType,
        isARepeat: Bool,
        eventMods: NSEvent.ModifierFlags,
        isLocal: Bool = false,
        targetKey: UInt16,
        targetModifiers: NSEvent.ModifierFlags,
        pauseKey: UInt16,
        pauseModifiers: NSEvent.ModifierFlags,
        switchKey: UInt16,
        switchModifiers: NSEvent.ModifierFlags,
        ttsKey: UInt16 = 1,
        ttsModifiers: NSEvent.ModifierFlags = [.option, .shift]
    ) {
        if eventType == .keyDown && !isARepeat {
            // Any regular keystroke cancels pending double-tap modifiers
            lastModifierTapTimes.removeAll()
            modifierKeyDownTimes.removeAll()
        }

        // Check for Escape key: only allowed when Dicty is the active application (isLocal).
        // A bare Escape from other apps (global monitor) must NEVER cancel recordings!
        // In long meetings or normal dictation, users frequently press Esc in other apps
        // (Vim, IDE, search bars, modals) — doing so must never discard their audio.
        if keyCode == 53 && eventMods.isEmpty {
            if eventType == .keyDown && !isARepeat {
                if isLocal {
                    if TTSManager.shared.isSpeaking || TTSManager.shared.isGenerating {
                        TTSManager.shared.stop()
                        return
                    }
                    // Never cancel meeting mode on bare Escape: meetings are long-running and precious.
                    // For short dictation, allow Escape only when Dicty is the active window.
                    if (isRecording || isProcessing) && !DictyAudioRecorder.isSystemAudioMode(activeMode) {
                        cancelRecording()
                    }
                }
            }
            return
        }

        // Check for TTS Speak Selection Hotkey
        if keyCode == ttsKey {
            let matchesTtsMods = (eventMods == ttsModifiers)
            if ttsRequireDoubleTap {
                if eventType == .keyDown && !isARepeat && matchesTtsMods {
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - lastDoubleTapTriggerTime < 0.45 { return }
                    if let lastTap = lastKeyTapTimes[keyCode], (now - lastTap) < 0.38 {
                        lastDoubleTapTriggerTime = now
                        lastKeyTapTimes.removeAll()
                        TTSManager.shared.speakSelection()
                    } else {
                        lastKeyTapTimes[keyCode] = now
                    }
                }
                return
            }
            if ttsHotkeyBehavior == "hold" {
                if eventType == .keyDown && !isARepeat && matchesTtsMods {
                    isHoldingToTts = true
                    TTSManager.shared.speakSelection()
                } else if eventType == .keyUp {
                    if isHoldingToTts {
                        isHoldingToTts = false
                        TTSManager.shared.stop()
                    }
                }
            } else {
                if eventType == .keyDown && !isARepeat && matchesTtsMods {
                    TTSManager.shared.speakSelection()
                }
            }
            if matchesTtsMods { return }
        }
        
        // Check for Switch Mode Hotkey
        if keyCode == switchKey {
            let matchesSwitchMods = (eventMods == switchModifiers)
            if switchModeRequireDoubleTap {
                if eventType == .keyDown && !isARepeat && matchesSwitchMods {
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - lastDoubleTapTriggerTime < 0.45 { return }
                    if let lastTap = lastKeyTapTimes[keyCode], (now - lastTap) < 0.38 {
                        lastDoubleTapTriggerTime = now
                        lastKeyTapTimes.removeAll()
                        ModeSwitcherHUDManager.shared.toggle(engineClient: self)
                    } else {
                        lastKeyTapTimes[keyCode] = now
                    }
                }
                return
            }
            if switchModeHotkeyBehavior == "hold" {
                if eventType == .keyDown && !isARepeat && matchesSwitchMods {
                    isHoldingToSwitchMode = true
                    ModeSwitcherHUDManager.shared.show(engineClient: self)
                } else if eventType == .keyUp {
                    if isHoldingToSwitchMode {
                        isHoldingToSwitchMode = false
                        ModeSwitcherHUDManager.shared.selectAndClose(engineClient: self)
                    }
                }
            } else {
                if eventType == .keyDown && !isARepeat && matchesSwitchMods {
                    ModeSwitcherHUDManager.shared.toggle(engineClient: self)
                }
            }
            if matchesSwitchMods { return }
        }
        
        // Check for Pause / Resume Hotkey while recording
        if isRecording && keyCode == pauseKey {
            let matchesPauseMods = (eventMods == pauseModifiers)
            if pauseRequireDoubleTap {
                if eventType == .keyDown && !isARepeat && matchesPauseMods {
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - lastDoubleTapTriggerTime < 0.45 { return }
                    if let lastTap = lastKeyTapTimes[keyCode], (now - lastTap) < 0.38 {
                        lastDoubleTapTriggerTime = now
                        lastKeyTapTimes.removeAll()
                        togglePauseRecording()
                    } else {
                        lastKeyTapTimes[keyCode] = now
                    }
                }
                return
            }
            if pauseHotkeyBehavior == "hold" {
                if eventType == .keyDown && !isARepeat && matchesPauseMods {
                    if !isPaused {
                        isHoldingToPause = true
                        pauseRecording()
                    }
                } else if eventType == .keyUp {
                    if isHoldingToPause {
                        isHoldingToPause = false
                        if isPaused {
                            resumeRecording()
                        }
                    }
                }
            } else {
                if eventType == .keyDown && !isARepeat && matchesPauseMods {
                    togglePauseRecording()
                }
            }
            if matchesPauseMods { return }
        }
        
        // Check for Record Hotkey (Start / Stop)
        let isRecordKey = (keyCode == targetKey)
        let matchesModifiers = (eventMods == targetModifiers)
        
        if isRecordKey {
            if recordRequireDoubleTap {
                if eventType == .keyDown && !isARepeat && matchesModifiers {
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - lastDoubleTapTriggerTime < 0.45 { return }
                    if let lastTap = lastKeyTapTimes[keyCode], (now - lastTap) < 0.38 {
                        lastDoubleTapTriggerTime = now
                        lastKeyTapTimes.removeAll()
                        toggleRecording()
                    } else {
                        lastKeyTapTimes[keyCode] = now
                    }
                }
                return
            }
            
            if hotkeyBehavior == "hold" {
                if eventType == .keyDown && !isARepeat && matchesModifiers {
                    if !isRecording {
                        startRecording(isHoldTrigger: true)
                    }
                } else if eventType == .keyUp {
                    if isHoldingToRecord || isRecording {
                        stopRecording()
                    }
                }
            } else {
                // "toggle" mode
                if eventType == .keyDown && !isARepeat && matchesModifiers {
                    toggleRecording()
                }
            }
            return
        }
        
        // Reset key taps if another key was pressed
        if eventType == .keyDown && !isARepeat {
            lastKeyTapTimes.removeAll()
        }
    }

    func setupGlobalMonitor() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = flagsMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localFlagsMonitor { NSEvent.removeMonitor(monitor) }
        
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        let standardModifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        
        let targetModifiers = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers)).intersection(standardModifierMask)
        let targetKey = UInt16(hotkeyKeyCode)
        let isTargetModifier = Self.isModifierKeyCode(targetKey)
        
        let pauseModifiers = NSEvent.ModifierFlags(rawValue: UInt(pauseHotkeyModifiers)).intersection(standardModifierMask)
        let pauseKey = UInt16(pauseHotkeyKeyCode)
        let isPauseModifier = Self.isModifierKeyCode(pauseKey)
        
        let switchModifiers = NSEvent.ModifierFlags(rawValue: UInt(switchModeHotkeyModifiers)).intersection(standardModifierMask)
        let switchKey = UInt16(switchModeHotkeyKeyCode)
        let isSwitchModifier = Self.isModifierKeyCode(switchKey)
        
        let ttsModifiers = NSEvent.ModifierFlags(rawValue: UInt(ttsHotkeyModifiers)).intersection(standardModifierMask)
        let ttsKey = UInt16(ttsHotkeyKeyCode)
        let isTtsModifier = Self.isModifierKeyCode(ttsKey)
        
        // Listen for standard key combinations
        globalMonitor = EventMonitorRegistrar.registerGlobal(matching: [.keyDown, .keyUp]) { [weak self] event in
            let keyCode = event.keyCode
            let eventType = event.type
            let isARepeat = event.isARepeat
            let eventMods = event.modifierFlags.intersection(standardModifierMask)
            Task { @MainActor [weak self] in
                self?.handleKeyEvent(
                    keyCode: keyCode,
                    eventType: eventType,
                    isARepeat: isARepeat,
                    eventMods: eventMods,
                    isLocal: false,
                    targetKey: targetKey,
                    targetModifiers: targetModifiers,
                    pauseKey: pauseKey,
                    pauseModifiers: pauseModifiers,
                    switchKey: switchKey,
                    switchModifiers: switchModifiers,
                    ttsKey: ttsKey,
                    ttsModifiers: ttsModifiers
                )
            }
        }
        
        // Listen for modifier-only hotkeys (e.g., Right Option by itself)
        flagsMonitor = EventMonitorRegistrar.registerGlobal(matching: .flagsChanged) { [weak self] event in
            let keyCode = event.keyCode
            let eventMods = event.modifierFlags
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(
                    keyCode: keyCode,
                    eventMods: eventMods,
                    pauseKey: pauseKey,
                    pauseModifiers: pauseModifiers,
                    isPauseModifier: isPauseModifier,
                    targetKey: targetKey,
                    targetModifiers: targetModifiers,
                    isTargetModifier: isTargetModifier,
                    switchKey: switchKey,
                    switchModifiers: switchModifiers,
                    isSwitchModifier: isSwitchModifier,
                    ttsKey: ttsKey,
                    ttsModifiers: ttsModifiers,
                    isTtsModifier: isTtsModifier
                )
            }
        }
        
        // --- Local Monitors for when Dicty is the active application ---
        
        localMonitor = EventMonitorRegistrar.registerLocal(matching: [.keyDown, .keyUp]) { [weak self] event in
            let keyCode = event.keyCode
            let eventType = event.type
            let isARepeat = event.isARepeat
            let eventMods = event.modifierFlags.intersection(standardModifierMask)
            Task { @MainActor [weak self] in
                self?.handleKeyEvent(
                    keyCode: keyCode,
                    eventType: eventType,
                    isARepeat: isARepeat,
                    eventMods: eventMods,
                    isLocal: true,
                    targetKey: targetKey,
                    targetModifiers: targetModifiers,
                    pauseKey: pauseKey,
                    pauseModifiers: pauseModifiers,
                    switchKey: switchKey,
                    switchModifiers: switchModifiers,
                    ttsKey: ttsKey,
                    ttsModifiers: ttsModifiers
                )
            }
            return event
        }
        
        localFlagsMonitor = EventMonitorRegistrar.registerLocal(matching: .flagsChanged) { [weak self] event in
            let keyCode = event.keyCode
            let eventMods = event.modifierFlags
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(
                    keyCode: keyCode,
                    eventMods: eventMods,
                    pauseKey: pauseKey,
                    pauseModifiers: pauseModifiers,
                    isPauseModifier: isPauseModifier,
                    targetKey: targetKey,
                    targetModifiers: targetModifiers,
                    isTargetModifier: isTargetModifier,
                    switchKey: switchKey,
                    switchModifiers: switchModifiers,
                    isSwitchModifier: isSwitchModifier,
                    ttsKey: ttsKey,
                    ttsModifiers: ttsModifiers,
                    isTtsModifier: isTtsModifier
                )
            }
            return event
        }
    }
    
    func cycleToNextProfile() {
        let profiles = ProfileManager.shared.profiles
        guard profiles.count > 1 else { return }
        if let currentIdx = profiles.firstIndex(where: { $0.id == ProfileManager.shared.activeProfileId }) {
            let nextIdx = (currentIdx + 1) % profiles.count
            self.manualOverrideActive = true
            ProfileManager.shared.switchProfile(to: profiles[nextIdx].id, engine: self)
        }
    }
    
    func fetchDevices() {
        Task {
            do {
                // Add timestamp to prevent URLSession from aggressively caching the GET request
                let timestamp = Date().timeIntervalSince1970
                let urlString = engineURL + "/devices?t=\(timestamp)"
                let (data, _) = try await EngineEndpoint.shared.session.data(from: URL(string: urlString)!)
                if let decoded = try? JSONDecoder().decode(DeviceResponse.self, from: data) {
                    DispatchQueue.main.async {
                        self.devices = decoded.devices
                    }
                }
            } catch {
                print("Fetch devices error: \(error)")
            }
        }
    }
    
    func fetchHistory() {
        Task {
            do {
                let url = URL(string: engineURL + "/history")!
                let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                // Unchanged since last fetch (the common case when just switching tabs): skip decoding and
                // republishing, which would re-render every view observing EngineClient.
                if data.hashValue == self.lastHistoryPayloadHash { return }
                let resp = try await Task.detached(priority: .userInitiated) {
                    try JSONDecoder().decode(HistoryResponse.self, from: data)
                }.value
                await MainActor.run {
                    self.lastHistoryPayloadHash = data.hashValue
                    self.history = resp.history
                }
            } catch {
                print("Error fetching history: \(error)")
            }
        }
    }
    
    // MARK: - App Rules API
    
    func fetchAppRules() {
        Task {
            do {
                guard let url = URL(string: engineURL + "/app-rules") else { return }
                let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                let resp = try JSONDecoder().decode(AppRulesResponse.self, from: data)
                await MainActor.run {
                    if self.appRules != resp.rules {
                        self.appRules = resp.rules
                    }
                    if self.appRulesSettings != resp.settings {
                        self.appRulesSettings = resp.settings
                    }
                }
            } catch {
                print("fetchAppRules error: \(error)")
            }
        }
    }
    
    func updateAppRulesSettings(enabled: Bool? = nil, overrideScope: String? = nil) {
        Task {
            do {
                guard let url = URL(string: engineURL + "/app-rules/settings") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                var payload: [String: Any] = [:]
                if let enabled = enabled { payload["enabled"] = enabled }
                if let overrideScope = overrideScope { payload["override_scope"] = overrideScope }
                req.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (data, _) = try await EngineEndpoint.shared.session.data(for: req)
                if let resp = try? JSONDecoder().decode(AppRulesResponse.self, from: data) {
                    await MainActor.run {
                        if self.appRulesSettings != resp.settings {
                            self.appRulesSettings = resp.settings
                        }
                        if self.appRules != resp.rules {
                            self.appRules = resp.rules
                        }
                    }
                } else {
                    struct SettingsOnlyResp: Codable { var settings: AppRulesSettings }
                    let resp = try JSONDecoder().decode(SettingsOnlyResp.self, from: data)
                    await MainActor.run {
                        if self.appRulesSettings != resp.settings {
                            self.appRulesSettings = resp.settings
                        }
                    }
                }
            } catch {
                print("updateAppRulesSettings error: \(error)")
            }
        }
    }
    
    func createAppRule(matchType: String, matchValue: String, modeId: String, displayName: String? = nil) {
        Task {
            do {
                guard let url = URL(string: engineURL + "/app-rules") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                var payload: [String: Any] = [
                    "match": [
                        "type": matchType,
                        "value": matchValue
                    ],
                    "mode_id": modeId,
                    "enabled": true
                ]
                if let displayName = displayName, !displayName.isEmpty {
                    payload["display_name"] = displayName
                }
                req.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (data, response) = try await EngineEndpoint.shared.session.data(for: req)
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                    let errStr = String(data: data, encoding: .utf8) ?? ""
                    print("createAppRule HTTP \(httpResp.statusCode): \(errStr)")
                    return
                }
                let rule: AppRule
                if let direct = try? JSONDecoder().decode(AppRule.self, from: data) {
                    rule = direct
                } else {
                    struct CreateRuleResp: Codable { var rule: AppRule }
                    rule = try JSONDecoder().decode(CreateRuleResp.self, from: data).rule
                }
                await MainActor.run {
                    if let idx = self.appRules.firstIndex(where: { $0.id == rule.id }) {
                        self.appRules[idx] = rule
                    } else {
                        self.appRules.append(rule)
                    }
                }
                self.fetchAppRules()
            } catch {
                print("createAppRule error: \(error)")
            }
        }
    }
    
    func updateAppRule(id: String, modeId: String? = nil, enabled: Bool? = nil, displayName: String? = nil) {
        Task {
            do {
                guard let url = URL(string: engineURL + "/app-rules/\(id)") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "PATCH"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                var payload: [String: Any] = [:]
                if let modeId = modeId { payload["mode_id"] = modeId }
                if let enabled = enabled { payload["enabled"] = enabled }
                if let displayName = displayName { payload["display_name"] = displayName }
                req.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (data, response) = try await EngineEndpoint.shared.session.data(for: req)
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                    let errStr = String(data: data, encoding: .utf8) ?? ""
                    print("updateAppRule HTTP \(httpResp.statusCode): \(errStr)")
                    return
                }
                let rule: AppRule
                if let direct = try? JSONDecoder().decode(AppRule.self, from: data) {
                    rule = direct
                } else {
                    struct UpdateRuleResp: Codable { var rule: AppRule }
                    rule = try JSONDecoder().decode(UpdateRuleResp.self, from: data).rule
                }
                await MainActor.run {
                    if let idx = self.appRules.firstIndex(where: { $0.id == rule.id }) {
                        self.appRules[idx] = rule
                    }
                }
                self.fetchAppRules()
            } catch {
                print("updateAppRule error: \(error)")
            }
        }
    }
    
    func deleteAppRule(id: String) {
        Task {
            do {
                guard let url = URL(string: engineURL + "/app-rules/\(id)") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "DELETE"
                _ = try await EngineEndpoint.shared.session.data(for: req)
                await MainActor.run {
                    self.appRules.removeAll(where: { $0.id == id })
                }
                self.fetchAppRules()
            } catch {
                print("deleteAppRule error: \(error)")
            }
        }
    }
    
    func resetAppRules() {
        Task {
            do {
                guard let url = URL(string: engineURL + "/app-rules/reset") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                let (data, _) = try await EngineEndpoint.shared.session.data(for: req)
                if let resp = try? JSONDecoder().decode(AppRulesResponse.self, from: data) {
                    await MainActor.run {
                        if self.appRules != resp.rules {
                            self.appRules = resp.rules
                        }
                        if self.appRulesSettings != resp.settings {
                            self.appRulesSettings = resp.settings
                        }
                    }
                }
                self.fetchAppRules()
            } catch {
                print("resetAppRules error: \(error)")
            }
        }
    }
    
    // MARK: - App Rule Suggestions (Phase 3 Learning)
    
    public func presentAppRuleSuggestion(_ suggestion: AppRuleSuggestion) {
        if self.pendingAppRuleSuggestion != suggestion {
            self.pendingAppRuleSuggestion = suggestion
        }
        AppRuleSuggestionBannerWindow.shared.show(suggestion: suggestion, engineClient: self)
    }
    
    public func dismissAppRuleSuggestion() {
        self.pendingAppRuleSuggestion = nil
        AppRuleSuggestionBannerWindow.shared.hide()
    }
    
    public func acceptAppRuleSuggestion(_ suggestion: AppRuleSuggestion) {
        dismissAppRuleSuggestion()
        Task {
            do {
                guard let url = URL(string: engineURL + "/app-rules/accept-suggestion") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload: [String: Any] = [
                    "app_id": suggestion.app_id,
                    "mode_id": suggestion.mode_id,
                    "display_name": suggestion.app_name
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: payload)
                _ = try await EngineEndpoint.shared.session.data(for: req)
                self.fetchAppRules()
            } catch {
                print("acceptAppRuleSuggestion error: \(error)")
            }
        }
    }
    
    public func suppressAppRuleSuggestion(appId: String, displayName: String) {
        dismissAppRuleSuggestion()
        Task {
            do {
                guard let url = URL(string: engineURL + "/app-rules/suppress-suggestion") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload: [String: Any] = [
                    "app_id": appId,
                    "display_name": displayName
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: payload)
                _ = try await EngineEndpoint.shared.session.data(for: req)
                self.fetchAppRules()
            } catch {
                print("suppressAppRuleSuggestion error: \(error)")
            }
        }
    }
    
    var effectiveResolvedModeDisplay: String {
        let raw = !currentResolvedMode.isEmpty ? currentResolvedMode : (activeMode == "dictation" ? (dictationFormatStyle == "raw" ? "dictation" : dictationFormatStyle) : activeMode)
        switch raw {
        case "dictation": return "General Dictation"
        case "message": return "Message"
        case "email": return "Email"
        case "code": return "Code"
        case "note": return "Note"
        case "book": return "Book / Prose"
        case "issue": return "Issue"
        case "librarian": return "Librarian"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    func resolveCurrentAppRule() {
        guard let appId = self.targetApp?.bundleIdentifier else {
            let def = self.activeMode == "dictation" ? (self.dictationFormatStyle == "raw" ? "dictation" : self.dictationFormatStyle) : self.activeMode
            if self.currentResolvedMode != def { self.currentResolvedMode = def }
            if self.currentResolvedReason != "default" { self.currentResolvedReason = "default" }
            return
        }
        Task {
            do {
                let encodedAppId = appId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? appId
                let manualParam = self.manualOverrideActive ? "true" : "false"
                var urlStr = "\(self.engineURL)/app-rules/resolve?app_id=\(encodedAppId)&manual_override_active=\(manualParam)"
                if let override = self.recordingOverrideMode {
                    let encodedOverride = override.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? override
                    urlStr += "&mode_override=\(encodedOverride)"
                }
                guard let url = URL(string: urlStr) else { return }
                let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                let resp = try JSONDecoder().decode(AppRuleResolveResponse.self, from: data)
                await MainActor.run {
                    if self.currentResolvedMode != resp.resolved_mode {
                        self.currentResolvedMode = resp.resolved_mode
                    }
                    if self.currentResolvedReason != resp.reason {
                        self.currentResolvedReason = resp.reason
                    }
                }
            } catch {
                print("resolveCurrentAppRule error: \(error)")
            }
        }
    }
    
    func fetchVocabulary() {
        Task {
            do {
                let timestamp = Date().timeIntervalSince1970
                let urlString = engineURL + "/vocabulary?t=\(timestamp)"
                let (data, _) = try await EngineEndpoint.shared.session.data(from: URL(string: urlString)!)
                if let decoded = try? JSONDecoder().decode(VocabularyResponse.self, from: data) {
                    DispatchQueue.main.async {
                        self.vocabulary = decoded.vocabulary
                    }
                }
            } catch {
                print("Failed to fetch vocabulary: \(error)")
            }
        }
    }
    
    func addVocabulary(word: String, replacement: String, autoSyncToCloud: Bool = true) {
        Task {
            do {
                var request = URLRequest(url: URL(string: engineURL + "/vocabulary")!)
                request.httpMethod = "POST"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                let body = ["word": word, "replacement": replacement]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
                let (_, response) = try await EngineEndpoint.shared.session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    fetchVocabulary()
                    // Auto-sync vocabulary to cloud in background if logged in
                    if autoSyncToCloud && isLoggedIn {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        await uploadSettingsToCloud()
                    }
                }
            } catch {
                print("Failed to add vocabulary: \(error)")
            }
        }
    }
    
    func deleteVocabulary(id: String, autoSyncToCloud: Bool = true) {
        Task {
            do {
                var request = URLRequest(url: URL(string: engineURL + "/vocabulary/\(id)")!)
                request.httpMethod = "DELETE"
                let (_, response) = try await EngineEndpoint.shared.session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    fetchVocabulary()
                    // Auto-sync vocabulary to cloud in background if logged in
                    if autoSyncToCloud && isLoggedIn {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        await uploadSettingsToCloud()
                    }
                }
            } catch {
                print("Failed to delete vocabulary: \(error)")
            }
        }
    }

    // MARK: - Voice snippets (local only: content may be personal, never synced to cloud)

    func fetchSnippets() {
        Task {
            guard let url = URL(string: engineURL + "/snippets?t=\(Date().timeIntervalSince1970)"),
                  let (data, _) = try? await EngineEndpoint.shared.session.data(from: url),
                  let decoded = try? JSONDecoder().decode(SnippetsResponse.self, from: data) else { return }
            await MainActor.run { if self.snippets != decoded.snippets { self.snippets = decoded.snippets } }
        }
    }

    /// Creates (id == nil) or updates a snippet. Returns an error message for the UI, or nil on success.
    func saveSnippet(id: String?, trigger: String, content: String, expandAnywhere: Bool) async -> String? {
        let path = id.map { "/snippets/\($0)" } ?? "/snippets"
        guard let url = URL(string: engineURL + path) else { return "Invalid engine URL" }
        var request = URLRequest(url: url)
        request.httpMethod = id == nil ? "POST" : "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["trigger": trigger, "content": content, "expand_anywhere": expandAnywhere]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await EngineEndpoint.shared.session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                fetchSnippets()
                return nil
            }
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            return detail ?? "Could not save snippet (HTTP \(status))"
        } catch {
            return "Engine not reachable: \(error.localizedDescription)"
        }
    }

    func deleteSnippet(id: String) {
        Task {
            guard let url = URL(string: engineURL + "/snippets/\(id)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            _ = try? await EngineEndpoint.shared.session.data(for: request)
            fetchSnippets()
        }
    }
    func fetchPrompts() {
        Task {
            do {
                let url = EngineEndpoint.shared.url("/prompts")
                let (data, response) = try await EngineEndpoint.shared.session.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let decoded = try JSONDecoder().decode([DictyPromptInfo].self, from: data)
                    DispatchQueue.main.async { self.prompts = decoded }
                }
            } catch {
                print("Failed to fetch prompts: \(error)")
            }
        }
    }
    
    func updatePrompt(key: String, value: String, autoSyncToCloud: Bool = true) {
        Task {
            do {
                let url = EngineEndpoint.shared.url("/prompts")
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                let body = ["key": key, "value": value]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
                let (_, response) = try await EngineEndpoint.shared.session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    fetchPrompts()
                    // Auto-sync prompts to cloud in the background if logged in
                    if autoSyncToCloud && isLoggedIn {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        await uploadSettingsToCloud()
                    }
                }
            } catch {
                print("Failed to update prompt: \(error)")
            }
        }
    }
    
    func resetPrompt(key: String, autoSyncToCloud: Bool = true) {
        Task {
            do {
                let url = EngineEndpoint.shared.url("/prompts/\(key)")
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                let (_, response) = try await EngineEndpoint.shared.session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    fetchPrompts()
                    // Auto-sync prompts to cloud in the background if logged in
                    if autoSyncToCloud && isLoggedIn {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        await uploadSettingsToCloud()
                    }
                }
            } catch {
                print("Failed to reset prompt: \(error)")
            }
        }
    }
    
    func deleteHistory(id: String) {
        Task {
            do {
                var req = URLRequest(url: URL(string: engineURL + "/history/\(id)")!)
                req.httpMethod = "DELETE"
                let _ = try await EngineEndpoint.shared.session.data(for: req)
                DispatchQueue.main.async {
                    self.history.removeAll { $0.id == id }
                }
            } catch {
                print("Failed to delete history: \(error)")
            }
        }
    }
    
    func fetchRetentionSettings() {
        Task {
            do {
                guard let url = URL(string: engineURL + "/history/settings/retention") else { return }
                let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                let decoded = try JSONDecoder().decode(RetentionSettings.self, from: data)
                await MainActor.run {
                    self.historyRetentionPeriod = decoded.retention_period
                    self.scrubAudioImmediately = decoded.scrub_audio_immediately
                }
            } catch {
                print("Failed to fetch retention settings: \(error)")
            }
        }
    }
    
    func saveRetentionSettings(period: String, scrubAudio: Bool) {
        Task {
            do {
                guard let url = URL(string: engineURL + "/history/settings/retention") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "retention_period": period,
                    "scrub_audio_immediately": scrubAudio
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                let _ = try await EngineEndpoint.shared.session.data(for: req)
                await MainActor.run {
                    self.historyRetentionPeriod = period
                    self.scrubAudioImmediately = scrubAudio
                }
                fetchHistory()
            } catch {
                print("Failed to save retention settings: \(error)")
            }
        }
    }
    
    func triggerHistoryCleanup() {
        Task {
            do {
                guard let url = URL(string: engineURL + "/history/cleanup") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                let _ = try await EngineEndpoint.shared.session.data(for: req)
                fetchHistory()
            } catch {
                print("Failed to trigger cleanup: \(error)")
            }
        }
    }
    
    @discardableResult
    func updateHistoryRecord(id: String, title: String? = nil, tags: [String]? = nil, notes: String? = nil) async -> Bool {
        do {
            guard let url = URL(string: engineURL + "/history/\(id)") else { return false }
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            var bodyDict: [String: Any] = [:]
            if let title = title {
                bodyDict["title"] = title
            }
            if let tags = tags {
                bodyDict["tags"] = tags
            }
            if let notes = notes {
                bodyDict["notes"] = notes
            }
            
            req.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
            let (data, response) = try await EngineEndpoint.shared.session.data(for: req)
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                let decoded = try JSONDecoder().decode(HistoryUpdateResponse.self, from: data)
                if let updatedRecord = decoded.record {
                    await MainActor.run {
                        if let index = self.history.firstIndex(where: { $0.id == id }) {
                            self.history[index] = updatedRecord
                        }
                    }
                    return true
                }
            }
            return false
        } catch {
            print("Failed to update history record: \(error)")
            return false
        }
    }
    
    func summarizeHistory(id: String, notes: String? = nil) {
        Task {
            await MainActor.run {
                summarizingIds.insert(id)
                summarizationErrors.removeValue(forKey: id)
            }
            do {
                var req = URLRequest(url: URL(string: engineURL + "/history/summarize/\(id)")!)
                req.httpMethod = "POST"
                
                let boundary = "Boundary-\(UUID().uuidString)"
                req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                
                var body = Data()
                func appendField(_ name: String, _ value: String) {
                    body.append("--\(boundary)\r\n".data(using: .utf8)!)
                    body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                    body.append("\(value)\r\n".data(using: .utf8)!)
                }
                
                let provider = self.effectiveLLMProvider
                let baseURL = UserDefaults.standard.string(forKey: "llmBaseUrl") ?? ""
                let model = UserDefaults.standard.string(forKey: "llmModel") ?? ""
                
                appendField("llm_provider", provider)
                appendField("llm_model", model)
                appendField("llm_base_url", baseURL)
                var llmApiKey = SecretsManager.readSecret(forKey: "llmApiKey") ?? ""
                if provider == "dicty_cloud" {
                    llmApiKey = SecretsManager.readSecret(forKey: "dicty_jwt_token") ?? ""
                }
                let openaiApiKey = SecretsManager.readSecret(forKey: "openaiApiKey") ?? ""
                
                appendField("llm_api_key", llmApiKey)
                appendField("openai_api_key", openaiApiKey)
                if let notes = notes {
                    appendField("notes", notes)
                }
                
                body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                req.httpBody = body
                
                let (data, _) = try await EngineEndpoint.shared.session.data(for: req)
                
                await MainActor.run {
                    summarizingIds.remove(id)
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String, status == "error",
                       let msg = json["message"] as? String {
                        summarizationErrors[id] = msg
                    }
                }
                fetchHistory()
            } catch {
                await MainActor.run {
                    summarizingIds.remove(id)
                    summarizationErrors[id] = "Network error: \(error.localizedDescription)"
                }
                print("Failed to summarize history: \(error)")
            }
        }
    }
    
    @MainActor
    func reprocessHistory(
        id: String,
        mode: String,
        formatStyle: String,
        customPrompt: String? = nil,
        retranscribeAudio: Bool = false
    ) async -> Bool {
        reprocessingIds.insert(id)
        reprocessErrors.removeValue(forKey: id)
        defer {
            reprocessingIds.remove(id)
        }
        
        do {
            guard let url = URL(string: engineURL + "/history/reprocess/\(id)") else { return false }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let provider = self.effectiveLLMProvider
            let baseURL = UserDefaults.standard.string(forKey: "llmBaseUrl") ?? ""
            let model = UserDefaults.standard.string(forKey: "llmModel") ?? ""
            var llmApiKey = SecretsManager.readSecret(forKey: "llmApiKey") ?? ""
            if provider == "dicty_cloud" {
                llmApiKey = SecretsManager.readSecret(forKey: "dicty_jwt_token") ?? ""
            }
            let openaiApiKey = SecretsManager.readSecret(forKey: "openaiApiKey") ?? ""
            
            var payload: [String: Any] = [
                "mode": mode,
                "format_style": formatStyle,
                "retranscribe_audio": retranscribeAudio,
                "language": UserDefaults.standard.string(forKey: "spokenLanguage") ?? "auto",
                "llm_provider": provider,
                "llm_base_url": baseURL,
                "llm_model": model,
                "llm_api_key": llmApiKey,
                "openai_api_key": openaiApiKey
            ]
            if let customPrompt = customPrompt, !customPrompt.isEmpty {
                payload["custom_prompt"] = customPrompt
            }
            
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, response) = try await EngineEndpoint.shared.session.data(for: req)
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode >= 400 {
                if let errObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = errObj["detail"] as? String {
                    reprocessErrors[id] = detail
                } else {
                    reprocessErrors[id] = "Server error (\(httpRes.statusCode))"
                }
                return false
            }
            
            let res = try JSONDecoder().decode(ReprocessResponse.self, from: data)
            if res.status == "success", let updatedRecord = res.record {
                if let idx = self.history.firstIndex(where: { $0.id == id }) {
                    self.history[idx] = updatedRecord
                }
                NSSound(named: NSSound.Name("Tink"))?.play()
                return true
            } else if let msg = res.message {
                reprocessErrors[id] = msg
                return false
            }
        } catch {
            print("Failed to reprocess history: \(error)")
            reprocessErrors[id] = error.localizedDescription
        }
        return false
    }
    
    func fetchModels(retryCount: Int = 0) {
        Task {
            do {
                let url = URL(string: engineURL + "/models")!
                let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                let resp = try JSONDecoder().decode(ModelsResponse.self, from: data)
                
                let activeUrl = URL(string: engineURL + "/models/active")!
                let (actData, _) = try await EngineEndpoint.shared.session.data(from: activeUrl)
                let actResp = try JSONDecoder().decode(ActiveModelResponse.self, from: actData)
                
                await MainActor.run {
                    if self.models != resp.models { self.models = resp.models }
                    
                    let backendActive = actResp.active_model
                    let hasValidBackendActive = !backendActive.isEmpty && resp.models.contains(where: { $0.id == backendActive })
                    
                    if hasValidBackendActive {
                        self.activeModel = backendActive
                    } else if self.activeModel.isEmpty || !resp.models.contains(where: { $0.id == self.activeModel }) {
                        self.activeModel = "tiny"
                    }
                    
                    if let textModel = actResp.active_text_model, !textModel.isEmpty {
                        self.activeTextModel = textModel
                    }
                    
                    // If activeModel is local and not downloaded, but "tiny" or another local model IS downloaded, auto-activate it
                    if let current = self.models.first(where: { $0.id == self.activeModel }),
                       current.is_cloud != true && current.is_downloaded != true {
                        if let downloaded = self.models.first(where: { $0.id == "tiny" && $0.is_downloaded == true }) ?? self.models.first(where: { $0.is_downloaded == true && $0.is_cloud != true }) {
                            self.setActiveModel(id: downloaded.id)
                        }
                    }
                    
                    self.updateMemoryMode()
                    self.fetchLocalLLMAddonStatus()
                }
            } catch {
                print("Error fetching models (attempt \(retryCount + 1)): \(error)")
                if retryCount < 30 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    self.fetchModels(retryCount: retryCount + 1)
                }
            }
        }
    }
    
    func fetchOpenRouterModels(force: Bool = false, sort: String? = nil) {
        if !force && sort == nil && !openRouterModels.isEmpty { return }
        isLoadingOpenRouterModels = true
        Task {
            do {
                var queryParts: [String] = []
                if force { queryParts.append("force=true") }
                if let sort = sort, !sort.isEmpty { queryParts.append("sort=\(sort)") }
                let query = queryParts.isEmpty ? "" : ("?" + queryParts.joined(separator: "&"))
                let urlStr = engineURL + "/models/openrouter" + query
                let url = URL(string: urlStr)!
                let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                let resp = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
                await MainActor.run {
                    self.openRouterModels = resp.models
                    self.isLoadingOpenRouterModels = false
                }
            } catch {
                print("Error fetching OpenRouter catalog: \(error)")
                await MainActor.run {
                    self.isLoadingOpenRouterModels = false
                }
            }
        }
    }
    
    func downloadModel(id: String, quality: String = "q5_0") {
        self.isDownloading = true
        self.downloadProgress[id] = 0.1
        Task {
            do {
                var request = URLRequest(url: URL(string: engineURL + "/models/download/\(id)?quality=\(quality)")!)
                request.httpMethod = "POST"
                let _ = try await EngineEndpoint.shared.session.data(for: request)
            } catch {
                print("Download error: \(error)")
            }
        }
    }
    
    func cancelDownload(id: String) {
        self.downloadProgress.removeValue(forKey: id)
        if self.downloadProgress.isEmpty {
            self.isDownloading = false
        }
        Task {
            do {
                var request = URLRequest(url: URL(string: engineURL + "/models/download/cancel?model_id=\(id)")!)
                request.httpMethod = "POST"
                let _ = try await EngineEndpoint.shared.session.data(for: request)
                DispatchQueue.main.async {
                    self.fetchModels()
                }
            } catch {
                print("Cancel download error: \(error)")
            }
        }
    }
    
    func deleteModel(id: String) {
        Task {
            do {
                guard let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let url = URL(string: engineURL + "/models/\(encodedId)") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                let (data, response) = try await EngineEndpoint.shared.session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    DispatchQueue.main.async {
                        self.fetchModels()
                    }
                } else {
                    let errBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("Delete model error (\((response as? HTTPURLResponse)?.statusCode ?? 0)): \(errBody)")
                }
            } catch {
                print("Delete error: \(error)")
            }
        }
    }

    // MARK: - Offline Formatting Add-on Management

    private var localLLMPollTask: Task<Void, Never>? = nil

    func fetchLocalLLMAddonStatus() {
        guard let url = URL(string: engineURL + "/addons/local-llm/status") else { return }
        Task {
            do {
                let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                if let status = try? JSONDecoder().decode(LocalLLMAddonStatus.self, from: data) {
                    await MainActor.run {
                        if self.localLLMAddonStatus != status {
                            self.localLLMAddonStatus = status
                        }
                        
                        let isBusy = status.stage == "preparing" || status.stage == "downloading_runner" || status.stage == "downloading_model" || status.stage == "starting"
                        if isBusy && self.localLLMPollTask == nil {
                            self.startLocalLLMPolling()
                        } else if !isBusy {
                            self.stopLocalLLMPolling()
                        }
                    }
                }
            } catch {
                // Engine might still be booting
            }
        }
    }

    private func startLocalLLMPolling() {
        localLLMPollTask?.cancel()
        localLLMPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                guard let url = URL(string: engineURL + "/addons/local-llm/status") else { break }
                do {
                    let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                    if let status = try? JSONDecoder().decode(LocalLLMAddonStatus.self, from: data) {
                        await MainActor.run {
                            if self.localLLMAddonStatus != status {
                                self.localLLMAddonStatus = status
                            }
                            let isBusy = status.stage == "preparing" || status.stage == "downloading_runner" || status.stage == "downloading_model" || status.stage == "starting"
                            if !isBusy {
                                self.stopLocalLLMPolling()
                                self.fetchModels()
                            }
                        }
                    }
                } catch {
                    break
                }
            }
        }
    }

    private func stopLocalLLMPolling() {
        localLLMPollTask?.cancel()
        localLLMPollTask = nil
    }

    func installLocalLLMAddon(modelId: String? = nil) {
        guard let url = URL(string: engineURL + "/addons/local-llm/install") else { return }
        Task {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let mid = modelId, !mid.isEmpty {
                    request.httpBody = try? JSONSerialization.data(withJSONObject: ["model_id": mid])
                }
                let _ = try await EngineEndpoint.shared.session.data(for: request)
                await MainActor.run {
                    self.fetchLocalLLMAddonStatus()
                }
            } catch {
                print("Failed to start addon install: \(error)")
            }
        }
    }

    func selectLocalLLMModel(_ modelId: String) {
        guard let url = URL(string: engineURL + "/addons/local-llm/models/select") else { return }
        Task {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: ["model_id": modelId])
                let (data, _) = try await EngineEndpoint.shared.session.data(for: request)
                if let status = try? JSONDecoder().decode(LocalLLMAddonStatus.self, from: data) {
                    await MainActor.run {
                        self.localLLMAddonStatus = status
                    }
                }
            } catch {
                print("Failed to select local model: \(error)")
            }
        }
    }

    func deleteLocalLLMModel(_ modelId: String) {
        guard let url = URL(string: engineURL + "/addons/local-llm/models/\(modelId)") else { return }
        Task {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                let _ = try await EngineEndpoint.shared.session.data(for: request)
                await MainActor.run {
                    self.fetchLocalLLMAddonStatus()
                }
            } catch {
                print("Failed to delete local model: \(error)")
            }
        }
    }

    func cancelLocalLLMAddonInstall() {
        guard let url = URL(string: engineURL + "/addons/local-llm/cancel") else { return }
        Task {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                let _ = try await EngineEndpoint.shared.session.data(for: request)
                await MainActor.run {
                    self.fetchLocalLLMAddonStatus()
                }
            } catch {
                print("Failed to cancel addon install: \(error)")
            }
        }
    }

    func uninstallLocalLLMAddon() {
        guard let url = URL(string: engineURL + "/addons/local-llm") else { return }
        Task {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                let _ = try await EngineEndpoint.shared.session.data(for: request)
                await MainActor.run {
                    self.fetchLocalLLMAddonStatus()
                    self.fetchModels()
                }
            } catch {
                print("Failed to uninstall addon: \(error)")
            }
        }
    }

    func toggleLocalLLMServer() {
        guard let url = URL(string: engineURL + "/addons/local-llm/toggle") else { return }
        Task {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                let (data, _) = try await EngineEndpoint.shared.session.data(for: request)
                if let status = try? JSONDecoder().decode(LocalLLMAddonStatus.self, from: data) {
                    await MainActor.run {
                        if self.localLLMAddonStatus != status {
                            self.localLLMAddonStatus = status
                        }
                    }
                }
            } catch {
                print("Failed to toggle addon server: \(error)")
            }
        }
    }
    
    private var completedDownloads: Set<String> = []
    
    private func fetchDownloadProgress() {
        guard let url = URL(string: engineURL + "/models/download/progress") else { return }
        Task {
            do {
                let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let progress = json["progress"] as? [String: Double] {
                    DispatchQueue.main.async {
                        self.downloadProgress = progress
                        
                        // Only trigger fetchModels() ONCE per finished model download
                        let newlyFinished = progress.filter { $0.value >= 100.0 && !self.completedDownloads.contains($0.key) }
                        if !newlyFinished.isEmpty {
                            for (modelId, _) in newlyFinished {
                                self.completedDownloads.insert(modelId)
                                if self.activeModel.isEmpty || self.activeModel == modelId || !self.isModelReady() {
                                    self.setActiveModel(id: modelId)
                                }
                            }
                            self.fetchModels()
                        }
                        
                        // Stop polling if there are no active downloads
                        if progress.isEmpty || progress.values.allSatisfy({ $0 >= 100.0 || $0 < 0 }) {
                            self.isDownloading = false
                        }
                    }
                }
            } catch {
                self.isDownloading = false
                // Silently ignore polling errors
            }
        }
    }
    
    func setActiveModel(id: String) {
        self.activeModel = id
        ProfileManager.shared.updateActiveProfileModels(whisperModel: id)
        Task {
            do {
                var request = URLRequest(url: URL(string: engineURL + "/models/active/\(id)")!)
                request.httpMethod = "POST"
                let _ = try await EngineEndpoint.shared.session.data(for: request)
                fetchModels()
            } catch {
                print("Set active error: \(error)")
            }
        }
    }
    
    func setActiveTextModel(id: String) {
        self.activeTextModel = id
        Task {
            do {
                var request = URLRequest(url: URL(string: engineURL + "/models/active_text/\(id)")!)
                request.httpMethod = "POST"
                let _ = try await EngineEndpoint.shared.session.data(for: request)
                fetchModels()
            } catch {
                print("Set active text model error: \(error)")
            }
        }
    }
    func openModelsFolder() {
        Task {
            let defaultPath = NSString(string: "~/Library/Application Support/Dicty/models").expandingTildeInPath
            do {
                var request = URLRequest(url: URL(string: engineURL + "/models/open")!)
                request.httpMethod = "POST"
                let (data, response) = try await EngineEndpoint.shared.session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let returnedPath = json["path"] as? String {
                    let folderURL = URL(fileURLWithPath: returnedPath)
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(folderURL)
                    }
                    return
                }
            } catch {
                print("Open folder network error: \(error)")
            }
            
            let folderURL = URL(fileURLWithPath: defaultPath)
            DispatchQueue.main.async {
                NSWorkspace.shared.open(folderURL)
            }
        }
    }
    
    private var lastToggleTime = Date()
    
    /// Cached NSSound instances so the first play doesn't read/decode the sound file on the hotkey path,
    /// and a still-playing instance is cleanly restarted on rapid back-to-back presses.
    private var cachedSounds: [String: NSSound] = [:]
    
    private func playRecordingSound(isStart: Bool) {
        let typeKey = isStart ? "startSoundType" : "stopSoundType"
        let nameKey = isStart ? "startSoundName" : "stopSoundName"
        let pathKey = isStart ? "startSoundPath" : "stopSoundPath"
        
        let defaultType = "Built-in"
        let defaultName = isStart ? "Hero" : "Pop"
        
        let type = UserDefaults.standard.string(forKey: typeKey) ?? defaultType
        
        if type == "None" { return }
        
        let cacheKey: String
        let makeSound: () -> NSSound?
        if type == "Built-in" {
            let name = UserDefaults.standard.string(forKey: nameKey) ?? defaultName
            cacheKey = "builtin:\(name)"
            makeSound = { NSSound(named: NSSound.Name(name)) }
        } else if type == "Custom" {
            let path = UserDefaults.standard.string(forKey: pathKey) ?? ""
            guard !path.isEmpty else { return }
            cacheKey = "custom:\(path)"
            makeSound = { NSSound(contentsOfFile: path, byReference: false) }
        } else {
            return
        }
        let sound = cachedSounds[cacheKey] ?? {
            let s = makeSound()
            if let s = s { cachedSounds[cacheKey] = s }
            return s
        }()
        if sound?.isPlaying == true { sound?.stop() }
        sound?.play()
    }
    
    func isModelReady() -> Bool {
        if activeModel.isEmpty {
            if let downloaded = models.first(where: { $0.id == "tiny" && $0.is_downloaded == true }) ?? models.first(where: { $0.is_downloaded == true && $0.is_cloud != true }) {
                setActiveModel(id: downloaded.id)
                return true
            }
            return false
        }
        guard let current = models.first(where: { $0.id == activeModel }) else {
            // If models catalog hasn't loaded yet from backend, allow fallback
            if models.isEmpty {
                return true
            }
            // Invalid model ID in activeModel: check if a downloaded model exists to auto-recover
            if let downloaded = models.first(where: { $0.id == "tiny" && $0.is_downloaded == true }) ?? models.first(where: { $0.is_downloaded == true && $0.is_cloud != true }) {
                setActiveModel(id: downloaded.id)
                return true
            }
            return false
        }
        if current.is_cloud == true { return true }
        if current.is_downloaded == true { return true }
        
        // If current active model is currently downloading, it's not ready yet — don't overwrite it
        if isDownloading && downloadProgress[activeModel] != nil {
            return false
        }
        
        // Active model is not downloaded: check if tiny or another local model is downloaded to auto-recover
        if let downloaded = models.first(where: { $0.id == "tiny" && $0.is_downloaded == true }) ?? models.first(where: { $0.is_downloaded == true && $0.is_cloud != true }) {
            setActiveModel(id: downloaded.id)
            return true
        }
        
        return false
    }
    
    static func hasScreenRecordingPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }
    
    @MainActor
    static func promptForScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
        
        let alert = NSAlert()
        alert.messageText = "Screen & System Audio Recording Permission Required"
        alert.informativeText = "Meeting Assistant and Focused App Meeting require Screen & System Audio Recording permission to capture system audio from your meetings (Zoom, Google Meet, Slack, browser, etc.).\n\nPlease enable Dicty in System Settings -> Privacy & Security -> Screen & System Audio Recording, then restart Dicty if requested."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    func startRecording(isHoldTrigger: Bool = false) {
        if isRecording { return }
        if Date().timeIntervalSince(lastToggleTime) < 0.2 { return }
        lastToggleTime = Date()
        recordingStartTime = Date()
        isHoldingToRecord = isHoldTrigger
        
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            if self.targetApp?.processIdentifier != frontmost.processIdentifier {
                self.targetApp = frontmost
            }
        } else {
            if self.targetApp != nil {
                self.targetApp = nil
            }
        }
        
        if !isModelReady() {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "No Active Model Ready"
                alert.informativeText = "Please select or download a model from the Models Library before recording."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }
        
        self.isRecording = true
        self.isPaused = false
        self.isMicMuted = ProfileManager.shared.activeProfile?.muteMicrophone ?? false
        self.pauseModifierWasPressed = false
        self.targetModifierWasPressed = false
        self.lastPauseToggleTime = Date.distantPast
        DispatchQueue.main.async {
            OverlayWindowManager.shared.show(engineClient: self)
        }
        
        // Snapshot the output-hardware state BEFORE opening the mic or playing the chime so
        // `isAudioPlayingAnywhere()` won't mistake the start chime for background music.
        let hardwarePlayingBeforeChime = MediaPlaybackManager.isSystemAudioPlaying()
        // Same moment, before Dicty opens the mic: a busy input now means another app (a call) owns it.
        let inputBusyBeforeMic = MediaPlaybackManager.isSystemInputInUse()
        
        Task {
            // 1. Check & pause background media in parallel with opening the microphone input stream:
            //    When a Bluetooth headset (AirPods / Sony / Bose) is the input device, opening the mic
            //    switches Bluetooth from A2DP (48 kHz stereo output) to HFP (24 kHz bidirectional).
            //    If the start chime is played BEFORE `recorder.start()` opens the mic, the A2DP -> HFP
            //    codec switch happens mid-chime and chops/lags the sound! Playing the chime immediately
            //    AFTER `/recording/start` opens the input stream ensures the audio route is already settled.
            async let mediaCheckTask: Void = {
                let wasAudioPlaying = await MediaPlaybackManager.isAudioPlayingAnywhere(
                    hardwarePlayingOverride: hardwarePlayingBeforeChime,
                    inputBusyElsewhere: inputBusyBeforeMic
                )
                await MainActor.run {
                    // Race guard: detection is async (MediaRemote query + AppleScript). If the user already
                    // stopped, resumeMediaIfNeeded() has run with nothing to resume; pausing now would pause
                    // the music AFTER the recording and nothing would ever resume it.
                    guard self.isRecording else {
                        MediaLogger.shared.log("[MediaPlaybackManager] Recording already stopped before media check finished. Skipping pause.")
                        return
                    }
                    MediaPlaybackManager.shared.pauseMediaIfNeeded(
                        wasAudioPlaying: wasAudioPlaying,
                        mode: self.activeMode,
                        setting: self.pauseMediaOnRecord
                    )
                }
            }()
            
            let effectiveLang = self.activeModel.hasSuffix(".en") ? "en" : self.transcriptionLanguage
            let appId = self.targetApp?.bundleIdentifier
            let modeOverride = self.recordingOverrideMode
            let manualActive = self.manualOverrideActive

            let queryParams = [
                self.activeDeviceID != -1 ? "device_id=\(self.activeDeviceID)" : nil,
                "language=\(effectiveLang)",
                "is_muted=\(self.isMicMuted)",
                "use_vad_streaming=\(self.useVADStreaming)",
                "mode=\(self.activeMode)",
                // Cloud models: transcribe while speaking (Deepgram live / pause-segmented). No secrets in the URL;
                // keys are pushed separately via /settings/stt_keys.
                "cloud_streaming=\(UserDefaults.standard.object(forKey: "cloudStreaming") as? Bool ?? true)",
                "cloud_route=\(self.effectiveLLMProvider)",
                "translate_to_english=\(self.translateToEnglish)",
                "enable_self_correction=\(self.enableSelfCorrection)",
                appId.map { "app_id=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)" },
                modeOverride.map { "mode_override=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)" },
                "manual_override_active=\(manualActive)"
            ].compactMap { $0 }.joined(separator: "&")
            let startUrlString = self.engineURL + "/recording/start?" + queryParams
            guard let startUrl = URL(string: startUrlString) else { return }
            var startReq = URLRequest(url: startUrl)
            startReq.httpMethod = "POST"
            
            do {
                // Start native Swift microphone capture (always has macOS TCC Microphone permission)
                self.audioRecorder.setMuted(self.isMicMuted)
                do {
                    let micUrl = try self.audioRecorder.startMicRecording()
                    print("[EngineClient] Native mic recording started: \(micUrl.lastPathComponent), TCC status: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) (3=authorized)")
                } catch {
                    print("[EngineClient] Native mic recording FAILED: \(error)")
                }
                // Start Python microphone recording first so the input stream & Bluetooth audio route are settled
                let (startData, _) = try await EngineEndpoint.shared.session.data(for: startReq)
                if let json = try? JSONSerialization.jsonObject(with: startData) as? [String: Any],
                   let resMode = json["resolved_mode"] as? String {
                    await MainActor.run {
                        if self.currentResolvedMode != resMode { self.currentResolvedMode = resMode }
                        if let reason = json["mode_reason"] as? String, self.currentResolvedReason != reason {
                            self.currentResolvedReason = reason
                        }
                    }
                }
                await MainActor.run {
                    self.playRecordingSound(isStart: true)
                }
                _ = await mediaCheckTask
                // Start Swift system audio recording for Meeting Modes
                if DictyAudioRecorder.isSystemAudioMode(self.activeMode) {
                    try await self.audioRecorder.startRecording(mode: self.activeMode)
                }
            } catch {
                print("Error starting recording: \(error)")
                MediaLogger.shared.log("[EngineClient] Error starting recording: \(error)")
                if let micUrl = self.audioRecorder.stopMicRecording() {
                    try? FileManager.default.removeItem(at: micUrl)
                }
                
                // Stop Python microphone recording so it does not remain stuck
                if let stopUrl = URL(string: self.engineURL + "/recording/stop") {
                    var stopReq = URLRequest(url: stopUrl)
                    stopReq.httpMethod = "POST"
                    _ = try? await EngineEndpoint.shared.session.data(for: stopReq)
                }
                
                await MainActor.run {
                    self.isRecording = false
                    self.isHoldingToRecord = false
                    self.isPaused = false
                    self.pauseModifierWasPressed = false
                    self.targetModifierWasPressed = false
                    self.lastPauseToggleTime = Date.distantPast
                    MediaPlaybackManager.shared.resumeMediaIfNeeded(shouldResume: self.resumeMediaAfterRecord)
                    
                    let nsError = error as NSError
                    // Prompt only when ScreenCaptureKit itself refused (-3801 = user declined TCC)
                    let isCaptureDenied = nsError.code == -3801 ||
                        (nsError.domain == "SCStreamErrorDomain" && !Self.hasScreenRecordingPermission())
                    if isCaptureDenied && DictyAudioRecorder.isSystemAudioMode(self.activeMode) {
                        Self.promptForScreenRecordingPermission()
                    }
                }
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        if Date().timeIntervalSince(lastToggleTime) < 0.2 { return }
        lastToggleTime = Date()
        let stopStartTime = Date()
        self.isHoldingToRecord = false
        
        // 1. Instantly stop native microphone recording on keyup so audio capture ends on keyup
        let nativeMicUrl = self.audioRecorder.stopMicRecording()
        
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            if self.targetApp?.processIdentifier != frontmost.processIdentifier {
                self.targetApp = frontmost
            }
        }
        
        // Asynchronously activate target app so WindowServer IPC does not block the stop sequence
        let target = self.targetApp
        DispatchQueue.global(qos: .userInitiated).async {
            if let target = target, !target.isTerminated {
                target.activate()
            }
        }
        
        // Play stop sound asynchronously
        DispatchQueue.main.async { [weak self] in
            self?.playRecordingSound(isStart: false)
        }
        
        self.isRecording = false
        self.isPaused = false
        self.pauseModifierWasPressed = false
        self.targetModifierWasPressed = false
        self.lastPauseToggleTime = Date.distantPast
        let shouldResume = self.resumeMediaAfterRecord
        Task { @MainActor in
            MediaPlaybackManager.shared.resumeMediaIfNeeded(shouldResume: shouldResume)
        }
        self.isProcessing = true
        
        let startMoment = self.recordingStartTime
        Task(priority: .userInitiated) {
            // Guard against microsecond release race conditions (e.g. key tapped or quickly released before /recording/start HTTP request finishes)
            let elapsed = Date().timeIntervalSince(startMoment)
            if elapsed < 0.3 {
                try? await Task.sleep(nanoseconds: UInt64((0.3 - elapsed) * 1_000_000_000))
            }
            
            do {
                defer {
                    if let u = nativeMicUrl {
                        try? FileManager.default.removeItem(at: u)
                    }
                }
                if DictyAudioRecorder.isSystemAudioMode(self.activeMode) {
                    // Stop Swift system audio and upload it (along with native mic track)
                    if let fileURL = try await audioRecorder.stopRecording() {
                        await uploadAudioForTranscription(fileURL: fileURL, micFileURL: nativeMicUrl)
                    }
                } else {
                    // Stop Python mic recording and attach the native Swift AVAudioRecorder WAV
                    let stopUrl = URL(string: engineURL + "/recording/stop")!
                    var stopReq = URLRequest(url: stopUrl)
                    stopReq.httpMethod = "POST"
                    stopReq.timeoutInterval = 600 // 10 minutes for long generations
                    let boundary = UUID().uuidString
                    stopReq.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                    
                    var body = self.buildFormBody(boundary: boundary)
                    if let micUrl = nativeMicUrl {
                        // ZERO-COPY: Send audio file path directly to the local Python engine
                        body.append("--\(boundary)\r\n".data(using: .utf8)!)
                        body.append("Content-Disposition: form-data; name=\"audio_file_path\"\r\n\r\n".data(using: .utf8)!)
                        body.append("\(micUrl.path)\r\n".data(using: .utf8)!)
                    }
                    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                    stopReq.httpBody = body
                    
                    DispatchQueue.main.async { self.processingStatusMessage = "Processing..." }
                    let statusTask = Task {
                        // Delay initial poll: normal dictations finish in <1s so don't crowd the loop
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        while !Task.isCancelled {
                            do {
                                let statusUrl = URL(string: self.engineURL + "/recording/status")!
                                var sReq = URLRequest(url: statusUrl)
                                EngineEndpoint.shared.authorize(&sReq)
                                let (statusData, _) = try await EngineEndpoint.shared.bareSession.data(for: sReq)
                                if let json = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
                                   let msg = json["status"] as? String {
                                    DispatchQueue.main.async {
                                        self.processingStatusMessage = msg
                                    }
                                }
                            } catch {}
                            try? await Task.sleep(nanoseconds: 500_000_000)
                        }
                    }
                    
                    EngineEndpoint.shared.authorize(&stopReq)
                    var (data, response) = try await EngineEndpoint.shared.bareSession.data(for: stopReq)
                    if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                        EngineEndpoint.shared.reloadTokenFromDisk()
                        EngineEndpoint.shared.authorize(&stopReq)
                        (data, response) = try await EngineEndpoint.shared.bareSession.data(for: stopReq)
                    }
                    statusTask.cancel()
                    let httpReceiveTime = Date()
                    handleTranscriptionResponse(data: data, stopStartTime: stopStartTime, httpReceiveTime: httpReceiveTime)
                }
            } catch {
                print("Error stopping recording: \(error)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.isPaused = false
                    self.pauseModifierWasPressed = false
                    self.targetModifierWasPressed = false
                    self.lastPauseToggleTime = Date.distantPast
                }
            }
        }
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording(isHoldTrigger: false)
        }
    }
    
    private func playPauseSound(isPause: Bool) {
        if isPause {
            NSSound(named: NSSound.Name("Pop"))?.play()
        } else {
            NSSound(named: NSSound.Name("Tink"))?.play()
        }
    }
    
    func pauseRecording() {
        guard isRecording && !isPaused else { return }
        self.isPaused = true
        self.playPauseSound(isPause: true)
        print("[*] Pause requested (isRecording=\(isRecording), isPaused=\(isPaused))")
        self.audioRecorder.pause()
        Task {
            guard let pauseUrl = URL(string: engineURL + "/recording/pause") else { return }
            var req = URLRequest(url: pauseUrl)
            req.httpMethod = "POST"
            let (data, _) = (try? await EngineEndpoint.shared.session.data(for: req)) ?? (Data(), URLResponse())
            if let respStr = String(data: data, encoding: .utf8) {
                print("[*] Engine pause response: \(respStr)")
            }
        }
    }
    
    func resumeRecording() {
        guard isRecording && isPaused else { return }
        self.isPaused = false
        self.playPauseSound(isPause: false)
        print("[*] Resume requested (isRecording=\(isRecording), isPaused=\(isPaused))")
        self.audioRecorder.resume()
        Task {
            guard let resumeUrl = URL(string: engineURL + "/recording/resume") else { return }
            var req = URLRequest(url: resumeUrl)
            req.httpMethod = "POST"
            let (data, _) = (try? await EngineEndpoint.shared.session.data(for: req)) ?? (Data(), URLResponse())
            if let respStr = String(data: data, encoding: .utf8) {
                print("[*] Engine resume response: \(respStr)")
            }
        }
    }
    
    func togglePauseRecording() {
        guard isRecording else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPauseToggleTime) > 0.15 else { return }
        lastPauseToggleTime = now
        
        if isPaused {
            resumeRecording()
        } else {
            pauseRecording()
        }
    }
    
    func toggleMicMute() {
        isMicMuted.toggle()
        self.audioRecorder.setMuted(isMicMuted)
        if isRecording {
            let muteUrlString = "\(engineURL)/recording/mute?is_muted=\(isMicMuted)"
            if let url = URL(string: muteUrlString) {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                Task {
                    _ = try? await EngineEndpoint.shared.session.data(for: req)
                }
            }
        }
    }
    
    func cancelRecording() {
        let wasRecording = isRecording
        let wasProcessing = isProcessing
        
        if !wasRecording && !wasProcessing { return }
        
        self.isRecording = false
        self.isPaused = false
        self.isHoldingToRecord = false
        self.isMicMuted = ProfileManager.shared.activeProfile?.muteMicrophone ?? false
        self.pauseModifierWasPressed = false
        self.targetModifierWasPressed = false
        self.lastPauseToggleTime = Date.distantPast
        self.isProcessing = false
        MediaPlaybackManager.shared.resumeMediaIfNeeded(shouldResume: self.resumeMediaAfterRecord)
        
        Task {
            do {
                if let micUrl = self.audioRecorder.stopMicRecording() {
                    try? FileManager.default.removeItem(at: micUrl)
                }
                if wasRecording && DictyAudioRecorder.isSystemAudioMode(activeMode) {
                    let _ = try await audioRecorder.stopRecording()
                }
                
                let cancelUrl = URL(string: engineURL + "/recording/cancel")!
                var request = URLRequest(url: cancelUrl)
                request.httpMethod = "POST"
                let _ = try await EngineEndpoint.shared.session.data(for: request)
            } catch {
                print("Error canceling recording/processing: \(error)")
            }
        }
    }
    
    private func handleTranscriptionResponse(data: Data, stopStartTime: Date? = nil, httpReceiveTime: Date? = nil) {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var incomingSuggestion: AppRuleSuggestion? = nil
            if let sugDict = json["suggestion"] as? [String: Any],
               let appId = sugDict["app_id"] as? String,
               let appName = sugDict["app_name"] as? String,
               let modeId = sugDict["mode_id"] as? String {
                let count = sugDict["count"] as? Int
                incomingSuggestion = AppRuleSuggestion(app_id: appId, app_name: appName, mode_id: modeId, count: count)
            }

            if let resMode = json["resolved_mode"] as? String {
                DispatchQueue.main.async {
                    if self.currentResolvedMode != resMode { self.currentResolvedMode = resMode }
                    if let reason = json["mode_reason"] as? String, self.currentResolvedReason != reason {
                        self.currentResolvedReason = reason
                    }
                }
            }
            if let s_wpm = json["avg_speaking_wpm"] as? Int {
                DispatchQueue.main.async { self.avgSpeakingWpm = s_wpm }
            }
            if let e_wpm = json["avg_engine_wpm"] as? Int {
                DispatchQueue.main.async { self.avgEngineWpm = e_wpm }
            }
            let metricsId = json["metrics_id"] as? String
            if let text = json["text"] as? String, !text.isEmpty {
                let responseMode = json["mode"] as? String ?? ""
                if responseMode == "librarian" {
                    print("[*] Librarian mode detected in response. Thought staged in Architecture Queue.")
                    self.reportEndToEndLatency(metricsId: metricsId, since: stopStartTime, pasted: false)
                    self.fetchStagedThoughts()
                } else {
                    DispatchQueue.main.async {
                        let backup: ClipboardBackup? = self.restoreClipboardAfterPaste ? ClipboardBackup.snapshot() : nil
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(text, forType: .string)
                        if self.autoPaste { 
                            // Latency is measured up to the moment Cmd+V is actually posted (after the focus wait)
                            self.simulatePaste(backupToRestore: backup) { pasted in
                                self.reportEndToEndLatency(metricsId: metricsId, since: stopStartTime, pasted: pasted)
                                if let sug = incomingSuggestion {
                                    self.presentAppRuleSuggestion(sug)
                                }
                            }
                        } else {
                            self.reportEndToEndLatency(metricsId: metricsId, since: stopStartTime, pasted: false)
                            if let sug = incomingSuggestion {
                                self.presentAppRuleSuggestion(sug)
                            }
                        }
                        
                        if let t0 = stopStartTime, let t1 = httpReceiveTime {
                            let httpMs = Int(t1.timeIntervalSince(t0) * 1000)
                            print("⏱️ [CLIENT TIMING] Engine HTTP round-trip: \(httpMs) ms")
                        }
                    }
                }
            }
        }
        if !self.isIncognitoMode {
            self.fetchHistory()
            self.fetchStats()
        }
        self.fetchAuthStatus(force: true)
        
        DispatchQueue.main.async {
            self.recordingOverrideMode = nil
            if self.appRulesSettings.override_scope == "recording" {
                self.manualOverrideActive = false
            }
            self.isProcessing = false
        }
    }
    
    private func buildFormBody(boundary: String) -> Data {
        var body = Data()
        // Add mode field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"mode\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(activeMode)\r\n".data(using: .utf8)!)
        
        if let appId = self.targetApp?.bundleIdentifier {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"app_id\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(appId)\r\n".data(using: .utf8)!)
        }
        if let modeOverride = self.recordingOverrideMode {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"mode_override\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(modeOverride)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"manual_override_active\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(self.manualOverrideActive ? "true" : "false")\r\n".data(using: .utf8)!)
        
        // Add formatting style field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"dictation_format_style\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(dictationFormatStyle)\r\n".data(using: .utf8)!)
        
        let currentAuthor = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentAuthor.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"author_name\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(currentAuthor)\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"use_vad_streaming\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(useVADStreaming)\r\n".data(using: .utf8)!)
        
        let token = UserDefaults.standard.string(forKey: "githubToken") ?? ""
        let repo = UserDefaults.standard.string(forKey: "selectedGitHubRepo") ?? ""
        let gitProvider = UserDefaults.standard.string(forKey: "gitProvider") ?? "github"
        let gitlabHost = UserDefaults.standard.string(forKey: "gitlabHost") ?? "https://gitlab.com"
        let gitlabToken = SecretsManager.readSecret(forKey: "gitlabToken") ?? ""
        let gitlabRepo = UserDefaults.standard.string(forKey: "selectedGitLabRepo") ?? ""
        let commits = UserDefaults.standard.string(forKey: "selectedGitHubCommits") ?? ""
        let prs = UserDefaults.standard.string(forKey: "selectedGitHubPRs") ?? ""
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"git_provider\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(gitProvider)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"github_token\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(token)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"github_repo\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(repo)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"gitlab_host\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(gitlabHost)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"gitlab_token\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(gitlabToken)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"gitlab_repo\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(gitlabRepo)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"github_commits\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(commits)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"github_prs\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(prs)\r\n".data(using: .utf8)!)
        
        let confluenceUrl = UserDefaults.standard.string(forKey: "confluenceUrl") ?? ""
        let confluenceSpace = UserDefaults.standard.string(forKey: "confluenceSpace") ?? ""
        let confluenceUser = UserDefaults.standard.string(forKey: "confluenceUser") ?? ""
        let confluenceToken = SecretsManager.readSecret(forKey: "confluenceToken") ?? ""
        
        let targetSystem = UserDefaults.standard.string(forKey: "targetSystem") ?? "confluence"
        let obsidianPath = UserDefaults.standard.string(forKey: "obsidianPath") ?? ""
        
        let llmProvider = self.effectiveLLMProvider
        let llmBaseUrl = UserDefaults.standard.string(forKey: "llmBaseUrl") ?? "http://localhost:1234/v1"
        var llmModel = UserDefaults.standard.string(forKey: "llmModel") ?? "openai/gpt-4o-mini"
        
        let dictationLLMModel = UserDefaults.standard.string(forKey: "dictationLLMModel") ?? ""
        if activeMode == "dictation" && !dictationLLMModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            llmModel = dictationLLMModel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        var llmApiKey = SecretsManager.readSecret(forKey: "llmApiKey") ?? ""
        if llmProvider == "dicty_cloud" {
            llmApiKey = SecretsManager.readSecret(forKey: "dicty_jwt_token") ?? ""
        }

        
        let openaiApiKey = SecretsManager.readSecret(forKey: "openaiApiKey") ?? ""
        
        let confluencePageTitle = UserDefaults.standard.string(forKey: "confluencePageTitle") ?? ""
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"confluence_url\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(confluenceUrl)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"confluence_space\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(confluenceSpace)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"confluence_user\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(confluenceUser)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"confluence_token\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(confluenceToken)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"confluence_page_title\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(confluencePageTitle)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"openai_api_key\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(openaiApiKey)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"target_type\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(targetSystem)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"obsidian_path\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(obsidianPath)\r\n".data(using: .utf8)!)
        
        let linearApiToken = SecretsManager.readSecret(forKey: "linearApiToken") ?? ""
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"linear_api_token\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(linearApiToken)\r\n".data(using: .utf8)!)
        
        let linearWorkspaceId = UserDefaults.standard.string(forKey: "linearWorkspaceId") ?? ""
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"linear_workspace_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(linearWorkspaceId)\r\n".data(using: .utf8)!)
        
        let linearSearchAll = UserDefaults.standard.bool(forKey: "linearSearchAllWorkspaces")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"linear_search_all\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(linearSearchAll)\r\n".data(using: .utf8)!)
        
        let notionApiKey = UserDefaults.standard.string(forKey: "notionApiKey") ?? ""
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"notion_api_key\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(notionApiKey)\r\n".data(using: .utf8)!)
        
        let notionPageId = UserDefaults.standard.string(forKey: "notionPageId") ?? ""
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"notion_page_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(notionPageId)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"llm_provider\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(llmProvider)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"llm_base_url\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(llmBaseUrl)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"llm_model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(llmModel)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"llm_api_key\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(llmApiKey)\r\n".data(using: .utf8)!)
        
        let effectiveLang = self.activeModel.hasSuffix(".en") ? "en" : self.transcriptionLanguage
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(effectiveLang)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"translate_to_english\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(translateToEnglish ? "true" : "false")\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"enable_auto_completion\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(enableAutoCompletion ? "true" : "false")\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"enable_self_correction\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(enableSelfCorrection ? "true" : "false")\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"self_correction_model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(selfCorrectionModel)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"translation_method\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(translationMethod)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"target_language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(targetLanguage)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"translation_model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(selectedTranslationModel)\r\n".data(using: .utf8)!)
        
        let activeProfile = ProfileManager.shared.activeProfile
        let rawSpeakerSeparation = activeProfile?.speakerSeparation ?? "you_others"
        let speakerSeparation = (rawSpeakerSeparation == "smart_llm") ? "you_others" : rawSpeakerSeparation
        let speakerYouLabel = activeProfile?.speakerYouLabel ?? "You"
        let meetingShowTimestamps = activeProfile?.meetingShowTimestamps ?? false
        let enableDiarization = false
        var rawDiarizationModel = activeProfile?.diarizationModel ?? "openai/gpt-4o-mini"
        if rawDiarizationModel.starts(with: "custom:") {
            rawDiarizationModel = String(rawDiarizationModel.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let diarizationModel = rawDiarizationModel.isEmpty ? "openai/gpt-4o-mini" : rawDiarizationModel
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"speaker_separation\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(speakerSeparation)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"speaker_you_label\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(speakerYouLabel)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"meeting_show_timestamps\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(meetingShowTimestamps ? "true" : "false")\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"enable_diarization\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(enableDiarization ? "true" : "false")\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"diarization_model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(diarizationModel)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"incognito_mode\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(isIncognitoMode ? "true" : "false")\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"mute_microphone\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(isMicMuted ? "true" : "false")\r\n".data(using: .utf8)!)
        
        let activeTags = activeProfile?.tags ?? []
        let tagsString = activeTags.joined(separator: ",")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"tags\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(tagsString)\r\n".data(using: .utf8)!)

        if let targetContext = TargetAppContext(application: targetApp) {
            for field in targetContext.formFields {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(field.value)\r\n".data(using: .utf8)!)
            }
        }

        return body
    }
    
    private func uploadAudioForTranscription(fileURL: URL, micFileURL: URL? = nil) async {
        guard let url = URL(string: engineURL + "/transcribe") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600 // 10 minutes for long audio processing
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = self.buildFormBody(boundary: boundary)
        
        // Add file field
        if let audioData = try? Data(contentsOf: fileURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)
        }
        if let micURL = micFileURL, let micData = try? Data(contentsOf: micURL), micData.count > 512 {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"mic_file\"; filename=\"mic.wav\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(micData)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        do {
            let uploadStart = Date()
            let (data, _) = try await EngineEndpoint.shared.session.data(for: request)
            handleTranscriptionResponse(data: data, stopStartTime: uploadStart, httpReceiveTime: Date())
        } catch {
            print("Error uploading audio: \(error)")
            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }
        
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    struct ClipboardBackup {
        struct Item {
            let data: [NSPasteboard.PasteboardType: Data]
        }
        
        let items: [Item]
        
        static func snapshot() -> ClipboardBackup? {
            let pb = NSPasteboard.general
            guard let pbItems = pb.pasteboardItems, !pbItems.isEmpty else { return nil }
            
            var saved: [Item] = []
            for item in pbItems {
                var itemData: [NSPasteboard.PasteboardType: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) {
                        itemData[type] = data
                    }
                }
                if !itemData.isEmpty {
                    saved.append(Item(data: itemData))
                }
            }
            return saved.isEmpty ? nil : ClipboardBackup(items: saved)
        }
        
        func restore() {
            let pb = NSPasteboard.general
            pb.clearContents()
            for item in items {
                let pbItem = NSPasteboardItem()
                for (type, data) in item.data {
                    pbItem.setData(data, forType: type)
                }
                pb.writeObjects([pbItem])
            }
        }
    }
    
    private func simulatePaste(backupToRestore: ClipboardBackup? = nil, onPasted: ((Bool) -> Void)? = nil) {
        let isOnboardingKey = WindowManager.onboardingWindow?.isKeyWindow == true
        if isOnboardingKey {
            onPasted?(false)
            return
        }
        
        if !Self.isAccessibilityTrusted {
            let trusted = AXIsProcessTrusted()
            if !trusted {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "Dicty needs Accessibility permissions to paste text. If you just updated Dicty, macOS may be holding a stale permission rule."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Reset Stale Rule & Open Settings")
                alert.addButton(withTitle: "Cancel")
                
                let response = alert.runModal()
                if response == .alertSecondButtonReturn {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                    process.arguments = ["reset", "Accessibility", "com.antigravity.Dicty"]
                    try? process.run()
                    process.waitUntilExit()
                }
                
                if response != .alertThirdButtonReturn {
                    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                onPasted?(false)
                return
            }
            Self.isAccessibilityTrusted = true
        }
        
        let vKeyCode: CGKeyCode = 9 // 'v'
        let cmdKeyCode: CGKeyCode = 55 // Command
        
        guard let src = Self.eventSource ?? CGEventSource(stateID: .hidSystemState) else {
            onPasted?(false)
            return
        }
        
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmdKeyCode, keyDown: true)
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: cmdKeyCode, keyDown: false)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
        
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        
        let tapLoc = CGEventTapLocation.cghidEventTap
        cmdDown?.post(tap: tapLoc)
        vDown?.post(tap: tapLoc)
        vUp?.post(tap: tapLoc)
        cmdUp?.post(tap: tapLoc)
        onPasted?(true)
        
        TelemetryClient.shared.track("text_injected", properties: [
            "is_trusted_accessibility": true
        ])
        
        if let backup = backupToRestore {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                backup.restore()
                print("[*] Restored previous clipboard content after auto-paste.")
            }
        }
    }
    
    func transcribeLocalFile(url: URL, targetModel: String, language: String, targetLanguage: String, translationMethod: String? = nil, translationModel: String? = nil) async throws -> String {
        let fileTranscriptionStart = Date()
        
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        
        // Native Swift conversion: directly extract and convert to 16kHz mono WAV
        let wavURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        do {
            let asset = AVAsset(url: url)
            
            // Wait for tracks to load (macOS 13+ compatible, avoiding deprecated sync tracks)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let audioTrack = tracks.first else {
                throw NSError(domain: "DictyClient", code: 3, userInfo: [NSLocalizedDescriptionKey: "No audio track found in the file."])
            }
            
            let reader = try AVAssetReader(asset: asset)
            // Decompress format to raw PCM
            let decompressedSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: decompressedSettings)
            reader.add(trackOutput)
            
            let writer = try AVAssetWriter(outputURL: wavURL, fileType: .wav)
            let writerSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
            writerInput.expectsMediaDataInRealTime = false
            writer.add(writerInput)
            
            guard reader.startReading() else {
                throw reader.error ?? NSError(domain: "DictyClient", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to start reading."])
            }
            guard writer.startWriting() else {
                throw writer.error ?? NSError(domain: "DictyClient", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to start writing."])
            }
            writer.startSession(atSourceTime: .zero)
            
            let queue = DispatchQueue(label: "dicty_audio_conversion")
            
            let conversionGroup = DispatchGroup()
            conversionGroup.enter()
            
            writerInput.requestMediaDataWhenReady(on: queue) { @Sendable in
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = trackOutput.copyNextSampleBuffer() {
                        let success = writerInput.append(sampleBuffer)
                        if !success {
                            writerInput.markAsFinished()
                            conversionGroup.leave()
                            break
                        }
                    } else {
                        writerInput.markAsFinished()
                        conversionGroup.leave()
                        break
                    }
                }
            }
            
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                conversionGroup.notify(queue: .global()) { @Sendable in
                    continuation.resume()
                }
            }
            
            await writer.finishWriting()
            
            if reader.status == .failed {
                throw reader.error ?? NSError(domain: "DictyClient", code: 4, userInfo: [NSLocalizedDescriptionKey: "Audio reader failed: \(reader.error?.localizedDescription ?? "")"])
            }
            if writer.status == .failed {
                throw writer.error ?? NSError(domain: "DictyClient", code: 5, userInfo: [NSLocalizedDescriptionKey: "Audio writer failed: \(writer.error?.localizedDescription ?? "")"])
            }
        } catch {
            try? FileManager.default.removeItem(at: wavURL)
            throw error
        }
        
        defer {
            try? FileManager.default.removeItem(at: wavURL)
        }
        
        let fileData = try Data(contentsOf: wavURL)
        
        let transcribeUrl = URL(string: engineURL + "/transcribe/file")!
        var request = URLRequest(url: transcribeUrl)
        request.httpMethod = "POST"
        request.timeoutInterval = 600 // 10 minutes
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(wavURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"target_model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(targetModel)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(language)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"translate_to_english\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(translateToEnglish ? "true" : "false")\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"enable_auto_completion\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(enableAutoCompletion ? "true" : "false")\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"target_language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(targetLanguage)\r\n".data(using: .utf8)!)
        
        let llmProvider = self.effectiveLLMProvider
        let llmBaseUrl = UserDefaults.standard.string(forKey: "llmBaseUrl") ?? ""
        let llmModel = UserDefaults.standard.string(forKey: "llmModel") ?? ""
        var llmApiKey = UserDefaults.standard.string(forKey: "llmApiKey") ?? ""
        if llmProvider == "dicty_cloud" {
            llmApiKey = SecretsManager.readSecret(forKey: "dicty_jwt_token") ?? ""
        }
        let openaiApiKey = UserDefaults.standard.string(forKey: "openaiApiKey") ?? ""
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"llm_provider\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(llmProvider)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"llm_base_url\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(llmBaseUrl)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"llm_model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(llmModel)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"llm_api_key\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(llmApiKey)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"openai_api_key\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(openaiApiKey)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 7200
        config.timeoutIntervalForResource = 7200
        let session = EngineEndpoint.shared.session(configuration: config)
        
        let (data, _) = try await session.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String, status == "success",
              let text = json["text"] as? String else {
            throw NSError(domain: "EngineClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Transcription failed"])
        }
        reportEndToEndLatency(metricsId: json["metrics_id"] as? String, since: fileTranscriptionStart, pasted: false)
        return text
    }
    
    func exportDiagnosticsPackage() async -> Bool {
        guard let url = URL(string: "\(engineURL)/diagnostics/export") else { return false }
        do {
            let (data, response) = try await EngineEndpoint.shared.session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            
            let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let zipName = "Dicty_Diagnostics_\(formatter.string(from: Date())).zip"
            let destURL = downloadsDir.appendingPathComponent(zipName)
            
            try data.write(to: destURL)
            
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([destURL])
            }
            return true
        } catch {
            print("[!] Export diagnostics error: \(error)")
            return false
        }
    }
    
    // MARK: - Librarian Voice Queue & Synthesis
    
    func fetchStagedThoughts() {
        guard let url = URL(string: "\(engineURL)/librarian/queue") else { return }
        Task { @MainActor in
            do {
                let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                if let res = try? JSONDecoder().decode(VoiceQueueResponse.self, from: data) {
                    self.stagedThoughts = res.items
                }
            } catch {
                print("[!] Error fetching staged thoughts: \(error)")
            }
        }
    }
    
    func addStagedThought(text: String, completion: (@Sendable @MainActor () -> Void)? = nil) {
        guard let url = URL(string: "\(engineURL)/librarian/queue") else { return }
        Task { @MainActor in
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload = ["text": text, "source": "manual"]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                _ = try await EngineEndpoint.shared.session.data(for: request)
                self.fetchStagedThoughts()
                completion?()
            } catch {
                print("[!] Error adding staged thought: \(error)")
                completion?()
            }
        }
    }
    
    func updateStagedThought(id: String, text: String, completion: (@Sendable @MainActor () -> Void)? = nil) {
        guard let url = URL(string: "\(engineURL)/librarian/queue/\(id)") else { return }
        Task { @MainActor in
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload = ["text": text]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                _ = try await EngineEndpoint.shared.session.data(for: request)
                self.fetchStagedThoughts()
                completion?()
            } catch {
                print("[!] Error updating staged thought: \(error)")
                completion?()
            }
        }
    }
    
    func deleteStagedThought(id: String) {
        guard let url = URL(string: "\(engineURL)/librarian/queue/\(id)") else { return }
        Task { @MainActor in
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                _ = try await EngineEndpoint.shared.session.data(for: request)
                self.fetchStagedThoughts()
            } catch {
                print("[!] Error deleting staged thought: \(error)")
            }
        }
    }
    
    func clearStagedThoughts() {
        guard let url = URL(string: "\(engineURL)/librarian/queue") else { return }
        Task { @MainActor in
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                _ = try await EngineEndpoint.shared.session.data(for: request)
                self.stagedThoughts = []
            } catch {
                print("[!] Error clearing staged thoughts: \(error)")
            }
        }
    }
    
    func synthesizeArchitectureDocs(
        targetFile: String? = nil,
        customPrompt: String? = nil,
        clearOnSuccess: Bool = true,
        completion: (@Sendable @MainActor (Bool, String?) -> Void)? = nil
    ) {
        guard let url = URL(string: "\(engineURL)/librarian/synthesize") else {
            completion?(false, "Invalid engine URL")
            return
        }
        
        self.isSynthesizingDocs = true
        
        Task { @MainActor in
            defer {
                self.isSynthesizingDocs = false
            }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 180.0
                
                let profile = ProfileManager.shared.activeProfile
                let token = SecretsManager.readSecret(forKey: "githubToken") ?? UserDefaults.standard.string(forKey: "githubToken") ?? ""
                let repo = (profile?.selectedGitHubRepo.isEmpty == false) ? profile!.selectedGitHubRepo : (UserDefaults.standard.string(forKey: "selectedGitHubRepo") ?? "")
                let branch = (profile?.selectedGitHubBranch.isEmpty == false) ? profile!.selectedGitHubBranch : (UserDefaults.standard.string(forKey: "selectedGitHubBranch") ?? "")
                let confluenceUrl = UserDefaults.standard.string(forKey: "confluenceUrl") ?? ""
                let confluenceSpace = (profile?.confluenceSpace.isEmpty == false) ? profile!.confluenceSpace : (UserDefaults.standard.string(forKey: "confluenceSpace") ?? "")
                let confluenceUser = UserDefaults.standard.string(forKey: "confluenceUser") ?? ""
                let confluenceToken = SecretsManager.readSecret(forKey: "confluenceToken") ?? ""
                let confluencePageTitle = (profile?.confluencePageTitle.isEmpty == false) ? profile!.confluencePageTitle : (UserDefaults.standard.string(forKey: "confluencePageTitle") ?? "")
                let targetSystem = (profile?.activeMode == "librarian" && profile?.targetSystem.isEmpty == false) ? profile!.targetSystem : (UserDefaults.standard.string(forKey: "targetSystem") ?? "obsidian")
                let centralObsidian = (UserDefaults.standard.string(forKey: "obsidianPath") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let obsidianPath = !centralObsidian.isEmpty ? centralObsidian : (profile?.obsidianPath ?? "")
                let linearApiToken = SecretsManager.readSecret(forKey: "linearApiToken") ?? ""
                let linearWorkspaceId = UserDefaults.standard.string(forKey: "linearWorkspaceId") ?? ""
                let linearSearchAll = UserDefaults.standard.bool(forKey: "linearSearchAll")
                let notionApiKey = SecretsManager.readSecret(forKey: "notionApiKey") ?? UserDefaults.standard.string(forKey: "notionApiKey") ?? ""
                let notionPageId = UserDefaults.standard.string(forKey: "notionPageId") ?? ""
                let rawProvider = (profile?.llmProvider.isEmpty == false && profile?.llmProvider != "openrouter") ? profile!.llmProvider : self.effectiveLLMProvider
                let llmProvider: String
                if rawProvider == "dicty_cloud" {
                    let hasCloudAccess = self.isLoggedIn && (self.isPro || self.computeBalance > 0)
                    llmProvider = hasCloudAccess ? "dicty_cloud" : "openrouter"
                } else {
                    llmProvider = rawProvider
                }
                let llmBaseUrl = UserDefaults.standard.string(forKey: "llmBaseUrl") ?? ""
                let llmModel = (profile?.llmModel.isEmpty == false) ? profile!.llmModel : (UserDefaults.standard.string(forKey: "llmModel") ?? "")
                var llmApiKey = SecretsManager.readSecret(forKey: "llmApiKey") ?? ""
                if llmProvider == "dicty_cloud" {
                    llmApiKey = SecretsManager.readSecret(forKey: "dicty_jwt_token") ?? UserDefaults.standard.string(forKey: "dicty_jwt_token") ?? ""
                }

                let selectedCommits = UserDefaults.standard.string(forKey: "selectedGitHubCommits") ?? ""
                let selectedPRs = UserDefaults.standard.string(forKey: "selectedGitHubPRs") ?? ""
                let selectedIssues = UserDefaults.standard.string(forKey: "selectedGitHubIssues") ?? ""

                var payload: [String: Any] = [
                    "target_type": targetSystem,
                    "target_file": targetFile ?? "docs/ARCHITECTURE.md",
                    "obsidian_path": obsidianPath,
                    "confluence_url": confluenceUrl,
                    "confluence_space": confluenceSpace,
                    "confluence_user": confluenceUser,
                    "confluence_token": confluenceToken,
                    "confluence_page_title": confluencePageTitle,
                    "linear_api_token": linearApiToken,
                    "linear_workspace_id": linearWorkspaceId,
                    "linear_search_all": linearSearchAll,
                    "notion_api_key": notionApiKey,
                    "notion_page_id": notionPageId,
                    "github_token": token,
                    "github_repo": repo,
                    "github_branch": branch,
                    "github_commits": selectedCommits,
                    "github_prs": selectedPRs,
                    "github_issues": selectedIssues,
                    "llm_provider": llmProvider,
                    "llm_base_url": llmBaseUrl,
                    "llm_model": llmModel,
                    "llm_api_key": llmApiKey,
                    "clear_queue_on_success": clearOnSuccess
                ]
                if let p = customPrompt, !p.isEmpty {
                    payload["custom_prompt"] = p
                }
                
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                
                let sessionConfig = URLSessionConfiguration.default
                sessionConfig.timeoutIntervalForRequest = 180.0
                sessionConfig.timeoutIntervalForResource = 180.0
                let session = EngineEndpoint.shared.session(configuration: sessionConfig)
                
                let (data, _) = try await session.data(for: request)
                
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion?(false, "Invalid response from server")
                    return
                }
                
                let status = json["status"] as? String ?? "error"
                if status == "success" {
                    self.fetchStagedThoughts()
                    let resultMessage = json["message"] as? String ?? "Documentation synthesized successfully!"
                    completion?(true, resultMessage)
                } else {
                    let msg = json["message"] as? String ?? json["detail"] as? String ?? "Synthesis failed"
                    completion?(false, msg)
                }
            } catch {
                completion?(false, error.localizedDescription)
            }
        }
    }
}

final class EventMonitorRegistrar: @unchecked Sendable {
    static func registerGlobal(matching mask: NSEvent.EventTypeMask, handler: @escaping @Sendable (NSEvent) -> Void) -> Any? {
        return NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            handler(event)
        }
    }
    
    static func registerLocal(matching mask: NSEvent.EventTypeMask, handler: @escaping @Sendable (NSEvent) -> NSEvent?) -> Any? {
        return NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            return handler(event)
        }
    }
}
