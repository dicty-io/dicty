import SwiftUI

/// "Where should Dicty run AI?" — the first thing on the Models page.
///
/// True 3-way selector across the entire app:
/// - "On this Mac": 100% private and offline (Local Whisper speech + Local Qwen text).
/// - "Cloud": Fastest and highest accuracy (Cloud speech via Deepgram Nova 3 + Cloud text via DeepSeek V4 Flash).
/// - "Custom": Mix and match speech and text models individually below.
struct AILocationCard: View {
    @ObservedObject var store: ModesStore
    @EnvironmentObject var engineClient: EngineClient
    let modelsInUse: [DictyModel]
    var onExpandCustom: (() -> Void)? = nil

    @AppStorage("llmModel") private var llmModel: String = "deepseek/deepseek-v4-flash"
    @AppStorage("llmProvider") private var llmProvider: String = "openrouter"
    @AppStorage("lastCloudTextModel") private var lastCloudTextModel: String = "deepseek/deepseek-v4-flash"
    @AppStorage("lastLocalSpeechModel") private var lastLocalSpeechModel: String = "base"
    @AppStorage("lastCloudSpeechModel") private var lastCloudSpeechModel: String = "deepgram/nova-3"
    @AppStorage("lastLocalTextModel") private var lastLocalTextModel: String = "qwen3.5-0.8b"
    @State private var customSelectedManually = false
    @State private var targetModeTag: String? = nil

    init(store: ModesStore, modelsInUse: [DictyModel], onExpandCustom: (() -> Void)? = nil) {
        self.store = store
        self.modelsInUse = modelsInUse
        self.onExpandCustom = onExpandCustom
    }

    private var speechModel: DictyModel? {
        if let current = engineClient.models.first(where: { $0.id == engineClient.activeModel }) {
            return current
        }
        if engineClient.activeModel.starts(with: "deepgram/") || engineClient.activeModel.contains("nova") {
            return DictyModel(id: engineClient.activeModel.isEmpty ? "deepgram/nova-3" : engineClient.activeModel,
                              name: "Nova 3",
                              size: "Cloud API",
                              speed: 1.0,
                              accuracy: 0.82,
                              is_downloaded: true,
                              is_cloud: true,
                              category: "voice",
                              provider: "Deepgram")
        }
        return modelsInUse.first { !$0.isTextModel }
    }

    private var friendlySpeechProvider: String {
        let id = (speechModel?.id ?? engineClient.activeModel).lowercased()
        if id.contains("nova") || id.contains("deepgram") {
            return "Deepgram"
        }
        if let p = speechModel?.provider?.lowercased(), !p.isEmpty {
            if p == "dicty_cloud" || p.contains("dicty") { return "Dicty Cloud" }
            if p.contains("openrouter") { return "OpenRouter" }
            if p.contains("groq") { return "Groq" }
            if p.contains("openai") { return "OpenAI" }
            if p.contains("elevenlabs") { return "ElevenLabs" }
            return p.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return "Cloud"
    }

    private var isSpeechCloud: Bool {
        if let speech = speechModel {
            return speech.is_cloud == true || speech.id.starts(with: "deepgram/") || speech.id.starts(with: "openai/")
        }
        return engineClient.activeModel.starts(with: "deepgram/") || engineClient.activeModel.starts(with: "openai/")
    }

    private var isTextCloud: Bool {
        let aiLoc = store.capabilities?.aiLocation ?? "local"
        return aiLoc != "local" && llmProvider != "local"
    }

    private var currentModeTag: String {
        if let target = targetModeTag {
            return target
        }
        if customSelectedManually {
            return "custom"
        }
        if !isSpeechCloud && !isTextCloud {
            return "local"
        } else if isSpeechCloud && isTextCloud {
            return "cloud"
        } else {
            return "custom"
        }
    }

    private var activeTextModelId: String {
        if !engineClient.activeTextModel.isEmpty {
            return engineClient.activeTextModel
        }
        return "qwen3.5-0.8b"
    }

    private var textModel: DictyModel? {
        if let current = engineClient.models.first(where: { $0.id == activeTextModelId }) {
            return current
        }
        if let current = engineClient.models.first(where: { $0.id == "qwen3.5-0.8b" }) {
            return current
        }
        if let current = engineClient.models.first(where: { $0.id == "qwen2.5-1.5b-instruct" }) {
            return current
        }
        return engineClient.models.first { $0.isTextModel && $0.is_cloud != true }
    }

    private var isTextModelDownloaded: Bool {
        textModel?.is_downloaded == true
    }

    private var hasCloudKey: Bool {
        let hasOpenRouter = !(SecretsManager.readSecret(forKey: "llmApiKey") ?? "").isEmpty
        return hasOpenRouter || engineClient.isLoggedIn
    }

    private var activeCloudTextModelId: String {
        if !llmModel.isEmpty && llmModel.contains("/") {
            return llmModel
        }
        if !lastCloudTextModel.isEmpty && lastCloudTextModel.contains("/") {
            return lastCloudTextModel
        }
        return "deepseek/deepseek-v4-flash"
    }

    private var cloudModelFriendlyName: String {
        ProjectsView.friendlyModelName(for: activeCloudTextModelId)
    }

    private var localFallbackName: String {
        textModel?.name ?? "Qwen 3.5 0.8B"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Where should Dicty run AI?")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundColor(.primary)
                Text("Choose whether Dicty runs entirely on your Mac, uses cloud models, or a custom mix.")
                    .font(.system(size: 12))
                    .foregroundColor(.dictySecondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    option(tag: "local", icon: "laptopcomputer", title: "On this Mac",
                           subtitle: "100% private, works offline.")
                    option(tag: "cloud", icon: "cloud", title: "Cloud",
                           subtitle: "Fastest & highest accuracy.")
                    option(tag: "custom", icon: "slider.horizontal.3", title: "Custom",
                           subtitle: "Mix and match below.")
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    option(tag: "local", icon: "laptopcomputer", title: "On this Mac",
                           subtitle: "100% private, works offline.")
                    option(tag: "cloud", icon: "cloud", title: "Cloud",
                           subtitle: "Fastest & highest accuracy.")
                    option(tag: "custom", icon: "slider.horizontal.3", title: "Custom",
                           subtitle: "Mix and match below.")
                }
            }

            // Two-Stage Pipeline Summary
            VStack(alignment: .leading, spacing: 10) {
                // Stage 1: Speech to text
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Speech to text")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.dictySecondary)
                        .textCase(.uppercase)

                    speechPipelineRow
                }

                Divider().opacity(0.4)

                // Stage 2: Cleanup, formatting & translation
                VStack(alignment: .leading, spacing: 4) {
                    Text("2. Cleanup, formatting & translation")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.dictySecondary)
                        .textCase(.uppercase)

                    textPipelineRow
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)
        }
        .padding(14)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Speech Pipeline Row
    @ViewBuilder
    private var speechPipelineRow: some View {
        if isSpeechCloud {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.appAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(speechModel?.name ?? "Nova 3")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.primary)
                    Text("Speech to text · via \(friendlySpeechProvider)")
                        .font(.system(size: 11))
                        .foregroundColor(.dictySecondary)
                }

                Spacer()

                activeBadge
            }
        } else {
            let isDownloaded = speechModel?.is_downloaded == true
            let sizeText = speechModel?.size.trimmingCharacters(in: .whitespacesAndNewlines)
            let downloadLabel = (sizeText != nil && !sizeText!.isEmpty) ? "Download · \(sizeText!)" : "Download · 140 MB"

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundColor(isDownloaded ? .appAccent : .dictySecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(speechModel?.name ?? "Fast")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.primary)
                    Text("Speech to text · on this Mac")
                        .font(.system(size: 11))
                        .foregroundColor(.dictySecondary)
                }

                Spacer()

                if isDownloaded {
                    activeBadge
                } else if engineClient.isDownloading && engineClient.downloadProgress[speechModel?.id ?? ""] != nil {
                    let prog = engineClient.downloadProgress[speechModel?.id ?? ""] ?? 0.0
                    Text("Downloading \(Int(prog))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.appAccent)
                } else {
                    Button(action: {
                        if let id = speechModel?.id {
                            engineClient.downloadModel(id: id)
                        }
                    }) {
                        Text(downloadLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.appAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.appAccent.opacity(0.12))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Text Pipeline Row
    @ViewBuilder
    private var textPipelineRow: some View {
        if isTextCloud {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: hasCloudKey ? "checkmark.circle.fill" : "key")
                    .font(.system(size: 13))
                    .foregroundColor(hasCloudKey ? .appAccent : .orange)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(cloudModelFriendlyName)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.primary)

                    Text("Cleanup, corrections, translation · via OpenRouter")
                        .font(.system(size: 11))
                        .foregroundColor(.dictySecondary)

                    Text("Falls back to \(localFallbackName) on this Mac.")
                        .font(.system(size: 11))
                        .foregroundColor(.dictySecondary)
                }

                Spacer()

                if hasCloudKey {
                    activeBadge
                } else {
                    HStack(spacing: 4) {
                        Text("Needs a key —")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.dictySecondary)

                        Button(action: {
                            WindowManager.openSettingsWindow(engineClient: engineClient, tabIndex: 11)
                        }) {
                            Text("Add key")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.appAccent)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            }
        } else {
            let isDownloaded = isTextModelDownloaded
            let sizeText = textModel?.size.trimmingCharacters(in: .whitespacesAndNewlines)
            let downloadLabel = (sizeText != nil && !sizeText!.isEmpty) ? "Download · \(sizeText!)" : "Download · 1.0 GB"

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundColor(isDownloaded ? .appAccent : .dictySecondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(textModel?.name ?? "Qwen 3.5 0.8B")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.primary)
                    Text("Cleanup, corrections, translation · on this Mac")
                        .font(.system(size: 11))
                        .foregroundColor(.dictySecondary)
                }

                Spacer()

                if isDownloaded {
                    activeBadge
                        .padding(.top, 2)
                } else {
                    Button(action: {
                        let targetId = textModel?.id ?? activeTextModelId
                        engineClient.downloadModel(id: targetId)
                    }) {
                        Text(downloadLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.appAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.appAccent.opacity(0.12))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
    }

    private var activeBadge: some View {
        Text("Active")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.appAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.appAccent.opacity(0.14))
            .cornerRadius(6)
    }

    // MARK: - Option Card
    @ViewBuilder
    private func option(tag: String, icon: String, title: String, subtitle: String) -> some View {
        let selected = currentModeTag == tag
        Button {
            handleOptionSelect(tag: tag)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selected ? .appAccent : .dictySecondary)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.appAccent)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.dictySecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.appAccent.opacity(0.08) : Color.primary.opacity(0.03))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.appAccent.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func handleOptionSelect(tag: String) {
        targetModeTag = tag
        if tag == "local" {
            customSelectedManually = false
            let localSpeech = !lastLocalSpeechModel.isEmpty ? lastLocalSpeechModel : (engineClient.transcriptionLanguage == "en" ? "base.en" : "base")
            let localText = !lastLocalTextModel.isEmpty ? lastLocalTextModel : "qwen3.5-0.8b"
            llmProvider = "local"
            llmModel = localText
            if isSpeechCloud {
                engineClient.setActiveModel(id: localSpeech)
            }
            Task {
                await store.setAILocation("local")
                await MainActor.run {
                    if targetModeTag == "local" && !isSpeechCloud && !isTextCloud {
                        targetModeTag = nil
                    }
                }
            }
        } else if tag == "cloud" {
            customSelectedManually = false
            let cloudSpeech = !lastCloudSpeechModel.isEmpty ? lastCloudSpeechModel : "deepgram/nova-3"
            let cloudText = !lastCloudTextModel.isEmpty && lastCloudTextModel.contains("/") ? lastCloudTextModel : "deepseek/deepseek-v4-flash"
            llmProvider = "openrouter"
            llmModel = cloudText
            lastCloudTextModel = cloudText
            if !isSpeechCloud {
                engineClient.setActiveModel(id: cloudSpeech)
            }
            Task {
                await store.setAILocation("cloud_when_better")
                await MainActor.run {
                    if targetModeTag == "cloud" && isSpeechCloud && isTextCloud {
                        targetModeTag = nil
                    }
                }
            }
        } else if tag == "custom" {
            customSelectedManually = true
            targetModeTag = nil
            onExpandCustom?()
        }
    }
}
