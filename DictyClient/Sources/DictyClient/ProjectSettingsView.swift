import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Projects Settings
struct ProjectsView: View {
    @EnvironmentObject var engineClient: EngineClient
    
    @AppStorage("selectedGitHubRepo") private var selectedGitHubRepo: String = ""
    @AppStorage("selectedGitHubBranch") private var selectedGitHubBranch: String = ""
    @AppStorage("gitProvider") private var gitProvider: String = "github"
    @AppStorage("gitlabHost") private var gitlabHost: String = "https://gitlab.com"
    @AppStorage("selectedGitLabRepo") private var selectedGitLabRepo: String = ""
    @AppStorage("selectedGitLabBranch") private var selectedGitLabBranch: String = ""
    @AppStorage("selectedBitbucketRepo") private var selectedBitbucketRepo: String = ""
    @AppStorage("selectedBitbucketBranch") private var selectedBitbucketBranch: String = ""
    @AppStorage("cachedAvailableRepos") private var cachedAvailableRepos: String = ""
    @AppStorage("cachedGitLabRepos") private var cachedGitLabRepos: String = ""
    @AppStorage("cachedBitbucketRepos") private var cachedBitbucketRepos: String = ""
    @AppStorage("selectedGitHubCommits") private var selectedCommitsStorage: String = ""
    @AppStorage("selectedGitHubPRs") private var selectedPRsStorage: String = ""
    @AppStorage("targetSystem") private var targetSystem: String = "local"
    @AppStorage("llmProvider") private var llmProvider: String = "openrouter"
    @AppStorage("llmModel") private var llmModel: String = "qwen/qwen3.7-plus"
    
    @AppStorage("projectsTabSelection") private var projectsTab: String = "repository"
    
    private let popularModels: [(id: String, name: String)] = [
        ("anthropic/claude-3.5-sonnet", "Claude 3.5 Sonnet"),
        ("openai/gpt-4o", "GPT-4o"),
        ("google/gemini-2.5-flash", "Gemini 2.5 Flash"),
        ("deepseek/deepseek-chat", "DeepSeek V3"),
        ("meta-llama/llama-3.3-70b-instruct", "Llama 3.3 70B"),
        ("qwen/qwen3.7-plus", "Qwen 3.7 Plus")
    ]
    
    static func friendlyModelName(for raw: String) -> String {
        let base = raw.components(separatedBy: "/").last ?? raw
        let cleaned = base.replacingOccurrences(of: ".gguf", with: "", options: .caseInsensitive)
        if cleaned.localizedCaseInsensitiveContains("qwen2.5-1.5b") || cleaned.localizedCaseInsensitiveContains("qwen_qwen2.5-1.5b") {
            return "Qwen 2.5 1.5B"
        }
        if cleaned.localizedCaseInsensitiveContains("qwen3.5-0.8b") || cleaned.localizedCaseInsensitiveContains("qwen_qwen3.5-0.8b") {
            return "Qwen 3.5 0.8B"
        }
        if cleaned.localizedCaseInsensitiveContains("qwen3.7-plus") {
            return "Qwen 3.7 Plus"
        }
        if cleaned.localizedCaseInsensitiveContains("llama-3.3-70b") {
            return "Llama 3.3 70B"
        }
        if cleaned.localizedCaseInsensitiveContains("llama-3.2-1b") {
            return "Llama 3.2 1B"
        }
        if cleaned.localizedCaseInsensitiveContains("llama-3.2-3b") {
            return "Llama 3.2 3B"
        }
        if cleaned.localizedCaseInsensitiveContains("claude-3.5-sonnet") {
            return "Claude 3.5 Sonnet"
        }
        if cleaned.localizedCaseInsensitiveContains("gpt-4o-mini") {
            return "GPT-4o mini"
        }
        if cleaned.localizedCaseInsensitiveContains("gpt-4o") {
            return "GPT-4o"
        }
        if cleaned.localizedCaseInsensitiveContains("gemini-2.5-flash") || cleaned.localizedCaseInsensitiveContains("gemini-2.0-flash") {
            return "Gemini 2.5 Flash"
        }
        if cleaned.localizedCaseInsensitiveContains("deepseek-v4-flash") || cleaned.localizedCaseInsensitiveContains("deepseek-chat") {
            return "DeepSeek V4 Flash"
        }
        if cleaned.localizedCaseInsensitiveContains("deepseek-v4-pro") {
            return "DeepSeek V4 Pro"
        }
        var name = cleaned
        if let range = name.range(of: "-Q[0-9].*", options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
    }
    
    private var modelChoices: [(id: String, name: String, rawId: String)] {
        var choices: [(id: String, name: String, rawId: String)] = []
        if let current = popularModels.first(where: { $0.id == llmModel }) {
            choices.append((current.id, "\(current.name) (Active)", current.id))
        } else if !llmModel.isEmpty {
            let friendly = Self.friendlyModelName(for: llmModel)
            choices.append((llmModel, "\(friendly) (Active)", llmModel))
        }
        for m in popularModels where m.id != llmModel {
            choices.append((m.id, m.name, m.id))
        }
        choices.append(("__choose_another__", "Choose another…", ""))
        return choices
    }
    
    @State private var isFetchingRepos: Bool = false
    @State private var fetchError: String? = nil
    @State private var showOpenRouterExplorer: Bool = false
    
    @State private var customBitbucketRepoInput: String = ""
    @State private var isConnectingCustomRepo: Bool = false
    
    @State private var availableBranches: [String] = []
    @State private var isFetchingBranches: Bool = false
    
    @State private var recentCommits: [GitHubCommitInfo] = []
    @State private var recentPRs: [GitHubPRInfo] = []
    @State private var isFetchingContext: Bool = false
    @State private var contextFetchError: String? = nil
    
    @State private var selectedCommitsSet: Set<String> = []
    @State private var selectedPRsSet: Set<Int> = []
    
    @State private var commitsLimit: Int = 10
    @State private var selectedContextTab: String = "commits"
    
    var availableRepos: [String] {
        let cache: String
        switch gitProvider {
        case "gitlab": cache = cachedGitLabRepos
        case "bitbucket": cache = cachedBitbucketRepos
        default: cache = cachedAvailableRepos
        }
        if cache.isEmpty { return [] }
        return cache.components(separatedBy: ",")
    }
    
    var activeRepoBinding: Binding<String> {
        Binding(
            get: { 
                switch gitProvider {
                case "gitlab": return selectedGitLabRepo
                case "bitbucket": return selectedBitbucketRepo
                default: return selectedGitHubRepo
                }
            },
            set: { 
                switch gitProvider {
                case "gitlab": selectedGitLabRepo = $0
                case "bitbucket": selectedBitbucketRepo = $0
                default: selectedGitHubRepo = $0
                }
            }
        )
    }
    
    var activeBranchBinding: Binding<String> {
        Binding(
            get: { 
                switch gitProvider {
                case "gitlab": return selectedGitLabBranch
                case "bitbucket": return selectedBitbucketBranch
                default: return selectedGitHubBranch
                }
            },
            set: { 
                switch gitProvider {
                case "gitlab": selectedGitLabBranch = $0
                case "bitbucket": selectedBitbucketBranch = $0
                default: selectedGitHubBranch = $0
                }
            }
        )
    }
    
    private func getProviderToken() -> String {
        switch gitProvider {
        case "gitlab":
            return SecretsManager.readSecret(forKey: "gitlabToken") ?? UserDefaults.standard.string(forKey: "gitlabToken") ?? ""
        case "bitbucket":
            return SecretsManager.readSecret(forKey: "bitbucketToken") ?? UserDefaults.standard.string(forKey: "bitbucketToken") ?? ""
        default:
            return SecretsManager.readSecret(forKey: "githubToken") ?? UserDefaults.standard.string(forKey: "githubToken") ?? ""
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SettingsPageHeader(
                title: "Projects",
                description: "Pick the repository you're working on. Dicty will write and update its docs.",
                helpTopic: .projects
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
            
            HStack {
                PageTabBar(
                    selection: $projectsTab,
                    tabs: [
                        PageTabItem(id: "repository", label: "Repository", icon: "folder"),
                        PageTabItem(id: "queue", label: "Queue", icon: "tray.full"),
                        PageTabItem(id: "advanced", label: "Advanced", icon: "slider.horizontal.3")
                    ],
                    minItemWidth: 74
                )
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 10)
            
            Divider().opacity(0.5)
            
            switch projectsTab {
            case "queue":
                VoiceQueueView(isEmbedded: true)
            case "advanced":
                ProjectsAdvancedView()
            default:
                repositoryTab
            }
        }
    }
    
    private var repositoryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    sourcePicker
                        .padding(.bottom, 4)
                        .onChange(of: gitProvider) { _, _ in
                            fetchError = nil
                            contextFetchError = nil
                            if availableRepos.isEmpty {
                                fetchRepositories()
                            } else if !activeRepoBinding.wrappedValue.isEmpty {
                                fetchBranches(repo: activeRepoBinding.wrappedValue)
                            }
                        }
                    
                    if gitProvider == "github" || gitProvider == "gitlab" || gitProvider == "bitbucket" {
                        let providerName = gitProvider == "gitlab" ? "GitLab" : (gitProvider == "bitbucket" ? "Bitbucket" : "GitHub")
                        let hasToken = !getProviderToken().isEmpty
                        
                        if !hasToken {
                            HStack(spacing: 12) {
                                Image(systemName: "puzzlepiece.extension")
                                    .font(.system(size: 20))
                                    .foregroundColor(.secondary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add a \(providerName) token in Settings → Integrations to see your repositories.")
                                        .font(.system(size: 13))
                                        .foregroundColor(.primary)
                                }
                                
                                Spacer()
                                
                                Button("Open Settings") {
                                    UserDefaults.standard.set(21, forKey: "settingsSubTabSelection")
                                    UserDefaults.standard.set(6, forKey: "settingsTabSelection")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.primary.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        } else if isFetchingRepos {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Fetching repositories...")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 13))
                            }
                            .padding(.vertical, 8)
                        } else if let error = fetchError {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                                
                                Text(error)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button("Open Settings") {
                                    UserDefaults.standard.set(21, forKey: "settingsSubTabSelection")
                                    UserDefaults.standard.set(6, forKey: "settingsTabSelection")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.primary.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        } else if availableRepos.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.badge.questionmark")
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                                
                                Text("No repositories found.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("Refresh") {
                                    fetchRepositories()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.primary.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        } else {
                            HStack {
                                Text("Target Repository")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Picker("", selection: activeRepoBinding) {
                                    ForEach(availableRepos, id: \.self) { repo in
                                        Text(repo).tag(repo)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(maxWidth: 250)
                                .onChange(of: activeRepoBinding.wrappedValue) { _, newRepo in
                                    fetchBranches(repo: newRepo)
                                    selectedCommitsSet.removeAll()
                                    selectedPRsSet.removeAll()
                                    saveSelections()
                                }
                                
                                if isFetchingBranches {
                                    ProgressView().controlSize(.small)
                                } else if !availableBranches.isEmpty {
                                    Picker("", selection: activeBranchBinding) {
                                        ForEach(availableBranches, id: \.self) { branch in
                                            Text(branch).tag(branch)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .frame(maxWidth: 150)
                                    .onChange(of: activeBranchBinding.wrappedValue) { _, newBranch in
                                        fetchContext(repo: activeRepoBinding.wrappedValue, branch: newBranch)
                                    }
                                }
                                
                                Button(action: {
                                    fetchRepositories()
                                    if !activeRepoBinding.wrappedValue.isEmpty {
                                        fetchBranches(repo: activeRepoBinding.wrappedValue)
                                    }
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Refresh repositories")
                            }
                        }
                        
                        if !activeRepoBinding.wrappedValue.isEmpty {
                            Divider().padding(.vertical, 4)
                            
                            // Dynamic Context Selection Area
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Active Context Selection")
                                        .font(.headline)
                                    Spacer()
                                    if isFetchingContext {
                                        ProgressView().scaleEffect(0.5)
                                    }
                                }
                                Text("Select specific commits or Pull Requests to feed into the Librarian's short-term memory.")
                                    .font(.caption)
                                    .foregroundColor(.dictySecondary)
                                
                                if let err = contextFetchError {
                                    Text(err).foregroundColor(.red).font(.caption)
                                }
                                
                                // Context Mode Tabs (Commits / PRs)
                                Picker("", selection: $selectedContextTab) {
                                    Text("Commits (\(selectedCommitsSet.count))").tag("commits")
                                    Text("\(gitProvider == "gitlab" ? "Merge Requests" : "Pull Requests") (\(selectedPRsSet.count))").tag("prs")
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(maxWidth: 320)
                                .padding(.top, 2)
                                
                                VStack(alignment: .leading, spacing: 10) {
                                    if selectedContextTab == "commits" {
                                        HStack {
                                            Text("Recent Commits")
                                                .font(.subheadline).bold()
                                            Spacer()
                                            HStack(spacing: 6) {
                                                Text("Limit:")
                                                    .font(.caption)
                                                    .foregroundColor(.dictySecondary)
                                                Picker("", selection: $commitsLimit) {
                                                    Text("5").tag(5)
                                                    Text("10").tag(10)
                                                    Text("20").tag(20)
                                                    Text("50").tag(50)
                                                }
                                                .pickerStyle(.segmented)
                                                .labelsHidden()
                                                .frame(width: 140)
                                                .onChange(of: commitsLimit) { _, _ in
                                                    fetchContext(repo: activeRepoBinding.wrappedValue, branch: activeBranchBinding.wrappedValue)
                                                }
                                            }
                                        }
                                        
                                        if recentCommits.isEmpty && !isFetchingContext {
                                            Text("No commits fetched.")
                                                .font(.caption).foregroundColor(.dictySecondary)
                                                .padding(.vertical, 8)
                                        } else {
                                            ScrollView {
                                                LazyVStack(alignment: .leading, spacing: 4) {
                                                    ForEach(recentCommits) { commit in
                                                        CommitRowView(
                                                            commit: commit,
                                                            selectedCommitsSet: $selectedCommitsSet,
                                                            saveSelections: saveSelections
                                                        )
                                                    }
                                                }
                                            }
                                            .frame(maxHeight: 200)
                                        }
                                    } else {
                                        HStack {
                                            Text(gitProvider == "gitlab" ? "Open Merge Requests" : "Open Pull Requests")
                                                .font(.subheadline).bold()
                                            Spacer()
                                        }
                                        
                                        if recentPRs.isEmpty && !isFetchingContext {
                                            Text(gitProvider == "gitlab" ? "No open Merge Requests found." : "No open Pull Requests found.")
                                                .font(.caption).foregroundColor(.dictySecondary)
                                                .padding(.vertical, 8)
                                        } else {
                                            ScrollView {
                                                LazyVStack(alignment: .leading, spacing: 4) {
                                                    ForEach(recentPRs) { pr in
                                                        PRRowView(
                                                            pr: pr,
                                                            selectedPRsSet: $selectedPRsSet,
                                                            saveSelections: saveSelections
                                                        )
                                                    }
                                                }
                                            }
                                            .frame(maxHeight: 200)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                
                Divider()
                
                // Architecture Analysis Section
                VStack(alignment: .leading, spacing: 14) {
                    Text("Architecture Analysis & Documentation")
                        .font(.headline)
                    Text("Dicty reads your code and writes an ARCHITECTURE.md file that explains how it works.")
                        .font(.subheadline)
                        .foregroundColor(.dictySecondary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Header row: Title + Explore 400+ Models Button
                        HStack {
                            Label("Model", systemImage: "cpu")
                                .font(.system(size: 13, weight: .semibold))
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
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.08))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Divider().opacity(0.5)
                        
                        // Selection row: Single Model label in card header; row shows picker with friendly names & tooltip
                        HStack {
                            Picker("", selection: Binding(
                                get: { llmModel },
                                set: { selected in
                                    if selected == "__choose_another__" {
                                        showOpenRouterExplorer = true
                                    } else {
                                        llmModel = selected
                                    }
                                }
                            )) {
                                ForEach(modelChoices, id: \.id) { m in
                                    Text(m.name).tag(m.id)
                                        .help(m.rawId.isEmpty ? m.name : m.rawId)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .help(llmModel)
                            
                            Spacer()
                        }
                        
                        HStack {
                            Text("Saves to: Obsidian folder")
                                .font(.caption)
                                .foregroundColor(.dictySecondary)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.04))
                    )
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: generateArchitecture) {
                            HStack(spacing: 6) {
                                if engineClient.isGeneratingArchitecture {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "cpu")
                                }
                                Text(engineClient.isGeneratingArchitecture ? "Analyzing & Generating..." : "Generate Architecture Document")
                            }
                        }
                        .buttonStyle(.flatPrimary)
                        .disabled(engineClient.isGeneratingArchitecture || activeRepoBinding.wrappedValue.isEmpty)
                        .help(activeRepoBinding.wrappedValue.isEmpty ? "Pick a repository first." : "Generate architecture document")
                        
                        if activeRepoBinding.wrappedValue.isEmpty && !engineClient.isGeneratingArchitecture {
                            Text("Pick a repository first.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let msg = engineClient.architectureGenMessage, !msg.isEmpty {
                        let isError = msg.contains("Error")
                        HStack(spacing: 8) {
                            Image(systemName: isError ? "exclamationmark.triangle.fill" : (engineClient.isGeneratingArchitecture ? "hourglass" : "checkmark.circle.fill"))
                                .font(.caption)
                                .foregroundColor(isError ? Color.red.opacity(0.85) : Color.sageGreen)
                            
                            Text(msg)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isError ? Color.red.opacity(0.08) : Color.sageGreen.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isError ? Color.red.opacity(0.2) : Color.sageGreen.opacity(0.25), lineWidth: 1)
                        )
                    }
                }
                
                Spacer()
            }
            .padding(24)
        }
        .sheet(isPresented: $showOpenRouterExplorer) {
            OpenRouterModelExplorerSheet(selectedModel: $llmModel)
                .environmentObject(engineClient)
        }
        .onAppear {
            loadSelections()
            if !activeRepoBinding.wrappedValue.isEmpty && availableBranches.isEmpty {
                fetchBranches(repo: activeRepoBinding.wrappedValue)
            } else if availableRepos.isEmpty {
                fetchRepositories()
            }
        }
    }
    
    private func saveSelections() {
        selectedCommitsStorage = selectedCommitsSet.joined(separator: ",")
        selectedPRsStorage = selectedPRsSet.map { String($0) }.joined(separator: ",")
    }
    
    private func loadSelections() {
        let cStrs = selectedCommitsStorage.split(separator: ",").map { String($0) }
        selectedCommitsSet = Set(cStrs)
        let pStrs = selectedPRsStorage.split(separator: ",").compactMap { Int(String($0)) }
        selectedPRsSet = Set(pStrs)
    }
    
    private func connectCustomBitbucketRepo() {
        let input = customBitbucketRepoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let token = getProviderToken()
        guard !token.isEmpty else {
            fetchError = "No Bitbucket token found in API Integrations."
            return
        }
        
        isConnectingCustomRepo = true
        fetchError = nil
        
        guard let url = URL(string: "https://api.bitbucket.org/2.0/repositories/\(input)") else {
            isConnectingCustomRepo = false
            return
        }
        var request = URLRequest(url: url)
        if token.contains(":") {
            let base64Token = Data(token.utf8).base64EncodedString()
            request.setValue("Basic \(base64Token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        EngineEndpoint.shared.session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isConnectingCustomRepo = false
                guard let data = data, error == nil else {
                    self.fetchError = "Network error: \(error?.localizedDescription ?? "Unknown")"
                    return
                }
                
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    var current = self.availableRepos
                    if !current.contains(input) {
                        current.append(input)
                    }
                    self.cachedBitbucketRepos = current.joined(separator: ",")
                    self.selectedBitbucketRepo = input
                    self.fetchBranches(repo: input)
                    self.customBitbucketRepoInput = ""
                } else {
                    if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorDict = jsonDict["error"] as? [String: Any],
                       let msg = errorDict["message"] as? String {
                        self.fetchError = "Bitbucket: \(msg)"
                    } else {
                        self.fetchError = "Could not find repository '\(input)' on Bitbucket."
                    }
                }
            }
        }.resume()
    }
    
    private func fetchContext(repo: String, branch: String? = nil) {
        let isGitLab = gitProvider == "gitlab"
        let isBitbucket = gitProvider == "bitbucket"
        let token = getProviderToken()
        
        guard !token.isEmpty, !repo.isEmpty else {
            return
        }
        
        isFetchingContext = true
        contextFetchError = nil
        recentCommits = []
        recentPRs = []
        
        let commitsUrl: URL?
        let prsUrl: URL?
        
        if isGitLab {
            var charSet = CharacterSet.urlPathAllowed
            charSet.remove("/")
            let encodedRepo = repo.addingPercentEncoding(withAllowedCharacters: charSet) ?? repo.replacingOccurrences(of: "/", with: "%2F")
            commitsUrl = URL(string: "\(gitlabHost)/api/v4/projects/\(encodedRepo)/repository/commits?per_page=\(commitsLimit)" + (branch != nil && !branch!.isEmpty ? "&ref_name=\(branch!)" : ""))
            prsUrl = URL(string: "\(gitlabHost)/api/v4/projects/\(encodedRepo)/merge_requests?state=opened&per_page=5")
        } else if isBitbucket {
            let branchQuery = (branch != nil && !branch!.isEmpty) ? "&include=\(branch!)" : ""
            commitsUrl = URL(string: "https://api.bitbucket.org/2.0/repositories/\(repo)/commits?pagelen=\(commitsLimit)\(branchQuery)")
            prsUrl = URL(string: "https://api.bitbucket.org/2.0/repositories/\(repo)/pullrequests?state=OPEN&pagelen=10")
        } else {
            let branchQuery = (branch != nil && !branch!.isEmpty) ? "&sha=\(branch!)" : ""
            commitsUrl = URL(string: "https://api.github.com/repos/\(repo)/commits?per_page=\(commitsLimit)\(branchQuery)")
            prsUrl = URL(string: "https://api.github.com/repos/\(repo)/pulls?state=open&per_page=10")
        }
        
        guard let cUrl = commitsUrl, let pUrl = prsUrl else { return }
              
        var commitsReq = URLRequest(url: cUrl)
        var prsReq = URLRequest(url: pUrl)
        
        if isGitLab {
            commitsReq.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
            prsReq.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        } else if isBitbucket {
            if token.contains(":") {
                let base64Token = Data(token.utf8).base64EncodedString()
                commitsReq.setValue("Basic \(base64Token)", forHTTPHeaderField: "Authorization")
                prsReq.setValue("Basic \(base64Token)", forHTTPHeaderField: "Authorization")
            } else {
                commitsReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                prsReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            commitsReq.setValue("application/json", forHTTPHeaderField: "Accept")
            prsReq.setValue("application/json", forHTTPHeaderField: "Accept")
        } else {
            commitsReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            commitsReq.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            prsReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            prsReq.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        }
        
        Task { @MainActor in
            do {
                let (commitsData, _) = try await EngineEndpoint.shared.session.data(for: commitsReq)
                if isBitbucket {
                    if let jsonDict = try? JSONSerialization.jsonObject(with: commitsData) as? [String: Any],
                       let values = jsonDict["values"] as? [[String: Any]] {
                        self.recentCommits = values.compactMap { dict -> GitHubCommitInfo? in
                            guard let hash = dict["hash"] as? String,
                                  let message = dict["message"] as? String,
                                  let dateString = dict["date"] as? String else { return nil }
                            let authorDict = dict["author"] as? [String: Any]
                            let authorName = authorDict?["raw"] as? String ?? dict["author"] as? String ?? "Unknown"
                            let links = dict["links"] as? [String: Any]
                            let htmlLink = links?["html"] as? [String: Any]
                            let webUrl = htmlLink?["href"] as? String ?? ""
                            let shortMsg = message.components(separatedBy: "\n").first ?? message
                            let date = formatRelativeDate(dateString)
                            return GitHubCommitInfo(id: hash, message: shortMsg, author: authorName, date: date, url: webUrl)
                        }
                    } else if let jsonDict = try? JSONSerialization.jsonObject(with: commitsData) as? [String: Any] {
                        let errorDict = jsonDict["error"] as? [String: Any]
                        let errorMsg = errorDict?["message"] as? String ?? (jsonDict["message"] as? String ?? "Error fetching Bitbucket commits")
                        self.contextFetchError = "Bitbucket Error: \(errorMsg)"
                    }
                } else if let jsonArray = try? JSONSerialization.jsonObject(with: commitsData) as? [[String: Any]] {
                    self.recentCommits = jsonArray.compactMap { dict -> GitHubCommitInfo? in
                        if isGitLab {
                            guard let sha = dict["id"] as? String,
                                  let message = dict["message"] as? String,
                                  let authorName = dict["author_name"] as? String,
                                  let dateString = dict["created_at"] as? String else { return nil }
                            let webUrl = dict["web_url"] as? String ?? ""
                            let shortMsg = message.components(separatedBy: "\n").first ?? message
                            let date = formatRelativeDate(dateString)
                            return GitHubCommitInfo(id: sha, message: shortMsg, author: authorName, date: date, url: webUrl)
                        } else {
                            guard let sha = dict["sha"] as? String,
                                  let htmlUrl = dict["html_url"] as? String,
                                  let commitDict = dict["commit"] as? [String: Any],
                                  let message = commitDict["message"] as? String,
                                  let authorDict = commitDict["author"] as? [String: Any],
                                  let authorName = authorDict["name"] as? String,
                                  let dateString = authorDict["date"] as? String else { return nil }
                            
                            let shortMsg = message.components(separatedBy: "\n").first ?? message
                            let date = formatRelativeDate(dateString)
                            
                            return GitHubCommitInfo(id: sha, message: shortMsg, author: authorName, date: date, url: htmlUrl)
                        }
                    }
                } else if let jsonDict = try? JSONSerialization.jsonObject(with: commitsData) as? [String: Any] {
                    let providerName = isGitLab ? "GitLab" : (isBitbucket ? "Bitbucket" : "GitHub")
                    if let message = jsonDict["message"] as? String {
                        self.contextFetchError = "\(providerName) Error: " + message
                    } else if let errorMsg = jsonDict["error"] as? String {
                        let errorDesc = jsonDict["error_description"] as? String ?? ""
                        self.contextFetchError = "\(providerName) Error: \(errorMsg) \(errorDesc)"
                    } else {
                        self.contextFetchError = "Unexpected response: " + (String(data: commitsData, encoding: .utf8) ?? "")
                    }
                } else {
                    self.contextFetchError = "Failed to parse response: " + (String(data: commitsData, encoding: .utf8) ?? "")
                }
                
                let (prsData, _) = try await EngineEndpoint.shared.session.data(for: prsReq)
                if isBitbucket {
                    if let jsonDict = try? JSONSerialization.jsonObject(with: prsData) as? [String: Any],
                       let values = jsonDict["values"] as? [[String: Any]] {
                        self.recentPRs = values.compactMap { dict -> GitHubPRInfo? in
                            guard let id = dict["id"] as? Int,
                                  let title = dict["title"] as? String,
                                  let dateString = dict["created_on"] as? String else { return nil }
                            let authorDict = dict["author"] as? [String: Any]
                            let login = authorDict?["display_name"] as? String ?? authorDict?["nickname"] as? String ?? "User"
                            let links = dict["links"] as? [String: Any]
                            let htmlLink = links?["html"] as? [String: Any]
                            let webUrl = htmlLink?["href"] as? String ?? ""
                            let date = formatRelativeDate(dateString)
                            return GitHubPRInfo(id: id, title: title, author: login, date: date, url: webUrl)
                        }
                    }
                } else if let jsonArray = try? JSONSerialization.jsonObject(with: prsData) as? [[String: Any]] {
                    self.recentPRs = jsonArray.compactMap { dict -> GitHubPRInfo? in
                        if isGitLab {
                            guard let number = dict["iid"] as? Int,
                                  let title = dict["title"] as? String,
                                  let authorDict = dict["author"] as? [String: Any],
                                  let login = authorDict["username"] as? String,
                                  let dateString = dict["created_at"] as? String else { return nil }
                            let webUrl = dict["web_url"] as? String ?? ""
                            let date = formatRelativeDate(dateString)
                            return GitHubPRInfo(id: number, title: title, author: login, date: date, url: webUrl)
                        } else {
                            guard let number = dict["number"] as? Int,
                                  let title = dict["title"] as? String,
                                  let htmlUrl = dict["html_url"] as? String,
                                  let userDict = dict["user"] as? [String: Any],
                                  let login = userDict["login"] as? String,
                                  let dateString = dict["created_at"] as? String else { return nil }
                            let date = formatRelativeDate(dateString)
                            return GitHubPRInfo(id: number, title: title, author: login, date: date, url: htmlUrl)
                        }
                    }
                }
            } catch {
                self.contextFetchError = error.localizedDescription
            }
            
            self.isFetchingContext = false
        }
    }
    
    private func generateArchitecture() {
        let token = getProviderToken()
        
        guard !token.isEmpty else {
            let providerName = gitProvider == "gitlab" ? "GitLab" : (gitProvider == "bitbucket" ? "Bitbucket" : "GitHub")
            engineClient.architectureGenMessage = "Add a \(providerName) token in Settings → Integrations to continue."
            return
        }
        guard !activeRepoBinding.wrappedValue.isEmpty else {
            engineClient.architectureGenMessage = "Please select a repository."
            return
        }
        
        let provider = UserDefaults.standard.string(forKey: "llmProvider") ?? "openrouter"
        let baseUrl = UserDefaults.standard.string(forKey: "llmBaseUrl") ?? "https://openrouter.ai/api/v1"
        let model = UserDefaults.standard.string(forKey: "llmModel") ?? "openai/gpt-4o-mini"
        
        let llmApiKey = SecretsManager.readSecret(forKey: "llmApiKey") ?? ""
        let linearApiKey = SecretsManager.readSecret(forKey: "linearApiToken") ?? ""
        
        engineClient.isGeneratingArchitecture = true
        engineClient.architectureGenMessage = "Agent is exploring the repository... this may take a few minutes."
        
        let url = EngineEndpoint.shared.url("/reconcile/architecture")
        var req = URLRequest(url: url, timeoutInterval: 600)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let targetSystem = UserDefaults.standard.string(forKey: "targetSystem") ?? "local"
        let targetUrl = targetSystem == "obsidian" 
            ? (UserDefaults.standard.string(forKey: "obsidianPath") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) 
            : (UserDefaults.standard.string(forKey: "confluenceUrl") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body: [String: Any] = [
            "github_token": token,
            "github_repo": selectedGitHubRepo,
            "github_branch": selectedGitHubBranch,
            "git_provider": gitProvider,
            "gitlab_host": gitlabHost,
            "gitlab_repo": selectedGitLabRepo,
            "gitlab_branch": selectedGitLabBranch,
            "bitbucket_repo": selectedBitbucketRepo,
            "bitbucket_branch": selectedBitbucketBranch,
            "target_type": targetSystem,
            "confluence_url": targetUrl,
            "linear_api_token": linearApiKey,
            "linear_workspace_id": UserDefaults.standard.string(forKey: "linearWorkspaceId") ?? "",
            "notion_api_key": UserDefaults.standard.string(forKey: "notionApiKey") ?? "",
            "notion_page_id": UserDefaults.standard.string(forKey: "notionPageId") ?? "",
            "voice_text": "Please analyze the whole architecture.",
            "llm_provider": provider,
            "llm_base_url": baseUrl,
            "llm_model": model,
            "llm_api_key": llmApiKey
        ]
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        Task { @MainActor in
            do {
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 300.0
                config.timeoutIntervalForResource = 300.0
                let session = EngineEndpoint.shared.session(configuration: config)
                let (data, response) = try await session.data(for: req)
                engineClient.isGeneratingArchitecture = false
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String, status == "failed" || status == "error" {
                        let msg = (json["detail"] as? String) ?? (json["message"] as? String) ?? (json["error"] as? String) ?? "Generation failed"
                        engineClient.architectureGenMessage = "Error: \(msg.isEmpty ? "Generation failed" : msg)"
                    } else {
                        engineClient.architectureGenMessage = "Architecture generation complete! Check Pending Updates."
                        NotificationCenter.default.post(name: NSNotification.Name("RefreshPendingUpdates"), object: nil)
                    }
                } else {
                    var errDetail = "Unknown server error"
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let d = json["detail"] as? String, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            errDetail = d
                        } else if let m = json["message"] as? String, !m.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            errDetail = m
                        } else if let e = json["error"] as? String, !e.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            errDetail = e
                        } else if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                            errDetail = raw
                        }
                    } else if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                        errDetail = raw
                    }
                    engineClient.architectureGenMessage = "Error: \(errDetail)"
                }
            } catch {
                engineClient.isGeneratingArchitecture = false
                let nsErr = error as NSError
                if nsErr.domain == NSURLErrorDomain {
                    engineClient.architectureGenMessage = "Error: Network issue or unable to reach backend. Please check your internet connection and try again."
                } else {
                    engineClient.architectureGenMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func fetchRepositories() {
        let token = getProviderToken()
        
        guard !token.isEmpty else {
            let providerName = gitProvider == "gitlab" ? "GitLab" : (gitProvider == "bitbucket" ? "Bitbucket" : "GitHub")
            self.fetchError = "Add a \(providerName) token in Settings → Integrations to see your repositories."
            return
        }
        
        isFetchingRepos = true
        fetchError = nil
        
        if gitProvider == "bitbucket" {
            fetchBitbucketWorkspaces(token: token)
        } else {
            if gitProvider == "gitlab" { cachedGitLabRepos = "" }
            else { cachedAvailableRepos = "" }
            fetchPage(page: 1, token: token, accumulated: [])
        }
    }
    
    private func fetchBitbucketWorkspaces(token: String) {
        let urlString = "https://api.bitbucket.org/2.0/workspaces?role=member&pagelen=50"
        guard let url = URL(string: urlString) else {
            isFetchingRepos = false
            return
        }
        
        var request = URLRequest(url: url)
        if token.contains(":") {
            let base64Token = Data(token.utf8).base64EncodedString()
            request.setValue("Basic \(base64Token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        EngineEndpoint.shared.session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data, error == nil else {
                    self.isFetchingRepos = false
                    self.fetchError = error?.localizedDescription
                    return
                }
                
                if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let values = jsonDict["values"] as? [[String: Any]], !values.isEmpty {
                    let workspaceSlugs = values.compactMap { item -> String? in
                        if let ws = item["workspace"] as? [String: Any] {
                            return ws["slug"] as? String
                        }
                        return item["slug"] as? String
                    }
                    
                    self.fetchBitbucketReposForWorkspaces(slugs: workspaceSlugs, token: token, accumulated: [])
                } else {
                    // Fallback to checking user profile
                    self.fetchBitbucketUserRepos(token: token)
                }
            }
        }.resume()
    }
    
    private func fetchBitbucketUserRepos(token: String) {
        let urlString = "https://api.bitbucket.org/2.0/user"
        guard let url = URL(string: urlString) else {
            self.isFetchingRepos = false
            return
        }
        var request = URLRequest(url: url)
        if token.contains(":") {
            let base64Token = Data(token.utf8).base64EncodedString()
            request.setValue("Basic \(base64Token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        EngineEndpoint.shared.session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let data = data,
                   let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let username = jsonDict["username"] as? String, !username.isEmpty {
                    self.fetchBitbucketReposForWorkspaces(slugs: [username], token: token, accumulated: [])
                } else {
                    // Fallback for Repository Access Tokens: Probe active or candidate repo
                    let candidate = self.selectedBitbucketRepo.isEmpty ? "vkazmin/test-repo-1" : self.selectedBitbucketRepo
                    self.testBitbucketRepo(repo: candidate, token: token)
                }
            }
        }.resume()
    }
    
    private func testBitbucketRepo(repo: String, token: String) {
        guard let url = URL(string: "https://api.bitbucket.org/2.0/repositories/\(repo)") else {
            self.isFetchingRepos = false
            return
        }
        var request = URLRequest(url: url)
        if token.contains(":") {
            let base64Token = Data(token.utf8).base64EncodedString()
            request.setValue("Basic \(base64Token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        EngineEndpoint.shared.session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isFetchingRepos = false
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    var current = self.availableRepos
                    if !current.contains(repo) {
                        current.append(repo)
                    }
                    self.cachedBitbucketRepos = current.joined(separator: ",")
                    self.selectedBitbucketRepo = repo
                    self.fetchBranches(repo: repo)
                } else {
                    if let data = data,
                       let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorDict = jsonDict["error"] as? [String: Any],
                       let msg = errorDict["message"] as? String {
                        self.fetchError = "Bitbucket: \(msg)"
                    } else {
                        self.fetchError = "Could not discover repositories. Click Refresh or check your token."
                    }
                }
            }
        }.resume()
    }
    
    private func fetchBitbucketReposForWorkspaces(slugs: [String], token: String, accumulated: [String]) {
        guard let currentSlug = slugs.first else {
            self.cachedBitbucketRepos = accumulated.joined(separator: ",")
            self.isFetchingRepos = false
            if !accumulated.isEmpty && !accumulated.contains(self.selectedBitbucketRepo) {
                self.selectedBitbucketRepo = accumulated[0]
                self.fetchBranches(repo: accumulated[0])
            } else if !self.selectedBitbucketRepo.isEmpty {
                self.fetchBranches(repo: self.selectedBitbucketRepo)
            }
            return
        }
        
        let remaining = Array(slugs.dropFirst())
        let urlString = "https://api.bitbucket.org/2.0/repositories/\(currentSlug)?pagelen=100"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        if token.contains(":") {
            let base64Token = Data(token.utf8).base64EncodedString()
            request.setValue("Basic \(base64Token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        EngineEndpoint.shared.session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                var newAccumulated = accumulated
                if let data = data,
                   let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let values = jsonDict["values"] as? [[String: Any]] {
                    let repos = values.compactMap { $0["full_name"] as? String }
                    newAccumulated.append(contentsOf: repos)
                }
                self.fetchBitbucketReposForWorkspaces(slugs: remaining, token: token, accumulated: newAccumulated)
            }
        }.resume()
    }
    
    private func fetchPage(page: Int, token: String, accumulated: [String]) {
        let isGitLab = gitProvider == "gitlab"
        let urlString: String
        if isGitLab {
            urlString = "\(gitlabHost)/api/v4/projects?membership=true&order_by=updated_at&sort=desc&per_page=100&page=\(page)"
        } else {
            urlString = "https://api.github.com/user/repos?per_page=100&sort=updated&page=\(page)"
        }
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        
        if isGitLab {
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        } else {
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        }
        
        EngineEndpoint.shared.session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.fetchError = error.localizedDescription
                    self.isFetchingRepos = false
                    return
                }
                guard let data = data else {
                    self.isFetchingRepos = false
                    return
                }
                do {
                    if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        let repos = jsonArray.compactMap { dict -> String? in
                            if isGitLab {
                                return dict["path_with_namespace"] as? String
                            } else {
                                return dict["full_name"] as? String
                            }
                        }
                        var newAccumulated = accumulated
                        newAccumulated.append(contentsOf: repos)
                        
                        if jsonArray.count == 100 {
                            self.fetchPage(page: page + 1, token: token, accumulated: newAccumulated)
                        } else {
                            if isGitLab {
                                self.cachedGitLabRepos = newAccumulated.joined(separator: ",")
                            } else {
                                self.cachedAvailableRepos = newAccumulated.joined(separator: ",")
                            }
                            self.isFetchingRepos = false
                            
                            if !newAccumulated.isEmpty && !newAccumulated.contains(self.activeRepoBinding.wrappedValue) {
                                self.activeRepoBinding.wrappedValue = newAccumulated[0]
                                self.fetchBranches(repo: newAccumulated[0])
                            } else if !self.activeRepoBinding.wrappedValue.isEmpty {
                                self.fetchBranches(repo: self.activeRepoBinding.wrappedValue)
                            }
                        }
                    } else if let jsonDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let providerName = isGitLab ? "GitLab" : "GitHub"
                        if let message = jsonDict["message"] as? String {
                            self.fetchError = "\(providerName) Error: " + message
                        } else if let errorMsg = jsonDict["error"] as? String {
                            let errorDesc = jsonDict["error_description"] as? String ?? ""
                            self.fetchError = "\(providerName) Error: \(errorMsg) \(errorDesc)"
                        } else {
                            self.fetchError = "Unexpected response: " + (String(data: data, encoding: .utf8) ?? "")
                        }
                        self.isFetchingRepos = false
                    } else {
                        self.fetchError = "Failed to parse response: " + (String(data: data, encoding: .utf8) ?? "")
                        self.isFetchingRepos = false
                    }
                } catch {
                    self.fetchError = "Failed to parse response."
                    self.isFetchingRepos = false
                }
            }
        }.resume()
    }
    
    private func fetchBranches(repo: String) {
        let isGitLab = gitProvider == "gitlab"
        let isBitbucket = gitProvider == "bitbucket"
        let token = getProviderToken()
        
        guard !token.isEmpty, !repo.isEmpty else { return }
        isFetchingBranches = true
        
        let urlString: String
        if isGitLab {
            var charSet = CharacterSet.urlPathAllowed
            charSet.remove("/")
            let encodedRepo = repo.addingPercentEncoding(withAllowedCharacters: charSet) ?? repo.replacingOccurrences(of: "/", with: "%2F")
            urlString = "\(gitlabHost)/api/v4/projects/\(encodedRepo)/repository/branches?per_page=100"
        } else if isBitbucket {
            urlString = "https://api.bitbucket.org/2.0/repositories/\(repo)/refs/branches?pagelen=100"
        } else {
            urlString = "https://api.github.com/repos/\(repo)/branches?per_page=100"
        }
        
        guard let url = URL(string: urlString) else {
            isFetchingBranches = false
            return
        }
        var request = URLRequest(url: url)
        if isGitLab {
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        } else if isBitbucket {
            if token.contains(":") {
                let base64Token = Data(token.utf8).base64EncodedString()
                request.setValue("Basic \(base64Token)", forHTTPHeaderField: "Authorization")
            } else {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        } else {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        }
        
        EngineEndpoint.shared.session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isFetchingBranches = false
                guard let data = data, error == nil else { return }
                do {
                    var branchNames: [String] = []
                    if isBitbucket {
                        if let jsonDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let values = jsonDict["values"] as? [[String: Any]] {
                            branchNames = values.compactMap { $0["name"] as? String }
                        }
                    } else if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        branchNames = jsonArray.compactMap { $0["name"] as? String }
                    }
                    
                    self.availableBranches = branchNames
                    if !branchNames.isEmpty {
                        if !branchNames.contains(self.activeBranchBinding.wrappedValue) {
                            let newBranch = branchNames.contains("main") ? "main" : (branchNames.contains("master") ? "master" : branchNames[0])
                            self.activeBranchBinding.wrappedValue = newBranch
                            self.fetchContext(repo: repo, branch: newBranch)
                        } else {
                            self.fetchContext(repo: repo, branch: self.activeBranchBinding.wrappedValue)
                        }
                    }
                } catch {
                    print("Error parsing branches: \(error)")
                }
            }
        }.resume()
    }

    private var sourcePicker: some View {
        HStack(spacing: 8) {
            Text("Source:")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                ForEach([("github", "GitHub"), ("gitlab", "GitLab"), ("bitbucket", "Bitbucket")], id: \.0) { item in
                    let isSelected = gitProvider == item.0
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            gitProvider = item.0
                        }
                    }) {
                        HStack(spacing: 6) {
                            GitProviderBrandLogo(provider: item.0, size: 14, isMonochrome: true)
                            Text(item.1)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .rounded))
                        }
                        .foregroundColor(isSelected ? .appAccent : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.appAccent.opacity(0.15) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            
            Spacer()
        }
    }
}

// MARK: - Row Views (Extracted to prevent hover lag)

struct CommitRowView: View {
    let commit: GitHubCommitInfo
    @Binding var selectedCommitsSet: Set<String>
    let saveSelections: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { selectedCommitsSet.contains(commit.id) },
                set: { isOn in
                    if isOn { selectedCommitsSet.insert(commit.id) }
                    else { selectedCommitsSet.remove(commit.id) }
                    saveSelections()
                }
            ))
            .labelsHidden()
            .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text(String(commit.id.prefix(7)))
                        .font(.system(.caption, design: .monospaced))
                        .bold()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                    
                    Text(commit.author)
                        .font(.caption)
                        .foregroundColor(.dictySecondary)
                    
                    Spacer()
                    
                    Text(commit.date)
                        .font(.caption2)
                        .foregroundColor(.dictySecondary)
                    
                    if !commit.url.isEmpty {
                        Link(destination: URL(string: commit.url) ?? URL(string: "https://bitbucket.org")!) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.dictySecondary)
                        }
                    }
                }
                
                Text(commit.message)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundColor(.primary)
            }
            .padding(6)
            .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .onHover { isHovered = $0 }
        }
    }
}

struct PRRowView: View {
    let pr: GitHubPRInfo
    @Binding var selectedPRsSet: Set<Int>
    let saveSelections: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { selectedPRsSet.contains(pr.id) },
                set: { isOn in
                    if isOn { selectedPRsSet.insert(pr.id) }
                    else { selectedPRsSet.remove(pr.id) }
                    saveSelections()
                }
            ))
            .labelsHidden()
            .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text("#\(pr.id)")
                        .font(.system(.caption, design: .monospaced))
                        .bold()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.sageGreen.opacity(0.18))
                        .foregroundColor(.primary)
                        .cornerRadius(4)
                    
                    Text(pr.author)
                        .font(.caption)
                        .foregroundColor(.dictySecondary)
                    
                    Spacer()
                    
                    Text(pr.date)
                        .font(.caption2)
                        .foregroundColor(.dictySecondary)
                    
                    if !pr.url.isEmpty {
                        Link(destination: URL(string: pr.url) ?? URL(string: "https://bitbucket.org")!) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.dictySecondary)
                        }
                    }
                }
                
                Text(pr.title)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundColor(.primary)
            }
            .padding(6)
            .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Projects → Advanced
//

// The Librarian's documentation prompts and its knowledge-base target used to
// sit on their own pages. They live here now, next to the projects that use them.
struct ProjectsAdvancedView: View {
    @EnvironmentObject var engineClient: EngineClient
    @AppStorage("targetSystem") private var targetSystem: String = "confluence"

    private let documentationPromptKeys = [
        "architecture_system",
        "confluence_agent_system",
        "obsidian_agent_system",
        "hub_system",
        "reconcile_system"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                knowledgeBaseCard
                
                PromptsSettingsView(title: "Documentation prompts", promptKeys: documentationPromptKeys)
                    .frame(minHeight: 450)
            }
            .padding(24)
        }
    }

    private var knowledgeBaseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Knowledge base")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    Text("Where Dicty writes the docs it creates. Pick a target, then open settings for its details.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Open knowledge base settings") {
                    UserDefaults.standard.set(9, forKey: "settingsTabSelection")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            KnowledgeBaseTargetChips(selection: $targetSystem)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

struct KnowledgeBaseTargetChips: View {
    @Binding var selection: String
    
    private let targets: [(id: String, name: String)] = [
        ("confluence", "Confluence"),
        ("linear", "Linear"),
        ("notion", "Notion"),
        ("obsidian", "Files")
    ]
    
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(targets, id: \.id) { target in
                    chipButton(target)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    chipButton(targets[0])
                    chipButton(targets[1])
                }
                HStack(spacing: 8) {
                    chipButton(targets[2])
                    chipButton(targets[3])
                }
            }
        }
    }
    
    @ViewBuilder
    private func chipButton(_ target: (id: String, name: String)) -> some View {
        let isSelected = selection == target.id
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selection = target.id
            }
        }) {
            HStack(spacing: 6) {
                targetIcon(for: target.id)
                Text(target.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .rounded))
            }
            .foregroundColor(isSelected ? .appAccent : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.appAccent.opacity(0.15) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.appAccent.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func targetIcon(for id: String) -> some View {
        switch id {
        case "confluence": ConfluenceLogoView(size: 14)
        case "linear": LinearLogoView(size: 14)
        case "notion": NotionLogoView(size: 14)
        case "obsidian": LocalFilesLogoView(size: 14)
        default: Image(systemName: "folder").font(.system(size: 12))
        }
    }
}
