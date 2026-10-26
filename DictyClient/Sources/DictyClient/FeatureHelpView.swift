import SwiftUI
import AppKit

// MARK: - Topic Identifiers
public enum FeatureHelpTopic: String, CaseIterable, Identifiable, Sendable {
    case models
    case modes
    case vocabulary
    case shortcuts
    case history
    case preferences
    case api_keys
    case transcribe
    case projects
    case sync_backup
    
    public var id: String { rawValue }
}

// MARK: - Help Data Structures
public struct HelpItem: Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let description: String
    
    public init(label: String, description: String) {
        self.label = label
        self.description = description
    }
}

public struct HelpSection: Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let items: [HelpItem]
    
    public init(title: String, items: [HelpItem]) {
        self.title = title
        self.items = items
    }
}

public struct FeatureGuide: Identifiable, Sendable {
    public let id: FeatureHelpTopic
    public let title: String
    public let badge: String
    public let systemIcon: String
    public let summary: String
    public let sections: [HelpSection]
    public let proTip: String
    public let targetTab: Int?
    public let actionTitle: String?
    
    public init(
        id: FeatureHelpTopic,
        title: String,
        badge: String,
        systemIcon: String,
        summary: String,
        sections: [HelpSection],
        proTip: String,
        targetTab: Int? = nil,
        actionTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.badge = badge
        self.systemIcon = systemIcon
        self.summary = summary
        self.sections = sections
        self.proTip = proTip
        self.targetTab = targetTab
        self.actionTitle = actionTitle
    }
}

// MARK: - Repository Guides
public let FEATURE_GUIDES: [FeatureGuide] = [
    FeatureGuide(
        id: .models,
        title: "Speech Models & Acceleration",
        badge: "Core Engine",
        systemIcon: "cpu",
        summary: "Dicty runs OpenAI Whisper locally via whisper.cpp with Apple Silicon Metal acceleration for high-speed, 100% private offline voice recognition.",
        sections: [
            HelpSection(title: "Local Offline vs Cloud Models", items: [
                HelpItem(
                    label: "Local Offline Models",
                    description: "Run directly on your Apple Silicon Neural Engine & GPU with zero network calls. Voice data never leaves your Mac, ensuring complete privacy with sub-second latency."
                ),
                HelpItem(
                    label: "Cloud Speech Models (API)",
                    description: "Optionally utilize OpenAI Whisper-1 or Parakeet cloud endpoints. Ideal for exceptionally long recordings or low-spec hardware without local RAM headroom."
                )
            ]),
            HelpSection(title: "Quantization & Model Tiers", items: [
                HelpItem(
                    label: "Turbo / Q5 (Recommended)",
                    description: "Whisper Large-v3 Turbo quantized to 5-bit. Delivers near-perfect studio accuracy with 4x-6x real-time speed on Apple Silicon."
                ),
                HelpItem(
                    label: "Studio Precision (F16 / Large-v3)",
                    description: "Full uncompressed 16-bit float weights. Offers maximum recognition fidelity for dense technical jargon, heavy accents, and noisy environments."
                ),
                HelpItem(
                    label: "Lightweight (Tiny / Small)",
                    description: "Compact models taking under 500MB RAM, optimized for maximum battery conservation during travel."
                )
            ]),
            HelpSection(title: "Language Support", items: [
                HelpItem(
                    label: "Multilingual Models",
                    description: "Automatically detect and transcribe 99+ languages with full punctuation and auto-capitalization."
                ),
                HelpItem(
                    label: "English-Optimized (.en)",
                    description: "Specifically fine-tuned acoustic weights for English speech with higher word-error-rate resilience."
                )
            ])
        ],
        proTip: "On Apple Silicon, Whisper models take advantage of unified memory and Metal shaders. Downloading a model stores it locally in ~/.cache/dicty for instant offline reuse.",
        targetTab: 2,
        actionTitle: "Open Models Library"
    ),
    
    FeatureGuide(
        id: .modes,
        title: "Modes & Workflow Profiles",
        badge: "Productivity",
        systemIcon: "slider.horizontal.3",
        summary: "Modes allow you to customize dictation formatting, system prompts, and model behavior for coding, emails, or architectural documentation.",
        sections: [
            HelpSection(title: "Why Use Different Modes?", items: [
                HelpItem(
                    label: "Dictation Mode",
                    description: "Clean, natural voice-to-text with auto-punctuation, automatically typed or pasted into your current active cursor position."
                ),
                HelpItem(
                    label: "Librarian Mode (Alpha)",
                    description: "Specialized mode for software engineers. Transcribes technical thoughts, tags Git branches, and batches changes for architectural docs (Obsidian, Confluence, Linear)."
                ),
                HelpItem(
                    label: "Meeting & Focused Meeting",
                    description: "Records ongoing conversations with speaker diarization timestamps and automatic meeting summary generation."
                )
            ]),
            HelpSection(title: "Custom Formatting Styles", items: [
                HelpItem(
                    label: "Formatting Styles",
                    description: "Choose between Raw Transcript, Book Prose, Fast Punctuation (0ms latency), Email, Messaging, or Custom Prompt."
                ),
                HelpItem(
                    label: "Quick Mode Switcher HUD",
                    description: "Press your global Mode Switcher shortcut or switch directly from the menu bar to jump between profiles instantly."
                )
            ])
        ],
        proTip: "Use the Librarian target selector to route thoughts straight to your local Obsidian markdown notes or remote Confluence docs without leaving your IDE.",
        targetTab: 1,
        actionTitle: "Configure Modes"
    ),
    
    FeatureGuide(
        id: .vocabulary,
        title: "Custom Vocabulary & Whisper Bias",
        badge: "Acoustic Tuning",
        systemIcon: "text.book.closed",
        summary: "Train Dicty to accurately transcribe company names, acronyms, technical terms, and accented speech that generic models misspell.",
        sections: [
            HelpSection(title: "How Acoustic Biasing Works", items: [
                HelpItem(
                    label: "Initial Prompt Biasing",
                    description: "Whisper models accept dictionary context prompts. Dicty feeds your vocabulary directly to the decoder so it actively listens for your unique terminology."
                ),
                HelpItem(
                    label: "Instant Phonetic Replacement",
                    description: "Define exact replacement rules (e.g., 'fast api' -> 'FastAPI', 'cubectl' -> 'kubectl') to automatically correct phonetically tricky words before pasting."
                )
            ]),
            HelpSection(title: "Best Practices", items: [
                HelpItem(
                    label: "Exact Casing",
                    description: "Enter terms with exact capitalization (e.g. 'TypeScript', 'GraphQL', 'SwiftUI')."
                ),
                HelpItem(
                    label: "Concise Wordlists",
                    description: "Keep your active list focused on 15-40 of your most common custom words for optimal biasing performance."
                )
            ])
        ],
        proTip: "Use the 'Starter Pack (10)' button to quickly import 10 common software engineering acronyms with a single click.",
        targetTab: 5,
        actionTitle: "Manage Vocabulary"
    ),
    
    FeatureGuide(
        id: .shortcuts,
        title: "Keyboard Shortcuts & Hotkeys",
        badge: "Global Controls",
        systemIcon: "keyboard",
        summary: "Trigger Dicty globally from any macOS application (Xcode, VS Code, Slack, Safari, Notes) using global keyboard shortcuts.",
        sections: [
            HelpSection(title: "Default Hotkeys", items: [
                HelpItem(
                    label: "Toggle Dictation (⌘R or Custom)",
                    description: "Press once to start recording, speak your thought, and press again to finish. Dicty automatically inserts the transcribed text at your active cursor."
                ),
                HelpItem(
                    label: "Pause / Resume (Space while active)",
                    description: "Temporarily pause the recording if you need to think or cough without canceling the active transcription session."
                ),
                HelpItem(
                    label: "Cancel Recording (Esc)",
                    description: "Immediately aborts the recording without transcribing or pasting anything."
                )
            ]),
            HelpSection(title: "Accessibility & Permissions", items: [
                HelpItem(
                    label: "Accessibility API",
                    description: "Dicty requires macOS Accessibility permissions in System Settings -> Privacy & Security to detect global hotkeys and inject text directly into third-party windows."
                ),
                HelpItem(
                    label: "Direct Typing vs Clipboard",
                    description: "Toggle between direct simulated keystrokes and system clipboard paste in Preferences."
                )
            ])
        ],
        proTip: "Dicty runs as a menu bar agent. You never need to switch focus away from your active code or document—just hit your hotkey and speak.",
        targetTab: 4,
        actionTitle: "Configure Shortcuts"
    ),
    
    FeatureGuide(
        id: .history,
        title: "Transcription History & Snippets",
        badge: "Archive",
        systemIcon: "clock",
        summary: "Browse, search, listen to, and re-process your local speech-to-text dictations with zero external telemetry.",
        sections: [
            HelpSection(title: "Key History Features", items: [
                HelpItem(
                    label: "Audio Playback",
                    description: "Listen back to your original recorded voice audio to verify speech clarity or revisit past conversations."
                ),
                HelpItem(
                    label: "Re-Transcribe With Any Model",
                    description: "Re-run any recording through a higher precision model (like Large-v3 Studio F16) with one click."
                ),
                HelpItem(
                    label: "Filter & Export",
                    description: "Search by keyword, filter by Dictation or Meeting mode, and export transcripts to Markdown (.md), Plain Text, or SRT subtitles."
                )
            ])
        ],
        proTip: "Audio recordings and database records are stored locally in your Application Support directory. Incognito mode can be enabled anytime from the menu bar to disable history logging.",
        targetTab: 3,
        actionTitle: "Open History"
    ),
    
    FeatureGuide(
        id: .preferences,
        title: "Preferences & Audio Setup",
        badge: "Configuration",
        systemIcon: "gearshape",
        summary: "Configure your microphone input hardware, audio chime feedback, theme appearance, and background launch behavior.",
        sections: [
            HelpSection(title: "Hardware & Audio Feedback", items: [
                HelpItem(
                    label: "Audio Input Selector",
                    description: "Choose your preferred microphone or leave on 'System Default' to follow dynamic macOS audio device switching."
                ),
                HelpItem(
                    label: "Recording Sound Chimes",
                    description: "Enable pleasant start/stop audio cues (Pop, Funk, Ping, Submarine) so you always know when dictation starts and stops."
                ),
                HelpItem(
                    label: "Auto-Pause Media",
                    description: "Automatically pauses Spotify, Apple Music, or Podcasts via MediaRemote when dictation begins, and resumes when you finish speaking."
                )
            ]),
            HelpSection(title: "App Lifecycle", items: [
                HelpItem(
                    label: "Show in Dock vs Menu Bar",
                    description: "Choose whether Dicty shows an icon in the macOS Dock or remains cleanly tucked away in the top menu bar."
                ),
                HelpItem(
                    label: "Launch at Login",
                    description: "Launch Dicty automatically on startup so your dictation hotkeys are always active."
                )
            ])
        ],
        proTip: "If you ever need to re-verify microphone permissions or test your input volume, you can replay the Onboarding Setup Wizard anytime from Preferences.",
        targetTab: 6,
        actionTitle: "Open Preferences"
    ),
    
    FeatureGuide(
        id: .api_keys,
        title: "Cloud AI & API Providers",
        badge: "Cloud AI",
        systemIcon: "key.fill",
        summary: "Optionally connect cloud LLM providers (OpenRouter, OpenAI, Groq, Anthropic) for smart rewriting, notes synthesis, and multilingual translation.",
        sections: [
            HelpSection(title: "Local vs Cloud Intelligence", items: [
                HelpItem(
                    label: "100% Offline Capability",
                    description: "Dicty does not require an API key to work. Local Whisper models perform complete speech recognition entirely on your Mac."
                ),
                HelpItem(
                    label: "Managed Dicty Cloud",
                    description: "Zero setup required. Managed cloud routing tied to your Dicty account balance."
                ),
                HelpItem(
                    label: "Bring Your Own Key (OpenRouter)",
                    description: "Connect OpenRouter to unlock 100+ frontier models (Claude 3.7, GPT-4o, Gemini 2.0, DeepSeek) at upstream token cost."
                )
            ]),
            HelpSection(title: "Developer Integrations", items: [
                HelpItem(
                    label: "GitHub, GitLab & Bitbucket",
                    description: "Store repository access tokens so Librarian can automatically detect active Git branches and PR context."
                ),
                HelpItem(
                    label: "Confluence, Linear & Notion",
                    description: "Push architectural thoughts and synthesized meeting records directly to your team's knowledge hubs."
                )
            ])
        ],
        proTip: "All API tokens and credentials are encrypted securely on your Mac. Dicty never transmits API keys to third-party tracking servers.",
        targetTab: 11,
        actionTitle: "Manage API Keys"
    ),
    
    FeatureGuide(
        id: .transcribe,
        title: "Audio & Video File Transcription",
        badge: "Batch Processing",
        systemIcon: "waveform.and.mic",
        summary: "Transcribe pre-recorded voice memos, meetings, lectures, and video files directly on your Mac without playing them aloud.",
        sections: [
            HelpSection(title: "File Support & Features", items: [
                HelpItem(
                    label: "Supported Formats",
                    description: "Supports .mp3, .wav, .m4a, .aac, .flac, .ogg, .mp4, .mov, and .mkv files."
                ),
                HelpItem(
                    label: "Drag & Drop",
                    description: "Drop audio files directly onto the Transcribe window for instant background processing with speaker identification."
                ),
                HelpItem(
                    label: "Batch Processing",
                    description: "Queue multiple media files to transcribe concurrently using your Apple Silicon hardware."
                )
            ])
        ],
        proTip: "Use Turbo or Large-v3 models for recorded files to achieve the highest accuracy on meetings with multiple speakers and overlapping audio.",
        targetTab: 7,
        actionTitle: "Open File Transcriber"
    ),
    
    FeatureGuide(
        id: .projects,
        title: "Projects & Librarian Architecture",
        badge: "Knowledge Base",
        systemIcon: "folder",
        summary: "Synthesize spoken engineering thoughts into structured architectural documentation, PR summaries, and repository decision records.",
        sections: [
            HelpSection(title: "How Librarian Works", items: [
                HelpItem(
                    label: "Voice Thought Staging",
                    description: "Record spontaneous engineering thoughts while programming. Dicty groups thoughts by active Git branch and repository."
                ),
                HelpItem(
                    label: "Architecture Doc Synthesis",
                    description: "When ready, click 'Synthesize Architecture Doc' to turn staged thoughts into clean, structured Markdown specifications."
                ),
                HelpItem(
                    label: "Mermaid Architecture Diagrams",
                    description: "Generates interactive Mermaid diagrams that can be zoomed, panned, and exported directly in the Knowledge Base."
                )
            ])
        ],
        proTip: "The staged thoughts counter appears directly in your menu bar menu so you can keep track of staged thoughts without opening the main window.",
        targetTab: 8,
        actionTitle: "View Projects & Queue"
    ),
    
    FeatureGuide(
        id: .sync_backup,
        title: "Cloud Sync & Data Portability",
        badge: "Backup",
        systemIcon: "arrow.triangle.2.circlepath.circle",
        summary: "Synchronize your custom vocabulary, mode profiles, and preferences seamlessly across your Mac and Windows devices.",
        sections: [
            HelpSection(title: "Sync Features", items: [
                HelpItem(
                    label: "Automatic Cloud Sync",
                    description: "When signed into your Dicty account, custom vocabulary and mode profiles sync seamlessly between your machines."
                ),
                HelpItem(
                    label: "Local Offline Backups",
                    description: "Export all your settings, vocabulary terms, and custom modes as a JSON file anytime for manual backup."
                ),
                HelpItem(
                    label: "Non-Destructive Merging",
                    description: "If you add words while offline, Dicty intelligently merges them with your cloud vocabulary when you reconnect."
                )
            ])
        ],
        proTip: "Sign in with Google OAuth to enable seamless cross-device synchronization in seconds.",
        targetTab: 15,
        actionTitle: "Open Sync & Backup"
    )
]

// MARK: - Feature Help Button (Reusable Icon)
public struct FeatureHelpButton: View {
    public let topic: FeatureHelpTopic
    public let label: String?
    
    @State private var isHovering = false
    
    public init(topic: FeatureHelpTopic, label: String? = nil) {
        self.topic = topic
        self.label = label
    }
    
    public var body: some View {
        Button(action: {
            WindowManager.openHelpWindow(initialTopic: topic)
        }) {
            Group {
                if let label = label, !label.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isHovering ? .primary : .secondary)
                        
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isHovering ? .primary : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(isHovering ? 0.15 : 0.08), lineWidth: 1)
                    )
                } else {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(isHovering ? .primary : .secondary)
                        .padding(4)
                        .background(isHovering ? Color.primary.opacity(0.08) : Color.clear)
                        .clipShape(Circle())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovering = hover
        }
        .help("Open help guide for \(topic.rawValue)")
    }
}

// MARK: - Embedded Help View for Settings Tab
public struct FeatureHelpEmbeddedView: View {
    public init() {}
    
    public var body: some View {
        FeatureHelpView(isEmbedded: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Feature Help Modal View
public struct FeatureHelpView: View {
    public let initialTopic: FeatureHelpTopic
    public let isEmbedded: Bool
    
    @State private var selectedTopic: FeatureHelpTopic
    @State private var searchText: String = ""
    @Environment(\.dismiss) private var dismiss
    
    public init(initialTopic: FeatureHelpTopic = .models, isEmbedded: Bool = false) {
        self.initialTopic = initialTopic
        self.isEmbedded = isEmbedded
        _selectedTopic = State(initialValue: initialTopic)
    }
    
    private var filteredGuides: [FeatureGuide] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return FEATURE_GUIDES
        }
        let query = searchText.lowercased()
        return FEATURE_GUIDES.filter { guide in
            guide.title.lowercased().contains(query) ||
            guide.summary.lowercased().contains(query) ||
            guide.badge.lowercased().contains(query) ||
            guide.sections.contains { section in
                section.title.lowercased().contains(query) ||
                section.items.contains { item in
                    item.label.lowercased().contains(query) ||
                    item.description.lowercased().contains(query)
                }
            }
        }
    }
    
    private var activeGuide: FeatureGuide? {
        FEATURE_GUIDES.first { $0.id == selectedTopic } ?? filteredGuides.first
    }

    /// "What Dicty can do" — six short cards. Each has a one-line example and a
    /// button that opens the place where that feature is set up.
    private var whatDictyCanDo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What Dicty can do")
                .font(.system(size: 16, weight: .bold, design: .rounded))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                CapabilityCard(icon: "slider.horizontal.3", title: "Modes",
                               example: "Long ideas for notes, short lines for chat.") { openPage(1) }
                CapabilityCard(icon: "macwindow.on.rectangle", title: "Apps",
                               example: "Different style in Slack than in Mail.") { openPage(1) }
                CapabilityCard(icon: "wand.and.sparkles", title: "Fix corrections",
                               example: "Turns \"uhm\" and \"kube\" into clean words.") { openPage(1) }
                CapabilityCard(icon: "text.badge.plus", title: "Snippets",
                               example: "Type \"sig\" to insert your signature.") { openWords("snippets") }
                CapabilityCard(icon: "character.book.closed", title: "Vocabulary",
                               example: "Say \"kube\" and get \"Kubernetes\".") { openWords("vocabulary") }
                CapabilityCard(icon: "globe", title: "Translate",
                               example: "Speak English and get Spanish text.") { openPage(1) }
            }
        }
        .padding(.bottom, 4)
    }

    /// Jump to a top-level settings page, then close Help.
    private func openPage(_ tab: Int) {
        UserDefaults.standard.set(tab, forKey: "settingsTabSelection")
        if !isEmbedded { dismiss() }
    }

    /// Jump to the Words page and select one of its tabs.
    private func openWords(_ tab: String) {
        UserDefaults.standard.set(tab, forKey: "wordsTabSelection")
        UserDefaults.standard.set(22, forKey: "settingsTabSelection")
        if !isEmbedded { dismiss() }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.appAccent)
                    Text("Dicty Help & Feature Guides")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                if !isEmbedded {
                    Button(action: {
                        dismiss()
                        WindowManager.helpWindow?.close()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.dictySecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close help guide (Esc)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.03))
            
            Divider()
            
            // Split Master-Detail View
            HStack(spacing: 0) {
                // Left Topic Navigation Sidebar
                VStack(spacing: 10) {
                    // Search Field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.dictySecondary)
                            .font(.system(size: 12))
                        TextField("Search guides & tips...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
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
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    
                    // Guide List
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredGuides) { guide in
                                Button(action: {
                                    selectedTopic = guide.id
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: guide.systemIcon)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(selectedTopic == guide.id ? .sageGreen : .dictySecondary)
                                            .frame(width: 20)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(guide.title)
                                                .font(.system(size: 12, weight: selectedTopic == guide.id ? .semibold : .regular))
                                                .foregroundColor(selectedTopic == guide.id ? .primary : .primary.opacity(0.85))
                                                .lineLimit(1)
                                            
                                            Text(guide.badge)
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(selectedTopic == guide.id ? .sageGreen : .dictySecondary)
                                                .textCase(.uppercase)
                                        }
                                        
                                        Spacer()
                                        
                                        if selectedTopic == guide.id {
                                            Circle()
                                                .fill(Color.sageGreen)
                                                .frame(width: 5, height: 5)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedTopic == guide.id ?
                                            Color.sageGreen.opacity(0.12) :
                                            Color.clear
                                    )
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)
                    }
                }
                .frame(width: isEmbedded ? 210 : 230)
                .background(Color.primary.opacity(0.02))
                
                Divider()
                
                // Right Detail View
                if let guide = activeGuide {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            whatDictyCanDo
                            
                            // Topic Header & Badge
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text(guide.badge)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.sageGreen)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.sageGreen.opacity(0.15))
                                        .clipShape(Capsule())
                                    
                                    Spacer()
                                    
                                    if let targetTab = guide.targetTab, let actionTitle = guide.actionTitle {
                                        Button(action: {
                                            UserDefaults.standard.set(targetTab, forKey: "settingsTabSelection")
                                            dismiss()
                                        }) {
                                            HStack(spacing: 5) {
                                                Text(actionTitle)
                                                    .font(.system(size: 11, weight: .medium))
                                                Image(systemName: "arrow.forward")
                                                    .font(.system(size: 10))
                                            }
                                            .foregroundColor(.sageGreen)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.sageGreen.opacity(0.12))
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                
                                HStack(spacing: 10) {
                                    Image(systemName: guide.systemIcon)
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.sageGreen)
                                    
                                    Text(guide.title)
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                }
                                
                                Text(guide.summary)
                                    .font(.system(size: 13))
                                    .foregroundColor(.dictySecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(2)
                            }
                            .padding(.bottom, 4)
                            
                            // Sections
                            ForEach(guide.sections) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(section.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(section.items) { item in
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(item.label)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.primary)
                                                Text(item.description)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.dictySecondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                    .lineSpacing(1.5)
                                            }
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.primary.opacity(0.035))
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                            }
                            
                            // Pro Tip Card
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(.warmAmber)
                                        .font(.system(size: 13))
                                    Text("PRO TIP")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.warmAmber)
                                }
                                Text(guide.proTip)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.warmAmber.opacity(0.08))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.warmAmber.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .padding(20)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.dictySecondary)
                        Text("No matching help topics found")
                            .font(.headline)
                            .foregroundColor(.dictySecondary)
                        Button("Clear Search") {
                            searchText = ""
                        }
                        .buttonStyle(.flatSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: isEmbedded ? .infinity : 740, maxHeight: isEmbedded ? .infinity : 530)
        .background(
            Group {
                if !isEmbedded {
                    NSVisualEffectViewRepresentable(material: .popover, blendingMode: .behindWindow)
                        .ignoresSafeArea()
                }
            }
        )
    }
}

// Visual Effect View Representable for frosted glass
struct NSVisualEffectViewRepresentable: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

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

// MARK: - What Dicty can do

/// One card in the "What Dicty can do" strip: a feature, a one-line example,
/// and a button that opens the place where it is set up.
struct CapabilityCard: View {
    let icon: String
    let title: String
    let example: String
    let setup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appAccent)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }

            Text(example)
                .font(.system(size: 11))
                .foregroundColor(.dictySecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button("Set up") { setup() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.appAccent.opacity(0.12))
                    .cornerRadius(6)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}
