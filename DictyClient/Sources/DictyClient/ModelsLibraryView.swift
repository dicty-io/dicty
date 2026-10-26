import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation


// MARK: - Unit-testable Model Language Filter
struct ModelLanguageFilter {
    static func isEnglish(_ languageCode: String) -> Bool {
        languageCode == "en" || languageCode.hasPrefix("en-")
    }

    static func isEnglish(languageCode: String) -> Bool {
        isEnglish(languageCode)
    }

    static func isModelFamilyVisible(_ family: ModelFamily, for languageCode: String) -> Bool {
        isModelFamilyVisible(familyId: family.id, languageCode: languageCode)
    }

    static func isModelFamilyVisible(familyId: String, languageCode: String) -> Bool {
        if familyId == "distil-turbo" {
            return isEnglish(languageCode)
        }
        return true
    }

    static func visibleFamilies(from families: [ModelFamily], languageCode: String) -> [ModelFamily] {
        families.filter { isModelFamilyVisible(familyId: $0.id, languageCode: languageCode) }
    }

    static func checkLanguageSwitchFallback(from oldLanguage: String? = nil, to newLanguage: String, activeModelId: String) -> (fallbackModelId: String, noticeMessage: String)? {
        let isEng = isEnglish(newLanguage)
        if !isEng && (activeModelId == "distil-large-v3" || activeModelId.contains("distil")) {
            return ("large-v3-turbo", "Switched to Turbo because Turbo (Distil) only supports English.")
        }
        return nil
    }

    static func checkLanguageSwitchFallback(activeModelId: String, newLanguage: String) -> (fallbackId: String, notice: String)? {
        guard let res = checkLanguageSwitchFallback(from: nil, to: newLanguage, activeModelId: activeModelId) else { return nil }
        return (fallbackId: res.fallbackModelId, notice: res.noticeMessage)
    }
}

struct ModelsLibraryView: View {
    @EnvironmentObject var engineClient: EngineClient
    @State private var searchText = ""
    @State private var showOpenRouterExplorer = false
    @State private var showAllCloudTextModels = false
    @State private var inspectedModel: DictyModel? = nil
    @State private var showSpokenLanguagePicker = false
    @AppStorage("lastCloudTextModel") private var lastCloudTextModel: String = ""
    @AppStorage("isAdvancedSettingsExpanded") private var isAdvancedSettingsExpanded: Bool = false
    @AppStorage("showAllModelVariants") private var showAllModelVariants: Bool = false
    @AppStorage("llmModel") private var llmModel: String = ""
    @AppStorage("llmProvider") private var llmProvider: String = "openrouter"
    @AppStorage("translationMethod") private var translationMethod: String = "none"
    @AppStorage("selectedTranslationModel") private var selectedTranslationModel: String = ""
    
    @State private var languageSwitchNotice: String? = nil
    @StateObject private var modesStore = ModesStore()
    @State private var chooseModelsExpanded: Bool = false
    @State private var didInitChooseModels = false
    @AppStorage("hasCustomizedModel") private var hasCustomizedModel: Bool = false
    @AppStorage("modelsScrollToLocalText") private var scrollToLocalText: Bool = false
    @State private var isHoveringFolder: Bool = false
    
    var isEnglishLanguage: Bool {
        ModelLanguageFilter.isEnglish(languageCode: engineClient.transcriptionLanguage)
    }

    var filteredModels: [DictyModel] {
        if searchText.isEmpty {
            return engineClient.models
        } else {
            return engineClient.models.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    // Standard model families
    static let standardFamilies: [ModelFamily] = [
        ModelFamily(id: "nano", name: "Nano", bestFor: "Quick notes, any Mac", enModelId: "tiny.en", multiModelId: "tiny"),
        ModelFamily(id: "base", name: "Base", bestFor: "Everyday use, older Macs", enModelId: "base.en", multiModelId: "base"),
        ModelFamily(id: "fast", name: "Fast", bestFor: "Everyday dictation", enModelId: "small.en", multiModelId: "small"),
        ModelFamily(id: "pro", name: "Pro", bestFor: "Long or technical speech", enModelId: "medium.en", multiModelId: "medium"),
        ModelFamily(id: "distil-turbo", name: "Turbo (Distil)", bestFor: "Fast high-accuracy English", enModelId: "distil-large-v3", multiModelId: nil),
        ModelFamily(id: "turbo", name: "Turbo", bestFor: "Best quality on fast Macs", enModelId: nil, multiModelId: "large-v3-turbo"),
        ModelFamily(id: "max", name: "Max", bestFor: "Hardest audio, slowest", enModelId: nil, multiModelId: "large-v3")
    ]

    var filteredFamilies: [ModelFamily] {
        let families = ModelLanguageFilter.visibleFamilies(from: Self.standardFamilies, languageCode: engineClient.transcriptionLanguage)
        if searchText.isEmpty {
            return families
        }
        return families.filter { fam in
            fam.name.localizedCaseInsensitiveContains(searchText) || fam.bestFor.localizedCaseInsensitiveContains(searchText)
        }
    }

    // Language-specific models: only show when language matches
    var languageSpecificModels: [DictyModel] {
        let lang = engineClient.transcriptionLanguage
        var targetId: String? = nil
        if lang == "ja" {
            targetId = "large-v3-turbo-ja"
        } else if lang == "zh" {
            targetId = "large-v2-zh"
        } else if lang == "fr" {
            targetId = "large-v2-french"
        }
        guard let id = targetId else { return [] }
        return filteredModels.filter { $0.id == id }
    }

    var languageSpecificGroupName: String {
        switch engineClient.transcriptionLanguage {
        case "ja": return "Made for Japanese"
        case "zh": return "Made for Chinese"
        case "fr": return "Made for French"
        default: return "Language-Specific"
        }
    }

    // Translation capable text models based on the selected method
    var translationCapableModels: [DictyModel] {
        var baseModels = translationMethod == "cloud" ? cloudTextModels : localTextModels
        baseModels = baseModels.filter { $0.supports_translation == true }
        
        // If an active custom cloud model is selected that isn't in the default list, include it!
        if translationMethod == "cloud" && !llmModel.isEmpty && !baseModels.contains(where: { $0.id == llmModel }) && !localTextModels.contains(where: { $0.id == llmModel }) {
            let customModel = DictyModel(
                id: llmModel,
                name: "\(llmModel) (Custom Active)",
                size: "Cloud",
                speed: 1.0,
                accuracy: 0.99,
                is_downloaded: false,
                is_cloud: true,
                category: "text",
                description: "Custom OpenRouter model",
                supports_translation: true
            )
            baseModels.insert(customModel, at: 0)
        }
        
        // If selectedTranslationModel is a custom model not in the list, include it too!
        if translationMethod == "cloud" && !selectedTranslationModel.isEmpty && !baseModels.contains(where: { $0.id == selectedTranslationModel }) && !localTextModels.contains(where: { $0.id == selectedTranslationModel }) {
            let customSelModel = DictyModel(
                id: selectedTranslationModel,
                name: "\(selectedTranslationModel) (Custom)",
                size: "Cloud",
                speed: 1.0,
                accuracy: 0.99,
                is_downloaded: false,
                is_cloud: true,
                category: "text",
                description: "Custom OpenRouter translation model",
                supports_translation: true
            )
            baseModels.insert(customSelModel, at: 0)
        }
        
        return baseModels
    }

    var localVoiceModels: [DictyModel] {
        filteredModels.filter { $0.is_cloud != true && !$0.isTextModel }
            .sorted { a, b in
                let aFav = engineClient.isFavorite(id: a.id)
                let bFav = engineClient.isFavorite(id: b.id)
                if aFav != bFav { return aFav }
                let aSize = a.sizeInMB
                let bSize = b.sizeInMB
                if aSize != bSize { return aSize < bSize }
                let aIsEn = a.id.hasSuffix(".en") || a.id == "distil-large-v3"
                let bIsEn = b.id.hasSuffix(".en") || b.id == "distil-large-v3"
                if aIsEn != bIsEn { return aIsEn }
                return a.id < b.id
            }
    }

    var cloudVoiceModels: [DictyModel] {
        filteredModels.filter { $0.is_cloud == true && !$0.isTextModel }
            .sorted { a, b in
                let aFav = engineClient.isFavorite(id: a.id)
                let bFav = engineClient.isFavorite(id: b.id)
                if aFav != bFav { return aFav }
                return a.id < b.id
            }
    }

    var localTextModels: [DictyModel] {
        filteredModels.filter { $0.is_cloud != true && $0.isTextModel }
            .sorted { a, b in
                let aFav = engineClient.isFavorite(id: a.id)
                let bFav = engineClient.isFavorite(id: b.id)
                if aFav != bFav { return aFav }
                let aSize = a.sizeInMB
                let bSize = b.sizeInMB
                if aSize != bSize { return aSize < bSize }
                return a.id < b.id
            }
    }

    var cloudTextModels: [DictyModel] {
        filteredModels.filter { $0.is_cloud == true && $0.isTextModel }
            .sorted { a, b in
                let aFav = engineClient.isFavorite(id: a.id)
                let bFav = engineClient.isFavorite(id: b.id)
                if aFav != bFav { return aFav }
                return a.id < b.id
            }
    }

    static var whisperLanguages: [(name: String, code: String)] {
        LanguageCatalog.allLanguages.map { ($0.displayName, $0.code) }
    }
    
    static var targetLanguages: [(name: String, code: String)] {
        [("Same as Spoken", "none")] + LanguageCatalog.allLanguages.map { ($0.displayName, $0.code) }
    }
    
    private var currentTargetLangName: String {
        if engineClient.targetLanguage == "none" || engineClient.targetLanguage.isEmpty {
            return "Same as Spoken"
        }
        return Self.targetLanguages.first(where: { $0.code == engineClient.targetLanguage })?.name ?? engineClient.targetLanguage.uppercased()
    }
    
    private var isEnglishOnly: Bool {
        engineClient.activeModel.hasSuffix(".en") || engineClient.activeModel == "distil-large-v3"
    }
    
    private var currentLangName: String {
        LanguageCatalog.displayName(for: engineClient.transcriptionLanguage)
    }

    var canUseDictyCloud: Bool {
        engineClient.isLoggedIn && (engineClient.isPro || engineClient.computeBalance > 0)
    }

    enum ModelAvailability {
        case usable
        case needsKey(providerName: String)
        case signIn
    }

    func checkModelAvailability(_ model: DictyModel) -> ModelAvailability {
        guard model.is_cloud == true else { return .usable }

        // Speech-to-text cloud models:
        if !model.isTextModel {
            let id = model.id.lowercased()
            if id.contains("deepgram") {
                let hasKey = !(SecretsManager.readSecret(forKey: "deepgramApiKey") ?? "").isEmpty
                return (engineClient.isLoggedIn || hasKey) ? .usable : (engineClient.isLoggedIn ? .usable : .needsKey(providerName: "Deepgram"))
            } else if id.contains("groq") {
                let hasKey = !(SecretsManager.readSecret(forKey: "groqApiKey") ?? "").isEmpty
                return (engineClient.isLoggedIn || hasKey) ? .usable : (engineClient.isLoggedIn ? .usable : .needsKey(providerName: "Groq"))
            } else if id.contains("elevenlabs") {
                let hasKey = !(SecretsManager.readSecret(forKey: "elevenlabsApiKey") ?? "").isEmpty
                return (engineClient.isLoggedIn || hasKey) ? .usable : (engineClient.isLoggedIn ? .usable : .needsKey(providerName: "ElevenLabs"))
            } else if id.contains("openai") {
                let hasKey = !(SecretsManager.readSecret(forKey: "openaiApiKey") ?? "").isEmpty
                return (engineClient.isLoggedIn || hasKey) ? .usable : (engineClient.isLoggedIn ? .usable : .needsKey(providerName: "OpenAI"))
            } else {
                // Nvidia Parakeet or Dicty Cloud hosted
                return engineClient.isLoggedIn ? .usable : .signIn
            }
        }

        // Text models (cloud):
        if llmProvider == "local" {
            return .usable
        }
        let hasOpenRouter = !(SecretsManager.readSecret(forKey: "llmApiKey") ?? "").isEmpty
        if engineClient.isLoggedIn || hasOpenRouter {
            return .usable
        }
        return .needsKey(providerName: "OpenRouter")
    }

    var cloudVoiceModelsNeedSignIn: Bool {
        guard !engineClient.isLoggedIn else { return false }
        return cloudVoiceModels.contains { model in
            if case .signIn = checkModelAvailability(model) { return true }
            return false
        }
    }

    var cloudTextModelsNeedSignIn: Bool {
        guard !engineClient.isLoggedIn else { return false }
        let hasOpenRouter = !(SecretsManager.readSecret(forKey: "llmApiKey") ?? "").isEmpty
        return !hasOpenRouter && llmProvider != "local"
    }

    private func handleLanguageVariantAutoSwitch(newLanguage: String) {
        let activeId = engineClient.activeModel
        if let fallback = ModelLanguageFilter.checkLanguageSwitchFallback(activeModelId: activeId, newLanguage: newLanguage) {
            engineClient.setActiveModel(id: fallback.fallbackId)
            withAnimation {
                languageSwitchNotice = fallback.notice
            }
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    withAnimation {
                        if languageSwitchNotice == fallback.notice {
                            languageSwitchNotice = nil
                        }
                    }
                }
            }
            return
        }

        guard let family = Self.standardFamilies.first(where: { fam in
            fam.enModelId == activeId || fam.multiModelId == activeId
        }) else { return }

        let preferredVariant = family.preferredVariant(for: newLanguage, models: engineClient.models)
        if let targetVariant = preferredVariant, targetVariant.id != activeId, (targetVariant.is_downloaded ?? false) {
            engineClient.setActiveModel(id: targetVariant.id)
        }
    }
    
    private var languageBarContent: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 6) {
                Text("Language:")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundColor(.secondary)
                
                Text(currentLangName)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
            }
            
            Button(action: {
                showSpokenLanguagePicker = true
            }) {
                HStack(spacing: 4) {
                    Text("Change")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.appAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.appAccent.opacity(0.12))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(engineClient.transcriptionLanguage == "en"
                  ? "English builds used"
                  : "Multilingual builds used")
            
            Text("—")
                .foregroundColor(.secondary.opacity(0.4))
                .fixedSize()
            
            Text(engineClient.transcriptionLanguage == "en"
                 ? "English builds used"
                 : "Multilingual builds used")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.dictySecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .fixedSize()
    }
    
    @ViewBuilder
    private var dictyCloudHeaderView: some View {
        if engineClient.isLoggedIn {
            HStack(spacing: 6) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 11))
                    .foregroundColor(canUseDictyCloud ? .appAccent : .secondary)
                Text("Dicty Cloud")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                
                Toggle("", isOn: Binding(
                    get: { canUseDictyCloud && llmProvider == "dicty_cloud" },
                    set: { newValue in
                        if newValue {
                            if canUseDictyCloud {
                                llmProvider = "dicty_cloud"
                            }
                        } else {
                            llmProvider = "openrouter"
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                .controlSize(.small)
                .disabled(!canUseDictyCloud)
            }
            .fixedSize()
        } else {
            Button(action: {
                WindowManager.openSettingsWindow(engineClient: engineClient, tabIndex: 11)
            }) {
                Text("Sign In")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.appAccent.opacity(0.12))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }
    
    // MARK: AI location card

    /// The speech and text models Dicty is set to use right now.
    var modelsInUse: [DictyModel] {
        var list: [DictyModel] = []
        if let speech = engineClient.models.first(where: { $0.id == engineClient.activeModel }) {
            list.append(speech)
        }
        if !llmModel.isEmpty, let text = engineClient.models.first(where: { $0.id == llmModel }) {
            list.append(text)
        }
        return list
    }

    var chooseModelsHeader: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.18)) {
                chooseModelsExpanded.toggle()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.dictySecondary)
                    .rotationEffect(.degrees(chooseModelsExpanded ? 90 : 0))
                Text("Choose models yourself")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Title and Controls
            HStack(alignment: .center, spacing: 10) {
                Text("Available Models")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
                
                FeatureHelpButton(topic: .models)
                
                Spacer(minLength: 16)
                
                Button(action: {
                    engineClient.openModelsFolder()
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(isHoveringFolder ? .primary : .secondary)
                        .padding(4)
                        .background(isHoveringFolder ? Color.primary.opacity(0.08) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringFolder = $0 }
                .help("Open models folder")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            // Secondary Bar: Language on left, Dicty Cloud status on right
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    languageBarContent
                    Spacer(minLength: 12)
                    dictyCloudHeaderView
                }
                VStack(alignment: .leading, spacing: 6) {
                    languageBarContent
                    HStack {
                        Spacer()
                        dictyCloudHeaderView
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            
            if let notice = languageSwitchNotice {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.appAccent)
                    Text(notice)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Button(action: { withAnimation { languageSwitchNotice = nil } }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.appAccent.opacity(0.12))
                .cornerRadius(8)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
            
            Divider()
            
            // Models List
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                    AILocationCard(store: modesStore, modelsInUse: modelsInUse, onExpandCustom: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            chooseModelsExpanded = true
                        }
                    })
                    
                    chooseModelsHeader
                    
                    if chooseModelsExpanded {
                    // 1. SPEECH TO TEXT — ON YOUR MAC
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Speech to text — on your Mac")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        
                        // Language-specific models if available
                        if !showAllModelVariants && !languageSpecificModels.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(languageSpecificGroupName)
                                        .font(.system(.caption, design: .rounded).weight(.bold))
                                        .foregroundColor(.appAccent)
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10))
                                        .foregroundColor(.appAccent)
                                }
                                .padding(.horizontal, 8)
                                .padding(.top, 4)
                                
                                ModelsTableHeaderRow()
                                
                                ForEach(languageSpecificModels) { model in
                                    UnifiedModelRowView(
                                        model: model,
                                        isActive: engineClient.activeModel == model.id,
                                        onActivate: { hasCustomizedModel = true; engineClient.setActiveModel(id: model.id) }
                                    )
                                }
                            }
                            .padding(.bottom, 6)
                        }
                        
                        ModelsTableHeaderRow()
                        
                        if showAllModelVariants {
                            ForEach(localVoiceModels) { model in
                                UnifiedModelRowView(
                                    model: model,
                                    isActive: engineClient.activeModel == model.id,
                                    onActivate: { hasCustomizedModel = true; engineClient.setActiveModel(id: model.id) }
                                )
                            }
                        } else {
                            ForEach(filteredFamilies) { family in
                                ModelFamilyCardView(
                                    family: family,
                                    models: engineClient.models
                                )
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    
                    // 2. SPEECH TO TEXT — CLOUD
                    if !cloudVoiceModels.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Speech to text — cloud")
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                            
                            ModelsTableHeaderRow(showMetrics: false)
                            
                            ForEach(cloudVoiceModels) { model in
                                UnifiedModelRowView(
                                    model: model,
                                    isActive: engineClient.activeModel == model.id,
                                    onActivate: {
                                        hasCustomizedModel = true
                                        if engineClient.canUseCloud {
                                            engineClient.setActiveModel(id: model.id)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.02))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    }
                    
                    // 3. TEXT MODELS — ON YOUR MAC
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Text models — on your Mac")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        
                        ModelsTableHeaderRow()
                        
                        ForEach(localTextModels) { model in
                            let isModelActive = (llmProvider == "local" || modesStore.capabilities?.aiLocation == "local") &&
                                (engineClient.activeTextModel == model.id || (engineClient.activeTextModel.isEmpty && model.id == "qwen2.5-1.5b-instruct"))
                            UnifiedModelRowView(
                                model: model,
                                isActive: isModelActive,
                                onActivate: {
                                    hasCustomizedModel = true
                                    llmModel = model.id
                                    llmProvider = "local"
                                    engineClient.setActiveTextModel(id: model.id)
                                }
                            )
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    .id("local_text_models_section")
                    
                    // 4. TEXT MODELS — CLOUD
                    if !cloudTextModels.isEmpty || (!llmModel.isEmpty && llmProvider != "local" && llmModel.contains("/")) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Text models — cloud")
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .foregroundColor(.primary)
                                Spacer()
                                Button(action: {
                                    showOpenRouterExplorer = true
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("Explore 400+ Models")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.06))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                            
                            ModelsTableHeaderRow(showMetrics: false)
                            
                            let displayCloudModels: [DictyModel] = {
                                var list = cloudTextModels.filter { $0.is_cloud == true }
                                if !llmModel.isEmpty &&
                                    llmProvider != "local" &&
                                    !llmModel.hasSuffix(".gguf") &&
                                    llmModel.contains("/") &&
                                    !list.contains(where: { $0.id == llmModel }) &&
                                    !localTextModels.contains(where: { $0.id == llmModel }) {
                                    let customActive = DictyModel(
                                        id: llmModel,
                                        name: ProjectsView.friendlyModelName(for: llmModel),
                                        size: "Cloud",
                                        speed: 0.95,
                                        accuracy: 0.99,
                                        is_downloaded: false,
                                        is_cloud: true,
                                        category: "text",
                                        description: "Selected from OpenRouter Catalog",
                                        supports_translation: true
                                    )
                                    list.insert(customActive, at: 0)
                                }
                                if showAllCloudTextModels { return list }
                                let defaultPrefix = Array(list.prefix(4))
                                if let active = list.first(where: { $0.id == llmModel && $0.is_cloud == true }), !defaultPrefix.contains(where: { $0.id == llmModel }) {
                                    return defaultPrefix + [active]
                                }
                                return defaultPrefix
                            }()
                            
                            ForEach(displayCloudModels) { model in
                                let isCloudActive = llmProvider != "local" && modesStore.capabilities?.aiLocation != "local" && llmModel == model.id
                                UnifiedModelRowView(
                                    model: model,
                                    isActive: isCloudActive,
                                    onActivate: {
                                        hasCustomizedModel = true
                                        if engineClient.canUseCloud {
                                            llmModel = model.id
                                            if llmProvider == "dicty_cloud" && !engineClient.isLoggedIn {
                                                llmProvider = "openrouter"
                                            } else if llmProvider == "local" {
                                                llmProvider = "openrouter"
                                            }
                                        }
                                    }
                                )
                            }
                            
                            if cloudTextModels.count > 4 {
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        showAllCloudTextModels.toggle()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Text(showAllCloudTextModels ? "Show Less Models" : "Show More Models")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        Image(systemName: showAllCloudTextModels ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundColor(.dictySecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Color.primary.opacity(0.04))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                                .padding(.horizontal, 8)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.02))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    }


                    
                    // Advanced Model Settings Section (Collapsed / folded by default)
                    VStack(alignment: .leading, spacing: 0) {
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isAdvancedSettingsExpanded.toggle()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.dictySecondary)
                                    .rotationEffect(.degrees(isAdvancedSettingsExpanded ? 90 : 0))
                                
                                Image(systemName: "gearshape.2")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.appAccent)
                                
                                Text("Performance")
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        if isAdvancedSettingsExpanded {
                            Divider().opacity(0.4)
                            
                            HStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "memorychip")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.appAccent)
                                        .frame(width: 18, alignment: .center)
                                    
                                    Text("Keep model in RAM (Fast)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: true, vertical: false)
                                    
                                    InfoSign(text: "Keeps speech recognition ready for instant, zero-delay typing. If turned off, it takes a couple of seconds to warm up before each recording, but saves computer memory.")
                                }
                                
                                Spacer(minLength: 12)
                                
                                Toggle("", isOn: engineClient.$keepModelInMemory)
                                    .labelsHidden()
                                    .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                                    .controlSize(.small)
                                    .onChange(of: engineClient.keepModelInMemory) { _, newValue in
                                        ProfileManager.shared.updateActiveProfileModels(keepModelInMemory: newValue)
                                        engineClient.updateMemoryMode()
                                    }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    } // end chooseModelsExpanded
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .onChange(of: scrollToLocalText) { _, shouldScroll in
                if shouldScroll {
                    chooseModelsExpanded = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            proxy.scrollTo("local_text_models_section", anchor: .top)
                        }
                    }
                }
            }
            .onAppear {
                if scrollToLocalText {
                    chooseModelsExpanded = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            proxy.scrollTo("local_text_models_section", anchor: .top)
                        }
                    }
                }
            }
            }
        }
        .searchable(text: $searchText, prompt: "Search models...")
        // Only animate the search filter change, NOT general state changes that happen during scroll
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: searchText)
        .sheet(isPresented: $showOpenRouterExplorer) {
            OpenRouterModelExplorerSheet(selectedModel: $llmModel)
                .environmentObject(engineClient)
        }
        .sheet(isPresented: $showSpokenLanguagePicker) {
            LanguagePickerSheet(
                mode: .spokenLanguage,
                currentCode: engineClient.transcriptionLanguage
            ) { selectedCode in
                engineClient.transcriptionLanguage = selectedCode
            }
        }
        .onChange(of: llmModel) { _, newModel in
            if !newModel.isEmpty && (newModel.contains("/") || llmProvider != "local") {
                lastCloudTextModel = newModel
            }
            ProfileManager.shared.updateActiveProfileModels(llmModel: newModel)
            if translationMethod == "cloud" && (selectedTranslationModel.isEmpty || !cloudTextModels.contains(where: { $0.id == selectedTranslationModel })) {
                selectedTranslationModel = newModel
            }
        }
        .onChange(of: llmProvider) { _, newProvider in
            ProfileManager.shared.updateActiveProfileModels(llmProvider: newProvider)
        }
        .onChange(of: translationMethod) { _, newMethod in
            ProfileManager.shared.updateActiveProfileModels(translationMethod: newMethod)
            if newMethod == "cloud" && (selectedTranslationModel.isEmpty || selectedTranslationModel == "none") && !llmModel.isEmpty {
                selectedTranslationModel = llmModel
            }
        }
        .onChange(of: selectedTranslationModel) { _, newModel in
            ProfileManager.shared.updateActiveProfileModels(selectedTranslationModel: newModel)
        }
        .onChange(of: engineClient.transcriptionLanguage) { _, newLang in
            ProfileManager.shared.updateActiveProfileModels(language: newLang)
            handleLanguageVariantAutoSwitch(newLanguage: newLang)
        }
        .onChange(of: engineClient.translateToEnglish) { _, newTranslate in
            ProfileManager.shared.updateActiveProfileModels(translateToEnglish: newTranslate)
        }
        .onChange(of: engineClient.targetLanguage) { _, newTarget in
            ProfileManager.shared.updateActiveProfileModels(targetLanguage: newTarget)
        }
        .onChange(of: engineClient.keepModelInMemory) { _, newKeep in
            ProfileManager.shared.updateActiveProfileModels(keepModelInMemory: newKeep)
        }
        .onChange(of: engineClient.enableAutoCompletion) { _, newAuto in
            ProfileManager.shared.updateActiveProfileModels(enableAutoCompletion: newAuto)
        }
        .onAppear {
            engineClient.fetchModels()
            if !didInitChooseModels {
                chooseModelsExpanded = hasCustomizedModel
                didInitChooseModels = true
            }
            if !canUseDictyCloud && llmProvider == "dicty_cloud" {
                llmProvider = "openrouter"
            }
            if translationMethod == "cloud" && (selectedTranslationModel.isEmpty || selectedTranslationModel == "none") && !llmModel.isEmpty {
                selectedTranslationModel = llmModel
            }
        }
        .task {
            await modesStore.refresh()
        }
        .onChange(of: engineClient.isLoggedIn) { _, loggedIn in
            if !loggedIn && llmProvider == "dicty_cloud" {
                llmProvider = "openrouter"
            }
        }
    }
}

// MARK: - Model Best For Catalog
struct ModelBestForCatalog {
    static let catalog: [String: String] = [
        // Standard local speech families
        "nano": "Quick notes, any Mac",
        "base": "Everyday use, older Macs",
        "fast": "Everyday dictation",
        "pro": "Long or technical speech",
        "distil-turbo": "Fast high-accuracy English",
        "turbo": "Best quality on fast Macs",
        "max": "Hardest audio, slowest",
        
        // Language-specific local speech
        "large-v3-turbo-ja": "Japanese speech, fast",
        "large-v2-zh": "Mandarin and regional dialects",
        "large-v2-french": "Native French pronunciation",
        
        // Cloud speech
        "deepgram/nova-3": "Live dictation, fast",
        "openai/whisper-1": "High accuracy across 90+ languages",
        "nvidia/parakeet-tdt-0.6b-v3": "Ultra-fast cloud dictation",
        "groq/whisper-large-v3-turbo": "Near-instant cloud transcription",
        "elevenlabs/scribe-v2": "Conversational nuances and dialogue",
        
        // Text models — on your Mac
        "qwen3.5-0.8b": "Fastest, light cleanup",
        "qwen2.5-1.5b-instruct": "Everyday cleanup",
        "qwen3.5-2b": "Better emails and notes",
        "llama-3.2-3b-instruct": "Best quality, slower",
        
        // Text models — cloud
        "anthropic/claude-opus-5": "Deep synthesis and book editing",
        "anthropic/claude-sonnet-5": "Complex reasoning, writing",
        "anthropic/claude-haiku-4.5": "Quick text cleanup",
        "openai/gpt-5.6-sol": "High-fidelity prose, multi-speaker",
        "openai/gpt-5.5": "Balanced everyday editing",
        "openai/gpt-5.6-luna": "Fast live structuring",
        "google/gemini-3.1-pro-preview": "Deep context, structured text",
        "google/gemini-3.7-flash": "Instant reasoning, massive context",
        "google/gemini-2.5-flash": "Everyday transcription polish",
        "deepseek/deepseek-v4-pro": "Literary prose styling",
        "deepseek/deepseek-v4-flash": "Sub-second text correction",
        "x-ai/grok-4.6": "Direct tone, rich vocabulary",
        "nvidia/nemotron-3-ultra-550b-a55b": "Code transcription, domain precision",
        "qwen/qwen3-next-80b": "Multilingual fluency, synthesis",
        "qwen/qwen3-30b-a3b-instruct": "High-speed text refinement",
        "moonshotai/kimi-k3": "Long-context reasoning",
        "moonshotai/kimi-k2.5": "Fast cleanup and translation",
        "z-ai/glm-5.2": "Bilingual and multilingual synthesis",
        "z-ai/glm-4.7-flash": "Instant budget-friendly refining",
        "minimax/minimax-m3": "Expressive writing, nuances"
    ]
    
    static func bestFor(for modelId: String, fallbackDescription: String? = nil) -> String {
        if let direct = catalog[modelId] {
            return direct
        }
        let lowId = modelId.lowercased()
        for (key, val) in catalog {
            if lowId.contains(key) {
                return val
            }
        }
        if let desc = fallbackDescription, !desc.isEmpty {
            let firstSentence = desc.components(separatedBy: ".").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? desc
            if firstSentence.count <= 42 {
                return firstSentence
            }
            return String(firstSentence.prefix(40)) + "…"
        }
        return "General dictation and editing"
    }
}

// MARK: - Model Differentiated Metrics (sensible spread for cloud models)
struct ModelDifferentiatedMetrics {
    static let speedOverrides: [String: Double] = [
        "qwen3.5-0.8b": 1.0,
        "qwen2.5-1.5b-instruct": 0.8,
        "qwen3.5-2b": 0.6,
        "llama-3.2-3b-instruct": 0.4,
        "deepgram/nova-3": 1.0,
        "groq/whisper-large-v3-turbo": 1.0,
        "openai/whisper-1": 0.65,
        "nvidia/parakeet-tdt-0.6b-v3": 0.95,
        "elevenlabs/scribe-v2": 0.65,
        "anthropic/claude-opus-5": 0.6,
        "anthropic/claude-sonnet-5": 0.8,
        "anthropic/claude-haiku-4.5": 1.0,
        "openai/gpt-5.6-sol": 0.6,
        "openai/gpt-5.5": 0.8,
        "openai/gpt-5.6-luna": 1.0,
        "google/gemini-3.1-pro-preview": 0.6,
        "google/gemini-3.7-flash": 1.0,
        "google/gemini-2.5-flash": 1.0,
        "deepseek/deepseek-v4-pro": 0.6,
        "deepseek/deepseek-v4-flash": 1.0,
        "x-ai/grok-4.6": 0.8,
        "nvidia/nemotron-3-ultra-550b-a55b": 0.6,
        "qwen/qwen3-next-80b": 0.6,
        "qwen/qwen3-30b-a3b-instruct": 1.0,
        "moonshotai/kimi-k3": 0.6,
        "moonshotai/kimi-k2.5": 0.8,
        "z-ai/glm-5.2": 0.6,
        "z-ai/glm-4.7-flash": 1.0,
        "minimax/minimax-m3": 0.8
    ]
    
    static let accuracyOverrides: [String: Double] = [
        "qwen3.5-0.8b": 0.4,
        "qwen2.5-1.5b-instruct": 0.6,
        "qwen3.5-2b": 0.8,
        "llama-3.2-3b-instruct": 1.0,
        "deepgram/nova-3": 0.82,
        "groq/whisper-large-v3-turbo": 0.88,
        "openai/whisper-1": 0.98,
        "nvidia/parakeet-tdt-0.6b-v3": 0.82,
        "elevenlabs/scribe-v2": 0.98,
        "anthropic/claude-opus-5": 1.0,
        "anthropic/claude-sonnet-5": 1.0,
        "anthropic/claude-haiku-4.5": 0.8,
        "openai/gpt-5.6-sol": 1.0,
        "openai/gpt-5.5": 1.0,
        "openai/gpt-5.6-luna": 0.8,
        "google/gemini-3.1-pro-preview": 1.0,
        "google/gemini-3.7-flash": 0.95,
        "google/gemini-2.5-flash": 0.8,
        "deepseek/deepseek-v4-pro": 1.0,
        "deepseek/deepseek-v4-flash": 0.8,
        "x-ai/grok-4.6": 1.0,
        "nvidia/nemotron-3-ultra-550b-a55b": 1.0,
        "qwen/qwen3-next-80b": 1.0,
        "qwen/qwen3-30b-a3b-instruct": 0.8,
        "moonshotai/kimi-k3": 1.0,
        "moonshotai/kimi-k2.5": 0.8,
        "z-ai/glm-5.2": 1.0,
        "z-ai/glm-4.7-flash": 0.8,
        "minimax/minimax-m3": 1.0
    ]
    
    static func speed(for modelId: String, defaultVal: Double) -> Double {
        if let o = speedOverrides[modelId] { return o }
        let low = modelId.lowercased()
        for (k, v) in speedOverrides where low.contains(k) { return v }
        return defaultVal
    }
    
    static func accuracy(for modelId: String, defaultVal: Double) -> Double {
        if let o = accuracyOverrides[modelId] { return o }
        let low = modelId.lowercased()
        for (k, v) in accuracyOverrides where low.contains(k) { return v }
        return defaultVal
    }
}

// MARK: - Model Provider Logo View
struct ModelProviderLogoView: View {
    let model: DictyModel
    var size: CGFloat = 16
    
    private var providerKey: String {
        let id = model.id.lowercased()
        if let p = model.provider, !p.isEmpty, p != "dicty_cloud" && p != "local" {
            return p
        }
        if id.contains("/") {
            return String(id.split(separator: "/").first ?? "")
        }
        if id.contains("qwen") { return "qwen" }
        if id.contains("llama") { return "meta" }
        if id.contains("whisper") { return "openai" }
        return model.name.lowercased()
    }
    
    var body: some View {
        getProviderIcon(for: providerKey, size: size)
            .frame(width: size, height: size)
    }
}

// MARK: - Models Table Header Row
struct ModelsTableHeaderRow: View {
    var showMetrics: Bool = true
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Model")
                .frame(width: 160, alignment: .leading)
            
            Text("Best for")
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            
            if showMetrics {
                Text("Speed")
                    .frame(width: 44, alignment: .leading)
                
                Text("Accuracy")
                    .frame(width: 54, alignment: .leading)
            }
            
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Text("Status")
                Color.clear.frame(width: 18, height: 18)
            }
            .frame(width: 140, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundColor(.secondary.opacity(0.8))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

// MARK: - Model Family Definition
struct ModelFamily: Identifiable {
    let id: String
    let name: String
    let bestFor: String
    let enModelId: String?
    let multiModelId: String?
    
    func targetVariant(for language: String, models: [DictyModel]) -> DictyModel? {
        if language == "en" {
            if let enId = enModelId, let m = models.first(where: { $0.id == enId }) {
                return m
            }
            if let multiId = multiModelId, let m = models.first(where: { $0.id == multiId }) {
                return m
            }
        } else {
            if let multiId = multiModelId, let m = models.first(where: { $0.id == multiId }) {
                return m
            }
            if let enId = enModelId, let m = models.first(where: { $0.id == enId }) {
                return m
            }
        }
        return nil
    }
    
    func preferredVariant(for language: String, models: [DictyModel]) -> DictyModel? {
        targetVariant(for: language, models: models)
    }
    
    func activeVariant(activeId: String, models: [DictyModel]) -> DictyModel? {
        if activeId == enModelId, let enId = enModelId, let m = models.first(where: { $0.id == enId }) {
            return m
        }
        if activeId == multiModelId, let multiId = multiModelId, let m = models.first(where: { $0.id == multiId }) {
            return m
        }
        return nil
    }
    
    func isFamilyActive(activeId: String) -> Bool {
        return (enModelId != nil && activeId == enModelId) || (multiModelId != nil && activeId == multiModelId)
    }
    
    func enVariant(models: [DictyModel]) -> DictyModel? {
        guard let id = enModelId else { return nil }
        return models.first { $0.id == id }
    }
    
    func multiVariant(models: [DictyModel]) -> DictyModel? {
        guard let id = multiModelId else { return nil }
        return models.first { $0.id == id }
    }
}

// MARK: - Model Family Row Component
struct ModelFamilyCardView: View {
    @EnvironmentObject var engineClient: EngineClient
    let family: ModelFamily
    let models: [DictyModel]
    
    @State private var isHovering = false
    @State private var showDetails = false
    @State private var showingDeleteAlert = false
    @State private var deleteTargetModel: DictyModel? = nil
    
    private var isFamilyActive: Bool {
        family.isFamilyActive(activeId: engineClient.activeModel)
    }
    
    private var targetVariant: DictyModel? {
        family.targetVariant(for: engineClient.transcriptionLanguage, models: models)
    }
    
    private var activeConcreteVariant: DictyModel? {
        family.activeVariant(activeId: engineClient.activeModel, models: models)
    }
    
    private var representativeModel: DictyModel? {
        if isFamilyActive, let active = activeConcreteVariant {
            return active
        }
        return targetVariant ?? family.enVariant(models: models) ?? family.multiVariant(models: models)
    }
    
    private var isLanguageMismatchWarning: Bool {
        guard isFamilyActive, let active = activeConcreteVariant else { return false }
        let currentLang = engineClient.transcriptionLanguage
        let isEnOnly = active.id.hasSuffix(".en") || active.id == "distil-large-v3"
        return isEnOnly && currentLang != "en" && family.multiModelId != nil
    }
    
    private var unusedVariantOnDisk: DictyModel? {
        guard let active = activeConcreteVariant else { return nil }
        let en = family.enVariant(models: models)
        let multi = family.multiVariant(models: models)
        if active.id == en?.id && (multi?.is_downloaded ?? false) {
            return multi
        }
        if active.id == multi?.id && (en?.is_downloaded ?? false) {
            return en
        }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                // Model Column (Name only)
                Text(family.name)
                    .font(.system(.body, design: .rounded).weight(isFamilyActive ? .semibold : .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .leading)
                
                // Best for Column
                Text(family.bestFor)
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundColor(.dictySecondary)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Speed (5-dot scale)
                speedScaleView
                    .frame(width: 44, alignment: .leading)
                
                // Accuracy (5-dot scale)
                accuracyScaleView
                    .frame(width: 54, alignment: .leading)
                
                // Status Column
                statusActionView
                    .frame(width: 140, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isFamilyActive ? Color.appAccent.opacity(0.08) : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(family.name) model family")
            .onHover { hovering in
                isHovering = hovering
            }
            .onTapGesture {
                if !isFamilyActive {
                    if let target = targetVariant, (target.is_downloaded ?? false) {
                        engineClient.setActiveModel(id: target.id)
                    } else if let target = targetVariant {
                        let q = engineClient.getSelectedQuality(for: target.id)
                        withAnimation {
                            engineClient.downloadModel(id: target.id, quality: q)
                        }
                    }
                }
            }
            .contextMenu {
                contextMenuItems
            }
            
            // Inline notice when active model can't handle selected language
            if isLanguageMismatchWarning, let multi = family.multiVariant(models: models) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.warmAmber)
                    
                    Text("English-only variant is active. Download multilingual version for \(currentLanguageDisplayName).")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if (multi.is_downloaded ?? false) {
                        Button(action: {
                            engineClient.setActiveModel(id: multi.id)
                        }) {
                            Text("Switch to Multilingual")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.appAccent)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: {
                            let q = engineClient.getSelectedQuality(for: multi.id)
                            engineClient.downloadModel(id: multi.id, quality: q)
                        }) {
                            Text("Download Multilingual (\(multi.size))")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.appAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.warmAmber.opacity(0.12))
                .cornerRadius(6)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(exactVariantTooltip)
        .alert("Delete Model?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let target = deleteTargetModel {
                    withAnimation {
                        engineClient.deleteModel(id: target.id)
                    }
                }
            }
        } message: {
            if let target = deleteTargetModel {
                Text("This will remove \(target.name) (\(target.id), \(target.size)) from your Mac. You can download it again anytime.")
            }
        }
    }
    
    private var currentLanguageDisplayName: String {
        ModelsLibraryView.whisperLanguages.first(where: { $0.code == engineClient.transcriptionLanguage })?.name ?? "this language"
    }
    
    private var exactVariantTooltip: String {
        if let active = activeConcreteVariant {
            let note = active.id.hasSuffix(".en") ? "English-optimized" : "Multilingual"
            return "Uses \(active.id) (\(note))"
        } else if let target = targetVariant {
            let note = target.id.hasSuffix(".en") ? "English-optimized" : "Multilingual"
            return "Prefers \(target.id) (\(note))"
        }
        return family.name
    }
    
    // MARK: - Speed Scale View (5 dots: accent fill on neutral track)
    private var speedScaleView: some View {
        let score = Int(round(min(max(representativeModel?.speed ?? 0.6, 0.1), 1.0) * 5.0))
        return HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { idx in
                Circle()
                    .fill(idx <= score ? Color.appAccent : Color.primary.opacity(0.12))
                    .frame(width: 5, height: 5)
            }
        }
        .help(String(format: "Speed: %d / 5", score))
    }
    
    // MARK: - Accuracy Scale View (5 dots: accent fill on neutral track)
    private var accuracyScaleView: some View {
        let score = Int(round(min(max(representativeModel?.accuracy ?? 0.8, 0.1), 1.0) * 5.0))
        return HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { idx in
                Circle()
                    .fill(idx <= score ? Color.appAccent : Color.primary.opacity(0.12))
                    .frame(width: 5, height: 5)
            }
        }
        .help(String(format: "Accuracy: %d / 5", score))
    }
    
    // MARK: - Status / Action View
    @ViewBuilder
    private var statusActionView: some View {
        let model = targetVariant ?? representativeModel
        let isDownloaded = model?.is_downloaded ?? false
        let activeVariantDownloaded = activeConcreteVariant?.is_downloaded ?? false
        
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            
            if isFamilyActive && (activeVariantDownloaded || isDownloaded) {
                Text("Active")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.appAccent)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appAccent.opacity(0.14))
                    .cornerRadius(6)
            } else if let m = model, engineClient.isDownloading, let progress = engineClient.downloadProgress[m.id], progress >= 0.0 && progress < 100.0 {
                HStack(spacing: 4) {
                    Text(String(format: "Downloading %d%%", Int(progress)))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.appAccent)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    
                    Button(action: {
                        engineClient.cancelDownload(id: m.id)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel download")
                }
            } else if !isDownloaded {
                Button(action: {
                    if let m = model {
                        let q = engineClient.getSelectedQuality(for: m.id)
                        withAnimation {
                            engineClient.downloadModel(id: m.id, quality: q)
                        }
                    }
                }) {
                    Text("Download · \(model?.size ?? "")")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Download \(model?.size ?? "")")
            } else {
                Text("Downloaded")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            
            // Hover details button (small ellipsis.circle)
            Button(action: {
                showDetails.toggle()
            }) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundColor(showDetails || isHovering ? .primary : .secondary.opacity(0.6))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering || showDetails ? 1.0 : 0.0)
            .accessibilityLabel("Model details for \(family.name)")
            .popover(isPresented: $showDetails, arrowEdge: .trailing) {
                if let rep = representativeModel {
                    ModelDetailsPopoverView(model: rep, engineClient: engineClient, onDeleted: {
                        showDetails = false
                    })
                }
            }
        }
    }
    
    // MARK: - Context Menu Items
    @ViewBuilder
    private var contextMenuItems: some View {
        Button(action: {
            showDetails = true
        }) {
            Label("Details", systemImage: "info.circle")
        }
        
        if let target = targetVariant, (target.is_downloaded ?? false), !isFamilyActive {
            Button(action: {
                engineClient.setActiveModel(id: target.id)
            }) {
                Label("Activate Preferred (\(target.id))", systemImage: "checkmark.circle")
            }
        }
        
        if let target = targetVariant, !(target.is_downloaded ?? false) {
            Button(action: {
                let q = engineClient.getSelectedQuality(for: target.id)
                withAnimation {
                    engineClient.downloadModel(id: target.id, quality: q)
                }
            }) {
                Label("Download (\(target.size))", systemImage: "arrow.down.circle")
            }
        }
        
        // Remove unused version on disk
        if let unused = unusedVariantOnDisk {
            Button(role: .destructive, action: {
                deleteTargetModel = unused
                showingDeleteAlert = true
            }) {
                Label("Delete Unused Version (\(unused.size))...", systemImage: "trash")
            }
        }
        
        if isFamilyActive {
            Button(role: .destructive, action: {}) {
                Label("Delete from Disk (Active model)", systemImage: "trash")
            }
            .disabled(true)
            .help("Switch to another model first")
        } else if let active = activeConcreteVariant, (active.is_downloaded ?? false) {
            Button(role: .destructive, action: {
                deleteTargetModel = active
                showingDeleteAlert = true
            }) {
                let note = active.size.isEmpty ? "" : " (\(active.size))"
                Label("Delete from Disk\(note)...", systemImage: "trash")
            }
        } else if let target = targetVariant, (target.is_downloaded ?? false) {
            Button(role: .destructive, action: {
                deleteTargetModel = target
                showingDeleteAlert = true
            }) {
                let note = target.size.isEmpty ? "" : " (\(target.size))"
                Label("Delete from Disk\(note)...", systemImage: "trash")
            }
        }
        
        Button(action: {
            engineClient.openModelsFolder()
        }) {
            Label("Show in Finder", systemImage: "folder")
        }
    }
}

// MARK: - Unified Model Row View
struct UnifiedModelRowView: View {
    @EnvironmentObject var engineClient: EngineClient
    let model: DictyModel
    let isActive: Bool
    let onActivate: () -> Void
    var bestForOverride: String? = nil
    
    @State private var isHovering = false
    @State private var showDetails = false
    @State private var showingDeleteAlert = false
    @AppStorage("llmProvider") private var llmProvider: String = "openrouter"
    
    private var checkCloudAvailability: ModelsLibraryView.ModelAvailability {
        guard model.is_cloud == true else { return .usable }
        if !model.isTextModel {
            let id = model.id.lowercased()
            if id.contains("deepgram") {
                let hasKey = !(SecretsManager.readSecret(forKey: "deepgramApiKey") ?? "").isEmpty
                return (engineClient.isLoggedIn || hasKey) ? .usable : .needsKey(providerName: "Deepgram")
            } else if id.contains("groq") {
                let hasKey = !(SecretsManager.readSecret(forKey: "groqApiKey") ?? "").isEmpty
                return (engineClient.isLoggedIn || hasKey) ? .usable : .needsKey(providerName: "Groq")
            } else if id.contains("elevenlabs") {
                let hasKey = !(SecretsManager.readSecret(forKey: "elevenlabsApiKey") ?? "").isEmpty
                return (engineClient.isLoggedIn || hasKey) ? .usable : .needsKey(providerName: "ElevenLabs")
            } else if id.contains("openai") {
                let hasKey = !(SecretsManager.readSecret(forKey: "openaiApiKey") ?? "").isEmpty
                return (engineClient.isLoggedIn || hasKey) ? .usable : .needsKey(providerName: "OpenAI")
            } else {
                return engineClient.isLoggedIn ? .usable : .signIn
            }
        }
        if llmProvider == "local" {
            return .usable
        }
        let hasOpenRouter = !(SecretsManager.readSecret(forKey: "llmApiKey") ?? "").isEmpty
        if engineClient.isLoggedIn || hasOpenRouter {
            return .usable
        }
        return .needsKey(providerName: "OpenRouter")
    }
    
    private var bestForText: String {
        if let override = bestForOverride, !override.isEmpty {
            return override
        }
        return ModelBestForCatalog.bestFor(for: model.id, fallbackDescription: model.description)
    }
    
    private var shouldShowProviderLogo: Bool {
        if model.is_cloud == true { return true }
        if model.isTextModel { return true }
        return false
    }
    
    private var shouldShowMetrics: Bool {
        model.is_cloud != true
    }
    
    private var effectiveSpeed: Double {
        ModelDifferentiatedMetrics.speed(for: model.id, defaultVal: model.speed)
    }
    
    private var effectiveAccuracy: Double {
        ModelDifferentiatedMetrics.accuracy(for: model.id, defaultVal: model.accuracy)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Model Column
            Text(model.name)
                .font(.system(size: 13, weight: isActive ? .semibold : .medium, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 160, alignment: .leading)
            
            // Best for Column
            Text(bestForText)
                .font(.system(size: 11.5, design: .rounded))
                .foregroundColor(.dictySecondary)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            
            if shouldShowMetrics {
                // Speed (5-dot scale)
                speedScaleView
                    .frame(width: 44, alignment: .leading)
                
                // Accuracy (5-dot scale)
                accuracyScaleView
                    .frame(width: 54, alignment: .leading)
            }
            
            // Status Column
            statusActionView
                .frame(width: 140, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isActive ? Color.appAccent.opacity(0.08) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(model.name) model")
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            if !isActive {
                if model.is_cloud == true || (model.is_downloaded ?? false) {
                    onActivate()
                } else {
                    let q = engineClient.getSelectedQuality(for: model.id)
                    withAnimation {
                        engineClient.downloadModel(id: model.id, quality: q)
                    }
                }
            }
        }
        .contextMenu {
            contextMenuItems
        }
        .alert("Delete \(model.name)?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Model", role: .destructive) {
                withAnimation {
                    engineClient.deleteModel(id: model.id)
                }
            }
        } message: {
            if isActive {
                Text("This is your active model (\(model.size)). Deleting it will remove it from disk.")
            } else {
                Text("This will remove the downloaded model (\(model.size)) from your Mac. You can download it again anytime.")
            }
        }
    }
    
    // MARK: - Speed Scale View (5 dots: accent fill on neutral track)
    private var speedScaleView: some View {
        let score = Int(round(min(max(effectiveSpeed, 0.1), 1.0) * 5.0))
        return HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { idx in
                Circle()
                    .fill(idx <= score ? Color.appAccent : Color.primary.opacity(0.12))
                    .frame(width: 5, height: 5)
            }
        }
        .help(String(format: "Speed: %d / 5", score))
    }
    
    // MARK: - Accuracy Scale View (5 dots: accent fill on neutral track)
    private var accuracyScaleView: some View {
        let score = Int(round(min(max(effectiveAccuracy, 0.1), 1.0) * 5.0))
        return HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { idx in
                Circle()
                    .fill(idx <= score ? Color.appAccent : Color.primary.opacity(0.12))
                    .frame(width: 5, height: 5)
            }
        }
        .help(String(format: "Accuracy: %d / 5", score))
    }
    
    // MARK: - Status Action View
    @ViewBuilder
    private var statusActionView: some View {
        let isDownloaded = model.is_downloaded ?? false
        
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            
            if isActive {
                Text("Active")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.appAccent)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appAccent.opacity(0.14))
                    .cornerRadius(6)
            } else if engineClient.isDownloading, let progress = engineClient.downloadProgress[model.id], progress >= 0.0 && progress < 100.0 {
                HStack(spacing: 4) {
                    Text(String(format: "Downloading %d%%", Int(progress)))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.appAccent)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    
                    Button(action: {
                        engineClient.cancelDownload(id: model.id)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel download")
                }
            } else if model.is_cloud != true && !isDownloaded {
                Button(action: {
                    let q = engineClient.getSelectedQuality(for: model.id)
                    withAnimation {
                        engineClient.downloadModel(id: model.id, quality: q)
                    }
                }) {
                    Text("Download · \(model.size)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Download \(model.size)")
            } else if model.is_cloud != true && isDownloaded {
                Text("Downloaded")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            } else if model.is_cloud == true {
                // Cloud model status check
                switch checkCloudAvailability {
                case .usable:
                    EmptyView()
                case .needsKey:
                    Button(action: {
                        WindowManager.openSettingsWindow(engineClient: engineClient, tabIndex: 11)
                    }) {
                        Text("Needs key")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.dictySecondary)
                            .underline()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .help("Add an API key in Settings → AI Providers")
                case .signIn:
                    Button(action: {
                        WindowManager.openSettingsWindow(engineClient: engineClient, tabIndex: 11)
                    }) {
                        Text("Sign in")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.dictySecondary)
                            .underline()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .help("Sign in to Dicty Cloud in Settings")
                }
            }
            
            // Hover details button (small ellipsis.circle)
            Button(action: {
                showDetails.toggle()
            }) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundColor(showDetails || isHovering ? .primary : .secondary.opacity(0.6))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering || showDetails ? 1.0 : 0.0)
            .accessibilityLabel("Model details for \(model.name)")
            .popover(isPresented: $showDetails, arrowEdge: .trailing) {
                ModelDetailsPopoverView(model: model, engineClient: engineClient, onDeleted: {
                    showDetails = false
                })
            }
        }
    }
    
    // MARK: - Context Menu Items
    @ViewBuilder
    private var contextMenuItems: some View {
        Button(action: {
            showDetails = true
        }) {
            Label("Details", systemImage: "info.circle")
        }
        
        if !isActive && (model.is_cloud == true || (model.is_downloaded ?? false)) {
            Button(action: {
                onActivate()
            }) {
                Label("Set as Active Model", systemImage: "checkmark.circle")
            }
        }
        
        if model.is_cloud != true {
            if model.is_downloaded ?? false {
                if isActive {
                    Button(role: .destructive, action: {}) {
                        Label("Delete from Disk (Active model)", systemImage: "trash")
                    }
                    .disabled(true)
                    .help("Switch to another model first")
                } else {
                    Button(role: .destructive, action: {
                        showingDeleteAlert = true
                    }) {
                        let note = model.size.isEmpty ? "" : " (\(model.size))"
                        Label("Delete from Disk\(note)...", systemImage: "trash")
                    }
                }
            } else {
                Button(action: {
                    let q = engineClient.getSelectedQuality(for: model.id)
                    withAnimation {
                        engineClient.downloadModel(id: model.id, quality: q)
                    }
                }) {
                    let note = model.size.isEmpty ? "" : " (\(model.size))"
                    Label("Download\(note)", systemImage: "arrow.down.circle")
                }
            }
            
            Button(action: {
                engineClient.openModelsFolder()
            }) {
                Label("Show in Finder", systemImage: "folder")
            }
        }
    }
}

// MARK: - Model Details Popover View
struct ModelDetailsPopoverView: View {
    var model: DictyModel
    @ObservedObject var engineClient: EngineClient
    var onDeleted: (() -> Void)? = nil
    
    @State private var showingConfirmDelete = false
    
    private var versionInUse: String? {
        if model.id.hasSuffix(".en") || model.id == "distil-large-v3" {
            return "English-optimized"
        } else if ["tiny", "base", "small", "medium", "large-v3", "large-v3-turbo", "large-v2"].contains(model.id) {
            return "Multilingual"
        }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                if model.is_cloud == true {
                    Text("Cloud")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.08))
                        .foregroundColor(.primary)
                        .cornerRadius(6)
                } else if model.is_downloaded == true {
                    Text("On your Mac")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.08))
                        .foregroundColor(.primary)
                        .cornerRadius(6)
                } else {
                    Text("Not downloaded")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05))
                        .foregroundColor(.dictySecondary)
                        .cornerRadius(6)
                }
            }
            
            if let desc = model.description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.dictySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Divider()
            
            // Size & Quality Specifications
            VStack(alignment: .leading, spacing: 8) {
                Text("Specifications")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.dictySecondary)
                
                if model.is_cloud == true {
                    HStack {
                        Image(systemName: "cloud")
                            .foregroundColor(.dictySecondary)
                        Text("Cloud processing (zero local RAM required)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                } else if model.is_downloaded == true {
                    let q = (model.quantization ?? "q5_0").uppercased().replacingOccurrences(of: "_0", with: "").replacingOccurrences(of: "_1", with: "")
                    HStack {
                        Image(systemName: "internaldrive")
                            .foregroundColor(.dictySecondary)
                        Text("Size: \(model.size)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                        Spacer()
                        if let version = versionInUse {
                            Text(version)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.dictySecondary)
                        }
                    }
                    .help("\(q) quantization")
                } else {
                    Text("Download Quality:")
                        .font(.system(size: 11))
                        .foregroundColor(.dictySecondary)
                    
                    let currentQ = engineClient.getSelectedQuality(for: model.id)
                    
                    VStack(spacing: 6) {
                        qualityRow(id: "q5_0", title: "Optimized (Q5)", sub: "Best balance of accuracy & speed (\(estimatedSize(for: "q5_0")))", icon: "cpu", isSelected: currentQ == "q5_0")
                        qualityRow(id: "f16", title: "Uncompressed (F16)", sub: "Max studio accuracy, high RAM usage (\(estimatedSize(for: "f16")))", icon: "cylinder", isSelected: currentQ == "f16")
                    }
                    
                    Button(action: {
                        let q = engineClient.getSelectedQuality(for: model.id)
                        withAnimation {
                            engineClient.downloadModel(id: model.id, quality: q)
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Model")
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.appAccent)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            
            // Delete from Disk
            if model.is_downloaded == true && model.is_cloud != true {
                Divider()
                
                let isActive = engineClient.activeModel == model.id
                
                if showingConfirmDelete {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Remove downloaded model (\(model.size)) from your Mac?")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.dictySecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        HStack(spacing: 8) {
                            Button(action: {
                                withAnimation {
                                    engineClient.deleteModel(id: model.id)
                                    showingConfirmDelete = false
                                    onDeleted?()
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "trash.fill")
                                    Text("Confirm Delete")
                                }
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.red.opacity(0.85))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                withAnimation { showingConfirmDelete = false }
                            }) {
                                Text("Cancel")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    HStack {
                        Button(action: {
                            if !isActive {
                                withAnimation { showingConfirmDelete = true }
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "trash")
                                Text("Delete from Disk (\(model.size))")
                            }
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(isActive ? .secondary.opacity(0.4) : .red.opacity(0.85))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(isActive ? Color.primary.opacity(0.03) : Color.red.opacity(0.08))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isActive)
                        .help(isActive ? "Switch to another model first" : "Delete model from disk")
                        
                        Spacer()
                        
                        if isActive {
                            Text("Active Model")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.appAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.appAccent.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
    
    private func estimatedSize(for precision: String) -> String {
        let components = model.size.split(separator: " ")
        guard components.count == 2, let val = Double(components[0]) else {
            return model.size
        }
        let unit = String(components[1])
        
        if precision == "q5_0" {
            return model.size
        } else if precision == "f16" {
            if unit == "MB" {
                let f16Val = val * 2.7
                if f16Val >= 1000 {
                    return String(format: "~%.1f GB", f16Val / 1000.0)
                }
                return String(format: "~%d MB", Int(f16Val))
            } else {
                return String(format: "~%.1f GB", val * 2.7)
            }
        } else { // q4_0
            if unit == "MB" {
                return String(format: "~%d MB", Int(val * 0.75))
            } else {
                let q4Val = val * 0.75
                if q4Val < 1.0 {
                    return String(format: "~%d MB", Int(q4Val * 1000))
                }
                return String(format: "~%.1f GB", q4Val)
            }
        }
    }
    
    private func qualityRow(id: String, title: String, sub: String, icon: String, isSelected: Bool) -> some View {
        Button(action: {
            engineClient.selectedQuantizations[model.id] = id
        }) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .appAccent : .secondary.opacity(0.4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(.primary)
                    Text(sub)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.dictySecondary)
                }
                Spacer()
            }
            .padding(8)
            .background(isSelected ? Color.appAccent.opacity(0.1) : Color.primary.opacity(0.03))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.appAccent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct HomeView: View {
    @EnvironmentObject var engineClient: EngineClient
    @State private var searchText: String = ""
    @Environment(\.colorScheme) private var colorScheme
    
    // Resolve user's first name, or fallback to email prefix, or "there"
    private var firstName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty {
            let parts = full.split(separator: " ")
            if let first = parts.first, !first.isEmpty {
                return String(first)
            }
        }
        if let email = engineClient.userEmail, !email.isEmpty {
            let local = email.components(separatedBy: "@").first ?? ""
            let namePart = local.components(separatedBy: ".").first ?? local
            if !namePart.isEmpty {
                return namePart.capitalized
            }
        }
        return "there"
    }
    
    // Configured hotkey display string (e.g. "⌥Space")
    private var hotkeyChipText: String {
        let display = engineClient.recordShortcutDisplay
        return display.isEmpty || display == "None" ? "⌥Space" : display
    }
    
    // Format saved time
    private var timeSavedString: String {
        TimeSavedFormatter.format(words: engineClient.totalWordsSpoken, speakingWpm: engineClient.avgSpeakingWpm)
    }
    
    // Filter today's history records
    private var todayRecords: [DictyHistory] {
        let calendar = Calendar.current
        let today = Date()
        return engineClient.history.filter { record in
            guard let date = HistoryRenderCache.isoFractional.date(from: record.timestamp) ?? HistoryRenderCache.iso.date(from: record.timestamp) else {
                return false
            }
            if !calendar.isDate(date, inSameDayAs: today) {
                return false
            }
            if !searchText.isEmpty {
                return record.text.localizedCaseInsensitiveContains(searchText) || (record.title ?? "").localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }
    
    private func formatTimeOnly(_ isoString: String) -> String {
        if let date = HistoryRenderCache.isoFractional.date(from: isoString) ?? HistoryRenderCache.iso.date(from: isoString) {
            let f = DateFormatter()
            f.timeStyle = .short
            return f.string(from: date)
        }
        return isoString
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // 1. Greeting + Hotkey chip
                HStack(alignment: .center, spacing: 10) {
                    Text("Hey \(firstName), start dictating with")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text(hotkeyChipText)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.appAccent)
                        )
                    
                    Spacer()
                }
                .padding(.top, 4)
                
                // 2. Three headline numbers: words today, speaking WPM, time saved
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(engineClient.totalWordsSpoken)")
                            .font(.system(size: 30, weight: .regular, design: .serif))
                            .foregroundColor(.primary)
                        Text("words today")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.dictySecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider().frame(height: 44)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(engineClient.avgSpeakingWpm)")
                            .font(.system(size: 30, weight: .regular, design: .serif))
                            .foregroundColor(.primary)
                        Text("speaking WPM")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.dictySecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider().frame(height: 44)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(timeSavedString)
                            .font(.system(size: 30, weight: .regular, design: .serif))
                            .foregroundColor(.primary)
                        Text("time saved")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.dictySecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                
                // 3. "Today" Feed
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Today")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundColor(.dictySecondary)
                            TextField("Search today...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .frame(width: 140)
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.dictySecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    
                    if todayRecords.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "mic.slash")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text(searchText.isEmpty ? "No dictations yet today." : "No matching dictations.")
                                .font(.system(size: 13))
                                .foregroundColor(.dictySecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.primary.opacity(0.02))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                        )
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(todayRecords) { record in
                                TodayRecordRow(record: record, formatTime: formatTimeOnly(record.timestamp))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            engineClient.statsPeriod = "day"
            engineClient.fetchStats()
            engineClient.fetchHistory()
        }
    }
}

// MARK: - Today Record Row (with hover-only copy button)
struct TodayRecordRow: View {
    let record: DictyHistory
    let formatTime: String
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(formatTime)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.dictySecondary)
                .frame(width: 65, alignment: .leading)
            
            Text(record.text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.text, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(.dictySecondary)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
            .opacity(isHovering ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(isHovering ? 0.05 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(isHovering ? 0.10 : 0.06), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct ShortcutsView: View {
    @EnvironmentObject var engineClient: EngineClient
    @State private var isRecordingShortcut = false
    @State private var isRecordingPauseShortcut = false
    @State private var isRecordingModeShortcut = false
    @State private var isRecordingTtsShortcut = false
    @State private var shortcutText = ""
    var overrideAccessibilityPermission: Bool? = nil
    @State private var hasAccessibilityPermission: Bool = AXIsProcessTrusted()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    Text("Keyboard Shortcuts").font(.system(.title2, design: .rounded).weight(.semibold))
                    FeatureHelpButton(topic: .shortcuts)
                }
                
                VStack(alignment: .leading, spacing: 15) {
                    // Recording Shortcut (Hold to talk or Toggle)
                    ShortcutCardView(
                        title: engineClient.hotkeyBehavior == "hold" ? "Push-to-Talk (Hold Shortcut)" : "Toggle Recording",
                        description: engineClient.hotkeyBehavior == "hold" ? "Press and hold shortcut to record, release to transcribe." : "Starts or stops voice transcription on press.",
                        isRecording: isRecordingShortcut,
                        shortcutText: shortcutText,
                        shortcutDisplay: engineClient.recordShortcutDisplay,
                        accentColor: .appAccent,
                        isSingleKey: engineClient.isRecordSingleKey,
                        singleKeyName: engineClient.formatShortcutString(keyCode: engineClient.hotkeyKeyCode, modifiers: engineClient.hotkeyModifiers),
                        requireDoubleTap: $engineClient.recordRequireDoubleTap,
                        activationBehavior: $engineClient.hotkeyBehavior,
                        activationOptions: [
                            ActivationStyleOption(tag: "hold", label: "Hold to Talk (Default)", description: "Hold shortcut while speaking, release when finished."),
                            ActivationStyleOption(tag: "toggle", label: "Toggle (Click to start/stop)", description: "Press shortcut once to start, press again to finish.")
                        ],
                        onRecord: {
                            isRecordingShortcut = true
                            shortcutText = "Listening..."
                        },
                        onCancel: {
                            isRecordingShortcut = false
                        },
                        onDoubleTapChange: {
                            engineClient.setupGlobalMonitor()
                        },
                        onActivationChange: {
                            engineClient.setupGlobalMonitor()
                        }
                    )
                    
                    // Pause / Resume Recording Shortcut
                    ShortcutCardView(
                        title: "Pause / Resume Recording",
                        description: "Pauses recording for a moment without ending it.",
                        isRecording: isRecordingPauseShortcut,
                        shortcutText: shortcutText,
                        shortcutDisplay: engineClient.pauseShortcutDisplay,
                        accentColor: .appAccent,
                        isSingleKey: engineClient.isPauseSingleKey,
                        singleKeyName: engineClient.formatShortcutString(keyCode: engineClient.pauseHotkeyKeyCode, modifiers: engineClient.pauseHotkeyModifiers),
                        requireDoubleTap: $engineClient.pauseRequireDoubleTap,
                        activationBehavior: $engineClient.pauseHotkeyBehavior,
                        activationOptions: [
                            ActivationStyleOption(tag: "toggle", label: "Toggle (Default)", description: "Press once to pause audio capture, press again to resume."),
                            ActivationStyleOption(tag: "hold", label: "Hold to Pause", description: "Hold shortcut to pause recording, release to resume.")
                        ],
                        onRecord: {
                            isRecordingPauseShortcut = true
                            shortcutText = "Listening..."
                        },
                        onCancel: {
                            isRecordingPauseShortcut = false
                        },
                        onDoubleTapChange: {
                            engineClient.setupGlobalMonitor()
                        },
                        onActivationChange: {
                            engineClient.setupGlobalMonitor()
                        }
                    )
                    
                    // Switch Active Mode Shortcut
                    ShortcutCardView(
                        title: "Switch Active Mode",
                        description: "Switches to your next mode.",
                        isRecording: isRecordingModeShortcut,
                        shortcutText: shortcutText,
                        shortcutDisplay: engineClient.switchModeShortcutDisplay,
                        accentColor: .appAccent,
                        isSingleKey: engineClient.isSwitchModeSingleKey,
                        singleKeyName: engineClient.formatShortcutString(keyCode: engineClient.switchModeHotkeyKeyCode, modifiers: engineClient.switchModeHotkeyModifiers),
                        requireDoubleTap: $engineClient.switchModeRequireDoubleTap,
                        activationBehavior: $engineClient.switchModeHotkeyBehavior,
                        activationOptions: [
                            ActivationStyleOption(tag: "toggle", label: "Toggle / Cycle (Default)", description: "Press shortcut to open HUD or cycle through modes."),
                            ActivationStyleOption(tag: "hold", label: "Hold to View", description: "Hold shortcut to inspect mode switcher, release to select.")
                        ],
                        onRecord: {
                            isRecordingModeShortcut = true
                            shortcutText = "Listening..."
                        },
                        onCancel: {
                            isRecordingModeShortcut = false
                        },
                        onDoubleTapChange: {
                            engineClient.setupGlobalMonitor()
                        },
                        onActivationChange: {
                            engineClient.setupGlobalMonitor()
                        }
                    )
                    
                    // Text to Voice (Read Aloud Selection) Shortcut
                    ShortcutCardView(
                        title: "Text to Voice (Read Aloud)",
                        description: "Reads selected text aloud in any app.",
                        isRecording: isRecordingTtsShortcut,
                        shortcutText: shortcutText,
                        shortcutDisplay: engineClient.ttsShortcutDisplay,
                        accentColor: .appAccent,
                        isSingleKey: engineClient.isTtsSingleKey,
                        singleKeyName: engineClient.formatShortcutString(keyCode: engineClient.ttsHotkeyKeyCode, modifiers: engineClient.ttsHotkeyModifiers),
                        requireDoubleTap: $engineClient.ttsRequireDoubleTap,
                        activationBehavior: $engineClient.ttsHotkeyBehavior,
                        activationOptions: [
                            ActivationStyleOption(tag: "toggle", label: "Toggle (Default)", description: "Press once to read selection, press again to stop."),
                            ActivationStyleOption(tag: "hold", label: "Hold to Read", description: "Hold shortcut to speak highlighted text, release to stop.")
                        ],
                        onRecord: {
                            isRecordingTtsShortcut = true
                            shortcutText = "Listening..."
                        },
                        onCancel: {
                            isRecordingTtsShortcut = false
                        },
                        onDoubleTapChange: {
                            engineClient.setupGlobalMonitor()
                        },
                        onActivationChange: {
                            engineClient.setupGlobalMonitor()
                        }
                    )
                }
                .padding(.top, 10)
                
                // Live Accessibility Status Row
                HStack(spacing: 8) {
                    if hasAccessibilityPermission {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.secondary)
                        Text("Shortcuts are ready")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.secondary)
                        Text("Dicty needs Accessibility access for shortcuts")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Grant access") {
                            let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                            if let url = URL(string: urlString) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.top, 16)
                
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            hasAccessibilityPermission = overrideAccessibilityPermission ?? AXIsProcessTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if overrideAccessibilityPermission == nil {
                hasAccessibilityPermission = AXIsProcessTrusted()
            }
        }
        .background(
            Group {
                if isRecordingShortcut {
                    ShortcutCapturer(isRecording: $isRecordingShortcut, liveText: $shortcutText) { keyCode, modifiers in
                        engineClient.hotkeyKeyCode = Int(keyCode)
                        engineClient.hotkeyModifiers = Int(modifiers.rawValue)
                        if !EngineClient.isSingleKeyShortcut(keyCode: Int(keyCode), modifiers: Int(modifiers.rawValue)) {
                            engineClient.recordRequireDoubleTap = false
                        }
                        engineClient.setupGlobalMonitor()
                        isRecordingShortcut = false
                    }
                }
                if isRecordingPauseShortcut {
                    ShortcutCapturer(isRecording: $isRecordingPauseShortcut, liveText: $shortcutText) { keyCode, modifiers in
                        engineClient.pauseHotkeyKeyCode = Int(keyCode)
                        engineClient.pauseHotkeyModifiers = Int(modifiers.rawValue)
                        if !EngineClient.isSingleKeyShortcut(keyCode: Int(keyCode), modifiers: Int(modifiers.rawValue)) {
                            engineClient.pauseRequireDoubleTap = false
                        }
                        engineClient.setupGlobalMonitor()
                        isRecordingPauseShortcut = false
                    }
                }
                if isRecordingModeShortcut {
                    ShortcutCapturer(isRecording: $isRecordingModeShortcut, liveText: $shortcutText) { keyCode, modifiers in
                        engineClient.switchModeHotkeyKeyCode = Int(keyCode)
                        engineClient.switchModeHotkeyModifiers = Int(modifiers.rawValue)
                        if !EngineClient.isSingleKeyShortcut(keyCode: Int(keyCode), modifiers: Int(modifiers.rawValue)) {
                            engineClient.switchModeRequireDoubleTap = false
                        }
                        engineClient.setupGlobalMonitor()
                        isRecordingModeShortcut = false
                    }
                }
                if isRecordingTtsShortcut {
                    ShortcutCapturer(isRecording: $isRecordingTtsShortcut, liveText: $shortcutText) { keyCode, modifiers in
                        engineClient.ttsHotkeyKeyCode = Int(keyCode)
                        engineClient.ttsHotkeyModifiers = Int(modifiers.rawValue)
                        if !EngineClient.isSingleKeyShortcut(keyCode: Int(keyCode), modifiers: Int(modifiers.rawValue)) {
                            engineClient.ttsRequireDoubleTap = false
                        }
                        engineClient.setupGlobalMonitor()
                        isRecordingTtsShortcut = false
                    }
                }
            }
        )
        .navigationTitle("Shortcuts")
    }
}

struct ActivationStyleOption: Identifiable, Hashable {
    var id: String { tag }
    let tag: String
    let label: String
    let description: String
}

struct ShortcutCardView: View {
    let title: String
    let description: String
    let isRecording: Bool
    let shortcutText: String
    let shortcutDisplay: String
    let accentColor: Color
    let isSingleKey: Bool
    let singleKeyName: String
    @Binding var requireDoubleTap: Bool
    @Binding var activationBehavior: String
    var activationOptions: [ActivationStyleOption] = []
    let onRecord: () -> Void
    var onCancel: (() -> Void)? = nil
    let onDoubleTapChange: () -> Void
    var onActivationChange: (() -> Void)? = nil
    
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.dictySecondary)
                }
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: onRecord) {
                        Text(isRecording ? shortcutText : shortcutDisplay)
                            .frame(minWidth: 120)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isRecording ? accentColor : Color.secondary.opacity(0.2))
                            .foregroundColor(isRecording ? .white : .primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    if isRecording, let cancel = onCancel {
                        Button(action: cancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel shortcut recording")
                    }
                }
            }
            
            // Accordion Button: "Options"
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.dictySecondary)
                        .frame(width: 12)
                    
                    Text("Options")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.dictySecondary)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        if !isExpanded, let currentOpt = activationOptions.first(where: { $0.tag == activationBehavior }) {
                            Text(currentOpt.label)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.dictySecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(4)
                        }
                        
                        if requireDoubleTap && isSingleKey {
                            Text("2× Double-Tap")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accentColor.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()
                        .opacity(0.15)
                    
                    // 1. Activation Style
                    if !activationOptions.isEmpty {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Activation Style")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                
                                let currentDesc = activationOptions.first(where: { $0.tag == activationBehavior })?.description ?? ""
                                if !currentDesc.isEmpty {
                                    Text(currentDesc)
                                        .font(.caption)
                                        .foregroundColor(.dictySecondary)
                                }
                            }
                            
                            Spacer()
                            
                            Picker("", selection: $activationBehavior) {
                                ForEach(activationOptions) { opt in
                                    Text(opt.label).tag(opt.tag)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(minWidth: 170, maxWidth: 220)
                            .onChange(of: activationBehavior) { _, _ in
                                onActivationChange?()
                            }
                        }
                        
                        Divider()
                            .opacity(0.15)
                    }
                    
                    // 2. Double-Tap
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Double-Tap to Trigger")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(isSingleKey ? .primary : .dictySecondary.opacity(0.6))
                                
                                if requireDoubleTap && isSingleKey {
                                    Text("ACTIVE")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(accentColor)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(accentColor.opacity(0.15))
                                        .cornerRadius(4)
                                }
                            }
                            
                            Text(isSingleKey ? "Press \(singleKeyName) twice quickly to trigger." : "Available when a single key or modifier is set.")
                                .font(.caption)
                                .foregroundColor(isSingleKey ? .dictySecondary : .dictySecondary.opacity(0.5))
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $requireDoubleTap)
                            .labelsHidden()
                            .toggleStyle(.appAccent)
                            .controlSize(.small)
                            .disabled(!isSingleKey)
                            .onChange(of: requireDoubleTap) { _, _ in
                                onDoubleTapChange()
                            }
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

struct ShortcutCapturer: NSViewRepresentable {
    @Binding var isRecording: Bool
    var liveText: Binding<String>? = nil
    var onCapture: (UInt16, NSEvent.ModifierFlags) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.isRecording = isRecording
        context.coordinator.onCapture = onCapture
        context.coordinator.onLiveUpdate = { text in
            liveText?.wrappedValue = text
        }
        context.coordinator.onCancel = {
            isRecording = false
        }
        context.coordinator.setupMonitors()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isRecording = isRecording
        context.coordinator.onCapture = onCapture
        context.coordinator.onLiveUpdate = { text in
            liveText?.wrappedValue = text
        }
        context.coordinator.onCancel = {
            isRecording = false
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: @unchecked Sendable {
        var localMonitor: Any?
        var globalMonitor: Any?
        var isRecording: Bool = false
        var onCapture: ((UInt16, NSEvent.ModifierFlags) -> Void)?
        var onLiveUpdate: ((String) -> Void)?
        var onCancel: (() -> Void)?
        
        // State tracking for modifier-only taps vs multi-key combinations
        var activeModifierKeyCode: UInt16? = nil
        var activeModifierFlags: NSEvent.ModifierFlags = []
        var isModifierCurrentlyDown: Bool = false
        var keyPressedDuringModifier: Bool = false
        
        func setupMonitors() {
            if localMonitor != nil { return }
            
            let standardModifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            
            localMonitor = EventMonitorRegistrar.registerLocal(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self = self, self.isRecording else { return event }
                let handled = self.processEvent(event, standardModifierMask: standardModifierMask)
                return handled ? nil : event
            }
            
            globalMonitor = EventMonitorRegistrar.registerGlobal(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self = self, self.isRecording else { return }
                _ = self.processEvent(event, standardModifierMask: standardModifierMask)
            }
        }
        
        private func processEvent(_ event: NSEvent, standardModifierMask: NSEvent.ModifierFlags) -> Bool {
            let keyCode = event.keyCode
            let mods = event.modifierFlags.intersection(standardModifierMask)
            let isModifier = EngineClient.isModifierKeyCode(keyCode)
            
            if event.type == .keyDown {
                // If Escape pressed alone without modifiers, cancel recording
                if keyCode == 53 && mods.isEmpty {
                    Task { @MainActor in
                        self.onCancel?()
                    }
                    return true
                }
                
                // Any key pressed (either with modifiers or single key like F5, Space, Return, 1, A, etc.)
                self.keyPressedDuringModifier = true
                Task { @MainActor in
                    self.onCapture?(keyCode, mods)
                }
                return true
            } else if event.type == .flagsChanged {
                if isModifier {
                    let isDown = EngineClient.isModifierDown(keyCode: keyCode, flags: event.modifierFlags)
                    
                    if isDown {
                        self.isModifierCurrentlyDown = true
                        self.activeModifierKeyCode = keyCode
                        self.activeModifierFlags = mods
                        self.keyPressedDuringModifier = false
                        
                        // Live feedback while modifier is held
                        var modStr = ""
                        if mods.contains(.control) { modStr += "⌃" }
                        if mods.contains(.option) { modStr += "⌥" }
                        if mods.contains(.shift) { modStr += "⇧" }
                        if mods.contains(.command) { modStr += "⌘" }
                        if keyCode == 63 { modStr = "Fn" }
                        if !modStr.isEmpty {
                            Task { @MainActor in
                                self.onLiveUpdate?(modStr + " ...")
                            }
                        }
                        return true
                    } else {
                        // Modifier released
                        if self.isModifierCurrentlyDown && !self.keyPressedDuringModifier && self.activeModifierKeyCode == keyCode {
                            // User pressed and released this modifier alone without pressing any other key!
                            let capturedKey = keyCode
                            let capturedMods = self.activeModifierFlags
                            self.isModifierCurrentlyDown = false
                            self.activeModifierKeyCode = nil
                            Task { @MainActor in
                                self.onCapture?(capturedKey, capturedMods)
                            }
                            return true
                        }
                        self.isModifierCurrentlyDown = false
                        self.activeModifierKeyCode = nil
                        self.keyPressedDuringModifier = false
                        Task { @MainActor in
                            self.onLiveUpdate?("Listening...")
                        }
                        return true
                    }
                }
            }
            return false
        }
        
        deinit {
            if let m = localMonitor { NSEvent.removeMonitor(m) }
            if let m = globalMonitor { NSEvent.removeMonitor(m) }
        }
    }
}

struct MetricItem: View {
    var title: String
    var value: String
    var icon: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(.title3, design: .rounded))
                .foregroundColor(valueColor == .primary ? .secondary : valueColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundColor(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.dictySecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(minWidth: 100, alignment: .leading)
    }
}

// MARK: - App Selection View (Focused Meeting)
struct MeetingAppItem: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let icon: NSImage?
    let isRunning: Bool
}

struct AppSelectionView: View {
    @AppStorage("selectedMeetingApps") var selectedMeetingApps: String = ""
    @State private var meetingApps: [MeetingAppItem] = []
    @State private var otherApps: [MeetingAppItem] = []
    @State private var isOtherAppsExpanded: Bool = false
    @State private var otherSearchQuery: String = ""
    
    private let candidateMeetingApps: [(bundleID: String, name: String)] = [
        ("us.zoom.xos", "Zoom"),
        ("com.microsoft.teams2", "Microsoft Teams"),
        ("com.microsoft.teams", "Microsoft Teams"),
        ("com.google.Chrome", "Google Chrome"),
        ("com.apple.Safari", "Safari"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.apple.FaceTime", "FaceTime"),
        ("com.cisco.webexmeetingsapp", "Webex"),
        ("com.hnc.Discord", "Discord"),
        ("com.brave.Browser", "Brave"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("org.mozilla.firefox", "Firefox")
    ]
    
    var selectedBundleIDs: Set<String> {
        Set(selectedMeetingApps.split(separator: ",").map(String.init))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: neutral title, subtitle, refresh button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apps to record")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Dicty records only these apps and your mic.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: refreshAppList) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .help("Refresh applications list")
            }
            
            // Meeting Apps Group
            if !meetingApps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Meeting apps")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 0) {
                        ForEach(meetingApps) { app in
                            meetingAppRow(app: app)
                            if app.id != meetingApps.last?.id {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                }
            }
            
            // Other Apps Group (collapsible, search field)
            VStack(alignment: .leading, spacing: 6) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isOtherAppsExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isOtherAppsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                        Text("Other apps")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(otherApps.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(8)
                    }
                }
                .buttonStyle(.plain)
                
                if isOtherAppsExpanded {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                            TextField("Search other apps...", text: $otherSearchQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                            if !otherSearchQuery.isEmpty {
                                Button(action: { otherSearchQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)
                        
                        let filtered = otherApps.filter {
                            otherSearchQuery.isEmpty ||
                            $0.name.localizedCaseInsensitiveContains(otherSearchQuery) ||
                            $0.bundleID.localizedCaseInsensitiveContains(otherSearchQuery)
                        }
                        
                        if filtered.isEmpty {
                            Text("No matching applications found.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(filtered) { app in
                                    meetingAppRow(app: app)
                                    if app.id != filtered.last?.id {
                                        Divider().padding(.leading, 42)
                                    }
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        .onAppear {
            refreshAppList()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshAppList()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshAppList()
        }
    }
    
    @ViewBuilder
    private func meetingAppRow(app: MeetingAppItem) -> some View {
        HStack(spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.secondary)
            }
            
            Text(app.name)
                .font(.system(size: 13, weight: .medium))
            
            if !app.isRunning {
                Text("Not running")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(4)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { selectedBundleIDs.contains(app.bundleID) },
                set: { isSelected in
                    var current = selectedBundleIDs
                    if isSelected {
                        current.insert(app.bundleID)
                    } else {
                        current.remove(app.bundleID)
                    }
                    selectedMeetingApps = current.joined(separator: ",")
                }
            ))
            .toggleStyle(.appAccent)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
    
    private func refreshAppList() {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let runningMap = Dictionary(uniqueKeysWithValues: running.compactMap { app -> (String, NSRunningApplication)? in
            guard let bid = app.bundleIdentifier else { return nil }
            return (bid, app)
        })
        
        var mApps: [MeetingAppItem] = []
        var seenBundleIDs: Set<String> = []
        
        for candidate in candidateMeetingApps {
            if seenBundleIDs.contains(candidate.bundleID) { continue }
            if let run = runningMap[candidate.bundleID] {
                seenBundleIDs.insert(candidate.bundleID)
                mApps.append(MeetingAppItem(
                    bundleID: candidate.bundleID,
                    name: run.localizedName ?? candidate.name,
                    icon: run.icon,
                    isRunning: true
                ))
            } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleID) {
                seenBundleIDs.insert(candidate.bundleID)
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                let displayName = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
                mApps.append(MeetingAppItem(
                    bundleID: candidate.bundleID,
                    name: displayName.isEmpty ? candidate.name : displayName,
                    icon: icon,
                    isRunning: false
                ))
            }
        }
        
        // Also ensure any currently selected app that wasn't in meetingApps is visible
        let currentSelected = selectedBundleIDs
        for sel in currentSelected {
            if seenBundleIDs.contains(sel) { continue }
            if let run = runningMap[sel] {
                seenBundleIDs.insert(sel)
                mApps.append(MeetingAppItem(
                    bundleID: sel,
                    name: run.localizedName ?? sel,
                    icon: run.icon,
                    isRunning: true
                ))
            } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: sel) {
                seenBundleIDs.insert(sel)
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                let displayName = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
                mApps.append(MeetingAppItem(
                    bundleID: sel,
                    name: displayName.isEmpty ? sel : displayName,
                    icon: icon,
                    isRunning: false
                ))
            } else {
                seenBundleIDs.insert(sel)
                mApps.append(MeetingAppItem(
                    bundleID: sel,
                    name: sel,
                    icon: nil,
                    isRunning: false
                ))
            }
        }
        
        // Other running apps
        var oApps: [MeetingAppItem] = []
        for app in running {
            guard let bid = app.bundleIdentifier, !seenBundleIDs.contains(bid) else { continue }
            oApps.append(MeetingAppItem(
                bundleID: bid,
                name: app.localizedName ?? bid,
                icon: app.icon,
                isRunning: true
            ))
        }
        oApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        self.meetingApps = mApps
        self.otherApps = oApps
    }
}

// Helper for true vibrancy
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct SidebarSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 3)
    }
}

// MARK: - OpenRouter Model Explorer Sheet
// MARK: - Custom Model ID Footer View
struct CustomModelIdFooterView: View {
    let onSelect: (String) -> Void
    @State private var customSlugInput: String = ""
    
    var body: some View {
        HStack(spacing: 10) {
            Text("Use a model ID…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            TextField("anthropic/claude-sonnet-4.5", text: $customSlugInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            
            Button("Use") {
                let trimmed = customSlugInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    onSelect(trimmed)
                }
            }
            .buttonStyle(.bordered)
            .tint(.appAccent)
            .disabled(customSlugInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - OpenRouter Model Explorer Sheet
struct OpenRouterModelExplorerSheet: View {
    @EnvironmentObject var engineClient: EngineClient
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedModel: String
    var initialProvider: String = "All"
    
    @State private var searchQuery: String = ""
    @State private var selectedProvider: String = "All"
    @State private var selectedSort: OpenRouterSortOption = .mostPopular
    @State private var displayLimit: Int = 40
    
    private let providers = ["All", "Free", "Claude", "OpenAI", "Google", "DeepSeek", "xAI", "NVIDIA", "Qwen", "Moonshot", "Zhipu", "MiniMax", "Meta", "Mistral"]
    
    private var filteredModels: [OpenRouterModelInfo] {
        var list = engineClient.openRouterModels
        
        if selectedProvider != "All" {
            let key = selectedProvider.lowercased()
            list = list.filter { m in
                let mid = m.id.lowercased()
                switch key {
                case "free":
                    return m.isFree
                case "claude": return mid.contains("anthropic/") || mid.contains("claude")
                case "openai": return mid.contains("openai/")
                case "google": return mid.contains("google/")
                case "deepseek": return mid.contains("deepseek/")
                case "xai": return mid.contains("x-ai/")
                case "nvidia": return mid.contains("nvidia/")
                case "qwen": return mid.contains("qwen/") || mid.contains("alibaba/")
                case "moonshot": return mid.contains("moonshot")
                case "zhipu": return mid.contains("z-ai/") || mid.contains("zhipu/") || mid.contains("thudm/")
                case "minimax": return mid.contains("minimax/")
                case "meta": return mid.contains("meta-llama/") || mid.contains("meta/")
                case "mistral": return mid.contains("mistralai/")
                default: return true
                }
            }
        }
        
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmedQuery.isEmpty {
            list = list.filter { m in
                m.id.lowercased().contains(trimmedQuery) ||
                m.name.lowercased().contains(trimmedQuery) ||
                (m.description ?? "").lowercased().contains(trimmedQuery)
            }
        }
        
        // Fast client-side sort overrides for pricing
        if selectedSort == .priceLowToHigh {
            list.sort { ($0.prompt_price_per_m ?? 0.0) < ($1.prompt_price_per_m ?? 0.0) }
        } else if selectedSort == .priceHighToLow {
            list.sort { ($0.prompt_price_per_m ?? 0.0) > ($1.prompt_price_per_m ?? 0.0) }
        }
        
        return list
    }
    
    private var visibleModels: [OpenRouterModelInfo] {
        let all = filteredModels
        return Array(all.prefix(displayLimit))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose a text model")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("400+ models through OpenRouter. Fast models work best for dictation.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(action: {
                        engineClient.fetchOpenRouterModels(force: true, sort: selectedSort.rawValue)
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh OpenRouter catalog")
                    
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            Divider()
            
            // Search, Sort & Provider Filter Chips
            VStack(spacing: 10) {
                // Search field + Sort Picker Menu
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                        TextField("Search model name, architecture, or ID...", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                        if !searchQuery.isEmpty {
                            Button(action: { 
                                searchQuery = ""
                                displayLimit = 40
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // Sort Menu
                    Menu {
                        ForEach(OpenRouterSortOption.allCases) { opt in
                            Button(action: {
                                selectedSort = opt
                                displayLimit = 40
                                engineClient.fetchOpenRouterModels(sort: opt.rawValue)
                            }) {
                                HStack {
                                    Text(opt.displayName)
                                    if selectedSort == opt {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(selectedSort.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                
                // Provider Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(providers, id: \.self) { p in
                            let isChosen = selectedProvider == p
                            Button(action: {
                                selectedProvider = p
                                displayLimit = 40
                            }) {
                                Text(p)
                                    .font(.system(size: 11, weight: isChosen ? .semibold : .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(isChosen ? Color.appAccent : Color.primary.opacity(0.05))
                                    .foregroundColor(isChosen ? .white : .primary)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            
            Divider()
            
            // Models List
            if engineClient.isLoadingOpenRouterModels && engineClient.openRouterModels.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Fetching catalog from OpenRouter...")
                        .font(.system(size: 13))
                        .foregroundColor(.dictySecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredModels.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No matching models found")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Try adjusting your search query or provider filter.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        let currentVisible = visibleModels
                        ForEach(currentVisible) { model in
                            OpenRouterModelRow(model: model, isSelected: selectedModel == model.id) {
                                selectedModel = model.id
                                dismiss()
                            }
                        }
                        
                        if filteredModels.count > displayLimit {
                            Button(action: {
                                displayLimit += 40
                            }) {
                                HStack(spacing: 6) {
                                    Text("Show More Models (\(filteredModels.count - displayLimit) remaining)")
                                        .font(.system(size: 12, weight: .medium))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundColor(.appAccent)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(Color.appAccent.opacity(0.08))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            
            Divider()
            
            // Custom ID Entry at Bottom (Isolated to prevent typing lag)
            CustomModelIdFooterView { slug in
                selectedModel = slug
                dismiss()
            }
        }
        .frame(minWidth: 680, idealWidth: 740, minHeight: 520, idealHeight: 620)
        .onAppear {
            if initialProvider != "All" {
                selectedProvider = initialProvider
            }
            engineClient.fetchOpenRouterModels(sort: selectedSort.rawValue)
        }
    }
}

// MARK: - OpenRouter Model Row
struct OpenRouterModelRow: View {
    let model: OpenRouterModelInfo
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovering = false
    
    @ViewBuilder
    private func neutralTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(4)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    getProviderIcon(for: model.providerName, size: 16)
                        .foregroundColor(.primary)
                    
                    Text(model.cleanDisplayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    if model.isFast {
                        neutralTag("Fast")
                    }
                    
                    if model.isFree {
                        neutralTag("Free")
                    }
                    
                    if model.isReasoning {
                        neutralTag("Reasoning (slower)")
                    }
                    
                    if let ctx = model.context_length, ctx > 0 {
                        let ctxLabel = ctx >= 1_000_000 ? "\(ctx / 1_000_000)M" : "\(ctx / 1000)K"
                        neutralTag("\(ctxLabel) context")
                    }
                    
                    if !model.priceText.isEmpty {
                        Text(model.priceText)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(model.id)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                
                if let desc = model.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }
            
            Spacer()
            
            if isSelected {
                Text("Active")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.appAccent)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appAccent.opacity(0.14))
                    .cornerRadius(6)
            } else {
                Button(action: onSelect) {
                    Text("Select")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.appAccent.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.appAccent.opacity(0.35), lineWidth: 1)
                        )
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(isSelected ? Color.appAccent.opacity(0.07) : (isHovering ? Color.primary.opacity(0.035) : Color.primary.opacity(0.015)))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.appAccent.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onHover { hovering in
            if isHovering != hovering {
                isHovering = hovering
            }
        }
    }
}

