import SwiftUI
import Combine

@MainActor
final class ProfileManager: ObservableObject {
    static let shared = ProfileManager()
    
    private let profilesStorageKey = "dicty_profiles_list"
    private let activeProfileIdKey = "dicty_active_profile_id"
    
    @Published var profiles: [DictyProfile] = []
    @Published var activeProfileId: UUID = UUID()
    
    var activeProfile: DictyProfile? {
        profiles.first(where: { $0.id == activeProfileId }) ?? profiles.first
    }
    
    static let defaultProfiles: [DictyProfile] = [
        DictyProfile(
            name: "General Dictation",
            description: "Instant speech-to-text directly to your clipboard for rapid typing anywhere.",
            icon: "mic.fill",
            isDefault: true,
            activeMode: "dictation",
            dictationFormatStyle: "raw",
            whisperModel: "tiny",
            keepModelInMemory: true,
            enableAutoCompletion: false,
            tags: ["dictation"]
        ),

        DictyProfile(
            name: "Code & Architecture",
            description: "Autonomous documentation assistant that records voice, queries your connected workspace, and writes structured documentation directly to your target knowledge base.",
            icon: "terminal.fill",
            isDefault: false,
            activeMode: "librarian",
            dictationFormatStyle: "punctuation_fast",
            whisperModel: "tiny",
            keepModelInMemory: true,
            enableAutoCompletion: false,
            targetSystem: "obsidian",
            tags: ["architecture", "dev"]
        ),
        DictyProfile(
            name: "Meeting Assistant",
            description: "Continuous discussion recording with speaker detection, structured summaries, and action item extraction.",
            icon: "person.2.fill",
            isDefault: false,
            activeMode: "meeting",
            dictationFormatStyle: "dialogue_structured",
            whisperModel: "tiny",
            keepModelInMemory: true,
            enableAutoCompletion: false,
            enableDiarization: false,
            diarizationModel: "openai/gpt-4o-mini",
            speakerSeparation: "you_others",
            speakerYouLabel: "You",
            meetingShowTimestamps: false,
            muteMicrophone: false,
            tags: ["meeting", "sync"]
        ),
        DictyProfile(
            name: "Focused App Meeting",
            description: "Records your microphone AND audio from a specific application (Zoom, Meet, Slack Huddle) simultaneously.",
            icon: "app.connected.to.app.below.fill",
            isDefault: false,
            activeMode: "focused_meeting",
            dictationFormatStyle: "dialogue_structured",
            whisperModel: "tiny",
            keepModelInMemory: true,
            enableAutoCompletion: false,
            enableDiarization: false,
            diarizationModel: "openai/gpt-4o-mini",
            speakerSeparation: "you_others",
            speakerYouLabel: "You",
            meetingShowTimestamps: false,
            muteMicrophone: false,
            tags: ["meeting", "app"]
        ),
        DictyProfile(
            name: "Prose & Book Writing",
            description: "Formatted continuous dictation into publication-ready book text with automatic paragraph indents, quotes, and punctuation cues.",
            icon: "book.fill",
            isDefault: false,
            activeMode: "dictation",
            dictationFormatStyle: "book",
            whisperModel: "tiny",
            keepModelInMemory: true,
            enableAutoCompletion: false,
            tags: ["book", "draft"]
        )
    ]
    
    private init() {
        loadProfiles()
    }
    
    func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: profilesStorageKey),
           let decoded = try? JSONDecoder().decode([DictyProfile].self, from: data),
           !decoded.isEmpty {
            var updated = decoded
            var didSanitize = false
            for i in 0..<updated.count {
                if updated[i].whisperModel.contains("mlx-community") || updated[i].whisperModel.isEmpty {
                    updated[i].whisperModel = "tiny"
                    didSanitize = true
                }
            }
            self.profiles = updated
            if didSanitize {
                saveProfiles()
            }
        } else {
            // Seed 5 default modes
            self.profiles = Self.defaultProfiles
            saveProfiles()
        }
        
        if let storedIdStr = UserDefaults.standard.string(forKey: activeProfileIdKey),
           let storedId = UUID(uuidString: storedIdStr),
           profiles.contains(where: { $0.id == storedId }) {
            self.activeProfileId = storedId
        } else if let first = profiles.first {
            self.activeProfileId = first.id
            UserDefaults.standard.set(first.id.uuidString, forKey: activeProfileIdKey)
        }
    }
    
    func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: profilesStorageKey)
        }
    }
    
    func resetToDefaults(engine: EngineClient? = nil) {
        self.profiles = Self.defaultProfiles
        saveProfiles()
        if let first = profiles.first {
            switchProfile(to: first.id, engine: engine)
        }
    }
    
    func switchProfile(to id: UUID, engine: EngineClient? = nil) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        self.activeProfileId = id
        UserDefaults.standard.set(id.uuidString, forKey: activeProfileIdKey)
        
        if let engine = engine {
            engine.manualOverrideActive = true
            let mode = profile.activeMode == "dictation" ? (profile.dictationFormatStyle == "raw" ? "dictation" : profile.dictationFormatStyle) : profile.activeMode
            if engine.currentResolvedMode != mode { engine.currentResolvedMode = mode }
            if engine.currentResolvedReason != "manual_override" { engine.currentResolvedReason = "manual_override" }
        }
        
        // Apply settings directly to UserDefaults and EngineClient
        UserDefaults.standard.set(profile.activeMode, forKey: "activeMode")
        UserDefaults.standard.set(profile.dictationFormatStyle, forKey: "dictationFormatStyle")
        UserDefaults.standard.set(profile.targetSystem, forKey: "targetSystem")
        
        // Advanced model & recognition settings
        UserDefaults.standard.set(profile.keepModelInMemory, forKey: "keepModelInMemory")
        UserDefaults.standard.set(profile.enableAutoCompletion, forKey: "enableAutoCompletion")
        UserDefaults.standard.set(profile.translateToEnglish, forKey: "translateToEnglish")
        UserDefaults.standard.set(profile.language, forKey: "transcriptionLanguage")
        UserDefaults.standard.set(profile.translationMethod, forKey: "translationMethod")
        UserDefaults.standard.set(profile.targetLanguage, forKey: "targetLanguage")
        UserDefaults.standard.set(profile.selectedTranslationModel, forKey: "selectedTranslationModel")
        
        if !profile.llmModel.isEmpty {
            UserDefaults.standard.set(profile.llmModel, forKey: "llmModel")
        }
        if !profile.llmProvider.isEmpty && profile.llmProvider != "openrouter" {
            UserDefaults.standard.set(profile.llmProvider, forKey: "llmProvider")
        }
        
        if profile.activeMode == "librarian" {
            if !profile.obsidianPath.isEmpty {
                UserDefaults.standard.set(profile.obsidianPath, forKey: "obsidianPath")
            } else if let central = UserDefaults.standard.string(forKey: "obsidianPath"), !central.isEmpty {
                if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
                    profiles[idx].obsidianPath = central
                    saveProfiles()
                }
            }
        }
        if !profile.confluenceSpace.isEmpty {
            UserDefaults.standard.set(profile.confluenceSpace, forKey: "confluenceSpace")
        }
        if !profile.confluencePageTitle.isEmpty {
            UserDefaults.standard.set(profile.confluencePageTitle, forKey: "confluencePageTitle")
        }
        if !profile.selectedGitHubRepo.isEmpty {
            UserDefaults.standard.set(profile.selectedGitHubRepo, forKey: "selectedGitHubRepo")
        }
        if !profile.selectedGitHubBranch.isEmpty {
            UserDefaults.standard.set(profile.selectedGitHubBranch, forKey: "selectedGitHubBranch")
        }
        UserDefaults.standard.set(profile.muteMicrophone, forKey: "muteMicrophone")
        UserDefaults.standard.set(profile.enableSelfCorrection, forKey: "enableSelfCorrection")
        
        if let engine = engine {
            engine.activeMode = profile.activeMode
            engine.dictationFormatStyle = profile.dictationFormatStyle
            engine.keepModelInMemory = profile.keepModelInMemory
            engine.enableAutoCompletion = profile.enableAutoCompletion
            engine.translateToEnglish = profile.translateToEnglish
            engine.isMicMuted = profile.muteMicrophone
            engine.enableSelfCorrection = profile.enableSelfCorrection
            engine.selfCorrectionModel = profile.selfCorrectionModel
            if !profile.language.isEmpty {
                engine.transcriptionLanguage = profile.language
            }
            if !profile.translationMethod.isEmpty {
                engine.translationMethod = profile.translationMethod
            }
            if !profile.targetLanguage.isEmpty {
                engine.targetLanguage = profile.targetLanguage
            }
            if !profile.selectedTranslationModel.isEmpty {
                engine.selectedTranslationModel = profile.selectedTranslationModel
            }
            
            // Switch Whisper voice model if specified for this mode
            if !profile.whisperModel.isEmpty && profile.whisperModel != engine.activeModel {
                engine.setActiveModel(id: profile.whisperModel)
            }
            
            engine.updateMemoryMode()
        }
        
        TelemetryClient.shared.track("profile_switched", properties: [
            "profile_name": profile.name,
            "mode": profile.activeMode,
            "format_style": profile.dictationFormatStyle,
            "whisper_model": profile.whisperModel,
            "keep_in_ram": profile.keepModelInMemory,
            "auto_completion": profile.enableAutoCompletion,
            "mute_microphone": profile.muteMicrophone
        ])
    }
    
    /// Updates the active profile's model library settings when the user changes them in ModelsLibraryView
    func updateActiveProfileModels(
        whisperModel: String? = nil,
        llmModel: String? = nil,
        llmProvider: String? = nil,
        language: String? = nil,
        translateToEnglish: Bool? = nil,
        translationMethod: String? = nil,
        targetLanguage: String? = nil,
        selectedTranslationModel: String? = nil,
        keepModelInMemory: Bool? = nil,
        enableAutoCompletion: Bool? = nil,
        targetSystem: String? = nil,
        obsidianPath: String? = nil,
        muteMicrophone: Bool? = nil,
        enableSelfCorrection: Bool? = nil
    ) {
        guard let idx = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        
        if let wm = whisperModel, !wm.isEmpty {
            profiles[idx].whisperModel = wm
        }
        if let lm = llmModel {
            profiles[idx].llmModel = lm
        }
        if let lp = llmProvider {
            profiles[idx].llmProvider = lp
        }
        if let lang = language {
            profiles[idx].language = lang
        }
        if let tte = translateToEnglish {
            profiles[idx].translateToEnglish = tte
        }
        if let tm = translationMethod {
            profiles[idx].translationMethod = tm
        }
        if let tl = targetLanguage {
            profiles[idx].targetLanguage = tl
        }
        if let stm = selectedTranslationModel {
            profiles[idx].selectedTranslationModel = stm
        }
        if let km = keepModelInMemory {
            profiles[idx].keepModelInMemory = km
        }
        if let ac = enableAutoCompletion {
            profiles[idx].enableAutoCompletion = ac
        }
        if let mm = muteMicrophone {
            profiles[idx].muteMicrophone = mm
            UserDefaults.standard.set(mm, forKey: "muteMicrophone")
        }
        if let ac = enableSelfCorrection {
            profiles[idx].enableSelfCorrection = ac
        }
        if let ts = targetSystem, !ts.isEmpty {
            profiles[idx].targetSystem = ts
            UserDefaults.standard.set(ts, forKey: "targetSystem")
        }
        if let op = obsidianPath {
            profiles[idx].obsidianPath = op
            UserDefaults.standard.set(op, forKey: "obsidianPath")
        }
        
        saveProfiles()
    }
    
    /// Sets the primary transcription language and model across profiles (useful during onboarding)
    func setGlobalLanguageAndModel(language: String, whisperModel: String) {
        for i in 0..<profiles.count {
            profiles[i].language = language
            if !whisperModel.isEmpty {
                profiles[i].whisperModel = whisperModel
            }
        }
        saveProfiles()
    }
    
    func createProfile(name: String, description: String = "", icon: String = "folder.fill", template: DictyProfile? = nil) -> DictyProfile {
        var newProfile = template ?? DictyProfile(name: name, description: description, icon: icon)
        newProfile.id = UUID()
        newProfile.name = name.isEmpty ? "New Mode" : name
        newProfile.description = description
        newProfile.icon = icon
        newProfile.isDefault = false
        newProfile.enableSelfCorrection = true
        
        profiles.append(newProfile)
        saveProfiles()
        
        TelemetryClient.shared.track("profile_created", properties: [
            "icon": newProfile.icon
        ])
        
        return newProfile
    }
    
    func updateProfile(_ profile: DictyProfile, engine: EngineClient? = nil) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
            saveProfiles()
            
            // If updating currently active profile, apply changes immediately
            if activeProfileId == profile.id {
                switchProfile(to: profile.id, engine: engine)
            }
        }
    }
    
    func deleteProfile(id: UUID, engine: EngineClient? = nil) {
        guard profiles.count > 1 else { return } // Keep at least one profile
        profiles.removeAll(where: { $0.id == id })
        saveProfiles()
        
        if activeProfileId == id, let first = profiles.first {
            switchProfile(to: first.id, engine: engine)
        }
    }
    
    func duplicateProfile(id: UUID) -> DictyProfile? {
        guard let source = profiles.first(where: { $0.id == id }) else { return nil }
        var dup = source
        dup.id = UUID()
        dup.name = "\(source.name) (Copy)"
        dup.isDefault = false
        profiles.append(dup)
        saveProfiles()
        return dup
    }
}
