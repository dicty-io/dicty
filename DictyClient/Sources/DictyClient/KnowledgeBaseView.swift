import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Linear Structs
struct LinearNode: Codable, Hashable {
    var id: String
    var name: String
}

struct LinearWorkspacesResponse: Codable {
    var status: String
    var workspaces: LinearWorkspacesData
}

struct LinearWorkspacesData: Codable {
    var teams: [LinearNode]
    var projects: [LinearNode]
}

// MARK: - Knowledge Base & Pending Updates

struct KnowledgeBaseSettingsView: View {
    @AppStorage("targetSystem") private var targetSystem: String = "confluence"
    @AppStorage("obsidianPath") private var obsidianPath: String = ""
    @AppStorage("confluenceUrl") private var confluenceUrl: String = ""
    @AppStorage("confluenceSpace") private var confluenceSpace: String = ""
    @AppStorage("confluenceUser") private var confluenceUser: String = ""
    @AppStorage("confluencePageTitle") private var confluencePageTitle: String = "ARCHITECTURE.md"
    
    @AppStorage("linearWorkspaceId") private var linearWorkspaceId: String = ""
    @AppStorage("linearSearchAllWorkspaces") private var linearSearchAllWorkspaces: Bool = false
    @AppStorage("notionApiKey") private var notionApiKey: String = ""
    @AppStorage("notionPageId") private var notionPageId: String = ""
    @State private var linearTeams: [LinearNode] = []
    @State private var linearProjects: [LinearNode] = []
    @State private var isFetchingWorkspaces = false
    @State private var isTestingNotion = false
    @State private var notionTestStatus: String? = nil
    @State private var notionTestSuccess: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(title: "Knowledge Base Settings", description: "Configure your remote or local knowledge base. Dicty will use this to synchronize your documentation.", helpTopic: .projects)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Target System")
                        .font(.headline)
                    KnowledgeBaseSegmentedPicker(selection: $targetSystem)
                    
                    if targetSystem == "confluence" {
                        Text("Target Page (Optional)")
                            .font(.headline)
                        TextField("E.g., Architecture Overview", text: $confluencePageTitle)
                            .textFieldStyle(.roundedBorder)
                    } else if targetSystem == "obsidian" {
                        Text("Specific Target File (Optional)")
                            .font(.headline)
                        HStack {
                            TextField("E.g., ProjectX/Architecture", text: $confluencePageTitle)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = true
                                panel.canChooseDirectories = false
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    let absPath = url.path
                                    if !obsidianPath.isEmpty && absPath.hasPrefix(obsidianPath) {
                                        let relative = absPath.dropFirst(obsidianPath.count)
                                        confluencePageTitle = relative.hasPrefix("/") ? String(relative.dropFirst()) : String(relative)
                                    } else {
                                        confluencePageTitle = absPath
                                    }
                                }
                            }
                        }
                    } else if targetSystem == "notion" {
                        Text("Target Page / Section Title (Optional)")
                            .font(.headline)
                        TextField("E.g., Architecture Overview", text: $confluencePageTitle)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Divider().padding(.vertical)
                    
                    if targetSystem == "confluence" {
                        Text("Host URL")
                            .font(.headline)
                        TextField("https://your-domain.atlassian.net", text: $confluenceUrl)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("Space Key")
                            .font(.headline)
                        TextField("ENG", text: $confluenceSpace)
                            .textFieldStyle(.roundedBorder)
                            
                        Text("Username / Email")
                            .font(.headline)
                        TextField("john@example.com", text: $confluenceUser)
                            .textFieldStyle(.roundedBorder)
                            
                        Text("API Token")
                            .font(.headline)
                        Text("Configure your Confluence API Token in the 'API Integrations' tab.")
                            .font(.caption)
                            .foregroundColor(.appAccent)
                    } else if targetSystem == "linear" {
                        Text("Target Document")
                            .font(.headline)
                        Text("No target required. The AI will autonomously explore your Linear workspace to find the right document or create a new one.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                        
                        Divider().padding(.vertical)
                        
                        HStack {
                            Text("Target Workspace")
                                .font(.headline)
                            Spacer()
                            Button("Refresh") {
                                fetchLinearWorkspaces()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                        
                        if isFetchingWorkspaces {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Picker("", selection: $linearWorkspaceId) {
                                Text("Default Team").tag("")
                                if !linearTeams.isEmpty {
                                    Divider()
                                    ForEach(linearTeams, id: \.id) { team in
                                        Text("Team: \(team.name)").tag("team:\(team.id)")
                                    }
                                }
                                if !linearProjects.isEmpty {
                                    Divider()
                                    ForEach(linearProjects, id: \.id) { project in
                                        Text("Project: \(project.name)").tag("project:\(project.id)")
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            
                            Toggle(isOn: $linearSearchAllWorkspaces) {
                                HStack(spacing: 6) {
                                    Image(systemName: "globe")
                                        .foregroundColor(.dictySecondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Global Document Search")
                                            .font(.subheadline)
                                        Text("If enabled, the AI will search across your entire Linear workspace rather than just the selected team/project.")
                                            .font(.caption2)
                                            .foregroundColor(.dictySecondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .toggleStyle(.appAccent)
                            .controlSize(.small)
                            .padding(.top, 8)
                        }
                        
                        Divider().padding(.vertical)
                        Text("API Token")
                            .font(.headline)
                        Text("Configure your Linear API Token in the 'API Integrations' tab.")
                            .font(.caption)
                            .foregroundColor(.appAccent)
                    } else if targetSystem == "notion" {
                        Text("Parent Page or Database ID")
                            .font(.headline)
                        TextField("32-character ID or full Notion page URL", text: $notionPageId)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("Create an Internal Integration at notion.so/profile/integrations and share your target parent page with it via '...' -> 'Add connections'.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                        
                        Divider().padding(.vertical)
                        
                        Text("API Token")
                            .font(.headline)
                        Text("Configure your Notion Integration Token in the 'API Integrations' tab.")
                            .font(.caption)
                            .foregroundColor(.appAccent)
                        
                        HStack(spacing: 12) {
                            Button(action: testNotionConnection) {
                                HStack(spacing: 6) {
                                    if isTestingNotion {
                                        ProgressView().scaleEffect(0.6)
                                    } else {
                                        Image(systemName: "bolt.horizontal.fill")
                                    }
                                    Text("Test Connection")
                                }
                            }
                            .disabled(isTestingNotion || notionPageId.isEmpty)
                            
                            if let status = notionTestStatus {
                                HStack(spacing: 4) {
                                    Image(systemName: notionTestSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .foregroundColor(notionTestSuccess ? .appAccent : .red)
                                    Text(status)
                                        .font(.caption)
                                        .foregroundColor(notionTestSuccess ? .appAccent : .red)
                                }
                            }
                        }
                        .padding(.top, 4)
                    } else {
                        HStack(spacing: 6) {
                            Text("Local Data Source Path")
                                .font(.headline)
                            InfoSign(text: "This can be an Obsidian vault, a local folder of markdown files, or a locally cloned GitHub repository. The AI will scan this folder for context.")
                        }
                        HStack {
                            TextField("/Users/name/Documents/MyDocs", text: $obsidianPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    obsidianPath = url.path
                                }
                            }
                        }
                    }
                }
                .padding(.top)
            }
            .padding(40)
        }
        .onAppear {
            if targetSystem == "linear" && linearTeams.isEmpty && linearProjects.isEmpty {
                fetchLinearWorkspaces()
            }
        }
        .onChange(of: targetSystem) { _, newSystem in
            ProfileManager.shared.updateActiveProfileModels(targetSystem: newSystem)
            if newSystem == "linear" && linearTeams.isEmpty && linearProjects.isEmpty {
                fetchLinearWorkspaces()
            }
        }
        .onChange(of: obsidianPath) { _, newPath in
            ProfileManager.shared.updateActiveProfileModels(obsidianPath: newPath)
        }
    }
    
    private func fetchLinearWorkspaces() {
        guard let token = SecretsManager.readSecret(forKey: "linearApiToken"), !token.isEmpty else { return }
        isFetchingWorkspaces = true
        var req = EngineEndpoint.shared.request("/linear/workspaces")
        req.setValue(token, forHTTPHeaderField: "X-Linear-Token")
        
        Task { @MainActor in
            do {
                let (data, _) = try await EngineEndpoint.shared.session.data(for: req)
                if let resp = try? JSONDecoder().decode(LinearWorkspacesResponse.self, from: data) {
                    self.linearTeams = resp.workspaces.teams
                    self.linearProjects = resp.workspaces.projects
                }
            } catch {
                print("Failed to fetch linear workspaces: \(error)")
            }
            self.isFetchingWorkspaces = false
        }
    }
    
    private func testNotionConnection() {
        let token = SecretsManager.readSecret(forKey: "notionApiKey") ?? UserDefaults.standard.string(forKey: "notionApiKey") ?? ""
        guard !token.isEmpty else {
            notionTestSuccess = false
            notionTestStatus = "Configure Notion Token in 'API Integrations' tab first."
            return
        }
        guard !notionPageId.isEmpty else {
            notionTestSuccess = false
            notionTestStatus = "Please enter a Parent Page or Database ID."
            return
        }
        isTestingNotion = true
        notionTestStatus = nil
        
        let url = EngineEndpoint.shared.url("/notion/test_connection")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "api_key": token,
            "parent_page_id": notionPageId
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        Task { @MainActor in
            do {
                let (data, _) = try await EngineEndpoint.shared.session.data(for: req)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let success = json["success"] as? Bool ?? false
                    self.notionTestSuccess = success
                    if success {
                        let msg = json["message"] as? String ?? "Connected successfully!"
                        self.notionTestStatus = msg
                    } else {
                        let err = json["error"] as? String ?? "Connection failed."
                        self.notionTestStatus = err
                    }
                } else {
                    self.notionTestSuccess = false
                    self.notionTestStatus = "Invalid engine response."
                }
            } catch {
                self.notionTestSuccess = false
                self.notionTestStatus = error.localizedDescription
            }
            self.isTestingNotion = false
        }
    }
}

struct PendingUpdate: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let original_content: String
    let proposed_content: String
    let page_id: String
    let version: Int
    let confluence_url: String
    let space_key: String
    let target_type: String
    let timestamp: String
}

struct PendingUpdatesView: View {
    @State private var pendingUpdates: [PendingUpdate] = []
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Pending Updates")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Spacer()
                Button(action: fetchPending) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.dictySecondary)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 0)
            
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pendingUpdates.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.sageGreen)
                    Text("You're all caught up!")
                        .font(.title3.bold())
                        .foregroundColor(.dictySecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(pendingUpdates) { update in
                            PendingUpdateCard(update: update, onRefresh: fetchPending)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear(perform: fetchPending)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshPendingUpdates"))) { _ in
            fetchPending()
        }
    }
    
    func fetchPending() {
        isLoading = true
        let url = EngineEndpoint.shared.url("/pending_updates")
        EngineEndpoint.shared.session.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                isLoading = false
                if let data = data,
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let updatesList = dict["updates"] as? [[String: Any]],
                   let jsonData = try? JSONSerialization.data(withJSONObject: updatesList),
                   let decoded = try? JSONDecoder().decode([PendingUpdate].self, from: jsonData) {
                    pendingUpdates = decoded
                }
            }
        }.resume()
    }
}

struct PendingUpdateCard: View {
    let update: PendingUpdate
    let onRefresh: () -> Void
    @State private var isApproving = false
    @State private var renderMarkdown = false
    
    @State private var removedIndices = Set<Int>()
    @State private var insertedIndices = Set<Int>()
    @State private var origLines: [String] = []
    @State private var propLines: [String] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(update.title)
                        .font(.title2.bold())
                    Text(formattedTimestamp(update.timestamp))
                        .font(.caption)
                        .foregroundColor(.dictySecondary)
                }
                Spacer()
                
                HStack(spacing: 8) {
                    // Raw Diff vs Rendered Markdown Toggle
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            renderMarkdown.toggle()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: renderMarkdown ? "text.alignleft" : "text.word.spacing")
                                .font(.system(size: 11))
                            Text(renderMarkdown ? "Raw Diff" : "Markdown")
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                    .help(renderMarkdown ? "Switch to line-by-line diff view" : "Switch to formatted Markdown preview")
                    
                    Text("Target: \(update.target_type == "obsidian" ? "Local Data" : update.target_type.capitalized)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.sageGreen.opacity(0.12))
                        .foregroundColor(.sageGreen)
                        .cornerRadius(4)
                }
            }
            
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Original")
                        .font(.headline)
                        .foregroundColor(.dictySecondary)
                    
                    if renderMarkdown {
                        RichMarkdownDocumentView(content: update.original_content)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 1) {
                                if origLines.isEmpty || (origLines.count == 1 && origLines[0].isEmpty) {
                                    Text("No original content")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.dictySecondary)
                                        .padding(8)
                                } else {
                                    ForEach(0..<origLines.count, id: \.self) { i in
                                        DiffLineRowView(
                                            lineNumber: i + 1,
                                            text: origLines[i],
                                            kind: removedIndices.contains(i) ? .deletion : .neutral
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding(.trailing, 8)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Proposed")
                        .font(.headline)
                        .foregroundColor(.sageGreen)
                    
                    if renderMarkdown {
                        RichMarkdownDocumentView(content: update.proposed_content)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 1) {
                                ForEach(0..<propLines.count, id: \.self) { i in
                                    DiffLineRowView(
                                        lineNumber: i + 1,
                                        text: propLines[i],
                                        kind: insertedIndices.contains(i) ? .addition : .neutral
                                    )
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
            .frame(minHeight: 200, idealHeight: 400, maxHeight: 600)
            .onAppear {
                origLines = update.original_content.components(separatedBy: .newlines)
                propLines = update.proposed_content.components(separatedBy: .newlines)
                
                let diff = propLines.difference(from: origLines)
                for change in diff {
                    switch change {
                    case .remove(let offset, _, _):
                        removedIndices.insert(offset)
                    case .insert(let offset, _, _):
                        insertedIndices.insert(offset)
                    }
                }
            }
            
            HStack {
                Button(action: rejectUpdate) {
                    Text("Reject")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: approveUpdate) {
                    if isApproving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Approve & Publish")
                            .bold()
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.sageGreen)
                            .cornerRadius(8)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isApproving)
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    func approveUpdate() {
        isApproving = true
        let confluenceToken = SecretsManager.readSecret(forKey: "confluenceToken") ?? ""
        let confluenceUser = UserDefaults.standard.string(forKey: "confluenceUser") ?? ""
        let linearToken = SecretsManager.readSecret(forKey: "linearApiToken") ?? ""
        let notionKey = SecretsManager.readSecret(forKey: "notionApiKey") ?? UserDefaults.standard.string(forKey: "notionApiKey") ?? ""
        let notionPage = UserDefaults.standard.string(forKey: "notionPageId") ?? ""
        
        let url = EngineEndpoint.shared.url("/pending_updates/\(update.id)/approve")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = [
            "username": confluenceUser, 
            "api_token": confluenceToken,
            "linear_api_token": linearToken,
            "notion_api_key": notionKey,
            "notion_page_id": notionPage
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        EngineEndpoint.shared.session.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                isApproving = false
                onRefresh()
            }
        }.resume()
    }
    
    func rejectUpdate() {
        let url = EngineEndpoint.shared.url("/pending_updates/\(update.id)/reject")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        EngineEndpoint.shared.session.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                onRefresh()
            }
        }.resume()
    }
    
    private func formattedTimestamp(_ isoString: String) -> String {
        if isoString.count >= 19 {
            let datePart = isoString.prefix(10)
            let timePart = isoString.dropFirst(11).prefix(8)
            return "\(datePart) \(timePart)"
        }
        return isoString
    }
}

struct HistoryUpdate: Identifiable, Codable {
    let id: String
    let title: String
    let original_content: String
    let proposed_content: String
    let target_type: String
    let status: String
    let timestamp: String
    let resolved_at: String?
}

struct UpdatesHistoryView: View {
    @State private var historyUpdates: [HistoryUpdate] = []
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Updates History")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Spacer()
                Button(action: fetchHistory) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.dictySecondary)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 0)
            
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if historyUpdates.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 50))
                        .foregroundColor(.dictySecondary)
                    Text("No history yet.")
                        .font(.title3.bold())
                        .foregroundColor(.dictySecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(historyUpdates) { update in
                            HistoryUpdateCard(update: update)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear(perform: fetchHistory)
    }
    
    func fetchHistory() {
        isLoading = true
        let url = EngineEndpoint.shared.url("/updates/history")
        EngineEndpoint.shared.session.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                isLoading = false
                if let data = data,
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let updatesList = dict["updates"] as? [[String: Any]],
                   let jsonData = try? JSONSerialization.data(withJSONObject: updatesList),
                   let decoded = try? JSONDecoder().decode([HistoryUpdate].self, from: jsonData) {
                    historyUpdates = decoded
                }
            }
        }.resume()
    }
}

struct HistoryUpdateCard: View {
    let update: HistoryUpdate
    @State private var isExpanded = false
    @State private var renderMarkdown = true
    @State private var isReuploading = false
    @State private var reuploadSuccess = false
    @State private var reuploadError: String? = nil
    
    private var formattedDate: String {
        let dateString = update.resolved_at ?? update.timestamp
        let parts = dateString.split(separator: "T")
        guard parts.count == 2 else { return dateString }
        let timeParts = parts[1].split(separator: ".")
        return "\(parts[0]) \(timeParts[0])"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(update.title)
                        .font(.title2.bold())
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundColor(.dictySecondary)
                }
                Spacer()
                
                HStack(spacing: 8) {
                    // Raw vs Markdown Toggle
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            renderMarkdown.toggle()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: renderMarkdown ? "text.alignleft" : "text.word.spacing")
                                .font(.system(size: 11))
                            Text(renderMarkdown ? "Raw Text" : "Markdown")
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                    .help(renderMarkdown ? "Switch to plain text view" : "Switch to formatted Markdown preview")
                    
                    Text("Target: \(update.target_type == "obsidian" ? "Local Data" : update.target_type.capitalized)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.sageGreen.opacity(0.12))
                        .foregroundColor(.sageGreen)
                        .cornerRadius(4)
                    
                    Text(update.status.capitalized)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(update.status == "approved" ? Color.stylishGreen.opacity(0.2) : Color.red.opacity(0.2))
                        .foregroundColor(update.status == "approved" ? .stylishGreen : .red)
                        .cornerRadius(6)
                }
            }
            
            // Content Container with reliable height measurement
            Group {
                if renderMarkdown {
                    RichMarkdownDocumentView(content: update.proposed_content)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            let lines = update.proposed_content.components(separatedBy: .newlines)
                            if lines.isEmpty || (lines.count == 1 && lines[0].isEmpty) {
                                Text("No content")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.dictySecondary)
                                    .padding(14)
                            } else {
                                ForEach(0..<lines.count, id: \.self) { i in
                                    DiffLineRowView(
                                        lineNumber: i + 1,
                                        text: lines[i],
                                        kind: .neutral
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
            }
            .frame(minHeight: 180, idealHeight: isExpanded ? 480 : 220, maxHeight: isExpanded ? 650 : 220)
            
            HStack(spacing: 14) {
                Button(action: { 
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle() 
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        Text(isExpanded ? "Show Less" : "Show More")
                    }
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Spacer()
                
                if let err = reuploadError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                if reuploadSuccess {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.stylishGreen)
                        Text("Synced to \(update.target_type.capitalized)!")
                            .font(.caption.bold())
                            .foregroundColor(.stylishGreen)
                    }
                }
                
                // Re-upload Button
                Button(action: reuploadUpdate) {
                    HStack(spacing: 6) {
                        if isReuploading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        Text(isReuploading ? "Uploading..." : "Re-upload to \(update.target_type == "obsidian" ? "Local Data" : update.target_type.capitalized)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(isReuploading ? Color.secondary.opacity(0.4) : Color.sageGreen)
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .disabled(isReuploading)
                .help("Re-publish this documentation directly to \(update.target_type.capitalized)")
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    func reuploadUpdate() {
        isReuploading = true
        reuploadSuccess = false
        reuploadError = nil
        
        let confluenceToken = SecretsManager.readSecret(forKey: "confluenceToken") ?? ""
        let confluenceUser = UserDefaults.standard.string(forKey: "confluenceUser") ?? ""
        let linearToken = SecretsManager.readSecret(forKey: "linearApiToken") ?? ""
        let notionKey = SecretsManager.readSecret(forKey: "notionApiKey") ?? UserDefaults.standard.string(forKey: "notionApiKey") ?? ""
        let notionPage = UserDefaults.standard.string(forKey: "notionPageId") ?? ""
        
        let url = EngineEndpoint.shared.url("/updates/history/\(update.id)/reupload")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = [
            "username": confluenceUser, 
            "api_token": confluenceToken,
            "linear_api_token": linearToken,
            "notion_api_key": notionKey,
            "notion_page_id": notionPage
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        EngineEndpoint.shared.session.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                isReuploading = false
                if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 {
                    reuploadSuccess = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        reuploadSuccess = false
                    }
                } else {
                    var msg = err?.localizedDescription ?? "Failed to re-upload"
                    if let data = data, let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let detail = dict["detail"] as? String ?? dict["message"] as? String {
                        msg = detail
                    }
                    reuploadError = msg
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        reuploadError = nil
                    }
                }
            }
        }.resume()
    }
}

// MARK: - Studio IDE Diff Line Row View

struct DiffLineRowView: View {
    @Environment(\.colorScheme) var colorScheme
    let lineNumber: Int
    let text: String
    let kind: DiffKind
    
    enum DiffKind {
        case deletion
        case addition
        case neutral
    }
    
    private var isModified: Bool {
        kind != .neutral
    }
    
    private var accentBarColor: Color {
        switch kind {
        case .deletion:
            return colorScheme == .dark
                ? Color(red: 248/255, green: 81/255, blue: 73/255)
                : Color(red: 207/255, green: 34/255, blue: 46/255)
        case .addition:
            return colorScheme == .dark
                ? Color.sageGreen
                : Color(red: 26/255, green: 127/255, blue: 55/255)
        case .neutral:
            return Color.clear
        }
    }
    
    private var textColor: Color {
        switch kind {
        case .deletion:
            return colorScheme == .dark
                ? Color(red: 255/255, green: 175/255, blue: 168/255)
                : Color(red: 165/255, green: 20/255, blue: 25/255)
        case .addition:
            return colorScheme == .dark
                ? Color(red: 170/255, green: 228/255, blue: 170/255)
                : Color(red: 20/255, green: 105/255, blue: 40/255)
        case .neutral:
            return .primary
        }
    }
    
    private var signColor: Color {
        switch kind {
        case .deletion:
            return colorScheme == .dark
                ? Color(red: 248/255, green: 81/255, blue: 73/255)
                : Color(red: 207/255, green: 34/255, blue: 46/255)
        case .addition:
            return colorScheme == .dark
                ? Color.sageGreen
                : Color(red: 26/255, green: 127/255, blue: 55/255)
        case .neutral:
            return Color.clear
        }
    }
    
    private var backgroundColor: Color {
        switch kind {
        case .deletion:
            return colorScheme == .dark
                ? Color(red: 248/255, green: 81/255, blue: 73/255).opacity(0.12)
                : Color(red: 255/255, green: 215/255, blue: 215/255).opacity(0.6)
        case .addition:
            return colorScheme == .dark
                ? Color.sageGreen.opacity(0.14)
                : Color(red: 215/255, green: 245/255, blue: 220/255).opacity(0.65)
        case .neutral:
            return Color.clear
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Accent Indicator Bar (3pt)
            Rectangle()
                .fill(accentBarColor)
                .frame(width: 3)
            
            // Gutter: Line Number + Operation Sign (+ / -)
            HStack(spacing: 4) {
                Text("\(lineNumber)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(colorScheme == .dark ? .dictySecondary.opacity(0.4) : .secondary.opacity(0.6))
                    .frame(width: 28, alignment: .trailing)
                
                Text(kind == .deletion ? "-" : (kind == .addition ? "+" : " "))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(signColor)
                    .frame(width: 12, alignment: .center)
            }
            .padding(.trailing, 6)
            
            // Text Content
            Text(text.isEmpty ? " " : text)
                .font(.system(size: 12, weight: isModified ? .medium : .regular, design: .monospaced))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2.5)
        }
        .background(backgroundColor)
    }
}

// MARK: - Rich Markdown Document View

struct RichMarkdownDocumentView: View {
    let content: String
    
    struct TableData {
        let headers: [String]
        let rows: [[String]]
    }
    
    struct CodeData {
        let language: String
        let code: String
    }
    
    struct Block: Identifiable {
        let id = UUID()
        enum Kind {
            case h1(String)
            case h2(String)
            case h3(String)
            case bullet(String)
            case quote(String)
            case divider
            case table(TableData)
            case codeBlock(CodeData)
            case paragraph(String)
        }
        let kind: Kind
    }
    
    let blocks: [Block]
    
    init(content: String) {
        self.content = content
        
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var res: [Block] = []
        var i = 0
        
        func parseTableRow(_ line: String) -> [String] {
            var raw = line.trimmingCharacters(in: .whitespaces)
            if raw.hasPrefix("|") { raw = String(raw.dropFirst()) }
            if raw.hasSuffix("|") { raw = String(raw.dropLast()) }
            return raw.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty {
                i += 1
                continue
            }
            
            // Check for Fenced Code Block (```lang)
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var codeLines: [String] = []
                while i < lines.count {
                    let cLine = lines[i]
                    if cLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(cLine)
                    i += 1
                }
                res.append(Block(kind: .codeBlock(CodeData(language: lang.isEmpty ? "code" : lang, code: codeLines.joined(separator: "\n")))))
                continue
            }
            
            // Check for Markdown table start
            if trimmed.hasPrefix("|") && i + 1 < lines.count && lines[i + 1].trimmingCharacters(in: .whitespaces).contains("-") && lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                let headers = parseTableRow(trimmed)
                i += 2 // skip header and separator
                
                var rows: [[String]] = []
                while i < lines.count {
                    let rLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if rLine.hasPrefix("|") {
                        rows.append(parseTableRow(rLine))
                        i += 1
                    } else {
                        break
                    }
                }
                res.append(Block(kind: .table(TableData(headers: headers, rows: rows))))
                continue
            }
            
            if trimmed.hasPrefix("# ") {
                res.append(Block(kind: .h1(String(trimmed.dropFirst(2)))))
            } else if trimmed.hasPrefix("## ") {
                res.append(Block(kind: .h2(String(trimmed.dropFirst(3)))))
            } else if trimmed.hasPrefix("### ") {
                res.append(Block(kind: .h3(String(trimmed.dropFirst(4)))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.range(of: "^[0-9]+\\. ", options: .regularExpression) != nil {
                let text = trimmed.replacingOccurrences(of: "^[0-9]+\\. |^- |^\\* ", with: "", options: .regularExpression)
                res.append(Block(kind: .bullet(text)))
            } else if trimmed.hasPrefix("> ") {
                res.append(Block(kind: .quote(String(trimmed.dropFirst(2)))))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                res.append(Block(kind: .divider))
            } else {
                res.append(Block(kind: .paragraph(trimmed)))
            }
            i += 1
        }
        self.blocks = res
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if blocks.isEmpty {
                    Text("No content")
                        .font(.body)
                        .foregroundColor(.dictySecondary)
                } else {
                    ForEach(blocks) { block in
                        switch block.kind {
                        case .h1(let text):
                            renderFormattedText(text)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.top, 6)
                        case .h2(let text):
                            renderFormattedText(text)
                                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.top, 4)
                        case .h3(let text):
                            renderFormattedText(text)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.top, 2)
                        case .bullet(let text):
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.sageGreen)
                                renderFormattedText(text)
                                    .font(.system(size: 13))
                            }
                            .padding(.leading, 6)
                        case .quote(let text):
                            HStack(alignment: .top, spacing: 8) {
                                Rectangle()
                                    .fill(Color.sageGreen)
                                    .frame(width: 3)
                                renderFormattedText(text)
                                    .font(.system(size: 12.5))
                                    .foregroundColor(.dictySecondary)
                            }
                            .padding(.vertical, 2)
                        case .divider:
                            Divider()
                                .padding(.vertical, 4)
                        case .table(let table):
                            renderTable(table)
                                .padding(.vertical, 6)
                        case .codeBlock(let codeData):
                            renderCodeBlock(codeData)
                                .padding(.vertical, 6)
                        case .paragraph(let text):
                            renderFormattedText(text)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .lineSpacing(3)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func renderCodeBlock(_ codeData: CodeData) -> some View {
        if codeData.language.lowercased() == "mermaid" {
            MermaidDiagramBlockView(code: codeData.code)
                .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Code header
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 10))
                            .foregroundColor(.appAccent)
                        Text(codeData.language.uppercased())
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    Button(action: {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(codeData.code, forType: .string)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                            Text("Copy")
                        }
                        .font(.system(size: 10.5))
                        .foregroundColor(.dictySecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06))
                
                Divider()
                
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(codeData.code)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.vertical, 6)
        }
    }
    
    @ViewBuilder
    private func renderTable(_ table: TableData) -> some View {
        VStack(spacing: 0) {
            // Header Row
            HStack(spacing: 0) {
                ForEach(table.headers.indices, id: \.self) { idx in
                    renderFormattedText(table.headers[idx])
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if idx < table.headers.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color.primary.opacity(0.08))
            
            Divider()
            
            // Body Rows
            ForEach(table.rows.indices, id: \.self) { rIdx in
                let row = table.rows[rIdx]
                HStack(spacing: 0) {
                    ForEach(table.headers.indices, id: \.self) { cIdx in
                        let cellText = cIdx < row.count ? row[cIdx] : ""
                        renderFormattedText(cellText)
                            .font(.system(size: 12.5))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if cIdx < table.headers.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(rIdx % 2 == 1 ? Color.primary.opacity(0.03) : Color.clear)
                
                if rIdx < table.rows.count - 1 {
                    Divider()
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func renderFormattedText(_ raw: String) -> some View {
        if let attr = try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attr)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(raw)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Mermaid Diagram Views

class MermaidCustomWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // Forward scroll events to parent document ScrollView so page scrolling is never obstructed
        self.nextResponder?.scrollWheel(with: event)
    }
}

struct MermaidWebView: NSViewRepresentable {
    let code: String
    @Binding var dynamicHeight: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    func makeNSView(context: Context) -> MermaidCustomWebView {
        let config = WKWebViewConfiguration()
        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "heightHandler")
        config.userContentController = userController
        
        let webView = MermaidCustomWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.parent = self
        context.coordinator.webView = webView
        return webView
    }
    
    func updateNSView(_ webView: MermaidCustomWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.webView = webView
        
        let key = code
        if context.coordinator.lastLoadedKey != key {
            context.coordinator.lastLoadedKey = key
            context.coordinator.hasUpdatedHeight = false
            
            let escapedCode = code
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            
            var scriptTag = "<script src=\"https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js\"></script>"
            if let jsURL = DictyResources.url(forResource: "mermaid.min", withExtension: "js"),
               let jsContent = try? String(contentsOf: jsURL, encoding: .utf8) {
                scriptTag = "<script>\(jsContent)</script>"
            }
            
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1">
              \(scriptTag)
              <style>
                * { box-sizing: border-box; }
                html, body {
                  margin: 0;
                  padding: 0;
                  background: transparent;
                  overflow: hidden;
                  user-select: none;
                  -webkit-user-select: none;
                }
                .mermaid-container {
                  width: 100%;
                  padding: 14px;
                  display: flex;
                  justify-content: center;
                  align-items: center;
                  background-color: #FFFFFF;
                  border-radius: 6px;
                }
                .mermaid {
                  width: 100%;
                  display: flex;
                  justify-content: center;
                  align-items: center;
                }
                svg {
                  width: 100% !important;
                  max-width: 100% !important;
                  height: auto !important;
                  display: block;
                }
                .error-box {
                  color: #cf222e;
                  font-family: ui-monospace, monospace;
                  font-size: 11.5px;
                  padding: 12px;
                  border: 1px solid rgba(207, 34, 46, 0.4);
                  border-radius: 6px;
                  background: rgba(207, 34, 46, 0.06);
                  width: 100%;
                }
              </style>
            </head>
            <body>
              <div class="mermaid-container">
                <pre class="mermaid" id="diagram">
            \(escapedCode)
                </pre>
              </div>
              <script>
                try {
                  mermaid.initialize({
                    startOnLoad: false,
                    theme: 'neutral',
                    securityLevel: 'loose',
                    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif'
                  });
                  mermaid.run().then(() => {
                    setTimeout(() => {
                      const svg = document.querySelector('svg');
                      let h = svg ? svg.getBoundingClientRect().height + 32 : document.body.scrollHeight;
                      window.webkit.messageHandlers.heightHandler.postMessage(h);
                    }, 40);
                  }).catch(err => {
                    document.body.innerHTML = '<div class="error-box">Mermaid Syntax Error: ' + err.message + '</div>';
                    window.webkit.messageHandlers.heightHandler.postMessage(80);
                  });
                } catch(e) {
                  document.body.innerHTML = '<div class="error-box">Failed to render Mermaid: ' + e.message + '</div>';
                }
              </script>
            </body>
            </html>
            """
            
            webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MermaidWebView
        weak var webView: MermaidCustomWebView?
        var lastLoadedKey: String? = nil
        var hasUpdatedHeight = false
        
        init(_ parent: MermaidWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightHandler", let height = message.body as? CGFloat, !hasUpdatedHeight {
                hasUpdatedHeight = true
                let clamped = min(max(height, 100), 800)
                DispatchQueue.main.async {
                    self.parent.dynamicHeight = clamped
                }
            }
        }
    }
}

// MARK: - Interactive Lightbox Canvas

struct MermaidLightboxWebView: NSViewRepresentable {
    let code: String
    @Binding var zoomScale: Double
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userController = WKUserContentController()
        config.userContentController = userController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.parent = self
        context.coordinator.webView = webView
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.webView = webView
        
        if context.coordinator.lastLoadedCode != code {
            context.coordinator.lastLoadedCode = code
            
            let escapedCode = code
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            
            var scriptTag = "<script src=\"https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js\"></script>"
            if let jsURL = DictyResources.url(forResource: "mermaid.min", withExtension: "js"),
               let jsContent = try? String(contentsOf: jsURL, encoding: .utf8) {
                scriptTag = "<script>\(jsContent)</script>"
            }
            
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1">
              \(scriptTag)
              <style>
                * { box-sizing: border-box; }
                html, body {
                  margin: 0;
                  padding: 0;
                  width: 100%;
                  height: 100%;
                  background-color: #F8FAFC;
                  overflow: auto;
                  user-select: text;
                  -webkit-user-select: text;
                }
                #wrapper {
                  min-width: 100%;
                  min-height: 100%;
                  display: inline-flex;
                  justify-content: center;
                  align-items: center;
                  padding: 40px;
                }
                #diagram-card {
                  background: #FFFFFF;
                  padding: 36px 48px;
                  border-radius: 12px;
                  box-shadow: 0 6px 28px rgba(0,0,0,0.08);
                  display: inline-block;
                }
                .mermaid {
                  display: flex;
                  justify-content: center;
                  align-items: center;
                }
                svg {
                  display: block;
                  max-width: none !important;
                  height: auto !important;
                }
                .error-box {
                  color: #cf222e;
                  font-family: ui-monospace, monospace;
                  font-size: 13px;
                  padding: 16px;
                  border: 1px solid rgba(207, 34, 46, 0.4);
                  border-radius: 6px;
                  background: rgba(207, 34, 46, 0.06);
                }
              </style>
            </head>
            <body>
              <div id="wrapper">
                <div id="diagram-card">
                  <pre class="mermaid" id="diagram">
            \(escapedCode)
                  </pre>
                </div>
              </div>
              <script>
                let baseWidth = 0;
                let baseHeight = 0;
                let currentScale = 1.0;
                
                function applyZoom(scale) {
                  currentScale = scale;
                  const svg = document.querySelector('svg');
                  if (svg && baseWidth > 0) {
                    svg.style.width = (baseWidth * scale) + 'px';
                    svg.style.height = (baseHeight * scale) + 'px';
                  }
                }
                
                window.setZoomScale = function(s) {
                  applyZoom(s);
                };
                
                try {
                  mermaid.initialize({
                    startOnLoad: false,
                    theme: 'neutral',
                    securityLevel: 'loose',
                    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif'
                  });
                  mermaid.run().then(() => {
                    const svg = document.querySelector('svg');
                    if (svg) {
                      const vb = svg.viewBox ? svg.viewBox.baseVal : null;
                      const bbox = svg.getBBox();
                      baseWidth = (vb && vb.width > 0) ? vb.width : (bbox.width > 0 ? bbox.width : svg.getBoundingClientRect().width);
                      baseHeight = (vb && vb.height > 0) ? vb.height : (bbox.height > 0 ? bbox.height : svg.getBoundingClientRect().height);
                      
                      if (baseWidth < 500) baseWidth = 700;
                      
                      svg.style.width = baseWidth + 'px';
                      svg.style.height = baseHeight + 'px';
                      svg.style.maxWidth = 'none';
                    }
                  });
                } catch(e) {
                  document.body.innerHTML = '<div class="error-box">Failed to render Mermaid: ' + e.message + '</div>';
                }
              </script>
            </body>
            </html>
            """
            
            webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
        } else {
            webView.evaluateJavaScript("setZoomScale(\(zoomScale));", completionHandler: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: MermaidLightboxWebView
        weak var webView: WKWebView?
        var lastLoadedCode: String? = nil
        
        init(_ parent: MermaidLightboxWebView) {
            self.parent = parent
        }
    }
}

struct MermaidLightboxModal: View {
    let code: String
    @Binding var isPresented: Bool
    @State private var zoomScale: Double = 1.0
    
    var body: some View {
        VStack(spacing: 0) {
            // Modal Header
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.sageGreen)
                    Text("Mermaid Diagram Preview")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                
                Spacer()
                
                // Zoom Controls
                HStack(spacing: 6) {
                    Button(action: { zoomScale = max(0.2, zoomScale - 0.2) }) {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 26, height: 24)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Zoom Out")
                    
                    Button(action: { zoomScale = 1.0 }) {
                        Text("\(Int(zoomScale * 100))%")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .frame(minWidth: 48)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Reset Zoom (100%)")
                    
                    Button(action: { zoomScale = min(3.0, zoomScale + 0.2) }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 26, height: 24)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Zoom In")
                }
                
                Divider().frame(height: 18)
                
                // Copy Button
                Button(action: {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(code, forType: .string)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Copy Code")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                
                // Close Button
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.dictySecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Full-screen interactive natural vector canvas
            MermaidLightboxWebView(code: code, zoomScale: $zoomScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 950, idealWidth: 1150, minHeight: 650, idealHeight: 800)
    }
}

struct MermaidDiagramBlockView: View {
    let code: String
    @State private var showCode = false
    @State private var diagramHeight: CGFloat = 220
    @State private var isLightboxOpen = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with Visual vs Code toggle + Lightbox Button
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.sageGreen)
                    Text("MERMAID DIAGRAM")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.dictySecondary)
                }
                
                Spacer()
                
                if !showCode {
                    // Lightbox Expand Button
                    Button(action: { isLightboxOpen = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 9.5))
                            Text("Expand")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.primary.opacity(0.06))
                        .foregroundColor(.dictySecondary)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Open in Fullscreen Lightbox Modal")
                    .padding(.trailing, 4)
                }
                
                // Diagram vs Code Segmented Control
                HStack(spacing: 2) {
                    Button(action: { showCode = false }) {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 9.5))
                            Text("Diagram")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(!showCode ? Color.sageGreen.opacity(0.2) : Color.clear)
                        .foregroundColor(!showCode ? .sageGreen : .dictySecondary)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { showCode = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "curlybraces")
                                .font(.system(size: 9.5))
                            Text("Code")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(showCode ? Color.sageGreen.opacity(0.2) : Color.clear)
                        .foregroundColor(showCode ? .sageGreen : .dictySecondary)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
                
                // Copy button
                Button(action: {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(code, forType: .string)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Copy")
                    }
                    .font(.system(size: 10.5))
                    .foregroundColor(.dictySecondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06))
            
            Divider()
            
            if showCode {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(code)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 350)
                .background(Color(NSColor.textBackgroundColor))
            } else {
                MermaidWebView(
                    code: code,
                    dynamicHeight: $diagramHeight
                )
                .frame(height: diagramHeight)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .cornerRadius(6)
                .padding(8)
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .sheet(isPresented: $isLightboxOpen) {
            MermaidLightboxModal(code: code, isPresented: $isLightboxOpen)
        }
    }
}
