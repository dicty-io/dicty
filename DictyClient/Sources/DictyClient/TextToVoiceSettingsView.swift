import SwiftUI
import AppKit

struct TextToVoiceSettingsView: View {
    @EnvironmentObject var engineClient: EngineClient
    @ObservedObject var tts = TTSManager.shared
    @State private var sampleText: String = "Dicty transforms written text into clear speech. Adjust the cadence, pause timing, and voice personality to hear the difference immediately."
    
    // Supported Silero language tabs
    private let sileroLanguages: [(key: String, label: String, flag: String)] = [
        ("all", "All", "all"),
        ("de", "German", "de"),
        ("ru", "Russian", "ru"),
        ("es", "Spanish", "es"),
        ("uk", "Ukrainian", "ua")
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                SettingsPageHeader(
                    title: "Text to Voice",
                    description: "Highlight text anywhere on your Mac and press \(engineClient.ttsShortcutDisplay) to hear it read aloud with human-like cadence and customizable neural persona.",
                    helpTopic: .models
                )
                
                Divider()
                
                // MARK: - 1. Engine Switcher (Kokoro vs Silero)
                engineSwitcherCard
                
                // MARK: - 2. Contextual Audition Box
                auditionBox
                
                // MARK: - 3. Engine-Specific Configuration
                if tts.activeEngine == "kokoro" {
                    kokoroSection
                } else {
                    sileroSection
                }
                
                // MARK: - 4. Shared Pacing & Storage Settings
                sharedSettingsSection
                
                // MARK: - 5. Global Shortcut Tip
                shortcutTip
            }
            .padding(24)
        }
        .onAppear {
            tts.checkStatus()
            updateSampleTextForActiveVoice()
        }
    }
    
    // MARK: - Engine Switcher Card
    private var engineSwitcherCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEURAL SYNTHESIS ENGINE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                // Kokoro Engine Button
                Button(action: {
                    tts.activeEngine = "kokoro"
                    tts.selectedLanguage = "all"
                    updateSampleTextForActiveVoice()
                }) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(tts.activeEngine == "kokoro" ? .sageGreen : .secondary)
                            Text("Kokoro Neural")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(tts.activeEngine == "kokoro" ? .primary : .secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                CountryFlagView("us", width: 16, height: 12, cornerRadius: 2.5)
                                CountryFlagView("gb", width: 16, height: 12, cornerRadius: 2.5)
                            }
                            if tts.activeEngine == "kokoro" {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.sageGreen)
                            }
                        }
                        Text("StyleTTS2 architecture • 256-D style interpolation for 2-voice hybrid blends • English focus")
                            .font(.caption2)
                            .foregroundColor(.dictySecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(14)
                    .background(tts.activeEngine == "kokoro" ? Color.sageGreen.opacity(0.12) : Color.primary.opacity(0.02))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tts.activeEngine == "kokoro" ? Color.sageGreen.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                
                // Silero Engine Button
                Button(action: {
                    tts.activeEngine = "silero"
                    tts.selectedLanguage = "all"
                    updateSampleTextForActiveVoice()
                }) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 18))
                                .foregroundColor(tts.activeEngine == "silero" ? .sageGreen : .secondary)
                            Text("Silero Neural (48kHz)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(tts.activeEngine == "silero" ? .primary : .secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                CountryFlagView("de", width: 16, height: 12, cornerRadius: 2.5)
                                CountryFlagView("ru", width: 16, height: 12, cornerRadius: 2.5)
                                CountryFlagView("es", width: 16, height: 12, cornerRadius: 2.5)
                                CountryFlagView("ua", width: 16, height: 12, cornerRadius: 2.5)
                            }
                            if tts.activeEngine == "silero" {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.sageGreen)
                            }
                        }
                        Text("Studio-grade 48kHz fidelity • Native syllable stress accents • On-demand models (~38 MB)")
                            .font(.caption2)
                            .foregroundColor(.dictySecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(14)
                    .background(tts.activeEngine == "silero" ? Color.sageGreen.opacity(0.12) : Color.primary.opacity(0.02))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tts.activeEngine == "silero" ? Color.sageGreen.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
    
    // MARK: - Interactive Audition Box
    private var auditionBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.sageGreen)
                Text("Audition Spoken Audio")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    updateSampleTextForActiveVoice()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Sample Text")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                if tts.isGenerating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Synthesizing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            HStack(spacing: 10) {
                TextField("Enter text to preview...", text: $sampleText)
                    .textFieldStyle(.roundedBorder)
                
                Button(action: {
                    if tts.isSpeaking {
                        tts.stop()
                    } else {
                        tts.speak(text: sampleText)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: tts.isSpeaking ? "stop.fill" : "play.fill")
                        Text(tts.isSpeaking ? "Stop" : "Play")
                    }
                    .frame(minWidth: 64)
                }
                .buttonStyle(.flatPrimary)
                .disabled(activeVoiceUninstalled && !tts.isSpeaking)
            }
            
            // Live Persona Tagline
            HStack(spacing: 6) {
                if tts.activeEngine == "kokoro" {
                    Image(systemName: tts.isBlendingEnabled ? "wand.and.stars" : "person.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.sageGreen)
                    
                    if tts.isBlendingEnabled {
                        let pName = tts.voice(for: tts.selectedVoice)?.name ?? tts.selectedVoice
                        let bName = tts.voice(for: tts.blendVoice)?.name ?? tts.blendVoice
                        let pPct = Int((1.0 - tts.blendRatio) * 100)
                        let bPct = Int(tts.blendRatio * 100)
                        Text("Active Persona: Hybrid Blend — \(pName) (\(pPct)%) + \(bName) (\(bPct)%) • Kokoro StyleTTS2")
                            .font(.caption2)
                            .foregroundColor(.dictySecondary)
                    } else {
                        let v = tts.voice(for: tts.selectedVoice)
                        let vName = v?.name ?? tts.selectedVoice
                        Text("Active Persona:")
                            .font(.caption2)
                            .foregroundColor(.dictySecondary)
                        CountryFlagView(v?.accent ?? "US", width: 15, height: 11, cornerRadius: 2)
                        Text("\(vName) • Kokoro Single Voice")
                            .font(.caption2)
                            .foregroundColor(.dictySecondary)
                    }
                } else {
                    let v = tts.voice(for: tts.selectedVoice)
                    let name = v?.name ?? tts.selectedVoice
                    let lang = v?.accent ?? "Multilingual"
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(.appAccent)
                    Text("Active Persona:")
                        .font(.caption2)
                        .foregroundColor(.dictySecondary)
                    CountryFlagView(v?.accent ?? v?.flag ?? "all", width: 15, height: 11, cornerRadius: 2)
                    Text("\(name) (\(lang)) • Silero Neural (48 kHz Broadcast Quality)")
                        .font(.caption2)
                        .foregroundColor(.dictySecondary)
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
    
    private var activeVoiceUninstalled: Bool {
        if tts.activeEngine == "kokoro" {
            return !tts.isModelInstalled
        } else {
            return !tts.isVoiceDownloaded(tts.selectedVoice)
        }
    }
    
    // MARK: - Kokoro Specific Section
    private var kokoroSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Kokoro Model Status & Download Banner
            if !tts.isModelInstalled {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.appAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kokoro 82M Neural Model Required")
                                .font(.headline)
                            Text("Download the offline neural voice pack (88 MB) to enable English speech synthesis.")
                                .font(.caption)
                                .foregroundColor(.dictySecondary)
                        }
                        Spacer()
                        
                        if tts.isDownloading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("\(Int(tts.downloadProgress * 100))%")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.appAccent)
                            }
                        } else {
                            Button("Download (88 MB)") {
                                tts.startModelDownload()
                            }
                            .buttonStyle(.flatPrimary(color: .appAccent))
                        }
                    }
                    
                    if tts.isDownloading {
                        ProgressView(value: tts.downloadProgress)
                            .progressViewStyle(.linear)
                        if !tts.downloadStatusMessage.isEmpty {
                            Text(tts.downloadStatusMessage)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(Color.appAccent.opacity(0.08))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appAccent.opacity(0.2), lineWidth: 1))
            }
            
            // Kokoro Voice Selection & Hybrid Blending
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "person.2.wave.2.fill")
                        .foregroundColor(.sageGreen)
                    Text("Kokoro Voice Persona & Synthesis Mode")
                        .font(.headline)
                    Spacer()
                }
                
                // Mode Selector: Single Voice vs Blend Hybrid Voice
                HStack(spacing: 8) {
                    Button(action: {
                        tts.isBlendingEnabled = false
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                            Text("Single Voice")
                                .fontWeight(.medium)
                        }
                        .font(.system(size: 13))
                        .foregroundColor(!tts.isBlendingEnabled ? .sageGreen : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(!tts.isBlendingEnabled ? Color.sageGreen.opacity(0.12) : Color.primary.opacity(0.03))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(!tts.isBlendingEnabled ? Color.sageGreen.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        tts.isBlendingEnabled = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                            Text("Blend Hybrid Voice")
                                .fontWeight(.medium)
                        }
                        .font(.system(size: 13))
                        .foregroundColor(tts.isBlendingEnabled ? .sageGreen : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(tts.isBlendingEnabled ? Color.sageGreen.opacity(0.12) : Color.primary.opacity(0.03))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(tts.isBlendingEnabled ? Color.sageGreen.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                if tts.isBlendingEnabled {
                    // Hybrid Blend Configuration
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.sageGreen)
                                .font(.system(size: 13))
                            Text("Active Default: This hybrid persona is automatically used whenever you highlight text and press \(engineClient.ttsShortcutDisplay).")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.sageGreen.opacity(0.10))
                        .cornerRadius(8)
                        
                        Text("Morph two distinct voice vectors into a completely bespoke persona by interpolating their 256-D neural style embeddings in real time.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                        
                        HStack(spacing: 16) {
                            // Primary Voice Selector
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Primary Voice (Base)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                
                                Picker("", selection: $tts.selectedVoice) {
                                    ForEach(tts.engineVoices) { voice in
                                        Text("\(voice.name) (\(voice.accent) \(voice.gender.capitalized))")
                                            .tag(voice.id)
                                    }
                                }
                                .labelsHidden()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.top, 16)
                            
                            // Secondary Voice Selector
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Secondary Voice (Color)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                
                                Picker("", selection: $tts.blendVoice) {
                                    ForEach(tts.engineVoices) { voice in
                                        Text("\(voice.name) (\(voice.accent) \(voice.gender.capitalized))")
                                            .tag(voice.id)
                                    }
                                }
                                .labelsHidden()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // Blend Ratio Slider
                        VStack(alignment: .leading, spacing: 8) {
                            let pName = tts.voice(for: tts.selectedVoice)?.name ?? "Primary"
                            let bName = tts.voice(for: tts.blendVoice)?.name ?? "Secondary"
                            let pPct = Int((1.0 - tts.blendRatio) * 100)
                            let bPct = Int(tts.blendRatio * 100)
                            
                            HStack {
                                Text("\(pName): \(pPct)%")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.sageGreen)
                                Spacer()
                                Text("Blend Ratio")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(bName): \(bPct)%")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.appAccent)
                            }
                            
                            Slider(value: $tts.blendRatio, in: 0.0...1.0, step: 0.05)
                                .tint(.sageGreen)
                            
                            // Visual blend bar
                            GeometryReader { geo in
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(Color.sageGreen)
                                        .frame(width: max(0, geo.size.width * CGFloat(1.0 - tts.blendRatio)))
                                    Rectangle()
                                        .fill(Color.appAccent)
                                        .frame(width: max(0, geo.size.width * CGFloat(tts.blendRatio)))
                                }
                                .cornerRadius(3)
                            }
                            .frame(height: 6)
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.02))
                        .cornerRadius(10)
                        
                        // Quick Audition Button for Blend
                        Button(action: {
                            let pName = tts.voice(for: tts.selectedVoice)?.name ?? "Primary"
                            let bName = tts.voice(for: tts.blendVoice)?.name ?? "Secondary"
                            tts.speak(text: "Hello, this is a hybrid blend of \(pName) and \(bName). How does this voice sound to you?")
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "speaker.wave.2.fill")
                                Text("Preview Hybrid Voice")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.sageGreen.opacity(0.12))
                            .foregroundColor(.sageGreen)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(!tts.isModelInstalled)
                    }
                } else {
                    // Single Voice List
                    VStack(spacing: 8) {
                        ForEach(tts.engineVoices) { voice in
                            let isSelected = tts.selectedVoice == voice.id
                            
                            Button(action: {
                                tts.selectedVoice = voice.id
                                updateSampleTextForActiveVoice()
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundColor(isSelected ? .sageGreen : .secondary.opacity(0.4))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            CountryFlagView(voice.accent, width: 17, height: 12.5, cornerRadius: 2.5)
                                            Text(voice.name)
                                                .font(.system(size: 14, weight: .semibold))
                                            Text("(\(voice.accent) \(voice.gender.capitalized))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Text(voice.description)
                                            .font(.caption)
                                            .foregroundColor(.dictySecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        tts.selectedVoice = voice.id
                                        tts.speak(text: "Hello! I am \(voice.name). How can I help you today?", overrideVoice: voice.id, forceSingleVoice: true)
                                    }) {
                                        Image(systemName: "speaker.wave.1.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                            .padding(6)
                                            .background(Color.primary.opacity(0.05))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Listen to preview")
                                }
                                .padding(12)
                                .background(isSelected ? Color.sageGreen.opacity(0.12) : Color.primary.opacity(0.02))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isSelected ? Color.sageGreen.opacity(0.4) : Color.primary.opacity(0.05), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
            
            // Kokoro StyleTTS2 Personality & Dynamics
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.sageGreen)
                    Text("Kokoro Personality & Dynamics (StyleTTS2)")
                        .font(.headline)
                }
                
                Text("Perturbs StyleTTS2 prosody style vectors for emotional dynamic cadence and natural speech unpredictability.")
                    .font(.caption)
                    .foregroundColor(.dictySecondary)
                
                // Expressiveness Slider
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Style Variance / Expressiveness")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(round(tts.expressiveness * 100)))%")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.sageGreen)
                    }
                    
                    Slider(value: $tts.expressiveness, in: 0.0...1.0, step: 0.05)
                        .tint(.sageGreen)
                    
                    HStack {
                        Text("Controlled (0%)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Natural (15%)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Expressive (100%)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(10)
                
                // Continuous Prosody Toggle
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $tts.continuousProsody) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Continuous Melodic Intonation")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Maintains melodic sentence-to-sentence prosody without resetting pitch abruptly to neutral.")
                                .font(.caption)
                                .foregroundColor(.dictySecondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .sageGreen))
                }
                .padding(12)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(10)
            }
            .padding(16)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }
    
    // MARK: - Silero Specific Section (Multilingual 48kHz)
    private var sileroSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Zero-Footprint Information Notice
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundColor(.appAccent)
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Silero Neural Models (48,000 Hz Studio Fidelity)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Zero models are downloaded by default. Each language model (~38 MB) is downloaded on-demand and features automatic syllable stress and accent marks for natural European speech.")
                        .font(.caption)
                        .foregroundColor(.dictySecondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color.appAccent.opacity(0.08))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appAccent.opacity(0.2), lineWidth: 1))
            
            // Active Download Progress Banner or Error Notice
            if tts.isDownloading {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.85)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(tts.downloadStatusMessage.isEmpty ? "Downloading components..." : tts.downloadStatusMessage)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("\(Int(round(tts.downloadProgress * 100)))%")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.appAccent)
                        }
                        ProgressView(value: max(0.02, min(1.0, tts.downloadProgress)))
                            .tint(.appAccent)
                    }
                }
                .padding(14)
                .background(Color.appAccent.opacity(0.12))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appAccent.opacity(0.3), lineWidth: 1))
            } else if let err = tts.lastDownloadError, !err.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                    Spacer()
                    Button(action: { tts.lastDownloadError = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(10)
            }
            
            // Silero Voice Catalog with Language Tabs
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "globe.europe.africa.fill")
                        .foregroundColor(.appAccent)
                    Text("Multilingual Voice Catalog")
                        .font(.headline)
                    Spacer()
                }
                
                // Language Filter Pills
                HStack(spacing: 6) {
                    ForEach(sileroLanguages, id: \.key) { item in
                        Button(action: {
                            tts.selectedLanguage = item.key
                        }) {
                            HStack(spacing: 5) {
                                CountryFlagView(item.flag, width: 15, height: 11, cornerRadius: 2)
                                Text(item.label)
                                    .font(.system(size: 11, weight: tts.selectedLanguage == item.key ? .bold : .medium))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(tts.selectedLanguage == item.key ? Color.appAccent.opacity(0.2) : Color.primary.opacity(0.04))
                            .foregroundColor(tts.selectedLanguage == item.key ? .appAccent : .secondary)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(tts.selectedLanguage == item.key ? Color.appAccent.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
                
                // Silero Voices List
                VStack(spacing: 8) {
                    ForEach(tts.filteredVoices) { voice in
                        let isSelected = tts.selectedVoice == voice.id
                        let isDownloaded = tts.isVoiceDownloaded(voice.id)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                tts.selectedVoice = voice.id
                                updateSampleTextForActiveVoice()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundColor(isSelected ? .sageGreen : .secondary.opacity(0.4))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            CountryFlagView(voice.accent, width: 17, height: 12.5, cornerRadius: 2.5)
                                            Text(voice.name)
                                                .font(.system(size: 14, weight: .semibold))
                                            Text("(\(voice.accent) \(voice.gender.capitalized))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            if isDownloaded {
                                                Text("48 kHz")
                                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                                    .background(Color.sageGreen.opacity(0.18))
                                                    .foregroundColor(.sageGreen)
                                                    .cornerRadius(4)
                                            }
                                        }
                                        Text(voice.description)
                                            .font(.caption)
                                            .foregroundColor(.dictySecondary)
                                    }
                                    
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            
                            // Download or Delete Controls
                            if !isDownloaded {
                                let isVoiceDownloading = (tts.downloadingVoiceId == voice.id) ||
                                    (tts.isDownloading && (tts.downloadingVoiceId?.contains(voice.lang ?? "none") == true || tts.downloadingLangKey == voice.lang))
                                
                                if isVoiceDownloading {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .scaleEffect(0.65)
                                        let pct = max(2, Int(tts.downloadProgress * 100))
                                        Text("\(pct)%")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(.appAccent)
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Color.appAccent.opacity(0.12))
                                    .cornerRadius(6)
                                } else {
                                    Button(action: {
                                        tts.startVoiceDownload(voice.id)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.down.circle")
                                            Text("Download")
                                        }
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(Color.appAccent.opacity(0.12))
                                        .foregroundColor(.appAccent)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                // Quick audition button
                                Button(action: {
                                    tts.selectedVoice = voice.id
                                    let preview = samplePhraseForLanguage(voice.lang ?? "en", name: voice.name)
                                    tts.speak(text: preview, overrideVoice: voice.id, forceSingleVoice: true)
                                }) {
                                    Image(systemName: "speaker.wave.1.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .padding(6)
                                        .background(Color.primary.opacity(0.05))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Listen to preview")
                                
                                // Delete / Uninstall button
                                Button(action: {
                                    tts.deleteVoice(voice.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary.opacity(0.7))
                                        .padding(6)
                                        .background(Color.primary.opacity(0.04))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Uninstall voice to free disk space")
                            }
                        }
                        .padding(12)
                        .background(isSelected ? Color.sageGreen.opacity(0.12) : Color.primary.opacity(0.02))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Color.sageGreen.opacity(0.4) : Color.primary.opacity(0.05), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(16)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }
    
    // MARK: - Shared Settings (Speed, Pause Timing, Storage)
    private var sharedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Cadence & Pause Timing Controls
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "timer")
                        .foregroundColor(.sageGreen)
                    Text("Cadence & Pause Timing")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button("Reset Defaults") {
                        tts.resetPacingDefaults()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.sageGreen)
                }
                
                // Sentence Break Pause
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sentence Break Pause")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Silence duration inserted between distinct sentences.")
                                .font(.caption)
                                .foregroundColor(.dictySecondary)
                        }
                        Spacer()
                        Text(String(format: "%.2fs", tts.sentencePause))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.sageGreen)
                    }
                    
                    Slider(value: $tts.sentencePause, in: 0.05...0.80, step: 0.05)
                        .tint(.sageGreen)
                }
                .padding(12)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(10)
                
                // Clause / Comma Pause
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clause & Comma Pause")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Micro-pause duration at commas, semicolons, and dashes.")
                                .font(.caption)
                                .foregroundColor(.dictySecondary)
                        }
                        Spacer()
                        Text(String(format: "%.2fs", tts.clausePause))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.sageGreen)
                    }
                    
                    Slider(value: $tts.clausePause, in: 0.02...0.30, step: 0.02)
                        .tint(.sageGreen)
                }
                .padding(12)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(10)
            }
            .padding(16)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
            
            // Speed & Playback Preferences
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "speedometer")
                        .foregroundColor(.sageGreen)
                    Text("Speech Tempo & Playback Speed")
                        .font(.headline)
                }
                
                HStack(spacing: 16) {
                    Slider(value: Binding(
                        get: { Double(tts.playbackSpeed) },
                        set: { tts.playbackSpeed = Float($0) }
                    ), in: 0.5...2.0, step: 0.05)
                    .tint(.sageGreen)
                    
                    Text(String(format: "%.2fx", tts.playbackSpeed))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(width: 50, alignment: .trailing)
                }
            }
            .padding(16)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
            
            // History & Recording Storage Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "archivebox.fill")
                        .foregroundColor(.sageGreen)
                    Text("Recording Storage")
                        .font(.headline)
                }
                
                Toggle(isOn: $tts.saveRecordings) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save Text-to-Voice Recordings")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Store spoken text and generated neural audio files in your History log for listening, replaying, and archiving.")
                            .font(.caption)
                            .foregroundColor(.dictySecondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .sageGreen))
                
                HStack(spacing: 6) {
                    Image(systemName: tts.saveRecordings ? "checkmark.circle.fill" : "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(tts.saveRecordings ? .sageGreen : .secondary)
                    
                    Text(tts.saveRecordings
                         ? "Speech audio and text will be preserved in your History tab."
                         : "Recordings are played live in memory and not saved to disk (Default).")
                        .font(.caption2)
                        .foregroundColor(.dictySecondary)
                }
                .padding(.top, 2)
            }
            .padding(16)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }
    
    // MARK: - Global Shortcut Reminder
    private var shortcutTip: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard.fill")
                .foregroundColor(.sageGreen)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text("Global Shortcut: \(engineClient.ttsShortcutDisplay)")
                    .font(.system(size: 13, weight: .semibold))
                Text("Highlight any sentence or paragraph in any macOS app and press the shortcut to trigger speech synthesis.")
                    .font(.caption)
                    .foregroundColor(.dictySecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sageGreen.opacity(0.08))
        .cornerRadius(10)
    }
    
    // MARK: - Localized Helpers
    private func updateSampleTextForActiveVoice() {
        let v = tts.voice(for: tts.selectedVoice)
        let lang = v?.lang ?? (tts.activeEngine == "silero" ? "de" : "en")
        let name = v?.name ?? "Dicty"
        sampleText = samplePhraseForLanguage(lang, name: name)
    }
    
    private func samplePhraseForLanguage(_ lang: String, name: String) -> String {
        switch lang {
        case "de":
            return "Dicty verwandelt geschriebenen Text in klare und natürliche Sprache. Überprüfe die Qualität und die Betonung."
        case "ru":
            return "Dicty преобразует написанный текст в четкую и выразительную речь. Проверь качество и интонацию."
        case "uk":
            return "Dicty перетворює текст на природне та виразне мовлення. Налаштуйте темп та паузи для ідеального звучання."
        case "es":
            return "Dicty convierte el texto escrito en voz clara y natural. Ajusta el tempo y las pausas a tu preferencia."
        default:
            return "Dicty transforms written text into clear speech. Adjust the cadence, pause timing, and voice personality to hear the difference immediately."
        }
    }
}
