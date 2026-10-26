import SwiftUI
import AppKit
import AVFoundation
import Combine

extension Color {
    static var dictyMain: Color { Color.appAccent }
    static let dictyBlue = Color(red: 74/255.0, green: 101/255.0, blue: 114/255.0) // #4A6572
}

struct OnboardingView: View {
    @EnvironmentObject var engineClient: EngineClient
    @State private var currentStep = 0
    @State private var animateGradient = false
    private let totalSteps = 7
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Progress Bar & Dismiss
            HStack(spacing: 16) {
                ProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                
                Button(action: {
                    WindowManager.onboardingWindow?.close()
                    WindowManager.onboardingWindow = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
            .padding(.top, 24)
            .padding(.horizontal, 32)
            
            // Content
            ZStack {
                switch currentStep {
                case 0:
                    PermissionsView(currentStep: $currentStep)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                case 1:
                    MicTestView(currentStep: $currentStep)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                case 2:
                    ModelSelectionView(currentStep: $currentStep)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                case 3:
                    TypingAppsView(currentStep: $currentStep)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                case 4:
                    AILocationStepView(currentStep: $currentStep)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                case 5:
                    ShortcutTestView(currentStep: $currentStep)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                case 6:
                    UsageStatsConsentView()
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                default:
                    EmptyView()
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
            .padding(.horizontal, 40)
            .padding(.top, 20)
        }
        .frame(width: 720, height: 560)
        .background(
            ZStack {
                // Base clear color to let the window's native NSVisualEffectView shine through
                Color.clear
                
                // Animated glowing ambient light blob 1
                Circle()
                    .fill(Color.dictyBlue.opacity(0.3))
                    .frame(width: 350, height: 350)
                    .blur(radius: 90)
                    .offset(x: animateGradient ? -150 : 150, y: animateGradient ? -100 : 150)
                
                // Animated glowing ambient light blob 2
                Circle()
                    .fill(Color.dictyMain.opacity(0.3))
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: animateGradient ? 150 : -150, y: animateGradient ? 150 : -100)
                
                // Dark overlay to ensure text is always readable
                Color.black.opacity(0.4)
            }
            .animation(.easeInOut(duration: 10.0).repeatForever(autoreverses: true), value: animateGradient)
            .onAppear {
                animateGradient.toggle()
                ensureStarterModelReady()
            }
            .onChange(of: engineClient.models) { _ in
                ensureStarterModelReady()
            }
        )
        .preferredColorScheme(.dark)
    }
    
    static func detectSystemLanguage() -> String {
        let code: String
        if #available(macOS 13, *) {
            code = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        } else {
            code = Locale.current.languageCode?.lowercased() ?? "en"
        }
        if ModelsLibraryView.whisperLanguages.contains(where: { $0.code == code }) {
            return code
        }
        return "en"
    }
    
    private func ensureStarterModelReady() {
        let currentLang = engineClient.transcriptionLanguage
        let targetLang: String
        if currentLang.isEmpty || currentLang == "auto" {
            targetLang = Self.detectSystemLanguage()
            engineClient.transcriptionLanguage = targetLang
            UserDefaults.standard.set(targetLang, forKey: "transcriptionLanguage")
        } else {
            targetLang = currentLang
        }
        
        let starterModel = (targetLang == "en") ? "tiny" : "base"
        
        if engineClient.activeModel.isEmpty || engineClient.activeModel.contains("mlx-community") || engineClient.activeModel == "distil-large-v3" {
            engineClient.setActiveModel(id: starterModel)
        }
        let isDownloaded = engineClient.models.first(where: { $0.id == starterModel })?.is_downloaded == true
        let isDownloading = engineClient.isDownloading && engineClient.downloadProgress[starterModel] != nil
        if !isDownloaded && !isDownloading && !engineClient.models.isEmpty {
            engineClient.downloadModel(id: starterModel)
        }
    }
}

// MARK: - Progress Bar
struct ProgressBar: View {
    var currentStep: Int
    var totalSteps: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Rectangle()
                    .fill(index <= currentStep ? Color.white : Color.gray.opacity(0.3))
                    .frame(height: 4)
                    .cornerRadius(2)
                    .animation(.easeInOut, value: currentStep)
            }
        }
    }
}

// MARK: - Step 1: Permissions
struct PermissionsView: View {
    @Binding var currentStep: Int
    
    @State private var micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axAuthorized = AXIsProcessTrusted()
    @State private var screenAuthorized = CGPreflightScreenCaptureAccess()
    
    // Timer to poll for accessibility and screen recording changes since there is no callback
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Let's set up permissions")
                .font(.system(size: 28, weight: .bold))
                .padding(.bottom, 6)
            
            // Mic Permission Row
            PermissionRow(
                icon: "mic.fill",
                title: "Allow Microphone Access",
                description: "Required to capture audio for transcription. Only used when dictation is active.",
                isGranted: micAuthorized
            ) {
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                if status == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async {
                            self.micAuthorized = granted
                        }
                    }
                } else if status == .denied || status == .restricted {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            
            Divider().background(Color.gray.opacity(0.3))
            
            // AX Permission Row
            PermissionRow(
                icon: "person.crop.circle.badge.exclamationmark",
                title: "Allow Accessibility Access",
                description: "Required to paste text into apps & interact with your system. Only used when needed.",
                isGranted: axAuthorized
            ) {
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            
            if !axAuthorized {
                Button(action: {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                    process.arguments = ["reset", "Accessibility", "com.antigravity.Dicty"]
                    try? process.run()
                    process.waitUntilExit()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Stale Rule (Fix After App Update)")
                    }
                    .font(.caption)
                    .foregroundColor(.dictyBlue)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 46)
            }
            
            Divider().background(Color.gray.opacity(0.3))
            
            // Screen & Audio Permission Row (For Meeting Modes)
            PermissionRow(
                icon: "waveform.and.mic",
                title: "Screen & System Audio (For Meetings)",
                description: "Required for Meeting Assistant to record audio from Zoom, Meet, Teams, or browsers.",
                isGranted: screenAuthorized
            ) {
                _ = CGRequestScreenCaptureAccess()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            Spacer()
            
            Button(action: {
                currentStep += 1
            }) {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.dictyBlue)
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, 30)
        }
        .onReceive(timer) { _ in
            axAuthorized = AXIsProcessTrusted()
            micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            screenAuthorized = CGPreflightScreenCaptureAccess()
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if isGranted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Allowed")
                    }
                    .foregroundColor(.white)
                    .font(.subheadline.weight(.semibold))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isGranted)
    }
}

// MARK: - Step 2: Mic Test
struct MicTestView: View {
    @EnvironmentObject var engineClient: EngineClient
    @Binding var currentStep: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Let's test your microphone")
                .font(.system(size: 28, weight: .bold))
            
            Text("Speak and see if the waves react.\nNo response? Try changing your input device below.")
                .foregroundColor(.gray)
            
            Menu {
                Picker("Audio Input", selection: $engineClient.activeDeviceID) {
                    Text("System Default").tag(-1)
                    ForEach(engineClient.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
            } label: {
                HStack {
                    Text(engineClient.activeDeviceID == -1 ? "System default" : (engineClient.devices.first(where: { $0.id == engineClient.activeDeviceID })?.name ?? "System default"))
                        .foregroundColor(.white)
                    Image(systemName: "macbook.and.iphone")
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Live Visualizer
            MicVisualizerView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            
            Spacer()
            
            Button(action: {
                currentStep += 1
            }) {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.dictyBlue)
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, 30)
        }
    }
}

// MARK: - Step 3: Model Selection
struct ModelSelectionView: View {
    @EnvironmentObject var engineClient: EngineClient
    @Binding var currentStep: Int
    @State private var selectedLanguage: String = "en"
    @State private var userSelection: String = "tiny"
    @State private var showLoginSheet: Bool = false
    
    struct LanguageOption: Identifiable {
        let id: String
        let name: String
        let flag: String
    }
    
    static let popularLanguages: [LanguageOption] = [
        LanguageOption(id: "en", name: "English", flag: "🇺🇸"),
        LanguageOption(id: "ru", name: "Русский", flag: "🇷🇺"),
        LanguageOption(id: "de", name: "Deutsch", flag: "🇩🇪"),
        LanguageOption(id: "es", name: "Español", flag: "🇪🇸"),
        LanguageOption(id: "fr", name: "Français", flag: "🇫🇷"),
        LanguageOption(id: "zh", name: "中文", flag: "🇨🇳"),
        LanguageOption(id: "ja", name: "日本語", flag: "🇯🇵"),
        LanguageOption(id: "auto", name: "Auto Detect", flag: "🌐")
    ]
    
    private var currentLanguageName: String {
        ModelsLibraryView.whisperLanguages.first(where: { $0.code == selectedLanguage })?.name ?? selectedLanguage.uppercased()
    }
    
    private var targetLocalModel: String {
        (selectedLanguage == "en" || selectedLanguage == "auto") ? "tiny" : "base"
    }
    
    private var isTargetModelDownloaded: Bool {
        engineClient.models.first(where: { $0.id == targetLocalModel })?.is_downloaded == true
    }
    
    private var isSelectionReady: Bool {
        if userSelection == "openai/whisper-1" {
            return engineClient.isLoggedIn
        }
        return isTargetModelDownloaded || engineClient.isModelReady()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Language & AI Engine")
                .font(.system(size: 26, weight: .bold))
            
            Text("Select your primary spoken language and how Dicty processes speech.")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            // Language Selection Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("1. Primary Spoken Language")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    if selectedLanguage != "en" && selectedLanguage != "auto" {
                        Label("Multilingual model enabled", systemImage: "lightbulb")
                            .font(.caption2)
                            .foregroundColor(.appAccent)
                    }
                }
                
                // Popular language pills + "More" picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.popularLanguages) { lang in
                            Button(action: {
                                selectLanguage(lang.id)
                            }) {
                                HStack(spacing: 5) {
                                    Text(lang.flag)
                                    Text(lang.name)
                                        .font(.system(size: 12, weight: selectedLanguage == lang.id ? .semibold : .regular))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedLanguage == lang.id ? Color.dictyBlue : Color.white.opacity(0.08))
                                .foregroundColor(selectedLanguage == lang.id ? .white : .white.opacity(0.8))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedLanguage == lang.id ? Color.white.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Dropdown for full 90+ Whisper languages
                        Menu {
                            ForEach(ModelsLibraryView.whisperLanguages, id: \.code) { lang in
                                Button(action: {
                                    selectLanguage(lang.code)
                                }) {
                                    HStack {
                                        Text(lang.name)
                                        if selectedLanguage == lang.code {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "ellipsis.circle")
                                Text("Other")
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.white.opacity(0.8))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.vertical, 4)
            
            // Mode Cards Section
            VStack(alignment: .leading, spacing: 8) {
                Text("2. Processing Mode")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                HStack(spacing: 16) {
                    // On-Device Card
                    Button(action: {
                        userSelection = targetLocalModel
                        engineClient.setActiveModel(id: targetLocalModel)
                        ensureModelDownloaded(id: targetLocalModel)
                    }) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "cpu")
                                    .font(.system(size: 24))
                                    .foregroundColor(userSelection != "openai/whisper-1" ? .white : .gray)
                                Spacer()
                                if userSelection != "openai/whisper-1" {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color.sageGreen)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("On-Device AI")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("100% private & offline. Runs on your Mac.")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                            }
                            
                            Spacer()
                            
                            // Badge showing model & readiness
                            HStack(spacing: 6) {
                                let modelName = (targetLocalModel == "tiny") ? "Nano (75 MB)" : "Base (140 MB)"
                                if isTargetModelDownloaded {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.bold())
                                        .foregroundColor(.sageGreen)
                                    Text("\(modelName) • Ready")
                                        .font(.caption2.weight(.medium))
                                        .foregroundColor(.white.opacity(0.9))
                                } else if engineClient.isDownloading && engineClient.downloadProgress[targetLocalModel] != nil {
                                    let prog = engineClient.downloadProgress[targetLocalModel] ?? 0.0
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 14, height: 14)
                                    Text("Downloading \(Int(prog))%")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.9))
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.caption2)
                                        .foregroundColor(.dictyBlue)
                                    Text("\(modelName) • Auto-download")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(6)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: 150)
                        .background(userSelection != "openai/whisper-1" ? Color.dictyBlue.opacity(0.4) : Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(userSelection != "openai/whisper-1" ? Color.dictyBlue : Color.white.opacity(0.1), lineWidth: 2)
                        )
                        .cornerRadius(14)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Dicty Cloud Card
                    Button(action: {
                        userSelection = "openai/whisper-1"
                        engineClient.setActiveModel(id: "openai/whisper-1")
                    }) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "cloud")
                                    .font(.system(size: 24))
                                    .foregroundColor(userSelection == "openai/whisper-1" ? .white : .gray)
                                Spacer()
                                if userSelection == "openai/whisper-1" {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color.sageGreen)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dicty Cloud AI")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Whisper Large-v3. Highest accuracy across all languages.")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                            }
                            
                            Spacer()
                            
                            // Cloud Account Status & Action
                            if engineClient.isLoggedIn {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2)
                                        .foregroundColor(.sageGreen)
                                    Text("Cloud Active (\(engineClient.userEmail ?? "User"))")
                                        .font(.caption2.bold())
                                        .foregroundColor(.white.opacity(0.9))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(6)
                            } else {
                                Button(action: {
                                    showLoginSheet = true
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.crop.circle.badge.plus")
                                            .font(.caption2)
                                        Text("Sign In to Cloud")
                                            .font(.caption2.weight(.semibold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.sageGreen.opacity(0.25))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.sageGreen.opacity(0.5), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: 150)
                        .background(userSelection == "openai/whisper-1" ? Color.dictyBlue.opacity(0.4) : Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(userSelection == "openai/whisper-1" ? Color.dictyBlue : Color.white.opacity(0.1), lineWidth: 2)
                        )
                        .cornerRadius(14)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Spacer()
            
            // Bottom Action Button
            Button(action: {
                if userSelection == "openai/whisper-1" && !engineClient.isLoggedIn {
                    showLoginSheet = true
                } else {
                    engineClient.setActiveModel(id: userSelection)
                    currentStep += 1
                }
            }) {
                if userSelection != "openai/whisper-1" && !isSelectionReady {
                    let progress = engineClient.downloadProgress[targetLocalModel] ?? 0.0
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text(progress > 0 ? "Downloading model... \(Int(progress))%" : "Preparing model download...")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.dictyBlue.opacity(0.5))
                    .cornerRadius(12)
                } else if userSelection == "openai/whisper-1" && !engineClient.isLoggedIn {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text("Sign In to Activate Dicty Cloud")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.sageGreen)
                    .cornerRadius(12)
                } else {
                    Text("Continue")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.dictyBlue)
                        .cornerRadius(12)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(userSelection != "openai/whisper-1" && !isSelectionReady)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView(
                isLoggedIn: $engineClient.isLoggedIn,
                userEmail: $engineClient.userEmail,
                isPro: $engineClient.isPro
            )
        }
        .onAppear {
            initializeSelection()
        }
        .onChange(of: engineClient.isLoggedIn) { loggedIn in
            if loggedIn {
                userSelection = "openai/whisper-1"
                engineClient.setActiveModel(id: "openai/whisper-1")
            }
        }
    }
    
    private func initializeSelection() {
        let curLang = engineClient.transcriptionLanguage
        if curLang.isEmpty || curLang == "auto" {
            selectedLanguage = OnboardingView.detectSystemLanguage()
            engineClient.transcriptionLanguage = selectedLanguage
            UserDefaults.standard.set(selectedLanguage, forKey: "transcriptionLanguage")
        } else {
            selectedLanguage = curLang
        }
        
        if engineClient.activeModel == "openai/whisper-1" && engineClient.isLoggedIn {
            userSelection = "openai/whisper-1"
        } else {
            userSelection = targetLocalModel
            engineClient.setActiveModel(id: targetLocalModel)
            ensureModelDownloaded(id: targetLocalModel)
        }
    }
    
    private func selectLanguage(_ code: String) {
        selectedLanguage = code
        engineClient.transcriptionLanguage = code
        UserDefaults.standard.set(code, forKey: "transcriptionLanguage")
        ProfileManager.shared.updateActiveProfileModels(language: code)
        
        let newLocal = (code == "en" || code == "auto") ? "tiny" : "base"
        if userSelection != "openai/whisper-1" {
            userSelection = newLocal
            engineClient.setActiveModel(id: newLocal)
        }
        ensureModelDownloaded(id: newLocal)
    }
    
    private func ensureModelDownloaded(id: String) {
        let isDownloaded = engineClient.models.first(where: { $0.id == id })?.is_downloaded == true
        let isDownloading = engineClient.isDownloading && engineClient.downloadProgress[id] != nil
        if !isDownloaded && !isDownloading && !engineClient.models.isEmpty {
            engineClient.downloadModel(id: id)
        }
    }
}

// MARK: - Step 4: Shortcut Test
struct ShortcutTestView: View {
    @EnvironmentObject var engineClient: EngineClient
    @Binding var currentStep: Int
    @State private var textBuffer: String = ""
    
    private var samplePromptText: String {
        let lang = engineClient.transcriptionLanguage
        switch lang {
        case "ru": return "Привет! Это моя первая запись в Dicty"
        case "de": return "Hallo! Das ist meine erste Aufnahme mit Dicty"
        case "es": return "¡Hola! Esta es mi primera grabación con Dicty"
        case "fr": return "Bonjour ! Ceci est mon premier enregistrement avec Dicty"
        case "it": return "Ciao! Questa è la mia prima registrazione con Dicty"
        case "zh": return "你好！这是我在 Dicty 的第一次录音"
        case "ja": return "こんにちは！Dictyでの最初の録音です"
        case "uk": return "Привіт! Це мій перший запис у Dicty"
        case "pl": return "Cześć! To moje pierwsze nagranie w Dicty"
        default: return "This is my first recording with Dicty"
        }
    }
    
    private var languageBadgeText: String {
        let lang = engineClient.transcriptionLanguage
        let name = ModelsLibraryView.whisperLanguages.first(where: { $0.code == lang })?.name ?? lang.uppercased()
        let flag: String = {
            switch lang {
            case "ru": return "🇷🇺"
            case "de": return "🇩🇪"
            case "es": return "🇪🇸"
            case "fr": return "🇫🇷"
            case "zh": return "🇨🇳"
            case "ja": return "🇯🇵"
            case "en": return "🇺🇸"
            case "uk": return "🇺🇦"
            case "pl": return "🇵🇱"
            default: return "🌐"
            }
        }()
        return "\(flag) \(name)"
    }
    
    private var modelBadgeText: String {
        if engineClient.activeModel == "openai/whisper-1" {
            return "Cloud AI (Whisper Large)"
        } else if engineClient.activeModel == "tiny" {
            return "On-Device (Nano)"
        } else if engineClient.activeModel == "base" {
            return "On-Device (Base Multilingual)"
        } else {
            return "On-Device (\(engineClient.activeModel))"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Try it: dictate one sentence")
                    .font(.system(size: 26, weight: .bold))
                Spacer()
                // Active Setup Badge
                HStack(spacing: 6) {
                    Text(languageBadgeText)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    
                    HStack(spacing: 3) {
                        Image(systemName: engineClient.activeModel == "openai/whisper-1" ? "cloud.fill" : "cpu.fill")
                            .font(.system(size: 9))
                        Text(modelBadgeText)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .foregroundColor(.white.opacity(0.85))
            }
            
            HStack {
                Text(engineClient.hotkeyBehavior == "hold" ? "Press and hold" : "Press")
                    .foregroundColor(.gray)
                
                Button(action: {
                    engineClient.toggleRecording()
                }) {
                    Text(engineClient.recordShortcutDisplay.isEmpty ? "⌥ Space" : engineClient.recordShortcutDisplay)
                        .font(.system(.subheadline, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(engineClient.isRecording ? Color.red : Color.white.opacity(0.2))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .animation(.easeInOut, value: engineClient.isRecording)
                }
                .buttonStyle(PlainButtonStyle())
                
                Text(engineClient.hotkeyBehavior == "hold" ? "to speak, release when done" : "or click it to test")
                    .foregroundColor(.gray)
            }
            
            HStack(alignment: .top, spacing: 12) {
                // What you said
                VStack(alignment: .leading, spacing: 6) {
                    Text("You said")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            .background(Color.white.opacity(0.04).cornerRadius(12))
                        Text(samplePromptText)
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(16)
                    }
                }

                // What Dicty wrote
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dicty wrote")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            .background(Color.white.opacity(0.05).cornerRadius(12))

                        if engineClient.isRecording {
                            HStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                Text("Listening... (Speak now)")
                                    .foregroundColor(.white)
                            }
                            .padding(20)
                        } else if engineClient.isProcessing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Transcribing audio...")
                                    .foregroundColor(.white)
                            }
                            .padding(20)
                        } else if textBuffer.isEmpty {
                            Text("Your words will appear here.")
                                .foregroundColor(.gray)
                                .padding(20)
                        }

                        TextEditor(text: $textBuffer)
                            .font(.system(size: 16))
                            .padding(16)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                    }
                }
            }
            .frame(height: 180)
            .onChange(of: engineClient.isProcessing) { isProcessing in
                if !isProcessing && !engineClient.isRecording {
                    // When processing finishes, Dicty puts the result on the clipboard.
                    // Instead of relying on Cmd+V (which requires strict focus), we just read it directly!
                    if let text = NSPasteboard.general.string(forType: .string) {
                        if !text.isEmpty {
                            textBuffer = text
                        }
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                currentStep += 1
            }) {
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
        .onAppear {
            if engineClient.activeModel.isEmpty || engineClient.activeModel.contains("mlx-community") {
                let fallbackModel = (engineClient.transcriptionLanguage == "en" || engineClient.transcriptionLanguage == "auto") ? "tiny" : "base"
                engineClient.setActiveModel(id: fallbackModel)
            }
            _ = engineClient.isModelReady()
        }
    }
}

@MainActor
class MicVisualizerManager: ObservableObject {
    @Published var levels: [CGFloat] = Array(repeating: 10, count: 40)
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?

    func start() {
        let url = URL(fileURLWithPath: "/dev/null")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateLevels()
                }
            }
        } catch {
            print("Failed to start audio recorder for visualizer")
        }
    }
    
    func stop() {
        timer?.invalidate()
        audioRecorder?.stop()
    }
    
    private func updateLevels() {
        guard let recorder = audioRecorder else { return }
        recorder.updateMeters()
        
        let power = recorder.averagePower(forChannel: 0)
        let normalized = max(0, power + 60) / 60.0 // map -60..0 to 0..1
        let targetHeight = CGFloat(normalized) * 40.0 + 10.0 // map to 10..50 points
        
        self.levels.removeFirst()
        self.levels.append(targetHeight)
    }
}

struct MicVisualizerView: View {
    @StateObject private var manager = MicVisualizerManager()
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<manager.levels.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 4, height: manager.levels[index])
                    .animation(.linear(duration: 0.05), value: manager.levels[index])
            }
        }
        .onAppear {
            manager.start()
        }
        .onDisappear {
            manager.stop()
        }
    }
}


// MARK: - Onboarding completion
@MainActor
enum OnboardingCompletion {
    static func finish(engineClient: EngineClient) {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        let bundlePath = Bundle.main.bundlePath
        if let attributes = try? FileManager.default.attributesOfItem(atPath: bundlePath),
           let creationDate = attributes[.creationDate] as? Date {
            UserDefaults.standard.set(creationDate.timeIntervalSince1970, forKey: "lastInstalledBundleCreationDate")
        }
        
        // Persist language and model across profiles
        UserDefaults.standard.set(engineClient.transcriptionLanguage, forKey: "transcriptionLanguage")
        ProfileManager.shared.setGlobalLanguageAndModel(
            language: engineClient.transcriptionLanguage,
            whisperModel: engineClient.activeModel
        )
        
        WindowManager.onboardingWindow?.close()
        WindowManager.onboardingWindow = nil
        
        // Open Settings so they can finish configuring
        WindowManager.openSettingsWindow(engineClient: engineClient)
    }
}

// MARK: - Step 5: Anonymous usage statistics consent
/// Explicit opt-in: nothing is pre-selected, both choices are equally prominent and both complete onboarding.
/// The choice can be changed anytime in Settings → Diagnostics.
struct UsageStatsConsentView: View {
    @EnvironmentObject var engineClient: EngineClient
    @State private var isSaving = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Help improve Dicty?")
                .font(.system(size: 28, weight: .bold))
            
            Text("You can share anonymous usage statistics to help us find bugs and make dictation faster. It's completely optional, and Dicty works exactly the same either way.")
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(alignment: .leading, spacing: 12) {
                consentRow(icon: "checkmark.circle.fill", color: .appAccent,
                           text: "What's shared: feature usage, errors, and performance (e.g. transcription speed, model used), tied to a random install ID.")
                consentRow(icon: "xmark.circle.fill", color: .red,
                           text: "Never shared: your audio, transcripts, email or account, or which apps you dictate into.")
                consentRow(icon: "gearshape.fill", color: .gray,
                           text: "You can change this anytime in Settings → Diagnostics.")
            }
            .padding(16)
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)
            
            Spacer()
            
            HStack(spacing: 12) {
                choiceButton(title: "Don't share", share: false)
                choiceButton(title: "Share anonymous stats", share: true)
            }
            .padding(.bottom, 24)
        }
    }
    
    private func consentRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(color)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func choiceButton(title: String, share: Bool) -> some View {
        // Both buttons share identical styling so neither choice is nudged.
        Button(action: {
            guard !isSaving else { return }
            isSaving = true
            Task {
                await DiagnosticsExportView.setShareAnonymousUsage(share)
                await MainActor.run { OnboardingCompletion.finish(engineClient: engineClient) }
            }
        }) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.12))
                .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isSaving)
    }
}
