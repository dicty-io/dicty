import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

extension String {
    func lstripHash() -> String {
        var str = self.trimmingCharacters(in: .whitespacesAndNewlines)
        while str.hasPrefix("#") {
            str = String(str.dropFirst())
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - History Views
struct HistoryContainerView: View {
    @AppStorage("historyTabSelection") private var selectedTab: Int = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PageTabBar(
                    selection: $selectedTab,
                    tabs: [
                        PageTabItem(id: 0, label: "Transcriptions", icon: "waveform"),
                        PageTabItem(id: 1, label: "Librarian updates", icon: "books.vertical")
                    ],
                    minItemWidth: 90
                )
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider().opacity(0.5)
            
            ZStack {
                HistoryView()
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0)
                
                UpdatesHistoryView()
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var engineClient: EngineClient
    @State private var searchText = ""
    @State private var selectedTags: Set<String> = []
    @State private var selectedApp: String? = nil
    @State private var showFilterPopover = false
    
    var availableApps: [String] {
        var apps = Set<String>()
        for record in engineClient.history {
            if let app = record.app_name ?? record.app_id, !app.isEmpty {
                apps.insert(app)
            }
        }
        return apps.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    var availableTags: [String] {
        var tagCounts: [String: Int] = [:]
        for record in engineClient.history {
            if let tags = record.tags {
                for tag in tags {
                    let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines).lstripHash()
                    if !cleaned.isEmpty {
                        tagCounts[cleaned, default: 0] += 1
                    }
                }
            }
        }
        return tagCounts.keys.sorted { (tagCounts[$0] ?? 0) > (tagCounts[$1] ?? 0) }
    }
    
    func tagCount(for tag: String) -> Int {
        engineClient.history.filter {
            $0.tags?.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lstripHash().caseInsensitiveCompare(tag) == .orderedSame }) == true
        }.count
    }
    
    private func toggleTag(_ tag: String) {
        let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines).lstripHash()
        if selectedTags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            selectedTags = Set(selectedTags.filter { $0.caseInsensitiveCompare(clean) != .orderedSame })
        } else {
            selectedTags.insert(clean)
        }
    }
    
    private func isTagSelected(_ tag: String) -> Bool {
        let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines).lstripHash()
        return selectedTags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame })
    }
    
    private func resetFilters() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            selectedTags.removeAll()
            selectedApp = nil
        }
    }
    
    var filteredHistory: [DictyHistory] {
        engineClient.history.filter { record in
            // Filter by tags if any are selected (record must match ANY of the selected tags)
            if !selectedTags.isEmpty {
                let hasTag = record.tags?.contains(where: { tag in
                    let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines).lstripHash()
                    return selectedTags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame })
                }) ?? false
                if !hasTag { return false }
            }
            
            // Filter by app if selected
            if let selectedApp = selectedApp {
                let appMatch = (record.app_name?.caseInsensitiveCompare(selectedApp) == .orderedSame) ||
                               (record.app_id?.caseInsensitiveCompare(selectedApp) == .orderedSame)
                if !appMatch { return false }
            }
            
            // Search text filter matching text, mode, tags, or app
            if !searchText.isEmpty {
                let matchesText = record.text.localizedCaseInsensitiveContains(searchText)
                let matchesMode = record.mode.localizedCaseInsensitiveContains(searchText)
                let matchesTag = record.tags?.contains(where: {
                    $0.localizedCaseInsensitiveContains(searchText) || "#\($0)".localizedCaseInsensitiveContains(searchText)
                }) ?? false
                let matchesNotes = record.notes?.localizedCaseInsensitiveContains(searchText) ?? false
                let matchesTitle = record.title?.localizedCaseInsensitiveContains(searchText) ?? false
                let matchesApp = (record.app_name?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                                 (record.app_id?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                                 (record.mode_id?.localizedCaseInsensitiveContains(searchText) ?? false)
                return matchesText || matchesMode || matchesTag || matchesNotes || matchesTitle || matchesApp
            }
            return true
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            if !engineClient.history.isEmpty {
                // Search Bar + Filter Button
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.dictySecondary)
                        TextField("Search dictation history or #tag...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.dictySecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                    
                    // Filter by Labels Button
                    Button(action: { showFilterPopover.toggle() }) {
                        HStack(spacing: 5) {
                            Image(systemName: selectedTags.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(selectedTags.isEmpty ? "Filter" : "Filter (\(selectedTags.count))")
                                .font(.system(size: 12, weight: selectedTags.isEmpty ? .regular : .semibold, design: .rounded))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .opacity(0.6)
                        }
                        .frame(minWidth: 86)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selectedTags.isEmpty ? Color.primary.opacity(0.06) : Color.primary.opacity(0.16))
                        .foregroundColor(selectedTags.isEmpty ? .secondary : .primary)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTags.isEmpty ? Color.secondary.opacity(0.15) : Color.primary.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
                        labelsFilterPopoverView
                    }
                    
                    // Filter by App Menu (when history contains apps)
                    if !availableApps.isEmpty {
                        Menu {
                            Button("All Apps") {
                                selectedApp = nil
                            }
                            Divider()
                            ForEach(availableApps, id: \.self) { app in
                                Button {
                                    selectedApp = app
                                } label: {
                                    HStack {
                                        Text(app)
                                        if selectedApp == app {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: selectedApp == nil ? "app.badge" : "app.badge.fill")
                                    .font(.system(size: 12))
                                Text(selectedApp ?? "All Apps")
                                    .font(.system(size: 12, weight: selectedApp == nil ? .regular : .semibold, design: .rounded))
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .opacity(0.6)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(selectedApp == nil ? Color.primary.opacity(0.06) : Color.primary.opacity(0.16))
                            .foregroundColor(selectedApp == nil ? .secondary : .primary)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedApp == nil ? Color.secondary.opacity(0.15) : Color.primary.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    }
                    
                    // Reset Button (Shown only when a filter or search is active)
                    if !selectedTags.isEmpty || selectedApp != nil || !searchText.isEmpty {
                        Button(action: resetFilters) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11.5))
                                Text("Reset")
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.secondary)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Reset filter")
                    }
                    
                    FeatureHelpButton(topic: .history)
                    
                    Button(action: openAudioRecordingsFolder) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Audio Folder")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .foregroundColor(.dictySecondary)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Open Audio Recordings Folder in Finder")
                    
                    Button(action: {
                        engineClient.fetchHistory()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.dictySecondary)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh History")
                }
                .padding(.top, 10)
            }
            
            if engineClient.history.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 40))
                        .foregroundColor(.dictySecondary)
                    Text("No History Yet")
                        .font(.system(.title3, design: .rounded))
                        .foregroundColor(.dictySecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredHistory) { record in
                            HistoryCardView(record: record)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .animation(.spring(), value: searchText)
                .animation(.spring(), value: selectedTags)
            }
        }
        .padding(.horizontal, 20)
        .navigationTitle("History")
        .onAppear {
            engineClient.fetchHistory()
        }
    }
    
    private func openAudioRecordingsFolder() {
        let historyDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dicty/transcripts_input/history")
        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(historyDir)
    }
    
    @ViewBuilder
    private var labelsFilterPopoverView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Filter by Labels")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if !selectedTags.isEmpty {
                    Button("Reset", action: resetFilters)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .buttonStyle(.plain)
                        .foregroundColor(.red.opacity(0.85))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            Divider()
                .opacity(0.4)
            
            if availableTags.isEmpty {
                Text("No labels found in history.")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(availableTags, id: \.self) { tag in
                            let isSelected = isTagSelected(tag)
                            let count = tagCount(for: tag)
                            
                            Button(action: {
                                toggleTag(tag)
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(isSelected ? .primary : .secondary.opacity(0.5))
                                    
                                    Text("#\(tag)")
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                                        .foregroundColor(isSelected ? .primary : Color.primary.opacity(0.85))
                                    
                                    Spacer()
                                    
                                    Text("\(count)")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.06))
                                        .cornerRadius(5)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(maxHeight: 220)
            }
            
            if !selectedTags.isEmpty {
                Divider()
                    .opacity(0.4)
                HStack {
                    Text("\(selectedTags.count) selected")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear All", action: resetFilters)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            } else {
                Spacer().frame(height: 4)
            }
        }
        .frame(width: 220)
    }
    
    private func retentionLabel(_ code: String) -> String {
        switch code {
        case "24h": return "Retain: 24h"
        case "7d": return "Retain: 7d"
        case "30d": return "Retain: 30d"
        default: return "Retain: Forever"
        }
    }
}

struct HistoryCardView: View {
    @EnvironmentObject var engineClient: EngineClient
    var record: DictyHistory
    @State private var isExpanded = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var isPaused = false
    @State private var playbackProgress: Double = 0.0
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 0.0
    @State private var playbackTimer: Timer?
    @State private var renderMarkdown = true
    @State private var showChatView = true
    @State private var showReprocessSheet = false
    @State private var showTagEditor = false
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var isAddingTag = false
    @State private var newTagText = ""
    @State private var isLoadingAudio = false
    @State private var isEditingNotes = false
    @State private var editedNotes = ""
    @State private var isSavingNotes = false
    @State private var isCardHovered = false
    @State private var cachedDuration: Double? = nil
    @State private var audioFileMissing = false
    @State private var showDeleteConfirm = false
    @State private var actionHoverId: String? = nil
    
    /// Smart date formatting: today → time only, this year → "22 Oct, 14:57", older → "22 Oct 2025, 14:57"
    private var smartDateString: String {
        guard let date = HistoryRenderCache.isoFractional.date(from: record.timestamp) ?? HistoryRenderCache.iso.date(from: record.timestamp) else {
            return record.timestamp
        }
        let cal = Calendar.current
        let tf = DateFormatter()
        tf.locale = Locale.current
        if cal.isDateInToday(date) {
            tf.dateFormat = "HH:mm"
        } else if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            tf.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        } else {
            tf.setLocalizedDateFormatFromTemplate("d MMM yyyy HH:mm")
        }
        return tf.string(from: date)
    }
    
    /// Tags that are default for the record's mode (shown only when expanded)
    private static let defaultModeTags: [String: Set<String>] = [
        "dictation": ["dictation"],
        "meeting": ["meeting"],
        "focused_meeting": ["focused_meeting", "meeting"],
        "librarian": ["librarian"],
    ]
    
    /// Tags to show in collapsed state: only user-added (non-default) tags
    private var collapsedTags: [String] {
        let defaults = Self.defaultModeTags[record.mode] ?? []
        return (record.tags ?? []).filter { tag in
            !defaults.contains(tag.lowercased())
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 10 : 6) {
            headerView
            
            if isExpanded {
                titleView
                tagsView
                notesView
                if let summary = record.summary, !summary.isEmpty {
                    summaryView(summary)
                }
            } else if let title = record.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            transcriptTextView
            
            if !isExpanded && !collapsedTags.isEmpty {
                tagsView
            }
            
            if let errorMsg = engineClient.summarizationErrors[record.id] {
                Label(errorMsg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.red)
            }
            if let reprocessErr = engineClient.reprocessErrors[record.id] {
                Label(reprocessErr, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.red)
            }
            
            if isExpanded {
                if record.isAudioAvailable && !audioFileMissing {
                    audioPlayerBarView
                } else if audioFileMissing {
                    Text("Audio not saved")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
                actionButtonsView
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isExpanded ? 14 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(isCardHovered ? 0.05 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isExpanded ? Color.appAccent.opacity(0.6) : Color.primary.opacity(isCardHovered ? 0.12 : 0.06), lineWidth: isExpanded ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            isCardHovered = hovering
        }
        .onTapGesture {
            if !isExpanded && !isEditingTitle && !isAddingTag && !isEditingNotes {
                withAnimation(.spring()) {
                    isExpanded = true
                }
            }
        }
        .sheet(isPresented: $showReprocessSheet) {
            ReprocessSheetView(record: record)
        }
        .sheet(isPresented: $showTagEditor) {
            TagEditorSheet(record: record)
        }
    }
    
    @ViewBuilder
    private var titleView: some View {
        if isEditingTitle {
            HStack(spacing: 6) {
                TextField("Card title...", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .onSubmit {
                        saveTitle()
                    }
                
                Button(action: saveTitle) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.stylishGreen)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                
                Button(action: { isEditingTitle = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.dictySecondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 6) {
                if let title = record.title, !title.isEmpty {
                    Text(title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                if isCardHovered || record.title != nil {
                    Button(action: {
                        editedTitle = record.title ?? ""
                        isEditingTitle = true
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: record.title == nil || record.title?.isEmpty == true ? "pencil.line" : "pencil")
                                .font(.system(size: 9, weight: .semibold))
                            if record.title == nil || record.title?.isEmpty == true {
                                Text("Add Title")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                            }
                        }
                        .foregroundColor(.dictySecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help(record.title == nil || record.title?.isEmpty == true ? "Add custom title" : "Rename title")
                }
                
                if (record.notes == nil || record.notes?.isEmpty == true) && !isEditingNotes {
                    if isCardHovered {
                        Button(action: {
                            editedNotes = ""
                            isEditingNotes = true
                            isExpanded = true
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "note.text.badge.plus")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("Add Notes")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(.dictySecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Add personal notes or context before summarizing")
                    }
                }
                
                Spacer()
            }
        }
    }
    
    private func saveTitle() {
        isEditingTitle = false
        let cleanTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? nil : cleanTitle
        Task {
            await engineClient.updateHistoryRecord(id: record.id, title: finalTitle, tags: record.tags)
        }
    }
    
    @ViewBuilder
    private var tagsView: some View {
        let allTags = record.tags ?? []
        let displayTags = isExpanded ? allTags : collapsedTags
        if !displayTags.isEmpty || isExpanded {
            HStack(spacing: 6) {
                ForEach(displayTags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                        
                        if isExpanded {
                            Button(action: { removeTag(tag) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 0.8)
                    )
                }
                
                if isExpanded {
                    if isAddingTag {
                        HStack(spacing: 4) {
                            TextField("tag", text: $newTagText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, design: .rounded))
                                .frame(width: 70)
                                .onSubmit {
                                    addTag()
                                }
                            Button(action: addTag) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.stylishGreen)
                            }
                            .buttonStyle(.plain)
                            Button(action: { isAddingTag = false; newTagText = "" }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                                    .foregroundColor(.dictySecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(6)
                    } else {
                        Button(action: { isAddingTag = true }) {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Tag")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(.dictySecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
            }
        }
    }
    
    private func addTag() {
        let clean = newTagText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "").lowercased()
        guard !clean.isEmpty else {
            isAddingTag = false
            return
        }
        var updated = record.tags ?? []
        if !updated.contains(clean) {
            updated.append(clean)
            Task {
                await engineClient.updateHistoryRecord(id: record.id, title: record.title, tags: updated)
            }
        }
        newTagText = ""
        isAddingTag = false
    }
    
    private func removeTag(_ tag: String) {
        var updated = record.tags ?? []
        updated.removeAll { $0 == tag }
        Task {
            await engineClient.updateHistoryRecord(id: record.id, title: record.title, tags: updated)
        }
    }
    
    private var isMeetingRecord: Bool {
        record.mode == "meeting" || record.mode == "focused_meeting"
    }

    private var parsedMeetingDialogue: (turns: [MeetingChatTurn], otherContent: String?) {
        MeetingDialogueParser.parseTurns(from: record.text, youLabel: "You")
    }

    @ViewBuilder
    private var transcriptTextView: some View {
        let meetingData = parsedMeetingDialogue
        let hasTurns = !meetingData.turns.isEmpty

        if isMeetingRecord && hasTurns && showChatView {
            VStack(alignment: .leading, spacing: 10) {
                MeetingDialogueChatView(turns: meetingData.turns, isExpanded: isExpanded)

                if isExpanded, let other = meetingData.otherContent, !other.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                    if renderMarkdown, let attr = HistoryRenderCache.markdown(other, clean: { cleanMarkdown($0, stripBold: false) }) {
                        Text(attr)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    } else {
                        Text(other)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                }
            }
        } else if isExpanded {
            if renderMarkdown, let attr = HistoryRenderCache.markdown(record.text, clean: { cleanMarkdown($0, stripBold: false) }) {
                Text(attr)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            } else {
                Text(record.text)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
        } else {
            if renderMarkdown, let attr = HistoryRenderCache.markdown(record.text, clean: { cleanMarkdown($0, stripBold: false) }) {
                Text(attr)
                    .font(.system(.body, design: .rounded))
                    .lineLimit(2)
                    .foregroundColor(.primary)
            } else {
                Text(record.text)
                    .font(.system(.body, design: .rounded))
                    .lineLimit(2)
                    .foregroundColor(.primary)
            }
        }
    }
    
    private func cleanMarkdown(_ text: String, stripBold: Bool = false) -> String {
        var clean = text
        // Convert block headings to inline bold so inlineOnly parser renders them
        clean = clean.replacingOccurrences(of: "(?m)^#+\\s+(.*?)$", with: "**$1**", options: .regularExpression)
        
        if stripBold {
            clean = clean.replacingOccurrences(of: "\\*\\*(.*?)\\*\\*", with: "$1", options: .regularExpression)
            clean = clean.replacingOccurrences(of: "\\*(.*?)\\*", with: "$1", options: .regularExpression)
        }
        clean = clean.replacingOccurrences(of: "- \\[ \\]", with: "•", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "- \\[x\\]", with: "✓", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "- \\[X\\]", with: "✓", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "\\[ \\]", with: "•", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "\\[x\\]", with: "✓", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "\\[X\\]", with: "✓", options: .regularExpression)
        return clean
    }
    
    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 8) {
            Text(smartDateString)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.dictySecondary)
                .layoutPriority(1)
            
            Spacer()
            
            if let credits = record.credits_used, credits > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                    Text(String(credits))
                }
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .foregroundColor(.secondary)
                .cornerRadius(6)
            }
            
            if record.reprocessed_at != nil {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Reprocessed")
                }
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .foregroundColor(.secondary)
                .cornerRadius(6)
            }
            
            if record.mode == "tts" {
                HStack(spacing: 3) {
                    Image(systemName: "speaker.wave.2.fill")
                    Text(record.voice != nil && !record.voice!.isEmpty ? "TTS (\(record.voice!))" : "TTS")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.appAccent.opacity(0.15))
                .foregroundColor(.appAccent)
                .cornerRadius(6)
            } else {
                let appText = record.app_name ?? record.app_id
                let modeText = (record.mode_id ?? record.mode).replacingOccurrences(of: "_", with: " ").capitalized
                let isAuto = record.mode_reason == "app_rule"
                
                let badgeLabel: String = {
                    if let app = appText, !app.isEmpty {
                        return isAuto ? "\(app) · \(modeText) (auto)" : "\(app) · \(modeText)"
                    } else {
                        return modeText
                    }
                }()
                
                Text(badgeLabel)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(record.mode == "dictation" ? Color.appAccent.opacity(0.15) : Color.primary.opacity(0.06))
                    .foregroundColor(record.mode == "dictation" ? .appAccent : .secondary)
                    .cornerRadius(6)
            }
            
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.dictySecondary)
                .layoutPriority(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring()) {
                isExpanded.toggle()
                if isExpanded {
                    loadAudioDurationIfNeeded()
                }
            }
        }
    }
    
    /// Load audio duration asynchronously when the row expands; cache per entry.
    private func loadAudioDurationIfNeeded() {
        guard cachedDuration == nil, !audioFileMissing, record.isAudioAvailable else { return }
        // Check if we already have duration from the server response
        if let d = record.duration, d > 0 {
            cachedDuration = d
            duration = d
            return
        }
        let audioURL = URL(string: "\(engineClient.engineURL)/history/audio/\(record.id)")!
        Task.detached(priority: .userInitiated) {
            let asset = EngineEndpoint.shared.audioAsset(for: audioURL)
            do {
                let cmDuration = try await asset.load(.duration)
                let secs = CMTimeGetSeconds(cmDuration)
                guard secs.isFinite, secs > 0 else {
                    await MainActor.run { audioFileMissing = true }
                    return
                }
                await MainActor.run {
                    cachedDuration = secs
                    duration = secs
                }
            } catch {
                await MainActor.run { audioFileMissing = true }
            }
        }
    }
    
    @ViewBuilder
    private var notesView: some View {
        if isEditingNotes {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .foregroundColor(.stylishGreen)
                    Text("Notes")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(.stylishGreen)
                    Spacer()
                    Text("Optional context for AI summary")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.dictySecondary)
                }
                
                TextEditor(text: $editedNotes)
                    .font(.system(.subheadline, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.stylishGreen.opacity(0.3), lineWidth: 1))
                    .frame(minHeight: 56, maxHeight: 120)
                
                HStack(spacing: 8) {
                    Spacer()
                    Button(action: {
                        isEditingNotes = false
                        editedNotes = record.notes ?? ""
                    }) {
                        Text("Cancel")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.dictySecondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: saveNotes) {
                        HStack(spacing: 4) {
                            if isSavingNotes {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "checkmark")
                            }
                            Text("Save")
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.stylishGreen)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingNotes)
                }
            }
            .padding(12)
            .background(Color.stylishGreen.opacity(0.08))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.stylishGreen.opacity(0.2), lineWidth: 1))
        } else if let notes = record.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .foregroundColor(.stylishGreen)
                    Text("Notes")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(.stylishGreen)
                    Spacer()
                    
                    Button(action: {
                        editedNotes = notes
                        isEditingNotes = true
                    }) {
                        Label("Edit", systemImage: "pencil")
                            .font(.system(.caption2))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.stylishGreen)
                    
                    Button(action: deleteNotes) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.dictySecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove notes")
                }
                
                if isExpanded {
                    Text(notes)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                } else {
                    Text(notes)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .background(Color.stylishGreen.opacity(0.08))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.stylishGreen.opacity(0.2), lineWidth: 1))
            .onTapGesture {
                if !isEditingNotes {
                    editedNotes = notes
                    isEditingNotes = true
                }
            }
        }
    }
    
    private func saveNotes() {
        isSavingNotes = true
        let clean = editedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNotes = clean.isEmpty ? "" : clean
        Task {
            await engineClient.updateHistoryRecord(id: record.id, notes: finalNotes)
            await MainActor.run {
                self.isSavingNotes = false
                self.isEditingNotes = false
            }
        }
    }
    
    private func deleteNotes() {
        editedNotes = ""
        isEditingNotes = false
        Task {
            await engineClient.updateHistoryRecord(id: record.id, notes: "")
        }
    }
    
    private func triggerSummarize() {
        if isEditingNotes {
            saveNotes()
        }
        let notesToSend = isEditingNotes ? editedNotes.trimmingCharacters(in: .whitespacesAndNewlines) : record.notes
        engineClient.summarizeHistory(id: record.id, notes: notesToSend)
    }

    @ViewBuilder
    private func summaryView(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "text.quote")
                    .foregroundColor(.pastelLavender)
                Text("Summary")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(.pastelLavender)
                Spacer()
                Button(action: {
                    withAnimation { renderMarkdown.toggle() }
                }) {
                    Label(renderMarkdown ? "Raw Text" : "Markdown", systemImage: renderMarkdown ? "text.alignleft" : "text.word.spacing")
                        .font(.system(.caption2))
                }
                .buttonStyle(.plain)
                .foregroundColor(.pastelLavender)
                
                Button(action: {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    if renderMarkdown {
                        pb.setString(cleanMarkdown(summary, stripBold: true), forType: .string)
                    } else {
                        pb.setString(summary, forType: .string)
                    }
                }) {
                    Label("Copy", systemImage: "doc.on.clipboard")
                        .font(.system(.caption2))
                }
                .buttonStyle(.plain)
                .foregroundColor(.pastelLavender)
                
                let isGenerating = engineClient.summarizingIds.contains(record.id)
                Button(action: triggerSummarize) {
                    Label(isGenerating ? "Summarizing..." : "Re-summarize", systemImage: "arrow.clockwise")
                        .font(.system(.caption2))
                }
                .buttonStyle(.plain)
                .foregroundColor(.pastelLavender)
                .disabled(isGenerating)
            }
            if isExpanded {
                if renderMarkdown, let attr = HistoryRenderCache.markdown(summary, clean: { cleanMarkdown($0, stripBold: false) }) {
                    Text(attr)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                } else {
                    Text(summary)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }
            } else {
                if renderMarkdown, let attr = HistoryRenderCache.markdown(summary, clean: { cleanMarkdown($0, stripBold: false) }) {
                    Text(attr)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                } else {
                    Text(summary)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.pastelLavender.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.pastelLavender.opacity(0.25), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var audioPlayerBarView: some View {
        HStack(spacing: 8) {
            // Play / Pause Button
            Button(action: togglePlayPause) {
                ZStack {
                    Circle()
                        .fill(Color.stylishGreen)
                        .frame(width: 26, height: 26)
                        .shadow(color: Color.stylishGreen.opacity(0.3), radius: 3, x: 0, y: 1)
                    
                    if isLoadingAudio {
                        ProgressView()
                            .controlSize(.mini)
                            .colorInvert()
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: isPlaying ? 0 : 0.5)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoadingAudio)
            .help(isPlaying ? "Pause playback" : "Play audio recording")
            
            // Stop button (visible when playing or paused)
            if isPlaying || isPaused {
                Button(action: stopPlayback) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 22, height: 22)
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.dictySecondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Stop playback")
                .transition(.scale.combined(with: .opacity))
            }
            
            // Current Time (e.g. 0:01)
            Text(formatDuration(currentTime))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
            
            // Scrubber Bar
            GeometryReader { geo in
                let prog = max(0.0, min(1.0, playbackProgress))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 5)
                    Capsule()
                        .fill(Color.stylishGreen)
                        .frame(width: max(0, geo.size.width * CGFloat(prog)), height: 5)
                    Circle()
                        .fill(Color.stylishGreen)
                        .frame(width: 10, height: 10)
                        .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                        .offset(x: max(0, min(geo.size.width - 10, geo.size.width * CGFloat(prog) - 5)))
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let frac = max(0.0, min(1.0, Double(val.location.x / max(1.0, geo.size.width))))
                            seekPlayback(to: frac)
                        }
                )
            }
            .frame(height: 14)
            
            // Total Duration (e.g. 0:07)
            let totalDur = duration > 0 ? duration : (record.duration ?? 0.0)
            Text(formatDuration(totalDur))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.dictySecondary)
                .frame(minWidth: 28, alignment: .leading)
            
            // Reveal in Finder Button
            Button(action: revealInFinder) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Finder")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .foregroundColor(.primary.opacity(0.85))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .help("Reveal audio file in Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.035))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            Button(action: {
                let pb = NSPasteboard.general
                pb.clearContents()
                if renderMarkdown {
                    pb.setString(cleanMarkdown(record.text, stripBold: true), forType: .string)
                } else {
                    pb.setString(record.text, forType: .string)
                }
            }) {
                Label("Copy", systemImage: "doc.on.clipboard")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundColor(actionHoverId == "copy" ? .appAccent : .secondary)
            .onHover { h in if h { actionHoverId = "copy" } else if actionHoverId == "copy" { actionHoverId = nil } }
            
            Button(action: {
                showTagEditor = true
            }) {
                Label("Tags", systemImage: "tag")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundColor(actionHoverId == "tags" ? .appAccent : .secondary)
            .onHover { h in if h { actionHoverId = "tags" } else if actionHoverId == "tags" { actionHoverId = nil } }

            if isMeetingRecord && !parsedMeetingDialogue.turns.isEmpty {
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        showChatView.toggle()
                    }
                }) {
                    Label(showChatView ? "Text View" : "Chat View", systemImage: showChatView ? "doc.text" : "bubble.left.and.bubble.right")
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundColor(.appAccent)
            }
            
            let isReprocessing = engineClient.reprocessingIds.contains(record.id)
            Button(action: {
                showReprocessSheet = true
            }) {
                HStack(spacing: 4) {
                    if isReprocessing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(isReprocessing ? "Processing..." : "Re-process")
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(isReprocessing ? .gray : (actionHoverId == "reprocess" ? .appAccent : .secondary))
            .onHover { h in if h { actionHoverId = "reprocess" } else if actionHoverId == "reprocess" { actionHoverId = nil } }
            .disabled(isReprocessing)
            
            let isGenerating = engineClient.summarizingIds.contains(record.id)
            if record.summary == nil || record.summary!.isEmpty {
                Button(action: triggerSummarize) {
                    Label(isGenerating ? "Summarizing..." : "Summarize", systemImage: "text.quote")
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundColor(isGenerating ? .gray : (actionHoverId == "summarize" ? .appAccent : .secondary))
                .onHover { h in if h { actionHoverId = "summarize" } else if actionHoverId == "summarize" { actionHoverId = nil } }
                .disabled(isGenerating)
            } else {
                Button(action: triggerSummarize) {
                    Label(isGenerating ? "Summarizing..." : "Re-summarize", systemImage: "arrow.clockwise")
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundColor(isGenerating ? .gray : (actionHoverId == "summarize" ? .appAccent : .secondary))
                .onHover { h in if h { actionHoverId = "summarize" } else if actionHoverId == "summarize" { actionHoverId = nil } }
                .disabled(isGenerating)
            }
            
            Spacer(minLength: 8)
            
            Button(action: {
                showDeleteConfirm = true
            }) {
                Label("Delete", systemImage: "trash")
                    .lineLimit(1)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .confirmationDialog("Delete this recording?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    withAnimation { engineClient.deleteHistory(id: record.id) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .lineLimit(1)
        .font(.system(.caption, design: .rounded).weight(.medium))
        .padding(.top, 4)
    }
    
    func startPlayback() {
        guard record.isAudioAvailable else { return }
        isLoadingAudio = true
        Task {
            do {
                let url = URL(string: "\(engineClient.engineURL)/history/audio/\(record.id)")!
                let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                let player = try AVAudioPlayer(data: data)
                await MainActor.run {
                    self.isLoadingAudio = false
                    self.audioPlayer = player
                    self.duration = player.duration
                    self.currentTime = 0.0
                    self.playbackProgress = 0.0
                    self.isPlaying = true
                    self.isPaused = false
                    player.play()
                    self.startTimer()
                }
            } catch {
                await MainActor.run {
                    self.isLoadingAudio = false
                }
                print("Audio error: \(error)")
            }
        }
    }

    func togglePlayPause() {
        if let player = audioPlayer {
            if player.isPlaying {
                player.pause()
                isPlaying = false
                isPaused = true
            } else {
                player.play()
                isPlaying = true
                isPaused = false
                startTimer()
            }
        } else {
            startPlayback()
        }
    }

    func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        isPaused = false
        currentTime = 0.0
        playbackProgress = 0.0
    }

    func seekPlayback(to fraction: Double) {
        if audioPlayer == nil {
            guard record.isAudioAvailable else { return }
            isLoadingAudio = true
            Task {
                do {
                    let url = URL(string: "\(engineClient.engineURL)/history/audio/\(record.id)")!
                    let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                    let player = try AVAudioPlayer(data: data)
                    await MainActor.run {
                        self.isLoadingAudio = false
                        self.audioPlayer = player
                        self.duration = player.duration
                        let target = max(0.0, min(player.duration, fraction * player.duration))
                        player.currentTime = target
                        self.currentTime = target
                        self.playbackProgress = fraction
                        self.isPlaying = true
                        self.isPaused = false
                        player.play()
                        self.startTimer()
                    }
                } catch {
                    await MainActor.run {
                        self.isLoadingAudio = false
                    }
                }
            }
            return
        }
        guard let player = audioPlayer, duration > 0 else { return }
        let target = max(0.0, min(duration, fraction * duration))
        player.currentTime = target
        currentTime = target
        playbackProgress = fraction
    }

    func revealInFinder() {
        let filePath = record.audio_file
        if !filePath.isEmpty && FileManager.default.fileExists(atPath: filePath) {
            let fileURL = URL(fileURLWithPath: filePath)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            return
        }
        
        let historyDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dicty/transcripts_input/history")
        
        let candidateWav = historyDir.appendingPathComponent("\(record.id).wav")
        if FileManager.default.fileExists(atPath: candidateWav.path) {
            NSWorkspace.shared.activateFileViewerSelecting([candidateWav])
            return
        }
        
        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(historyDir)
    }

    private func startTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            DispatchQueue.main.async {
                guard let player = self.audioPlayer else { return }
                if player.isPlaying {
                    self.currentTime = player.currentTime
                    if self.duration > 0 {
                        self.playbackProgress = max(0.0, min(1.0, player.currentTime / self.duration))
                    }
                } else if !self.isPaused && player.currentTime >= player.duration - 0.1 {
                    self.stopPlayback()
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    
    func formatDate(_ isoString: String) -> String {
        return smartDateString
    }
}

struct VocabularyResponse: Codable {
    let vocabulary: [DictyVocabulary]
}

struct DictyVocabulary: Codable, Identifiable {
    let id: String
    let word: String
    let replacement: String
}

struct VocabularyView: View {
    @EnvironmentObject var engineClient: EngineClient
    @Environment(\.colorScheme) var colorScheme
    @State private var newWord = ""
    @State private var newReplacement = ""
    @State private var searchText = ""
    @State private var hoveredItemId: String? = nil
    
    var filteredVocabulary: [DictyVocabulary] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return engineClient.vocabulary
        } else {
            return engineClient.vocabulary.filter {
                $0.word.localizedCaseInsensitiveContains(searchText) ||
                $0.replacement.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with Statistics Badge
            HStack(alignment: .top) {
                SettingsPageHeader(
                    title: "Vocabulary",
                    description: "Teach Dicty custom terminology and acronyms: what you say is replaced with how it should be written.",
                    helpTopic: .vocabulary
                )
                
                Spacer()
                
                // Count badge
                HStack(spacing: 6) {
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.sageGreen)
                    Text("\(engineClient.vocabulary.count) \(engineClient.vocabulary.count == 1 ? "Rule" : "Rules")")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.sageGreen.opacity(colorScheme == .dark ? 0.2 : 0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.sageGreen.opacity(0.25), lineWidth: 1)
                )
            }
            
            Divider()
            
            // Search Bar & Actions
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.dictySecondary)
                    
                    TextField("Search custom words or replacements...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.dictySecondary.opacity(0.8))
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.06)
                                : Color.black.opacity(0.03)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                
                Button(action: {
                    importCSV()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Import CSV")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.08)
                                    : Color.white
                            )
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 3, y: 1.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary)
            }
            
            // New Term Creation Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundColor(.sageGreen)
                    Text("Add Pronunciation / Voice Snippet")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                }
                
                HStack(spacing: 12) {
                    // Left Input: Spoken / trigger word
                    VStack(alignment: .leading, spacing: 4) {
                        Text("When you say:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.dictySecondary)
                        
                        TextField("e.g. digty, pr, k8s", text: $newWord)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                            .onSubmit {
                                submitNewRule()
                            }
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.sageGreen)
                        .padding(.top, 14)
                    
                    // Right Input: Replacement / Expansion
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dicty writes:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.dictySecondary)
                        
                        TextField("e.g. Dicty, Pull Request, Kubernetes", text: $newReplacement)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                            .onSubmit {
                                submitNewRule()
                            }
                    }
                    
                    // Add Button
                    Button(action: {
                        submitNewRule()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Add Rule")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? Color.secondary.opacity(0.2)
                                        : Color.sageGreen
                                )
                        )
                        .foregroundColor(
                            newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? .secondary
                                : .white
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, 14)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.04)
                            : Color.black.opacity(0.02)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
            
            // Vocabulary List
            ScrollView {
                if filteredVocabulary.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: searchText.isEmpty ? "character.bubble" : "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.dictySecondary.opacity(0.6))
                            .padding(.top, 30)
                        
                        Text(searchText.isEmpty ? "No custom vocabulary rules yet" : "No rules match \"\(searchText)\"")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.dictySecondary)
                        
                        if searchText.isEmpty {
                            Text("Add technical terms, foreign names, or shorthand expansions above.")
                                .font(.caption)
                                .foregroundColor(.dictySecondary.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredVocabulary) { item in
                            let isHovered = hoveredItemId == item.id
                            
                            HStack(spacing: 12) {
                                // Spoken term pill
                                HStack(spacing: 6) {
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.dictySecondary)
                                    Text(item.word)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.primary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(
                                            colorScheme == .dark
                                                ? Color.white.opacity(0.08)
                                                : Color.black.opacity(0.05)
                                        )
                                )
                                
                                // Directional Arrow
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.sageGreen)
                                
                                // Replacement pill
                                HStack(spacing: 6) {
                                    Image(systemName: "text.quote")
                                        .font(.system(size: 10))
                                        .foregroundColor(.sageGreen)
                                    Text(item.replacement.isEmpty ? item.word : item.replacement)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(item.replacement.isEmpty ? .dictySecondary : .primary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.sageGreen.opacity(colorScheme == .dark ? 0.15 : 0.08))
                                )
                                
                                Spacer()
                                
                                // Delete Button with subtle hover reaction
                                Button(action: {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        engineClient.deleteVocabulary(id: item.id)
                                    }
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundColor(isHovered ? .red : .dictySecondary.opacity(0.6))
                                        .padding(6)
                                        .background(
                                            Circle()
                                                .fill(isHovered ? Color.red.opacity(0.12) : Color.clear)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("Delete rule")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        colorScheme == .dark
                                            ? Color.white.opacity(isHovered ? 0.07 : 0.035)
                                            : Color.white.opacity(isHovered ? 0.9 : 0.6)
                                    )
                                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.03), radius: 2, y: 1)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        isHovered
                                            ? Color.sageGreen.opacity(0.3)
                                            : Color.primary.opacity(0.06),
                                        lineWidth: 1
                                    )
                            )
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    hoveredItemId = hovering ? item.id : nil
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(20)
        .navigationTitle("Vocabulary")
    }
    
    private func submitNewRule() {
        let cleanWord = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReplacement = newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanWord.isEmpty else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            engineClient.addVocabulary(word: cleanWord, replacement: cleanReplacement)
            newWord = ""
            newReplacement = ""
        }
    }
    
    func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try String(contentsOf: url, encoding: .utf8)
                let rows = data.components(separatedBy: .newlines)
                for row in rows {
                    let cols = row.components(separatedBy: ",")
                    if cols.count >= 1 {
                        let word = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        let replacement = cols.count >= 2 ? cols[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                        if !word.isEmpty && word.lowercased() != "word" { // skip header
                            engineClient.addVocabulary(word: word, replacement: replacement)
                        }
                    }
                }
            } catch {
                print("Failed to import CSV: \(error)")
            }
        }
    }
}

struct GitHubCommitInfo: Identifiable, Hashable {
    let id: String // sha
    let message: String
    let author: String
    let date: String
    let url: String
}

struct GitHubPRInfo: Identifiable, Hashable {
    let id: Int // number
    let title: String
    let author: String
    let date: String
    let url: String
}

func formatRelativeDate(_ isoString: String) -> String {
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: isoString) {
        let relFormatter = RelativeDateTimeFormatter()
        relFormatter.unitsStyle = .full
        return relFormatter.localizedString(for: date, relativeTo: Date())
    }
    return String(isoString.prefix(10))
}

// MARK: - Reprocess Modal Sheet
struct ReprocessSheetView: View {
    @EnvironmentObject var engineClient: EngineClient
    @Environment(\.dismiss) var dismiss
    
    var record: DictyHistory
    
    @State private var targetMode: String
    @State private var formatStyle: String = "raw"
    @State private var customPrompt: String = ""
    @State private var retranscribeAudio: Bool = false
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil
    
    init(record: DictyHistory) {
        self.record = record
        let initial = (record.mode == "meeting" || record.mode == "focused_meeting") ? record.mode : "dictation"
        _targetMode = State(initialValue: initial)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.stylishGreen)
                        Text("Re-process Recording")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                    }
                    Text("Change category, formatting structure, or prompt without speaking again.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.dictySecondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.dictySecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Original Context Card
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CURRENT TRANSCRIPT")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.dictySecondary)
                            Text(record.text)
                                .font(.system(.caption, design: .rounded))
                                .lineLimit(3)
                                .foregroundColor(.primary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    
                    // Target Mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TARGET MODE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.dictySecondary)
                        
                        Picker("", selection: $targetMode) {
                            Text("Dictation").tag("dictation")
                            Text("Meeting").tag("meeting")
                            Text("Focused Meeting").tag("focused_meeting")
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Formatting Style
                    if targetMode == "dictation" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FORMATTING STYLE")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.dictySecondary)
                            
                            Picker("", selection: $formatStyle) {
                                Text("Raw / Verbatim").tag("raw")
                                Text("Structured Note").tag("note")
                                Text("Professional Email").tag("email")
                                Text("Chat Message").tag("message")
                                Text("Book Prose").tag("book")
                                Text("Code / Commit").tag("code")
                                Text("Custom Prompt...").tag("custom")
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                    
                    // Custom Prompt Editor
                    if targetMode == "dictation" && formatStyle == "custom" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CUSTOM PROMPT INSTRUCTIONS")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.dictySecondary)
                            
                            TextEditor(text: $customPrompt)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 65)
                                .padding(6)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                            
                            Text("Enter custom instructions (e.g., 'Summarize in 3 bullet points with Spanish translation').")
                                .font(.system(size: 10))
                                .foregroundColor(.dictySecondary)
                        }
                    }
                    
                    // Processing Engine Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PROCESSING ENGINE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.dictySecondary)
                        
                        Picker("", selection: $retranscribeAudio) {
                            Text("Fast Re-Format (LLM)").tag(false)
                            Text(record.isAudioAvailable ? "Full Re-Transcribe (Audio)" : "Full Re-Transcribe (No Audio)").tag(true)
                        }
                        .pickerStyle(.segmented)
                        
                        if !retranscribeAudio {
                            Text(record.isAudioAvailable ? "Restructures existing transcript with LLM. Fast & zero audio lag." : "Restructures existing transcript with LLM (original audio was deleted or scrubbed).")
                                .font(.system(size: 11))
                                .foregroundColor(.dictySecondary)
                        } else {
                            if record.isAudioAvailable {
                                Text("Re-runs speech recognition from audio file. Useful if words were misheard or you changed models.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.dictySecondary)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                    Text("Audio file is not available because it was scrubbed by retention policy.")
                                }
                                .font(.system(size: 11))
                                .foregroundColor(.dictySecondary)
                            }
                        }
                    }
                    
                    if let err = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(.red)
                        }
                        .padding(10)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: executeReprocess) {
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(isProcessing ? "Processing..." : "Re-process Transcript")
                    }
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.stylishGreen)
                .disabled(isProcessing)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 460, height: 480)
    }
    
    private func executeReprocess() {
        isProcessing = true
        errorMessage = nil
        Task {
            let success = await engineClient.reprocessHistory(
                id: record.id,
                mode: targetMode,
                formatStyle: formatStyle,
                customPrompt: customPrompt.isEmpty ? nil : customPrompt,
                retranscribeAudio: retranscribeAudio
            )
            await MainActor.run {
                isProcessing = false
                if success {
                    dismiss()
                } else {
                    errorMessage = engineClient.reprocessErrors[record.id] ?? "Failed to reprocess recording."
                }
            }
        }
    }
}

// MARK: - Tag Editor Sheet
struct TagEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var engineClient: EngineClient
    let record: DictyHistory
    @State private var tags: [String] = []
    @State private var newTagInput: String = ""
    @State private var isSaving = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .foregroundColor(.sageGreen)
                    Text("Edit Record Tags")
                        .font(.headline)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Text("Assign or remove tags for this transcription record.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text("#\(tag)")
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.primary.opacity(0.85))
                                Button(action: {
                                    tags.removeAll(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
                                }) {
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
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.14), lineWidth: 0.8))
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text("No tags currently assigned.")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.vertical, 4)
            }
            
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("#")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13, weight: .bold))
                    TextField("Add tag (e.g. meeting, standup)...", text: $newTagInput)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            addTag()
                        }
                }
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
                        .background(newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.35) : Color.sageGreen)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button(action: {
                    isSaving = true
                    Task {
                        await engineClient.updateHistoryTags(recordId: record.id, tags: tags)
                        await MainActor.run {
                            isSaving = false
                            dismiss()
                        }
                    }
                }) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save Tags")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.sageGreen)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            self.tags = (record.tags ?? []).map { $0.lstripHash() }
        }
    }
    
    private func addTag() {
        let clean = newTagInput.lstripHash()
        guard !clean.isEmpty else { return }
        if !tags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            tags.append(clean)
        }
        newTagInput = ""
    }
}



/// Formatters are expensive to create, and markdown parsing ran for every card on every render
/// (300+ records => History took ~300 ms to open). Both are cached here.
@MainActor
enum HistoryRenderCache {
    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    static let iso = ISO8601DateFormatter()
    static let display: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()

    private static var markdownCache: [String: AttributedString] = [:]

    static func markdown(_ text: String, clean: (String) -> String) -> AttributedString? {
        if let hit = markdownCache[text] { return hit }
        guard let attr = try? AttributedString(markdown: clean(text), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return nil }
        if markdownCache.count > 1000 { markdownCache.removeAll() }
        markdownCache[text] = attr
        return attr
    }
}
