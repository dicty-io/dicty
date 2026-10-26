import Foundation

public struct DictyProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String
    public var icon: String
    public var isDefault: Bool
    
    // AI & Formatting Mode
    public var activeMode: String
    public var dictationFormatStyle: String
    public var customPrompt: String
    public var llmModel: String
    public var llmProvider: String
    
    // Voice Recognition & Models Library State (Per-Mode Configuration)
    public var whisperModel: String
    public var language: String
    public var translateToEnglish: Bool
    public var translationMethod: String
    public var targetLanguage: String
    public var selectedTranslationModel: String
    public var keepModelInMemory: Bool
    public var enableAutoCompletion: Bool
    public var enableDiarization: Bool
    public var diarizationModel: String
    public var speakerSeparation: String
    public var speakerYouLabel: String
    public var meetingShowTimestamps: Bool
    public var muteMicrophone: Bool
    public var enableSelfCorrection: Bool
    public var selfCorrectionModel: String
    
    // Workspace & Knowledge Base Targets
    public var targetSystem: String
    public var obsidianPath: String
    public var confluenceSpace: String
    public var confluencePageTitle: String
    public var selectedGitHubRepo: String
    public var selectedGitHubBranch: String
    public var gitProvider: String
    public var gitlabHost: String
    public var selectedGitLabRepo: String
    public var tags: [String]
    
    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        icon: String = "folder.fill",
        isDefault: Bool = false,
        activeMode: String = "dictation",
        dictationFormatStyle: String = "raw",
        customPrompt: String = "",
        llmModel: String = "",
        llmProvider: String = "",
        whisperModel: String = "",
        language: String = "auto",
        translateToEnglish: Bool = false,
        translationMethod: String = "none",
        targetLanguage: String = "none",
        selectedTranslationModel: String = "",
        keepModelInMemory: Bool = true,
        enableAutoCompletion: Bool = false,
        enableDiarization: Bool = false,
        diarizationModel: String = "openai/gpt-4o-mini",
        speakerSeparation: String = "you_others",
        speakerYouLabel: String = "You",
meetingShowTimestamps: Bool = false,
         muteMicrophone: Bool = false,
         enableSelfCorrection: Bool = true,
         selfCorrectionModel: String = "",
         targetSystem: String = "obsidian",
        obsidianPath: String = "",
        confluenceSpace: String = "",
        confluencePageTitle: String = "",
        selectedGitHubRepo: String = "",
        selectedGitHubBranch: String = "",
        gitProvider: String = "github",
        gitlabHost: String = "https://gitlab.com",
        selectedGitLabRepo: String = "",
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.isDefault = isDefault
        self.activeMode = activeMode
        self.dictationFormatStyle = dictationFormatStyle
        self.customPrompt = customPrompt
        self.llmModel = llmModel
        self.llmProvider = llmProvider
        self.whisperModel = whisperModel
        self.language = language
        self.translateToEnglish = translateToEnglish
        self.translationMethod = translationMethod
        self.targetLanguage = targetLanguage
        self.selectedTranslationModel = selectedTranslationModel
        self.keepModelInMemory = keepModelInMemory
        self.enableAutoCompletion = enableAutoCompletion
        self.enableDiarization = enableDiarization
        self.diarizationModel = diarizationModel
        self.speakerSeparation = speakerSeparation
        self.speakerYouLabel = speakerYouLabel
        self.meetingShowTimestamps = meetingShowTimestamps
        self.muteMicrophone = muteMicrophone
        self.enableSelfCorrection = enableSelfCorrection
        self.selfCorrectionModel = selfCorrectionModel
        self.targetSystem = targetSystem
        self.obsidianPath = obsidianPath
        self.confluenceSpace = confluenceSpace
        self.confluencePageTitle = confluencePageTitle
        self.selectedGitHubRepo = selectedGitHubRepo
        self.selectedGitHubBranch = selectedGitHubBranch
        self.gitProvider = gitProvider
        self.gitlabHost = gitlabHost
        self.selectedGitLabRepo = selectedGitLabRepo
        self.tags = tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Default Profile"
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "folder.fill"
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        activeMode = try container.decodeIfPresent(String.self, forKey: .activeMode) ?? "dictation"
        dictationFormatStyle = try container.decodeIfPresent(String.self, forKey: .dictationFormatStyle) ?? "raw"
        customPrompt = try container.decodeIfPresent(String.self, forKey: .customPrompt) ?? ""
        llmModel = try container.decodeIfPresent(String.self, forKey: .llmModel) ?? ""
        llmProvider = try container.decodeIfPresent(String.self, forKey: .llmProvider) ?? "openrouter"
        whisperModel = try container.decodeIfPresent(String.self, forKey: .whisperModel) ?? "tiny"
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        translateToEnglish = try container.decodeIfPresent(Bool.self, forKey: .translateToEnglish) ?? false
        translationMethod = try container.decodeIfPresent(String.self, forKey: .translationMethod) ?? "none"
        targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "none"
        selectedTranslationModel = try container.decodeIfPresent(String.self, forKey: .selectedTranslationModel) ?? ""
        keepModelInMemory = try container.decodeIfPresent(Bool.self, forKey: .keepModelInMemory) ?? true
        enableAutoCompletion = try container.decodeIfPresent(Bool.self, forKey: .enableAutoCompletion) ?? false
        enableDiarization = try container.decodeIfPresent(Bool.self, forKey: .enableDiarization) ?? false
        diarizationModel = try container.decodeIfPresent(String.self, forKey: .diarizationModel) ?? "openai/gpt-4o-mini"
        let decodedSep = try container.decodeIfPresent(String.self, forKey: .speakerSeparation)
        if let decodedSep = decodedSep {
            speakerSeparation = (decodedSep == "smart_llm") ? "you_others" : decodedSep
        } else {
            speakerSeparation = "you_others"
        }
        speakerYouLabel = try container.decodeIfPresent(String.self, forKey: .speakerYouLabel) ?? "You"
        meetingShowTimestamps = try container.decodeIfPresent(Bool.self, forKey: .meetingShowTimestamps) ?? false
        muteMicrophone = try container.decodeIfPresent(Bool.self, forKey: .muteMicrophone) ?? false
        enableSelfCorrection = try container.decodeIfPresent(Bool.self, forKey: .enableSelfCorrection) ?? false
        selfCorrectionModel = try container.decodeIfPresent(String.self, forKey: .selfCorrectionModel) ?? ""
        targetSystem = try container.decodeIfPresent(String.self, forKey: .targetSystem) ?? "obsidian"
        obsidianPath = try container.decodeIfPresent(String.self, forKey: .obsidianPath) ?? ""
        confluenceSpace = try container.decodeIfPresent(String.self, forKey: .confluenceSpace) ?? ""
        confluencePageTitle = try container.decodeIfPresent(String.self, forKey: .confluencePageTitle) ?? ""
        selectedGitHubRepo = try container.decodeIfPresent(String.self, forKey: .selectedGitHubRepo) ?? ""
        selectedGitHubBranch = try container.decodeIfPresent(String.self, forKey: .selectedGitHubBranch) ?? ""
        gitProvider = try container.decodeIfPresent(String.self, forKey: .gitProvider) ?? "github"
        gitlabHost = try container.decodeIfPresent(String.self, forKey: .gitlabHost) ?? "https://gitlab.com"
        selectedGitLabRepo = try container.decodeIfPresent(String.self, forKey: .selectedGitLabRepo) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}
