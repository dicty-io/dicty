import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import Combine

extension Color {
    static var stylishGreen: Color { appAccent }
    static var sageGreen: Color { appAccent }
    static let warmAmber = Color(NSColor(name: nil, dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 232/255.0, green: 146/255.0, blue: 78/255.0, alpha: 1.0)
        } else {
            return NSColor(red: 196/255.0, green: 104/255.0, blue: 38/255.0, alpha: 1.0)
        }
    }))
    static let mutedSlate = Color(NSColor(name: nil, dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 130/255.0, green: 160/255.0, blue: 185/255.0, alpha: 1.0)
        } else {
            return NSColor(red: 75/255.0, green: 105/255.0, blue: 130/255.0, alpha: 1.0)
        }
    }))
    static let pastelLavender = Color(NSColor(name: nil, dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 185/255.0, green: 165/255.0, blue: 220/255.0, alpha: 1.0)
        } else {
            return NSColor(red: 125/255.0, green: 100/255.0, blue: 175/255.0, alpha: 1.0)
        }
    }))
    static let pastelSand = Color(NSColor(name: nil, dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 235/255.0, green: 195/255.0, blue: 140/255.0, alpha: 1.0)
        } else {
            return NSColor(red: 180/255.0, green: 130/255.0, blue: 65/255.0, alpha: 1.0)
        }
    }))
}

@main
struct DictyClientApp: App {
    @StateObject private var engineClient = EngineClient.shared
    @ObservedObject private var profileManager = ProfileManager.shared
    @AppStorage("targetSystem") private var targetSystem: String = "obsidian"
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra {
            if engineClient.engineAuthFailed {
                Text("Engine connection lost — Restart engine")
                Divider()
            }

            Button(engineClient.isRecording ? "Stop Recording (⌘R)" : "Start Recording (⌘R)") {
                engineClient.toggleRecording()
            }
            
            if engineClient.isRecording {
                Button(engineClient.isPaused ? "Resume Recording (Space)" : "Pause Recording (Space)") {
                    engineClient.togglePauseRecording()
                }
                
                Button("Cancel Recording") {
                    engineClient.cancelRecording()
                }
            }
            
            Divider()
            
            Menu("Profile: \(profileManager.activeProfile?.name ?? "Default")") {
                ForEach(profileManager.profiles) { profile in
                    Button(action: {
                        profileManager.switchProfile(to: profile.id, engine: engineClient)
                    }) {
                        HStack {
                            if profile.id == profileManager.activeProfileId {
                                Image(systemName: "checkmark")
                            }
                            Text(profile.name)
                        }
                    }
                }
            }
            
            Menu("Active Mode") {
                Picker("Active Mode", selection: $engineClient.activeMode) {
                    Text("Librarian (Alpha)").tag("librarian")
                    Text("Dictation").tag("dictation")
                    Text("Meeting (Alpha)").tag("meeting")
                    Text("Focused Meeting (Alpha)").tag("focused_meeting")
                    Text("Formatting").tag("formatting")
                }
                .pickerStyle(.inline)
            }
            
            if engineClient.activeMode == "librarian" {
                Menu("Librarian Target") {
                    Picker("Librarian Target", selection: $targetSystem) {
                        Text("Confluence (Remote)").tag("confluence")
                        Text("Linear (Docs)").tag("linear")
                        Text("Notion (Cloud)").tag("notion")
                        Text("Local Files (Obsidian)").tag("obsidian")
                    }
                    .pickerStyle(.inline)
                }
                
                Button("Architecture Queue (\(engineClient.stagedThoughts.count) thoughts)...") {
                    UserDefaults.standard.set(17, forKey: "settingsTabSelection")
                    openSettingsWindow()
                }
                
                if !engineClient.stagedThoughts.isEmpty {
                    Button(engineClient.isSynthesizingDocs ? "Synthesizing Architecture..." : "Synthesize Architecture Doc") {
                        engineClient.synthesizeArchitectureDocs { _, _ in }
                    }
                    .disabled(engineClient.isSynthesizingDocs)
                }
            }
            
            if engineClient.activeMode == "dictation" {
                Menu("Dictation Style") {
                    Picker("Dictation Style", selection: $engineClient.dictationFormatStyle) {
                        Text("Auto (match active app)").tag("auto")
                        Text("Raw Transcript").tag("raw")
                        Text("Book / Book Prose").tag("book")
                        Text("Fast Punctuation (0ms)").tag("punctuation_fast")
                        Text("Email").tag("email")
                        Text("Message").tag("message")
                        Text("Structured Note").tag("note")
                        Text("Code / Commit").tag("code")
                        Text("Custom Prompt").tag("custom")
                    }

                    .pickerStyle(.inline)
                    
                    Divider()
                    
                    Button(engineClient.authorName.isEmpty ? "Sender Name (e.g. Bruce Wayne)..." : "Sender Name: \(engineClient.authorName)...") {
                        WindowManager.promptForAuthorName(engineClient: engineClient)
                    }
                }
            }
            
            Divider()
            
            Menu("Audio Input") {
                Button("Refresh Devices") {
                    engineClient.fetchDevices()
                }
                Divider()
                Picker("Audio Input", selection: $engineClient.activeDeviceID) {
                    Text("System Default (Dynamic)").tag(-1)
                    ForEach(engineClient.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .pickerStyle(.inline)
            }
            
            Divider()
            
            Toggle(isOn: $engineClient.isIncognitoMode) {
                HStack {
                    Image(systemName: engineClient.isIncognitoMode ? "eye.slash.fill" : "eye.slash")
                    Text("Incognito Mode")
                }
            }
            
            Divider()
            
            Button("Configuration Setup...") {
                openSettingsWindow()
            }
            
            Menu("Help & Guides") {
                Button("Feature Guides & Shortcuts...") {
                    WindowManager.openHelpWindow()
                }
                Button("Replay Welcome Tutorial...") {
                    WindowManager.openOnboardingWindow(engineClient: engineClient)
                }
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            getTrayIcon()
                .onChange(of: engineClient.activeMode) { _, newMode in
                    TelemetryClient.shared.track("mode_switched", properties: ["active_mode": newMode])
                }
                .onChange(of: engineClient.dictationFormatStyle) { _, newStyle in
                    TelemetryClient.shared.track("format_style_switched", properties: ["format_style": newStyle])
                }
        }
    }
    
    func getTrayIcon() -> Image {
        if let url = DictyResources.url(forResource: "dicty_tray_icon", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            nsImage.size = NSSize(width: 22, height: 22)
            nsImage.isTemplate = true
            return Image(nsImage: nsImage)
        }
        return Image(systemName: engineClient.isRecording ? "waveform.circle.fill" : "waveform.circle")
    }
    
    func openSettingsWindow() {
        WindowManager.openSettingsWindow(engineClient: engineClient)
    }
}

@MainActor
class WindowManager {
    static var settingsWindow: NSWindow?
    
    static func promptForAuthorName(engineClient: EngineClient) {
        let alert = NSAlert()
        alert.messageText = "Your Name for Email Dictations"
        alert.informativeText = "Dicty signs formatted emails with this name instead of writing [Your Name]."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.stringValue = engineClient.authorName
        textField.placeholderString = "e.g. Bruce Wayne"
        alert.accessoryView = textField
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let input = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            engineClient.updateAuthorName(input)
        }
    }
    
    static func openSettingsWindow(engineClient: EngineClient, tabIndex: Int? = nil) {
        if let tab = tabIndex {
            UserDefaults.standard.set(tab, forKey: "settingsTabSelection")
        }
        
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView()
            .environmentObject(engineClient)
            .environmentObject(UpdateChecker.shared)
        let hostingController = NSHostingController(rootView: settingsView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        
        containerView.addSubview(visualEffect)
        containerView.addSubview(hostingController.view)
        
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: containerView.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
        
        let savedW = UserDefaults.standard.double(forKey: "settingsWindowWidth")
        let savedH = UserDefaults.standard.double(forKey: "settingsWindowHeight")
        let initialWidth = savedW >= 760 ? savedW : 840
        let initialHeight = savedH >= 500 ? savedH : 560
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Dicty Configuration"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.minSize = NSSize(width: 760, height: 500)
        window.center()
        
        window.contentView = containerView
        
        let customToolbar = NSToolbar(identifier: "SettingsToolbar")
        customToolbar.showsBaselineSeparator = false
        window.toolbar = customToolbar
        window.titlebarAppearsTransparent = true
        
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
    
    static var onboardingWindow: NSWindow?
    
    static func openOnboardingWindow(engineClient: EngineClient) {
        if let window = onboardingWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let onboardingView = OnboardingView()
            .environmentObject(engineClient)
        let hostingController = NSHostingController(rootView: onboardingView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow // Darker, rich blur
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        
        containerView.addSubview(visualEffect)
        containerView.addSubview(hostingController.view)
        
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: containerView.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Welcome to Dicty"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.appearance = NSAppearance(named: .darkAqua) // Force beautiful dark mode
        window.center()
        
        window.contentView = containerView
        
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
    
    static var helpWindow: NSWindow?
    
    static func openHelpWindow(initialTopic: FeatureHelpTopic = .models) {
        let helpView = FeatureHelpView(initialTopic: initialTopic)
        let hostingController = NSHostingController(rootView: helpView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        
        if let window = helpWindow, window.isVisible {
            window.contentView = hostingController.view
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 530),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Dicty Help & Feature Guides"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.center()
        
        window.contentView = hostingController.view
        
        window.makeKeyAndOrderFront(nil)
        helpWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
    
    static var updateWindow: NSWindow?
    
    static func showUpdateNotification(engineClient: EngineClient) {
        if let window = updateWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        let notificationView = UpdateNotificationView(closeAction: {
            updateWindow?.close()
        })
        .environmentObject(engineClient)
        .environmentObject(UpdateChecker.shared)
        
        let hostingController = NSHostingController(rootView: notificationView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        
        containerView.addSubview(visualEffect)
        containerView.addSubview(hostingController.view)
        
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: containerView.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 185),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.center()
        
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        updateWindow = window
    }
    
    @MainActor
    static func runScreenshotCapture() async {
        let engine = EngineClient.shared
        engine.fetchModels()
        engine.fetchHistory()
        engine.fetchDevices()
        engine.fetchStats()
        
        print("Waiting for engine data...")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        let outDir = "/Users/vasiliikazmin/.gemini/antigravity-ide/brain/b94c08e7-e91e-4ea1-aa51-1c7f82ae4487"
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        
        struct CaptureJob {
            let name: String
            let tab: Int
            let wordsTab: String?
            let projTab: String?
            let histTab: Int?
            let editMode: Bool
        }
        
        let jobs: [CaptureJob] = [
            CaptureJob(name: "models", tab: 2, wordsTab: nil, projTab: nil, histTab: nil, editMode: false),
            CaptureJob(name: "mode_detail", tab: 1, wordsTab: nil, projTab: nil, histTab: nil, editMode: true),
            CaptureJob(name: "words_vocabulary", tab: 22, wordsTab: "vocabulary", projTab: nil, histTab: nil, editMode: false),
            CaptureJob(name: "words_snippets", tab: 22, wordsTab: "snippets", projTab: nil, histTab: nil, editMode: false),
            CaptureJob(name: "projects_repository", tab: 8, wordsTab: nil, projTab: "repository", histTab: nil, editMode: false),
            CaptureJob(name: "projects_queue", tab: 8, wordsTab: nil, projTab: "queue", histTab: nil, editMode: false),
            CaptureJob(name: "projects_advanced", tab: 8, wordsTab: nil, projTab: "advanced", histTab: nil, editMode: false),
            CaptureJob(name: "history", tab: 3, wordsTab: nil, projTab: nil, histTab: 0, editMode: false)
        ]
        
        for job in jobs {
            UserDefaults.standard.set(job.tab, forKey: "settingsTabSelection")
            if let wt = job.wordsTab { UserDefaults.standard.set(wt, forKey: "wordsTabSelection") }
            if let pt = job.projTab { UserDefaults.standard.set(pt, forKey: "projectsTabSelection") }
            if let ht = job.histTab { UserDefaults.standard.set(ht, forKey: "historyTabSelection") }
            UserDefaults.standard.set(job.editMode, forKey: "modesEditFirstOnLaunch")
            
            for (schemeName, colorScheme) in [("dark", ColorScheme.dark), ("light", ColorScheme.light)] {
                for (widthName, w, h) in [("min", 760.0, 520.0), ("normal", 960.0, 600.0)] {
                    let baseView = SettingsView()
                        .environmentObject(engine)
                        .environmentObject(UpdateChecker.shared)
                        .preferredColorScheme(colorScheme)
                        .background(colorScheme == .dark ? Color(NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)) : Color(NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)))
                        .frame(width: w, height: h)
                    
                    let hosting = NSHostingView(rootView: baseView)
                    hosting.frame = NSRect(x: 0, y: 0, width: w, height: h)
                    window.setContentSize(NSSize(width: w, height: h))
                    window.contentView = hosting
                    window.layoutIfNeeded()
                    
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    
                    if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                        hosting.cacheDisplay(in: hosting.bounds, to: rep)
                        if let pngData = rep.representation(using: .png, properties: [:]) {
                            let filename = "\(job.name)_\(widthName)_\(schemeName).png"
                            let path = "\(outDir)/\(filename)"
                            try? pngData.write(to: URL(fileURLWithPath: path))
                            print("RENDERED_IMAGE: \(filename)")
                        }
                    }
                }
            }
        }
        print("ALL_SCREENSHOTS_RENDERED_SUCCESS")
        exit(0)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var appearanceObservation: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor in
                WindowManager.openSettingsWindow(engineClient: EngineClient.shared)
            }
        }
        return true
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
    
    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        
        if url.scheme == "dicty" && url.host == "auth" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let tokenItem = components.queryItems?.first(where: { $0.name == "token" }),
                   let token = tokenItem.value {
                    Task { @MainActor in
                        EngineClient.shared.handleOAuthToken(token)
                    }
                } else if let refreshItem = components.queryItems?.first(where: { $0.name == "refresh" }),
                          refreshItem.value == "true" {
                    Task { @MainActor in
                        EngineClient.shared.fetchAuthStatus(force: true)
                    }
                }
            }
        } else if url.scheme == "dicty" && url.host == "window" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                let width = Double(components.queryItems?.first(where: { $0.name == "width" })?.value ?? "") ?? 840
                let height = Double(components.queryItems?.first(where: { $0.name == "height" })?.value ?? "") ?? 560
                Task { @MainActor in
                    WindowManager.settingsWindow?.setContentSize(NSSize(width: width, height: height))
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Without this the engine (and its ~300 MB whisper-server) kept running after quitting Dicty.
        MainActor.assumeIsolated {
            DictyEngineManager.shared.stopEngine()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--capture-screenshots") {
            Task { @MainActor in
                await WindowManager.runScreenshotCapture()
            }
            return
        }
        DictyEngineManager.shared.ensureEngineRunning()
        AppDelegate.applyActivationPolicy()
        AppDelegate.applyTheme()
        _ = MediaPlaybackManager.shared
        TelemetryClient.shared.syncWithEngine()
        
        // DEV: Force reset onboarding state (Disabled to allow flow progression)
        // UserDefaults.standard.removeObject(forKey: "hasSeenOnboarding")
        
        let shouldShowOnboarding = AppDelegate.shouldPresentOnboarding()
        let isTrusted = AXIsProcessTrusted()
        let micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        TelemetryClient.shared.track("app_launched", properties: [
            "has_seen_onboarding": !shouldShowOnboarding,
            "accessibility_granted": isTrusted,
            "microphone_granted": micAuthorized
        ])
        
        if shouldShowOnboarding {
            Task { @MainActor in
                WindowManager.openOnboardingWindow(engineClient: EngineClient.shared)
            }
            #if !DEBUG
            UpdateChecker.shared.checkForUpdates(manual: false)
            UpdateChecker.shared.$updateAvailable
                .dropFirst()
                .receive(on: RunLoop.main)
                .sink { isAvailable in
                    if isAvailable {
                        WindowManager.showUpdateNotification(engineClient: EngineClient.shared)
                    }
                }
                .store(in: &cancellables)
            #endif
        }
        
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { app, _ in
            Task { @MainActor in
                AppDelegate.updateAppIcon()
            }
        }
        
        Task { @MainActor in
            OverlayWindowManager.shared.show(engineClient: EngineClient.shared)
        }
    }
    
    @MainActor
    static func shouldPresentOnboarding() -> Bool {
        let defaults = UserDefaults.standard
        let hasSeen = defaults.bool(forKey: "hasSeenOnboarding")
        // Once the user has completed onboarding, updates must never re-trigger onboarding or permissions flow
        return !hasSeen
    }

    @MainActor
    static func applyActivationPolicy() {
        UserDefaults.standard.register(defaults: ["showInDock": true])
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }
    
    @MainActor
    static func updateAppIcon() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let iconName = isDark ? "Icon-macOS-Dark-1024" : "Icon-macOS-Default-1024"
        
        if let imagePath = DictyResources.path(forResource: iconName, ofType: "png") {
            NSApp.applicationIconImage = NSImage(contentsOfFile: imagePath)
        } else if let image = NSImage(named: NSImage.Name(iconName)) {
            NSApp.applicationIconImage = image
        } else {
            print("Failed to find \(iconName).png in DictyResources")
        }
    }
    
    @MainActor
    static func applyTheme() {
        UserDefaults.standard.register(defaults: ["appTheme": "Dark", "showInDock": true, "appAccentColor": "olive"])
        let theme = UserDefaults.standard.string(forKey: "appTheme") ?? "Dark"
        if theme == "Light" {
            NSApp.appearance = NSAppearance(named: .aqua)
        } else if theme == "Dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else {
            NSApp.appearance = nil
        }
        updateAppIcon()
    }
}
