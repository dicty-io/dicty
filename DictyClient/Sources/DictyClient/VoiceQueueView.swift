import SwiftUI
import AppKit

struct VoiceQueueView: View {
    @EnvironmentObject var engineClient: EngineClient
    @ObservedObject var profileManager = ProfileManager.shared
    @AppStorage("targetSystem") private var targetSystem: String = "obsidian"
    /// When true the page is shown inside a Projects tab and drops its own title bar.
    var isEmbedded: Bool = false
    
    @State private var editingThoughtId: String? = nil
    @State private var editingText: String = ""
    @State private var newManualText: String = ""
    @State private var isAddingManual: Bool = false
    @State private var searchText: String = ""
    @State private var showClearConfirmation: Bool = false
    @State private var synthesisResultMessage: String? = nil
    @State private var showResultAlert: Bool = false
    @State private var isSuccessResult: Bool = false
    
    var filteredThoughts: [VoiceThought] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return engineClient.stagedThoughts
        }
        return engineClient.stagedThoughts.filter {
            $0.text.localizedCaseInsensitiveContains(searchText) ||
            ($0.git_branch?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if !isEmbedded {
                // Header Bar
                headerView
                
                Divider()
                    .opacity(0.15)
            }
            
            // Main Content Area
            if engineClient.stagedThoughts.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Quick search and stats
                        searchAndStatsBar
                        
                        // New Manual Note Card (collapsible)
                        if isAddingManual {
                            manualInputCard
                        } else {
                            Button(action: { isAddingManual = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Add thought")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                }
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.02))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                        .foregroundColor(Color.primary.opacity(0.1))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // List of Staged Thought Cards
                        ForEach(filteredThoughts) { thought in
                            ThoughtCardView(
                                thought: thought,
                                isEditing: editingThoughtId == thought.id,
                                editingText: $editingText,
                                onStartEdit: {
                                    editingThoughtId = thought.id
                                    editingText = thought.text
                                },
                                onSaveEdit: {
                                    engineClient.updateStagedThought(id: thought.id, text: editingText)
                                    editingThoughtId = nil
                                },
                                onCancelEdit: {
                                    editingThoughtId = nil
                                },
                                onDelete: {
                                    engineClient.deleteStagedThought(id: thought.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            }
            
            Divider()
                .opacity(0.15)
            
            // Bottom Action Footer
            footerActionView
        }
        .background(Color.clear)
        .onAppear {
            engineClient.fetchStagedThoughts()
        }
        .alert("Clear All Thoughts?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                engineClient.clearStagedThoughts()
            }
        } message: {
            Text("This will remove all \(engineClient.stagedThoughts.count) staged voice thoughts from the queue. This action cannot be undone.")
        }
        .alert(isSuccessResult ? "Documentation Synthesized!" : "Synthesis Notice", isPresented: $showResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(synthesisResultMessage ?? (isSuccessResult ? "Documentation proposal created! Check Pending Updates." : "Synthesis encountered an error."))
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Voice Queue")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    
                    if !engineClient.stagedThoughts.isEmpty {
                        let count = engineClient.stagedThoughts.count
                        Text("\(count) \(count == 1 ? "item" : "items")")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
                
                Text("Collect thoughts, notes, and tasks while you speak. Send them to your note app in batches or let Dicty organize them.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !engineClient.stagedThoughts.isEmpty {
                Button(action: { isAddingManual.toggle() }) {
                    Label(isAddingManual ? "Cancel" : "Add Note", systemImage: isAddingManual ? "xmark" : "plus")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(role: .destructive, action: { showClearConfirmation = true }) {
                    Label("Clear All", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    // MARK: - Search & Stats Bar
    private var searchAndStatsBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search staged thoughts...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .rounded))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            
            Spacer()
            
            let totalWords = engineClient.stagedThoughts.reduce(0) { $0 + $1.text.split(separator: " ").count }
            Text("\(totalWords) total words staged")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Spacer()
            
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 34))
                .foregroundColor(.secondary.opacity(0.7))
            
            VStack(spacing: 6) {
                Text("No Thoughts Staged Yet")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                
                Text("Collect thoughts, notes, and tasks while you speak. Send them to your note app in batches or let Dicty organize them.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            
            Button(action: { isAddingManual = true }) {
                Label("Add Thought Manually", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .buttonStyle(.borderedProminent)
            .tint(.appAccent)
            
            if isAddingManual {
                manualInputCard
                    .padding(.horizontal, 24)
            }
            
            Spacer()
        }
        .padding(24)
    }
    
    // MARK: - Manual Input Card
    private var manualInputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Add Written Thought or Snippet", systemImage: "text.quote")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                Button(action: { isAddingManual = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            TextEditor(text: $newManualText)
                .font(.system(size: 13, design: .rounded))
                .frame(minHeight: 70, maxHeight: 140)
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            
            HStack {
                Spacer()
                Button("Cancel") {
                    newManualText = ""
                    isAddingManual = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Save to Queue") {
                    let trimmed = newManualText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        engineClient.addStagedThought(text: trimmed) {
                            newManualText = ""
                            isAddingManual = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
                .controlSize(.small)
                .disabled(newManualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
    
    // MARK: - Footer
    private var footerActionView: some View {
        HStack(spacing: 16) {
            let displayTarget: String = {
                switch targetSystem {
                case "notion": return "Notion"
                case "linear": return "Linear"
                case "confluence": return "Confluence"
                case "obsidian", "local": return "Obsidian"
                default: return targetSystem.capitalized
                }
            }()
            
            HStack(spacing: 4) {
                Text("Saves to:")
                    .foregroundColor(.secondary)
                Text(displayTarget)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
            }
            .font(.system(size: 12, design: .rounded))
            
            Spacer()
            
            // Primary Synthesize Button
            Button(action: {
                engineClient.synthesizeArchitectureDocs(targetFile: nil) { success, message in
                    self.isSuccessResult = success
                    self.synthesisResultMessage = message
                    self.showResultAlert = true
                }
            }) {
                HStack(spacing: 6) {
                    if engineClient.isSynthesizingDocs {
                        ProgressView()
                            .controlSize(.small)
                        Text("Synthesizing...")
                    } else {
                        Image(systemName: "sparkles")
                        Text("Synthesize with LLM")
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.appAccent)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(engineClient.stagedThoughts.isEmpty || engineClient.isSynthesizingDocs)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.02))
    }
}

// MARK: - Thought Card View
struct ThoughtCardView: View {
    let thought: VoiceThought
    let isEditing: Bool
    @Binding var editingText: String
    let onStartEdit: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered: Bool = false
    @State private var showDeleteConfirm: Bool = false
    
    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: thought.timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Card Header: Date, Badges, Actions
            HStack(alignment: .center, spacing: 8) {
                Text(formattedDate)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                
                if let branch = thought.git_branch, !branch.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text(branch)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                    .foregroundColor(.secondary)
                }
                
                if thought.source == "manual" {
                    Text("Note")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .foregroundColor(.secondary)
                        .cornerRadius(4)
                }
                
                Spacer()
                
                if !isEditing {
                    HStack(spacing: 8) {
                        Button(action: onStartEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit thought text")
                        
                        Button(action: { showDeleteConfirm = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Delete thought")
                        .confirmationDialog("Delete this thought?", isPresented: $showDeleteConfirm) {
                            Button("Delete", role: .destructive, action: onDelete)
                            Button("Cancel", role: .cancel) { }
                        }
                    }
                    .opacity(isHovered ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                }
            }
            
            // Thought Content
            if isEditing {
                VStack(alignment: .trailing, spacing: 8) {
                    TextEditor(text: $editingText)
                        .font(.system(size: 13, design: .rounded))
                        .frame(minHeight: 60, maxHeight: 160)
                        .padding(6)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appAccent.opacity(0.4), lineWidth: 1))
                    
                    HStack(spacing: 8) {
                        Button("Cancel", action: onCancelEdit)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        
                        Button("Save Changes", action: onSaveEdit)
                            .buttonStyle(.borderedProminent)
                            .tint(.appAccent)
                            .controlSize(.small)
                    }
                }
            } else {
                Text(thought.text)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isEditing ? Color.appAccent.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
