import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

// MARK: - API Settings
// MARK: - AI Providers Settings
struct APISettingsView: View {
    @AppStorage("llmProvider") private var llmProvider: String = "openrouter"
    @AppStorage("llmBaseUrl") private var llmBaseUrl: String = "http://localhost:1234/v1"
    @AppStorage("llmModel") private var llmModel: String = "qwen/qwen3.7-plus"
    
    @EnvironmentObject var engineClient: EngineClient
    @State private var llmApiKey: String = ""
    @State private var showSavedLLM = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsPageHeader(
                    title: "AI Providers",
                    description: "Choose how Dicty connects to AI text and speech models.",
                    helpTopic: .api_keys
                )
                
                Divider()
                
                // LLM Intelligence Provider Section
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.appAccent)
                        Text("Text Model Provider")
                            .font(.headline)
                    }
                    
                    Text("Powers speech restructuring, markdown note styling, summarization, and audio re-processing. Choose how Dicty accesses text models:")
                        .font(.caption)
                        .foregroundColor(.dictySecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    LLMProviderSegmentedPicker(selection: $llmProvider)
                    
                    if llmProvider == "dicty_cloud" {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "cloud.fill")
                                    .foregroundColor(.appAccent)
                                    .font(.system(size: 13))
                                Text("Dicty Cloud")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            Text("Zero setup required. Usage is tied to your Dicty account balance without needing separate provider accounts.")
                                .font(.caption)
                                .foregroundColor(.dictySecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appAccent.opacity(0.08))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appAccent.opacity(0.2), lineWidth: 1))
                    } else if llmProvider == "openrouter" {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    OpenRouterLogoView(size: 14)
                                    Text("OpenRouter (Bring Your Own Key)")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                }
                                Text("Connect your OpenRouter account to unlock Claude, GPT, Gemini, DeepSeek and more. Requests are billed directly to your OpenRouter balance.")
                                    .font(.caption)
                                    .foregroundColor(.dictySecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("OpenRouter API Key")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Spacer()
                                    if let url = URL(string: "https://openrouter.ai/keys") {
                                        Link("Get key", destination: url)
                                            .font(.caption)
                                            .foregroundColor(.appAccent)
                                    }
                                }
                                HStack {
                                    SecureField("sk-or-v1-...", text: $llmApiKey)
                                        .textFieldStyle(.roundedBorder)
                                    Button("Save") {
                                        SecretsManager.saveSecret(llmApiKey, forKey: "llmApiKey")
                                        Task { await engineClient.pushSTTProviderKeys() }
                                        showSavedLLM = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showSavedLLM = false }
                                    }
                                }
                                if showSavedLLM { Text("Saved!").foregroundColor(.appAccent).font(.caption) }
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Default Model ID")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("qwen/qwen3.7-plus", text: $llmModel)
                                    .textFieldStyle(.roundedBorder)
                                Text("You can also browse and select models with 1-click in the Models Library tab.")
                                    .font(.caption2)
                                    .foregroundColor(.dictySecondary)
                            }
                        }
                    } else if llmProvider == "local" {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "server.rack")
                                        .foregroundColor(.appAccent)
                                        .font(.system(size: 13))
                                    Text("Local Server (Ollama / LM Studio)")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                }
                                Text("Format speech and generate summaries 100% offline with complete privacy. Runs entirely on your Mac without external API keys.")
                                    .font(.caption)
                                    .foregroundColor(.dictySecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Base URL")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("http://localhost:1234/v1", text: $llmBaseUrl)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Model Identifier")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("local-model", text: $llmModel)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                // Cloud Transcription: bring-your-own speech-to-text keys
                SpeechProviderKeysSection()
                
                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            llmApiKey = SecretsManager.readSecret(forKey: "llmApiKey") ?? ""
        }
    }
}

// MARK: - Integrations Settings
struct IntegrationsSettingsView: View {
    struct IntegrationItem: Identifiable {
        let id: String
        let name: String
        let tokenKey: String
        let placeholder: String
        let tokenDocURL: String
        let alsoUsesUserDefaults: Bool
    }
    
    private let integrations: [IntegrationItem] = [
        IntegrationItem(id: "github", name: "GitHub", tokenKey: "githubToken", placeholder: "ghp_...", tokenDocURL: "https://github.com/settings/tokens", alsoUsesUserDefaults: false),
        IntegrationItem(id: "gitlab", name: "GitLab", tokenKey: "gitlabToken", placeholder: "glpat-...", tokenDocURL: "https://gitlab.com/-/user_settings/personal_access_tokens", alsoUsesUserDefaults: false),
        IntegrationItem(id: "bitbucket", name: "Bitbucket", tokenKey: "bitbucketToken", placeholder: "App password or token", tokenDocURL: "https://bitbucket.org/account/settings/app-passwords/", alsoUsesUserDefaults: false),
        IntegrationItem(id: "confluence", name: "Confluence", tokenKey: "confluenceToken", placeholder: "API token", tokenDocURL: "https://id.atlassian.com/manage-profile/security/api-tokens", alsoUsesUserDefaults: false),
        IntegrationItem(id: "linear", name: "Linear", tokenKey: "linearApiToken", placeholder: "lin_api_...", tokenDocURL: "https://linear.app/settings/api", alsoUsesUserDefaults: false),
        IntegrationItem(id: "notion", name: "Notion", tokenKey: "notionApiKey", placeholder: "secret_... or ntn_...", tokenDocURL: "https://www.notion.so/my-integrations", alsoUsesUserDefaults: true),
    ]
    
    @State private var activeSheetItem: IntegrationItem? = nil
    @State private var sheetTokenInput: String = ""
    @State private var disconnectConfirmationItem: IntegrationItem? = nil
    @State private var connectedMap: [String: Bool] = [:]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "Integrations",
                    description: "Connect code and project tools to sync documentation, export notes, and feed context into your workflows.",
                    helpTopic: .api_keys
                )
                
                Divider()
                
                VStack(spacing: 8) {
                    ForEach(integrations) { item in
                        integrationRow(item)
                    }
                }
                
                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            refreshConnectionStatuses()
        }
        .sheet(item: $activeSheetItem) { item in
            connectSheet(for: item)
        }
        .alert(
            "Disconnect \(disconnectConfirmationItem?.name ?? "")?",
            isPresented: Binding(
                get: { disconnectConfirmationItem != nil },
                set: { if !$0 { disconnectConfirmationItem = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { disconnectConfirmationItem = nil }
            Button("Disconnect", role: .destructive) {
                if let item = disconnectConfirmationItem {
                    performDisconnect(item)
                }
                disconnectConfirmationItem = nil
            }
        } message: {
            Text("This will remove your stored token from your Mac's Keychain.")
        }
    }
    
    private func refreshConnectionStatuses() {
        for item in integrations {
            let secret = SecretsManager.readSecret(forKey: item.tokenKey) ?? (item.alsoUsesUserDefaults ? UserDefaults.standard.string(forKey: item.tokenKey) : nil) ?? ""
            connectedMap[item.id] = !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    @ViewBuilder
    private func integrationLogo(for id: String) -> some View {
        switch id {
        case "github": GitHubLogoView(size: 16)
        case "gitlab": GitLabLogoView(size: 16)
        case "bitbucket": BitbucketLogoView(size: 16)
        case "confluence": ConfluenceLogoView(size: 16)
        case "linear": LinearLogoView(size: 16)
        case "notion": NotionLogoView(size: 16)
        default: Image(systemName: "puzzlepiece.extension").font(.system(size: 16))
        }
    }
    
    private func integrationRow(_ item: IntegrationItem) -> some View {
        let isConnected = connectedMap[item.id] == true
        
        return HStack(spacing: 12) {
            integrationLogo(for: item.id)
                .frame(width: 20, height: 20, alignment: .center)
            
            Text(item.name)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(isConnected ? "Connected" : "Not connected")
                .font(.system(size: 11, weight: isConnected ? .semibold : .regular, design: .rounded))
                .foregroundColor(isConnected ? .appAccent : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isConnected ? Color.appAccent.opacity(0.12) : Color.primary.opacity(0.04))
                .cornerRadius(5)
            
            Button(isConnected ? "Manage" : "Connect") {
                sheetTokenInput = SecretsManager.readSecret(forKey: item.tokenKey) ?? (item.alsoUsesUserDefaults ? UserDefaults.standard.string(forKey: item.tokenKey) : nil) ?? ""
                activeSheetItem = item
            }
            .buttonStyle(.bordered)
            .tint(isConnected ? .secondary : .appAccent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }
    
    private func connectSheet(for item: IntegrationItem) -> some View {
        let isConnected = connectedMap[item.id] == true
        
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                integrationLogo(for: item.id)
                Text(isConnected ? "Manage \(item.name)" : "Connect to \(item.name)")
                    .font(.headline)
                Spacer()
                Button(action: { activeSheetItem = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            
            Text("Enter your \(item.name) token to enable integration features.")
                .font(.caption)
                .foregroundColor(.dictySecondary)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Token")
                        .font(.caption)
                        .foregroundColor(.dictySecondary)
                    Spacer()
                    if let url = URL(string: item.tokenDocURL) {
                        Link("Get token", destination: url)
                            .font(.caption)
                            .foregroundColor(.appAccent)
                    }
                }
                
                SecureField(item.placeholder, text: $sheetTokenInput)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                if isConnected {
                    Button(role: .destructive, action: {
                        disconnectConfirmationItem = item
                    }) {
                        Text("Disconnect")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Button("Cancel") {
                    activeSheetItem = nil
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    saveToken(for: item, token: sheetTokenInput)
                    activeSheetItem = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 380)
    }
    
    private func saveToken(for item: IntegrationItem, token: String) {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        SecretsManager.saveSecret(clean, forKey: item.tokenKey)
        if item.alsoUsesUserDefaults {
            UserDefaults.standard.set(clean, forKey: item.tokenKey)
        }
        refreshConnectionStatuses()
    }
    
    private func performDisconnect(_ item: IntegrationItem) {
        SecretsManager.saveSecret("", forKey: item.tokenKey)
        if item.alsoUsesUserDefaults {
            UserDefaults.standard.set("", forKey: item.tokenKey)
        }
        sheetTokenInput = ""
        refreshConnectionStatuses()
    }
}

struct InfoSign: View {
    let text: String
    @State private var isHovering = false

    var body: some View {
        Button(action: {
            isHovering.toggle()
        }) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(isHovering ? .sageGreen : .secondary.opacity(0.7))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovering = hover
        }
        .popover(isPresented: $isHovering, arrowEdge: .top) {
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.primary)
                .padding(12)
                .frame(width: 280, alignment: .leading)
        }
    }
}
