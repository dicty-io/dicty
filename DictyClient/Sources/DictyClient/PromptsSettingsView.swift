import SwiftUI
import AppKit

// MARK: - Prompts Settings
struct PromptsSettingsView: View {
    @EnvironmentObject var engineClient: EngineClient
    @State private var selectedKey: String? = nil
    @State private var currentEditText: String = ""
    @State private var showResetConfirm: Bool = false
    @State private var hoveredKey: String? = nil
    @State private var isLegacyExpanded: Bool = false
    @State private var editingPromptForSheet: DictyPromptInfo? = nil

    /// Title shown above the list. The embedded Projects editor reuses this view.
    var title: String = "Prompts"
    /// When set, only these prompt keys are listed (used for the documentation prompts).
    var promptKeys: [String]? = nil

    private var visiblePrompts: [DictyPromptInfo] {
        guard let promptKeys else { return engineClient.prompts }
        return engineClient.prompts.filter { promptKeys.contains($0.key) }
    }

    private var activePrompts: [DictyPromptInfo] {
        visiblePrompts.filter { !$0.key.contains("reconcile") }
    }

    private var legacyPrompts: [DictyPromptInfo] {
        visiblePrompts.filter { $0.key.contains("reconcile") }
    }

    var customPrompts: [DictyPromptInfo] {
        activePrompts.filter { $0.is_custom || $0.key == "dictation_custom_system" }
    }
    
    var builtinPrompts: [DictyPromptInfo] {
        activePrompts.filter { !$0.is_custom && $0.key != "dictation_custom_system" }
    }

    static func friendlyPromptName(for key: String) -> String {
        switch key {
        case "architecture_system": return "Architecture documentation"
        case "confluence_agent_system": return "Confluence documentation"
        case "obsidian_agent_system": return "Files documentation"
        case "hub_system": return "Knowledge hub"
        case "reconcile_system": return "Reconcile (legacy)"
        default:
            return key.replacingOccurrences(of: "_system", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    static func friendlyPromptDescription(for key: String, fallback: String) -> String {
        switch key {
        case "architecture_system": return "Generates ARCHITECTURE.md from code structure."
        case "confluence_agent_system": return "Updates team docs in Confluence spaces."
        case "obsidian_agent_system": return "Updates markdown notes in your knowledge base."
        case "hub_system": return "Structures knowledge base summaries and indexes."
        case "reconcile_system": return "Legacy documentation reconciliation prompt."
        default:
            return fallback.isEmpty ? "System prompt for \(key)" : fallback
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            let isCompact = geo.size.width < 560
            
            Group {
                if isCompact {
                    compactListView
                } else {
                    HStack(spacing: 0) {
                        promptListSidebar
                            .frame(width: 190)
                            .background(Color.primary.opacity(0.01))
                        
                        Divider().opacity(0.15)
                        
                        promptEditorView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .sheet(item: $editingPromptForSheet) { prompt in
                sheetEditorView(prompt: prompt)
            }
        }
        .onAppear {
            engineClient.fetchPrompts()
            if selectedKey == nil, let first = visiblePrompts.first {
                selectedKey = first.key
                currentEditText = first.active_value
            }
        }
        .onChange(of: selectedKey) { _, newKey in
            if let key = newKey, let prompt = engineClient.prompts.first(where: { $0.key == key }) {
                currentEditText = prompt.active_value
            } else {
                currentEditText = ""
            }
        }
        .onChange(of: engineClient.prompts.map { "\($0.key):\($0.active_value)" }) { _, _ in
            if selectedKey == nil, let first = visiblePrompts.first {
                selectedKey = first.key
                currentEditText = first.active_value
            } else if let key = selectedKey, let prompt = engineClient.prompts.first(where: { $0.key == key }) {
                if currentEditText == prompt.default_value || !prompt.is_custom {
                    currentEditText = prompt.active_value
                } else if currentEditText != prompt.active_value {
                    currentEditText = prompt.active_value
                }
            }
        }
    }

    // MARK: - List Sidebar (Regular)
    private var promptListSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)
            
            Divider().opacity(0.15)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if promptKeys == nil {
                        if !customPrompts.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Custom")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 2)
                                
                                ForEach(customPrompts) { prompt in
                                    promptRow(prompt, opensSheet: false)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Built-in")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 2)
                            
                            ForEach(builtinPrompts) { prompt in
                                promptRow(prompt, opensSheet: false)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(activePrompts) { prompt in
                                promptRow(prompt, opensSheet: false)
                            }
                        }
                    }

                    if !legacyPrompts.isEmpty {
                        DisclosureGroup(isExpanded: $isLegacyExpanded) {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(legacyPrompts) { prompt in
                                    promptRow(prompt, opensSheet: false)
                                }
                            }
                            .padding(.top, 4)
                        } label: {
                            Text("Legacy")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Compact List (Opens Sheet)
    private var compactListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)
            
            Divider().opacity(0.15)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(activePrompts) { prompt in
                        promptRow(prompt, opensSheet: true)
                    }

                    if !legacyPrompts.isEmpty {
                        DisclosureGroup(isExpanded: $isLegacyExpanded) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(legacyPrompts) { prompt in
                                    promptRow(prompt, opensSheet: true)
                                }
                            }
                            .padding(.top, 4)
                        } label: {
                            Text("Legacy")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                    }
                }
                .padding(10)
            }
        }
    }

    // MARK: - Inline Editor View
    private var promptEditorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let key = selectedKey, let prompt = engineClient.prompts.first(where: { $0.key == key }) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(Self.friendlyPromptName(for: prompt.key))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            if prompt.is_custom {
                                Text("Edited")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.appAccent.opacity(0.15))
                                    .foregroundColor(.appAccent)
                                    .cornerRadius(4)
                            }
                        }
                        
                        Text(Self.friendlyPromptDescription(for: prompt.key, fallback: prompt.description))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 2)
                
                TextEditor(text: $currentEditText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                
                HStack {
                    Button("Reset to Default") {
                        showResetConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!prompt.is_custom)
                    .confirmationDialog("Reset this prompt to default?", isPresented: $showResetConfirm) {
                        Button("Reset to Default", role: .destructive) {
                            engineClient.resetPrompt(key: key)
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This will discard all customizations made to \(Self.friendlyPromptName(for: prompt.key)) and restore the factory prompt.")
                    }
                    
                    Spacer()
                    
                    Button("Save Changes") {
                        engineClient.updatePrompt(key: key, value: currentEditText)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    .controlSize(.small)
                    .disabled(currentEditText == prompt.active_value)
                }
                .padding(.top, 4)
            } else {
                Spacer()
                HStack {
                    Spacer()
                    Text("Select a prompt to edit")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Spacer()
            }
        }
        .padding(16)
    }

    // MARK: - Sheet Editor (Compact Mode)
    @ViewBuilder
    private func sheetEditorView(prompt: DictyPromptInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.friendlyPromptName(for: prompt.key))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(Self.friendlyPromptDescription(for: prompt.key, fallback: prompt.description))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    editingPromptForSheet = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            TextEditor(text: $currentEditText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            
            HStack {
                Button("Reset to Default") {
                    engineClient.resetPrompt(key: prompt.key)
                    currentEditText = prompt.default_value
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!prompt.is_custom)
                
                Spacer()
                
                Button("Save Changes") {
                    engineClient.updatePrompt(key: prompt.key, value: currentEditText)
                    editingPromptForSheet = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
                .controlSize(.small)
                .disabled(currentEditText == prompt.active_value)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 380)
    }
    
    @ViewBuilder
    private func promptRow(_ prompt: DictyPromptInfo, opensSheet: Bool) -> some View {
        let isSelected = selectedKey == prompt.key
        let isHovered = hoveredKey == prompt.key
        
        Button(action: {
            selectedKey = prompt.key
            currentEditText = prompt.active_value
            if opensSheet {
                editingPromptForSheet = prompt
            }
        }) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Self.friendlyPromptName(for: prompt.key))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundColor(isSelected ? .primary : .primary.opacity(0.85))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if prompt.is_custom {
                        Text("Edited")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(.appAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.appAccent.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                
                Text(Self.friendlyPromptDescription(for: prompt.key, fallback: prompt.description))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.appAccent.opacity(0.15) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.appAccent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredKey = prompt.key }
            else if hoveredKey == prompt.key { hoveredKey = nil }
        }
    }
}
