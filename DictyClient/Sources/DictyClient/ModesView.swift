import SwiftUI
import AppKit

// MARK: - Modes & Profiles (redesigned)

struct ModesView: View {
    @EnvironmentObject var engineClient: EngineClient
    @ObservedObject var profileManager = ProfileManager.shared
    @StateObject private var store = ModesStore()

    @AppStorage("modesEditFirstOnLaunch") private var editFirstOnLaunch = false
    @State private var selectedProfileForEdit: DictyProfile? = nil
    @State private var isCreatingNew = false
    @State private var showResetConfirm = false
    @State private var showAppRules = false
    @State private var selectedTab: Int = 0 // 0 = Modes, 1 = App Rules

    let availableIcons = [
        "mic.fill", "book.fill", "terminal.fill", "person.2.fill",
        "app.connected.to.app.below.fill", "doc.text.fill", "sparkles",
        "pencil", "message.fill", "brain.head.profile", "briefcase.fill", "bolt.fill"
    ]

    var body: some View {
        ZStack {
            if let editingProfile = selectedProfileForEdit {
                ModeDetailView(
                    profile: editingProfile,
                    isActive: editingProfile.id == profileManager.activeProfileId,
                    store: store,
                    onBack: {
                        selectedProfileForEdit = nil
                    },
                    onActivate: {
                        profileManager.switchProfile(to: editingProfile.id, engine: engineClient)
                        if let modeId = store.engineMode(for: editingProfile)?.id {
                            Task { await store.setActiveMode(modeId) }
                        }
                    },
                    onUpdate: { updated in
                        profileManager.updateProfile(updated, engine: engineClient)
                        selectedProfileForEdit = updated
                    },
                    onDelete: {
                        profileManager.deleteProfile(id: editingProfile.id, engine: engineClient)
                        selectedProfileForEdit = nil
                    }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            } else {
                VStack(spacing: 0) {
                    // Top Segmented Tabs: Modes | App Rules
                    HStack {
                        HStack(spacing: 4) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedTab = 0
                                }
                            }) {
                                Text("Modes")
                                    .font(.system(size: 12, weight: selectedTab == 0 ? .semibold : .medium, design: .rounded))
                                    .foregroundColor(selectedTab == 0 ? .appAccent : .secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(selectedTab == 0 ? Color.appAccent.opacity(0.15) : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedTab = 1
                                }
                            }) {
                                Text("App Rules")
                                    .font(.system(size: 12, weight: selectedTab == 1 ? .semibold : .medium, design: .rounded))
                                    .foregroundColor(selectedTab == 1 ? .appAccent : .secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(selectedTab == 1 ? Color.appAccent.opacity(0.15) : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 2)
                    
                    if selectedTab == 0 {
                        ModesListView(
                            profiles: profileManager.profiles,
                            activeProfileId: profileManager.activeProfileId,
                            store: store,
                            onSelect: { profile in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedProfileForEdit = profile
                                }
                            },
                            onCreateNew: {
                                isCreatingNew = true
                            },
                            onResetDefaults: {
                                showResetConfirm = true
                            },
                            onShowAppRules: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedTab = 1
                                }
                            }
                        )
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                    } else {
                        AppRulesPageView(store: store)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                    }
                }
            }
        }
        .sheet(isPresented: $isCreatingNew) {
            NewModeSheet(
                isPresented: $isCreatingNew,
                availableIcons: availableIcons,
                onCreate: { name, desc, icon in
                    let newProfile = profileManager.createProfile(name: name, description: desc, icon: icon, template: profileManager.activeProfile)
                    profileManager.switchProfile(to: newProfile.id, engine: engineClient)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedProfileForEdit = newProfile
                    }
                }
            )
        }
        .sheet(isPresented: $showAppRules) {
            AppRulesSheet(store: store, isPresented: $showAppRules)
        }
        .confirmationDialog(
            "Reset to Default Modes?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset Modes", role: .destructive) {
                profileManager.resetToDefaults(engine: engineClient)
                selectedProfileForEdit = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the starter modes and removes the ones you made.")
        }
        .task {
            await store.refresh()
            await store.migrateIfNeeded(profiles: profileManager.profiles)
        }
        .onAppear {
            if editFirstOnLaunch && selectedProfileForEdit == nil {
                selectedProfileForEdit = profileManager.activeProfile ?? profileManager.profiles.first
            }
        }
    }
}

// MARK: - Screen 1: Modes list

struct ModesListView: View {
    let profiles: [DictyProfile]
    let activeProfileId: UUID
    @ObservedObject var store: ModesStore
    let onSelect: (DictyProfile) -> Void
    let onCreateNew: () -> Void
    let onResetDefaults: () -> Void
    let onShowAppRules: () -> Void

    private var dictationProfiles: [DictyProfile] {
        profiles.filter { !DictyAudioRecorder.isSystemAudioMode($0.activeMode) }
    }

    private var meetingProfiles: [DictyProfile] {
        profiles.filter { DictyAudioRecorder.isSystemAudioMode($0.activeMode) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    autoRuleCard

                    if !dictationProfiles.isEmpty {
                        group(title: "Dictation", profiles: dictationProfiles)
                    }
                    if !meetingProfiles.isEmpty {
                        group(title: "Meetings", profiles: meetingProfiles)
                    }

                    HStack {
                        Spacer()
                        Button(action: onResetDefaults) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 11))
                                Text("Reset to starter modes")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.secondary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Text("Modes")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                FeatureHelpButton(topic: .modes)
            }

            Spacer()

            Button(action: onCreateNew) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Create mode")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.08))
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var autoRuleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pick the mode by app automatically")
                        .font(.system(size: 14, weight: .medium))
                    Text("Dicty switches to the right mode when you start talking in an app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { store.automaticAppRules },
                    set: { newValue in
                        Task { await store.setAutomaticAppRules(newValue) }
                    }
                ))
                .toggleStyle(.appAccent)
                .controlSize(.small)
            }

            Button(action: onShowAppRules) {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 11))
                    Text("See all app rules")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.appAccent)
            }
            .buttonStyle(.plain)

            if !store.loaded {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 11))
                    Text("Dicty's engine is offline. Start it to use app rules and downloads.")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private func group(title: String, profiles: [DictyProfile]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)

            VStack(spacing: 10) {
                ForEach(profiles) { profile in
                    ModeListCard(
                        profile: profile,
                        isActive: profile.id == activeProfileId,
                        capability: store.capability(for: profile),
                        onClick: { onSelect(profile) }
                    )
                }
            }
        }
    }
}

// MARK: - Mode card

struct ModeListCard: View {
    let profile: DictyProfile
    let isActive: Bool
    let capability: ModeCapability?
    let onClick: () -> Void

    @State private var isHovered = false

    private var isMeeting: Bool { DictyAudioRecorder.isSystemAudioMode(profile.activeMode) }

    var body: some View {
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Image(systemName: profile.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isActive ? .appAccent : .primary)
                        .frame(width: 22)

                    Text(profile.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)

                    if isActive {
                        Text("Active")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.appAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.appAccent.opacity(0.14))
                            .cornerRadius(6)
                    }

                    Spacer()

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(6)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                if let line = capabilityLine {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 11))
                        Text(line)
                            .font(.system(size: 11.5))
                    }
                    .foregroundColor(.secondary)
                    .padding(.leading, 34)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(isHovered ? 0.07 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isActive ? Color.appAccent.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var subtitle: String {
        if isMeeting {
            if profile.activeMode == "focused_meeting" { return "Focused meeting" }
            return "Meeting"
        }
        return StyleOption.option(for: profile.dictationFormatStyle).shortTitle
    }

    private var capabilityLine: String? {
        guard let missing = capability?.missing else { return nil }
        if missing == "text_model" {
            let size = capability?.sizeMb ?? 980
            return "Needs a text model · \(size) MB"
        }
        if missing == "cloud_access" {
            return "Needs cloud access · Sign in"
        }
        return nil
    }
}

// MARK: - Screen 2: Mode detail

struct ModeDetailView: View {
    @EnvironmentObject var engineClient: EngineClient
    let profile: DictyProfile
    let isActive: Bool
    @ObservedObject var store: ModesStore
    let onBack: () -> Void
    let onActivate: () -> Void
    let onUpdate: (DictyProfile) -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false
    @State private var showAppPicker = false
    @State private var showTranslatePicker = false
    @State private var isMoreExpanded = false
    @State private var newTagText = ""
    @State private var isFixing = false
    @AppStorage("obsidianPath") private var centralObsidianPath: String = ""
    @AppStorage("modesOpenAppPickerOnLaunch") private var openAppPickerOnLaunch = false

    private var isMeeting: Bool { DictyAudioRecorder.isSystemAudioMode(profile.activeMode) }
    private var engineModeId: String? { store.engineMode(for: profile)?.id }
    private var capability: ModeCapability? { store.capability(for: profile) }
    private var modeRules: [ModeAppRule] {
        guard let id = engineModeId else { return [] }
        return store.rules(forModeId: id)
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if capability?.missing != nil {
                        capabilityBanner
                    }

                    styleCard

                    if isMeeting {
                        meetingOptionsCard

                        if profile.activeMode == "focused_meeting" {
                            AppSelectionView()
                        }
                    } else {
                        correctionsCard
                        translateCard
                        appsCard
                    }

                    moreDisclosure
                }
                .padding(20)
            }
        }
        .sheet(isPresented: $showAppPicker) {
            AppPickerSheet { bundleId, name in
                guard let id = engineModeId else { return }
                Task { await store.addAppRule(bundleId: bundleId, name: name, modeId: id) }
            }
        }
        .sheet(isPresented: $showTranslatePicker) {
            LanguagePickerSheet(
                mode: .translationTarget,
                currentCode: profile.targetLanguage.isEmpty ? "none" : profile.targetLanguage
            ) { selectedCode in
                var p = profile
                p.targetLanguage = selectedCode
                p.translationMethod = (selectedCode == "none" || selectedCode.isEmpty) ? "none" : "cloud"
                onUpdate(p)
            }
        }
        .confirmationDialog("Delete this mode?", isPresented: $showDeleteConfirm) {
            Button("Delete Mode", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This mode and its settings are removed for good.")
        }
        .task {
            if store.engineModes.isEmpty {
                await store.migrateIfNeeded(profiles: ProfileManager.shared.profiles)
                await store.refresh()
            }
        }
        .onAppear {
            if openAppPickerOnLaunch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showAppPicker = true
                }
            }
        }
    }

    // MARK: Nav bar

    private var navigationBar: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Modes")
                        .font(.system(size: 13))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: profile.icon)
                    .font(.system(size: 15))
                    .foregroundColor(isActive ? .appAccent : .primary)
                Text(profile.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }

            Spacer()

            if !isActive {
                Button(action: onActivate) {
                    Text("Activate")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.appAccent)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            } else {
                Text("Active")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appAccent.opacity(0.14))
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: Capability

    private var capabilityBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: capability?.missing == "text_model" ? "arrow.down.circle" : "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(capability?.missing == "text_model" ? "Needs a text model" : "Needs cloud access")
                    .font(.system(size: 13, weight: .semibold))
                Text(capability?.missing == "text_model"
                     ? "Download the \(capability?.sizeMb ?? 980) MB model to run this mode on your Mac."
                     : "Sign in to use AI features with this mode.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if capability?.missing == "text_model" {
                Button(action: startFix) {
                    Text(isFixing ? "Starting…" : "Download")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
                .controlSize(.small)
                .disabled(isFixing)
            } else {
                Button(action: openAccountSettings) {
                    Text("Sign in")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func startFix() {
        guard let id = engineModeId, !isFixing else { return }
        isFixing = true
        Task {
            await store.fix(modeId: id)
            isFixing = false
        }
    }

    private func openAccountSettings() {
        UserDefaults.standard.set(16, forKey: "settingsTabSelection")
    }

    // MARK: Row 1 — Style

    private var styleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Style")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Picker("", selection: Binding(
                    get: { StyleOption.option(for: profile.dictationFormatStyle).id },
                    set: { newValue in
                        var p = profile
                        p.dictationFormatStyle = newValue
                        onUpdate(p)
                    }
                )) {
                    ForEach(StyleOption.all) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
            }

            ExampleView(before: StyleOption.option(for: profile.dictationFormatStyle).before,
                        after: StyleOption.option(for: profile.dictationFormatStyle).after)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    // MARK: Row 2 — Fix my corrections

    private var correctionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fix my corrections")
                        .font(.system(size: 14, weight: .medium))
                    Text("Removes the words you took back, like “Tuesday — actually Wednesday”.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { profile.enableSelfCorrection },
                    set: { newValue in
                        var p = profile
                        p.enableSelfCorrection = newValue
                        onUpdate(p)
                    }
                ))
                .toggleStyle(.appAccent)
                .controlSize(.small)
            }

            ExampleView(before: "Let's meet Tuesday — actually Wednesday",
                        after: "Let's meet Wednesday.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    // MARK: Row 3 — Translate to

    private var isTextModelUnder2B: Bool {
        if store.capabilities?.aiLocation == "cloud_when_better" {
            let hasOpenRouter = !(SecretsManager.readSecret(forKey: "llmApiKey") ?? "").isEmpty
            if hasOpenRouter || engineClient.isLoggedIn {
                return false
            }
        }
        let activeId = engineClient.activeTextModel.isEmpty ? "qwen2.5-1.5b-instruct" : engineClient.activeTextModel
        let low = activeId.lowercased()
        if low.contains("0.5b") || low.contains("0.8b") || low.contains("1.5b") || low.contains("-1b") || low.contains(" 1b") {
            return true
        }
        if let model = engineClient.models.first(where: { $0.id == activeId }) {
            if model.is_cloud == true { return false }
            let name = model.name.lowercased()
            if name.contains("0.5b") || name.contains("0.8b") || name.contains("1.5b") || name.contains(" 1b") {
                return true
            }
        }
        return false
    }

    private var translateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Translate to")
                        .font(.system(size: 14, weight: .medium))
                    Text("Writes the transcript in another language.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { showTranslatePicker = true }) {
                    HStack(spacing: 6) {
                        Text(LanguageCatalog.displayName(for: profile.targetLanguage))
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            if isTextModelUnder2B {
                Text("Small models translate less well. A bigger model or cloud gives better results.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    // MARK: Row 4 — Use in these apps

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Use in these apps")
                    .font(.system(size: 14, weight: .medium))
                Text("Dicty switches to this mode when you dictate in these apps.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !modeRules.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(modeRules) { rule in
                            AppChip(rule: rule) {
                                guard let id = engineModeId else { return }
                                Task { await store.removeAppRule(bundleId: rule.match.value, modeId: id) }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Button(action: { showAppPicker = true }) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add app")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(engineModeId == nil ? .secondary : .appAccent)
            }
            .buttonStyle(.plain)
            .disabled(engineModeId == nil)

            if engineModeId == nil {
                if store.isBusy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Connecting to engine…")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if store.errorMessage != nil || !store.loaded {
                    HStack(spacing: 8) {
                        Text("App rules need the engine.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task {
                                await store.migrateIfNeeded(profiles: ProfileManager.shared.profiles)
                                await store.refresh()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    // MARK: Meeting options (replaces rows 2–4 for meeting modes)

    private var meetingOptionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if DictyAudioRecorder.isSystemAudioMode(profile.activeMode) && !CGPreflightScreenCaptureAccess() {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Screen recording permission is off")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Meeting modes record audio from your meeting apps. macOS asks for Screen & System Audio Recording permission first.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open System Settings") {
                            EngineClient.promptForScreenRecordingPermission()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 2)
                    }
                    Spacer()
                }
                Divider().opacity(0.6)
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mute my microphone")
                        .font(.system(size: 14, weight: .medium))
                    Text("Records only what other people say.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { profile.muteMicrophone },
                    set: { newValue in
                        var p = profile
                        p.muteMicrophone = newValue
                        onUpdate(p)
                    }
                ))
                .toggleStyle(.appAccent)
                .controlSize(.small)
            }

            Divider().opacity(0.6)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speaker separation")
                        .font(.system(size: 14, weight: .medium))
                    Text("Labels who is speaking.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { profile.speakerSeparation == "off" ? "off" : "you_others" },
                    set: { newValue in
                        var p = profile
                        p.speakerSeparation = newValue
                        p.enableDiarization = false
                        onUpdate(p)
                    }
                )) {
                    Text("None").tag("off")
                    Text("You & Others").tag("you_others")
                }
                .pickerStyle(.menu)
                .frame(width: 160)
            }

            if profile.speakerSeparation != "off" {
                Divider().opacity(0.6)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your name in transcripts")
                            .font(.system(size: 13, weight: .medium))
                        Text("Labels your turns.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("You", text: Binding(
                        get: { profile.speakerYouLabel },
                        set: { newValue in
                            var p = profile
                            p.speakerYouLabel = newValue
                            onUpdate(p)
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: 140)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show turn timestamps")
                            .font(.system(size: 13, weight: .medium))
                        Text("Adds a time tag to each paragraph.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { profile.meetingShowTimestamps },
                        set: { newValue in
                            var p = profile
                            p.meetingShowTimestamps = newValue
                            onUpdate(p)
                        }
                    ))
                    .toggleStyle(.appAccent)
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    // MARK: More

    private var moreDisclosure: some View {
        DisclosureGroup(isExpanded: $isMoreExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Name")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    TextField("Name", text: Binding(
                        get: { profile.name },
                        set: { newValue in
                            var p = profile
                            p.name = newValue
                            onUpdate(p)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                }

                Divider().opacity(0.6)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags")
                        .font(.system(size: 13, weight: .medium))
                    Text("Every recording in this mode gets these tags.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !profile.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(profile.tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text("#\(tag)")
                                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                        Button(action: { removeTag(tag) }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.08))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Add a tag", text: $newTagText)
                            .textFieldStyle(.plain)
                            .onSubmit { addTag() }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))

                        Button(action: addTag) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 26, height: 26)
                                .background(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.35) : Color.appAccent)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Divider().opacity(0.6)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Edit instructions")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button("Reset to default") {
                            var p = profile
                            p.customPrompt = ""
                            onUpdate(p)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.appAccent)
                        .disabled(profile.customPrompt.isEmpty)
                    }
                    Text("Adds extra rules for this mode. Leave empty to use the built-in instructions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: Binding(
                        get: { profile.customPrompt },
                        set: { newValue in
                            var p = profile
                            p.customPrompt = newValue
                            onUpdate(p)
                        }
                    ))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .frame(height: 70)
                    .font(.system(size: 12))
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                }

                Divider().opacity(0.6)

                if ProfileManager.shared.profiles.count > 1 {
                    Button(action: { showDeleteConfirm = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                            Text("Delete mode")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)
        } label: {
            Text("More")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.primary.opacity(0.04))
    }

    private func addTag() {
        var clean = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasPrefix("#") {
            clean = String(clean.dropFirst())
        }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var p = profile
        if !p.tags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            p.tags.append(clean)
            onUpdate(p)
        }
        newTagText = ""
    }

    private func removeTag(_ tag: String) {
        var p = profile
        p.tags.removeAll(where: { $0 == tag })
        onUpdate(p)
    }
}

// MARK: - Shared small views

struct ExampleView: View {
    let before: String
    let after: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(label: "Before", text: before, emphasized: false)
            row(label: "After", text: after, emphasized: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
    }

    private func row(label: String, text: String, emphasized: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(emphasized ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppChip: View {
    let rule: ModeAppRule
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            appIcon
            Text(displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.08))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 0.8))
    }

    private var displayName: String {
        rule.displayName?.isEmpty == false ? rule.displayName! : DictyAppDirectory.name(for: rule.match.value)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = DictyAppDirectory.icon(for: rule.match.value) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 15, height: 15)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Style and language options

struct StyleOption: Identifiable {
    let id: String
    let title: String
    let shortTitle: String
    let before: String
    let after: String

    static let all: [StyleOption] = [
        StyleOption(id: "raw", title: "Exact — no changes", shortTitle: "Exact",
                    before: "um so I think we should uh ship it",
                    after: "um so I think we should uh ship it"),
        StyleOption(id: "punctuation_fast", title: "Clean — punctuation and capitals", shortTitle: "Clean",
                    before: "um so I think we should uh ship it",
                    after: "I think we should ship it."),
        StyleOption(id: "message", title: "Message", shortTitle: "Message",
                    before: "hey um can we push the call to tomorrow",
                    after: "Hey, can we push the call to tomorrow?"),
        StyleOption(id: "email", title: "Email", shortTitle: "Email",
                    before: "hi sarah thanks for the update can we move the review to friday",
                    after: "Hi Sarah,\n\nThanks for the update. Can we move the review to Friday?"),
        StyleOption(id: "note", title: "Note", shortTitle: "Note",
                    before: "the api is slow because the cache misses on every request",
                    after: "The API is slow because the cache misses on every request."),
        StyleOption(id: "book", title: "Book prose", shortTitle: "Book",
                    before: "the first chapter begins here",
                    after: "The first chapter begins here."),
        StyleOption(id: "custom", title: "Custom — your instructions", shortTitle: "Custom",
                    before: "Run the instructions you write under More.",
                    after: "Whatever your instructions ask for.")
    ]

    static func option(for id: String) -> StyleOption {
        switch id {
        case "raw", "raw_dialogue": return all[0]
        case "punctuation_fast": return all[1]
        case "message": return all[2]
        case "email": return all[3]
        case "note", "dialogue_structured", "dialogue_summary", "meeting_summary": return all[4]
        case "book": return all[5]
        case "custom", "code": return all[6]
        default: return all[1]
        }
    }
}



// MARK: - App Rules Page View (Full Page Tab)

struct AppRulesPageView: View {
    @ObservedObject var store: ModesStore
    @State private var searchText = ""
    @State private var isAddingApp = false

    var filteredRules: [ModeAppRule] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.appRules.rules }
        return store.appRules.rules.filter { rule in
            (rule.displayName?.lowercased().contains(q) ?? false) ||
            rule.match.value.lowercased().contains(q) ||
            rule.modeId.lowercased().contains(q) ||
            DictyAppDirectory.name(for: rule.match.value).lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("App Rules")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Pick a mode based on the app you're using when dictating.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                }

                // Automatic mode switching card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic app mode switching")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text("Dicty automatically detects your active application and switches to its assigned preset.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.automaticAppRules },
                            set: { val in Task { await store.setAutomaticAppRules(val) } }
                        ))
                        .toggleStyle(.appAccent)
                        .controlSize(.small)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Search & Add App bar
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        TextField("Search apps...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .rounded))
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                    Spacer()

                    Button {
                        isAddingApp = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Add app")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.appAccent.opacity(0.15))
                        .foregroundColor(.appAccent)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                // Table
                VStack(spacing: 0) {
                    // Column Headers
                    HStack(spacing: 12) {
                        Text("Application")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 34)
                        Text("Mode")
                            .frame(width: 160, alignment: .leading)
                        Text("On")
                            .frame(width: 44, alignment: .center)
                        Text("Actions")
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.02))

                    Divider()

                    if filteredRules.isEmpty {
                        VStack(spacing: 6) {
                            Text(store.appRules.rules.isEmpty ? "No app rules configured yet" : "No matching applications")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            Text(store.appRules.rules.isEmpty ? "Click “Add app” to assign a dictation mode to any application." : "Try a different search query.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(filteredRules) { rule in
                            AppRulePageRow(rule: rule, store: store)
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .sheet(isPresented: $isAddingApp) {
            AppPickerSheet { bundleId, appName in
                isAddingApp = false
                Task {
                    await store.addAppRule(bundleId: bundleId, name: appName, modeId: "general")
                }
            }
        }
    }
}

struct AppRulePageRow: View {
    let rule: ModeAppRule
    @ObservedObject var store: ModesStore

    var body: some View {
        HStack(spacing: 12) {
            // App Icon & Names
            HStack(spacing: 10) {
                if let icon = DictyAppDirectory.icon(for: rule.match.value) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 22, height: 22)
                        Image(systemName: "app.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if rule.source == "default" || rule.source == "builtin" {
                            Text("Default")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.primary.opacity(0.06))
                                .foregroundColor(.secondary)
                                .cornerRadius(4)
                        }
                    }
                    Text(rule.match.value)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Mode Picker
            Picker("", selection: Binding(
                get: {
                    if rule.modeId == "dictation" && store.engineModes.contains(where: { $0.id == "general" }) {
                        return "general"
                    }
                    return rule.modeId
                },
                set: { newValue in
                    Task { await store.setAppRuleMode(ruleId: rule.id, modeId: newValue) }
                }
            )) {
                if !store.engineModes.contains(where: { $0.id == rule.modeId }) && rule.modeId != "dictation" && rule.modeId != "general" {
                    Text(store.modeName(forModeId: rule.modeId)).tag(rule.modeId)
                }
                ForEach(store.engineModes) { mode in
                    Text(mode.name).tag(mode.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)

            // Enabled Toggle
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    Task { await store.setAppRuleEnabled(ruleId: rule.id, enabled: newValue) }
                }
            ))
            .toggleStyle(.appAccent)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 44, alignment: .center)

            // Reset / Remove Action
            HStack(spacing: 6) {
                if rule.source == "default" || rule.source == "builtin" {
                    Button {
                        Task { await store.resetAppRule(ruleId: rule.id) }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default mode")
                }

                Button(role: .destructive) {
                    Task { await store.removeAppRule(bundleId: rule.match.value, modeId: rule.modeId) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete rule")
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var displayName: String {
        rule.displayName?.isEmpty == false ? rule.displayName! : DictyAppDirectory.name(for: rule.match.value)
    }
}

// MARK: - App rules sheet (full table)

struct AppRulesSheet: View {
    @ObservedObject var store: ModesStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("App rules")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    .controlSize(.small)
            }
            .padding(16)

            Divider()

            if store.appRules.rules.isEmpty {
                VStack(spacing: 6) {
                    Text("No app rules yet")
                        .font(.system(size: 13, weight: .medium))
                    Text("Add apps from a mode's “Use in these apps” list.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                columnHeader
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.appRules.rules) { rule in
                            AppRuleRow(rule: rule, store: store)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: 540, height: 460)
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("App")
                .frame(width: 200, alignment: .leading)
            Text("Mode")
                .frame(width: 150, alignment: .leading)
            Text("On")
                .frame(width: 44, alignment: .center)
            Text("Reset")
                .frame(width: 60, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct AppRuleRow: View {
    let rule: ModeAppRule
    @ObservedObject var store: ModesStore

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                if let icon = DictyAppDirectory.icon(for: rule.match.value) {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                } else {
                    Image(systemName: "app.fill").font(.system(size: 13)).foregroundColor(.secondary)
                }
                Text(displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .frame(width: 200, alignment: .leading)

            Picker("", selection: Binding(
                get: {
                    if rule.modeId == "dictation" && store.engineModes.contains(where: { $0.id == "general" }) {
                        return "general"
                    }
                    return rule.modeId
                },
                set: { newValue in
                    Task { await store.setAppRuleMode(ruleId: rule.id, modeId: newValue) }
                }
            )) {
                if !store.engineModes.contains(where: { $0.id == rule.modeId }) && rule.modeId != "dictation" && rule.modeId != "general" {
                    Text(store.modeName(forModeId: rule.modeId)).tag(rule.modeId)
                }
                ForEach(store.engineModes) { mode in
                    Text(mode.name).tag(mode.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    Task { await store.setAppRuleEnabled(ruleId: rule.id, enabled: newValue) }
                }
            ))
            .toggleStyle(.appAccent)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 44)

            Button("Reset") {
                Task { await store.resetAppRule(ruleId: rule.id) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.appAccent)
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var displayName: String {
        rule.displayName?.isEmpty == false ? rule.displayName! : DictyAppDirectory.name(for: rule.match.value)
    }
}

// MARK: - App picker sheet ("+ Add app")

struct AppPickerSheet: View {
    let onPick: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var suggestedItems: [AppPickerItem] = []
    @State private var runningItems: [AppPickerItem] = []
    @State private var otherItems: [AppPickerItem] = []

    private static let suggestedAppSpecs: [(name: String, bundleIds: [String])] = [
        ("Slack", ["com.tinyspeck.slackmacgap"]),
        ("Mail", ["com.apple.mail"]),
        ("Outlook", ["com.microsoft.Outlook"]),
        ("Cursor", ["com.todesktop.230313mzl4w4u92"]),
        ("VS Code", ["com.microsoft.VSCode"]),
        ("Xcode", ["com.apple.dt.Xcode"]),
        ("Notion", ["notion.id"]),
        ("Obsidian", ["md.obsidian"]),
        ("Notes", ["com.apple.Notes"]),
        ("Telegram", ["ru.keepcoder.Telegram", "com.tdesktop.Telegram"]),
        ("Messages", ["com.apple.MobileSMS", "com.apple.iChat"]),
        ("Chrome", ["com.google.Chrome"]),
        ("Safari", ["com.apple.Safari"])
    ]

    private static let systemUtilities: Set<String> = [
        "com.apple.ActivityMonitor",
        "com.apple.finder",
        "com.apple.systempreferences"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add app")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(16)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search apps", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            .padding(.horizontal, 16)

            Divider().padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !filteredSuggested.isEmpty {
                        sectionHeader(title: "Suggested")
                        ForEach(filteredSuggested) { item in
                            appRow(item)
                        }
                    }

                    if !filteredRunning.isEmpty {
                        sectionHeader(title: "Running Apps")
                        ForEach(filteredRunning) { item in
                            appRow(item)
                        }
                    }

                    if !filteredOthers.isEmpty {
                        sectionHeader(title: "Other Applications")
                        ForEach(filteredOthers) { item in
                            appRow(item)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button(action: chooseFromApplications) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("Choose from Applications…")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.appAccent)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.02))
        }
        .frame(width: 440, height: 500)
        .onAppear(perform: refresh)
    }

    @ViewBuilder
    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(.dictySecondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func appRow(_ item: AppPickerItem) -> some View {
        Button(action: {
            onPick(item.bundleId, item.name)
            dismiss()
        }) {
            HStack(spacing: 10) {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app.fill").font(.system(size: 13)).foregroundColor(.secondary)
                }
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                if item.isRunning {
                    Text("Running")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.appAccent.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider().padding(.leading, 46)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesQuery(_ item: AppPickerItem) -> Bool {
        if trimmedQuery.isEmpty {
            // Hide system utilities unless searched
            if Self.systemUtilities.contains(item.bundleId) ||
                ["Activity Monitor", "Finder", "System Settings"].contains(item.name) {
                return false
            }
            return true
        }
        return item.name.localizedCaseInsensitiveContains(trimmedQuery) ||
            item.bundleId.localizedCaseInsensitiveContains(trimmedQuery)
    }

    private var filteredSuggested: [AppPickerItem] {
        suggestedItems.filter(matchesQuery)
    }

    private var filteredRunning: [AppPickerItem] {
        runningItems.filter(matchesQuery)
    }

    private var filteredOthers: [AppPickerItem] {
        otherItems.filter(matchesQuery)
    }

    private func chooseFromApplications() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose App"
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                onPick(bundleId, name)
                dismiss()
            }
        }
    }

    private func refresh() {
        var seenBundleIds: Set<String> = []
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var runningMap: [String: NSRunningApplication] = [:]
        for app in runningApps {
            if let bid = app.bundleIdentifier {
                runningMap[bid] = app
            }
        }

        // 1. Suggested apps (installed)
        var suggested: [AppPickerItem] = []
        for spec in Self.suggestedAppSpecs {
            var found = false
            for bid in spec.bundleIds {
                if let run = runningMap[bid] {
                    suggested.append(AppPickerItem(
                        bundleId: bid,
                        name: spec.name,
                        icon: run.icon,
                        isRunning: true
                    ))
                    seenBundleIds.insert(bid)
                    found = true
                    break
                } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    suggested.append(AppPickerItem(
                        bundleId: bid,
                        name: spec.name,
                        icon: icon,
                        isRunning: false
                    ))
                    seenBundleIds.insert(bid)
                    found = true
                    break
                }
            }
            if found { continue }
        }

        // 2. Running apps (not already in suggested)
        var runningList: [AppPickerItem] = []
        for app in runningApps {
            guard let bid = app.bundleIdentifier, !seenBundleIds.contains(bid) else { continue }
            seenBundleIds.insert(bid)
            let name = app.localizedName ?? bid
            runningList.append(AppPickerItem(
                bundleId: bid,
                name: name,
                icon: app.icon,
                isRunning: true
            ))
        }
        runningList.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // 3. Other installed apps
        var others: [AppPickerItem] = []
        let scanDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        for dir in scanDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for url in contents where url.pathExtension == "app" {
                if let b = Bundle(url: url), let bid = b.bundleIdentifier, !seenBundleIds.contains(bid) {
                    seenBundleIds.insert(bid)
                    let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? url.deletingPathExtension().lastPathComponent
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    let isRunning = runningMap[bid] != nil
                    others.append(AppPickerItem(
                        bundleId: bid,
                        name: name,
                        icon: icon,
                        isRunning: isRunning
                    ))
                }
            }
        }
        others.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        suggestedItems = suggested
        runningItems = runningList
        otherItems = others
    }
}

struct AppPickerItem: Identifiable {
    var id: String { bundleId }
    let bundleId: String
    let name: String
    let icon: NSImage?
    let isRunning: Bool
}

// MARK: - New mode sheet

struct NewModeSheet: View {
    @Binding var isPresented: Bool
    let availableIcons: [String]
    let onCreate: (String, String, String) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var selectedIcon = "doc.text.fill"

    var body: some View {
        VStack(spacing: 16) {
            Text("Create New Mode")
                .font(.system(size: 16, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 6) {
                Text("Mode Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. Email Composer", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. Drafts polished emails with professional tone", text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Select Icon")
                    .font(.caption)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 6), spacing: 8) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button(action: { selectedIcon = icon }) {
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .foregroundColor(selectedIcon == icon ? .white : .primary)
                                .frame(width: 34, height: 34)
                                .background(selectedIcon == icon ? Color.appAccent : Color.primary.opacity(0.06))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Create Mode") {
                    onCreate(name, description, selectedIcon)
                    isPresented = false
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 340)
    }
}
