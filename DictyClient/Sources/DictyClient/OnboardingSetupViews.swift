import SwiftUI

// MARK: - Onboarding: where you type most

/// First-run step: pick the apps you type in most. Each pick turns on the
/// matching built-in app rule so Dicty writes in the right style there.
struct TypingAppsView: View {
    @EnvironmentObject var engineClient: EngineClient
    @Binding var currentStep: Int
    @StateObject private var store = ModesStore()
    @State private var selected: Set<String> = []

    private struct Choice: Identifiable {
        let id: String
        let name: String
        let icon: String
        let style: String
    }

    private let choices: [Choice] = [
        Choice(id: "com.tinyspeck.slackmacgap", name: "Slack / chat", icon: "message.fill", style: "message"),
        Choice(id: "com.apple.mail", name: "Email", icon: "envelope.fill", style: "email"),
        Choice(id: "com.microsoft.VSCode", name: "Code", icon: "chevron.left.forwardslash.chevron.right", style: "code"),
        Choice(id: "com.apple.Notes", name: "Notes", icon: "note.text", style: "note")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Where do you type most?")
                .font(.system(size: 26, weight: .bold))
            Text("Dicty will use the right writing style in each app you pick. You can change this any time in Modes.")
                .foregroundColor(.gray)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(choices) { choice in
                    appCard(choice)
                }
            }

            Spacer()

            Button {
                Task {
                    await applyRules()
                    currentStep += 1
                }
            } label: {
                Text("Continue")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.dictyBlue)
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, 24)
        }
        .task { await store.refresh() }
    }

    private func appCard(_ choice: Choice) -> some View {
        let isOn = selected.contains(choice.id)
        return Button {
            if isOn { selected.remove(choice.id) } else { selected.insert(choice.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: choice.icon)
                    .font(.system(size: 15))
                    .foregroundColor(.appAccent)
                Text(choice.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.appAccent)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? Color.appAccent.opacity(0.18) : Color.white.opacity(0.06))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isOn ? Color.appAccent.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func applyRules() async {
        guard !selected.isEmpty else { return }
        let dictationModes = store.engineModes.filter { $0.kind == "dictation" }
        for choice in choices where selected.contains(choice.id) {
            let mode = dictationModes.first(where: { $0.style == choice.style }) ?? dictationModes.first
            guard let modeId = mode?.id else { continue }
            await store.addAppRule(bundleId: choice.id, name: choice.name, modeId: modeId)
        }
    }
}

// MARK: - Onboarding: local or cloud

/// First-run step: choose where Dicty runs AI and, for "On this Mac", offer the
/// downloads that make it work offline.
struct AILocationStepView: View {
    @EnvironmentObject var engineClient: EngineClient
    @Binding var currentStep: Int
    @StateObject private var store = ModesStore()
    @State private var choice: String = "local"

    /// The speech and text models worth having for fully offline use.
    private var offlineModels: [DictyModel] {
        let speechId = engineClient.activeModel.isEmpty
            ? (engineClient.transcriptionLanguage == "en" ? "tiny" : "base")
            : engineClient.activeModel
        var ids = [speechId, "qwen2.5-1.5b-instruct"]
        if engineClient.transcriptionLanguage == "en" { ids.insert("base.en", at: 0) }
        return ids.compactMap { id in engineClient.models.first(where: { $0.id == id }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Private on this Mac, or cloud when better?")
                .font(.system(size: 26, weight: .bold))
            Text("You can switch any time on the Models page.")
                .foregroundColor(.gray)

            HStack(alignment: .top, spacing: 12) {
                option(tag: "local", icon: "laptopcomputer", title: "On this Mac",
                       subtitle: "Private, works offline.")
                option(tag: "cloud_when_better", icon: "cloud", title: "Cloud when better",
                       subtitle: "Faster or better on hard tasks. Needs sign-in or an API key.")
            }

            if choice == "local", !offlineModels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dicty can download these so it works offline:")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    ForEach(offlineModels) { model in
                        downloadRow(model)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
            }

            Spacer()

            Button {
                Task {
                    await store.setAILocation(choice)
                    currentStep += 1
                }
            } label: {
                Text("Continue")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.dictyBlue)
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, 24)
        }
        .task {
            await store.refresh()
            if let location = store.capabilities?.aiLocation, !location.isEmpty {
                choice = location
            }
        }
    }

    @ViewBuilder
    private func option(tag: String, icon: String, title: String, subtitle: String) -> some View {
        let isOn = choice == tag
        Button {
            choice = tag
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isOn ? .appAccent : .gray)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    if isOn {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.appAccent)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? Color.appAccent.opacity(0.18) : Color.white.opacity(0.06))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isOn ? Color.appAccent.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func downloadRow(_ model: DictyModel) -> some View {
        let downloaded = model.is_downloaded == true
        let progress = engineClient.downloadProgress[model.id]
        return HStack(spacing: 10) {
            Image(systemName: downloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundColor(downloaded ? .appAccent : .gray)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                if !model.size.isEmpty {
                    Text(model.size)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            Spacer()
            if downloaded {
                Text("Ready")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            } else if let progress {
                ProgressView(value: progress)
                    .frame(width: 90)
            } else {
                Button("Download") {
                    engineClient.downloadModel(id: model.id)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.appAccent)
            }
        }
    }
}
