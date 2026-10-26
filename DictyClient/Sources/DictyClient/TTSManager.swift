import Foundation
import SwiftUI
import AppKit
import AVFoundation

struct TTSVoice: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let gender: String
    let accent: String
    let description: String
    var lang: String? = "en"
    var engine: String? = "kokoro"
    var installed: Bool? = true
    var flag: String? = ""

    static let defaultCatalog: [TTSVoice] = [
        TTSVoice(id: "af_heart", name: "Heart", gender: "female", accent: "US", description: "Warm, engaging, and expressive (Recommended)", lang: "en", engine: "kokoro", installed: true, flag: "🇺🇸"),
        TTSVoice(id: "af_bella", name: "Bella", gender: "female", accent: "US", description: "Clear, lively, and articulate", lang: "en", engine: "kokoro", installed: true, flag: "🇺🇸"),
        TTSVoice(id: "af_nicole", name: "Nicole", gender: "female", accent: "US", description: "Professional, calm, and polished", lang: "en", engine: "kokoro", installed: true, flag: "🇺🇸"),
        TTSVoice(id: "af_sky", name: "Sky", gender: "female", accent: "US", description: "Soft, natural, and friendly", lang: "en", engine: "kokoro", installed: true, flag: "🇺🇸"),
        TTSVoice(id: "af_sarah", name: "Sarah", gender: "female", accent: "US", description: "Mature, balanced, and confident", lang: "en", engine: "kokoro", installed: true, flag: "🇺🇸"),
        TTSVoice(id: "am_adam", name: "Adam", gender: "male", accent: "US", description: "Deep, confident, and resonant", lang: "en", engine: "kokoro", installed: true, flag: "🇺🇸"),
        TTSVoice(id: "am_michael", name: "Michael", gender: "male", accent: "US", description: "Conversational, natural, and clear", lang: "en", engine: "kokoro", installed: true, flag: "🇺🇸"),
        TTSVoice(id: "am_echo", name: "Echo", gender: "male", accent: "US", description: "Crisp and energetic", lang: "en", engine: "kokoro", installed: true, flag: "🇺🇸"),
        TTSVoice(id: "am_fenrir", name: "Fenrir", gender: "male", accent: "US", description: "Strong, authoritative, and steady", lang: "en", engine: "kokoro", installed: true, flag: "🇺🇸"),
        TTSVoice(id: "bf_emma", name: "Emma", gender: "female", accent: "UK", description: "Refined British narrator", lang: "en", engine: "kokoro", installed: true, flag: "🇬🇧"),
        TTSVoice(id: "bf_isabella", name: "Isabella", gender: "female", accent: "UK", description: "Sophisticated and articulate British", lang: "en", engine: "kokoro", installed: true, flag: "🇬🇧"),
        TTSVoice(id: "bm_george", name: "George", gender: "male", accent: "UK", description: "Warm, classic British timbre", lang: "en", engine: "kokoro", installed: true, flag: "🇬🇧"),
        TTSVoice(id: "bm_lewis", name: "Lewis", gender: "male", accent: "UK", description: "Modern and expressive British narrator", lang: "en", engine: "kokoro", installed: true, flag: "🇬🇧"),
        // Russian (Silero Neural 48kHz)
        TTSVoice(id: "silero:ru_xenia", name: "Xenia", gender: "female", accent: "RU", description: "Crisp, studio-grade Russian female narrator (Silero 48kHz)", lang: "ru", engine: "silero", installed: false, flag: "🇷🇺"),
        TTSVoice(id: "silero:ru_kseniya", name: "Kseniya", gender: "female", accent: "RU", description: "Warm, conversational Russian female voice (Silero 48kHz)", lang: "ru", engine: "silero", installed: false, flag: "🇷🇺"),
        TTSVoice(id: "silero:ru_baya", name: "Baya", gender: "female", accent: "RU", description: "Expressive, dynamic Russian female voice (Silero 48kHz)", lang: "ru", engine: "silero", installed: false, flag: "🇷🇺"),
        TTSVoice(id: "silero:ru_aidar", name: "Aidar", gender: "male", accent: "RU", description: "Deep, authoritative Russian male voice (Silero 48kHz)", lang: "ru", engine: "silero", installed: false, flag: "🇷🇺"),
        TTSVoice(id: "silero:ru_eugene", name: "Eugene", gender: "male", accent: "RU", description: "Clear, modern Russian male narrator (Silero 48kHz)", lang: "ru", engine: "silero", installed: false, flag: "🇷🇺"),
        // German (Silero Neural 48kHz)
        TTSVoice(id: "silero:de_karlsson", name: "Karlsson", gender: "male", accent: "DE", description: "Natural, conversational German male voice (Silero 48kHz)", lang: "de", engine: "silero", installed: false, flag: "🇩🇪"),
        TTSVoice(id: "silero:de_eva_k", name: "Eva", gender: "female", accent: "DE", description: "Clear and articulate German female narrator (Silero 48kHz)", lang: "de", engine: "silero", installed: false, flag: "🇩🇪"),
        TTSVoice(id: "silero:de_bernd_ungerer", name: "Bernd", gender: "male", accent: "DE", description: "Classic German documentary narrator (Silero 48kHz)", lang: "de", engine: "silero", installed: false, flag: "🇩🇪"),
        TTSVoice(id: "silero:de_friedrich", name: "Friedrich", gender: "male", accent: "DE", description: "Expressive, lively German male voice (Silero 48kHz)", lang: "de", engine: "silero", installed: false, flag: "🇩🇪"),
        TTSVoice(id: "silero:de_hokuspokus", name: "Hokuspokus", gender: "male", accent: "DE", description: "Warm storytelling German voice (Silero 48kHz)", lang: "de", engine: "silero", installed: false, flag: "🇩🇪"),
        // Spanish (Silero Neural 48kHz)
        TTSVoice(id: "silero:es_es_0", name: "Elena", gender: "female", accent: "ES", description: "Clear, expressive Spanish female narrator (Silero 48kHz)", lang: "es", engine: "silero", installed: false, flag: "🇪🇸"),
        TTSVoice(id: "silero:es_es_1", name: "Mateo", gender: "male", accent: "ES", description: "Warm conversational Spanish male narrator (Silero 48kHz)", lang: "es", engine: "silero", installed: false, flag: "🇪🇸"),
        // Ukrainian (Silero Neural 48kHz)
        TTSVoice(id: "silero:ua_mykyta", name: "Mykyta", gender: "male", accent: "UA", description: "Natural Ukrainian male narrator (Silero 48kHz)", lang: "uk", engine: "silero", installed: false, flag: "🇺🇦")
    ]
}

@MainActor
final class TTSManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = TTSManager()
    
    @Published var isSpeaking: Bool = false
    @Published var isGenerating: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentText: String = ""
    @Published var activeEngine: String = UserDefaults.standard.string(forKey: "DictyTTSEngine") ?? "kokoro" {
        didSet {
            UserDefaults.standard.set(activeEngine, forKey: "DictyTTSEngine")
            ensureValidVoiceForActiveEngine()
        }
    }
    @Published var selectedLanguage: String = "all"
    @Published var selectedVoice: String = UserDefaults.standard.string(forKey: "DictyTTSVoice") ?? "af_heart" {
        didSet {
            UserDefaults.standard.set(selectedVoice, forKey: "DictyTTSVoice")
        }
    }
    
    var engineVoices: [TTSVoice] {
        if activeEngine == "multilingual" || activeEngine == "silero" {
            return availableVoices.filter { $0.engine == "silero" }
        }
        return availableVoices.filter { ($0.engine ?? "kokoro") == activeEngine }
    }
    
    var filteredVoices: [TTSVoice] {
        let base = engineVoices
        if selectedLanguage == "all" {
            return base
        }
        return base.filter { $0.lang == selectedLanguage }
    }
    
    func ensureValidVoiceForActiveEngine() {
        let voices = engineVoices
        if !voices.contains(where: { $0.id == selectedVoice }) {
            if let firstInstalled = voices.first(where: { isVoiceDownloaded($0.id) }) {
                selectedVoice = firstInstalled.id
            } else if let first = voices.first {
                selectedVoice = first.id
            }
        }
    }
    
    func isVoiceDownloaded(_ voiceId: String) -> Bool {
        if let v = availableVoices.first(where: { $0.id == voiceId }) {
            return v.installed ?? ((v.engine == "silero" || v.engine == "piper") ? false : isModelInstalled)
        }
        return isModelInstalled
    }
    @Published var playbackSpeed: Float = Float(UserDefaults.standard.double(forKey: "DictyTTSSpeed") > 0 ? UserDefaults.standard.double(forKey: "DictyTTSSpeed") : 1.0) {
        didSet {
            UserDefaults.standard.set(Double(playbackSpeed), forKey: "DictyTTSSpeed")
            audioPlayer?.rate = playbackSpeed
        }
    }
    @Published var availableVoices: [TTSVoice] = TTSVoice.defaultCatalog
    @Published var isModelInstalled: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var isDownloading: Bool = false
    @Published var downloadStatusMessage: String = ""
    @Published var downloadingVoiceId: String? = nil
    @Published var downloadingLangKey: String? = nil
    @Published var lastDownloadError: String? = nil

    // MARK: - Advanced Voice Parameters
    @Published var isBlendingEnabled: Bool = UserDefaults.standard.bool(forKey: "DictyTTSBlendingEnabled") {
        didSet {
            UserDefaults.standard.set(isBlendingEnabled, forKey: "DictyTTSBlendingEnabled")
        }
    }
    @Published var blendVoice: String = UserDefaults.standard.string(forKey: "DictyTTSBlendVoice") ?? "bf_emma" {
        didSet {
            UserDefaults.standard.set(blendVoice, forKey: "DictyTTSBlendVoice")
        }
    }
    @Published var blendRatio: Double = UserDefaults.standard.object(forKey: "DictyTTSBlendRatio") != nil ? UserDefaults.standard.double(forKey: "DictyTTSBlendRatio") : 0.3 {
        didSet {
            UserDefaults.standard.set(blendRatio, forKey: "DictyTTSBlendRatio")
        }
    }
    @Published var expressiveness: Double = UserDefaults.standard.object(forKey: "DictyTTSExpressiveness") != nil ? UserDefaults.standard.double(forKey: "DictyTTSExpressiveness") : 0.15 {
        didSet {
            UserDefaults.standard.set(expressiveness, forKey: "DictyTTSExpressiveness")
        }
    }
    @Published var sentencePause: Double = UserDefaults.standard.object(forKey: "DictyTTSSentencePause") != nil ? UserDefaults.standard.double(forKey: "DictyTTSSentencePause") : 0.25 {
        didSet {
            UserDefaults.standard.set(sentencePause, forKey: "DictyTTSSentencePause")
        }
    }
    @Published var clausePause: Double = UserDefaults.standard.object(forKey: "DictyTTSClausePause") != nil ? UserDefaults.standard.double(forKey: "DictyTTSClausePause") : 0.10 {
        didSet {
            UserDefaults.standard.set(clausePause, forKey: "DictyTTSClausePause")
        }
    }
    @Published var continuousProsody: Bool = UserDefaults.standard.bool(forKey: "DictyTTSContinuousProsody") {
        didSet {
            UserDefaults.standard.set(continuousProsody, forKey: "DictyTTSContinuousProsody")
        }
    }
    @Published var saveRecordings: Bool = UserDefaults.standard.bool(forKey: "DictyTTSSaveRecordings") {
        didSet {
            UserDefaults.standard.set(saveRecordings, forKey: "DictyTTSSaveRecordings")
        }
    }

    // MARK: - Timeline & Audio Progress
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var playbackProgress: Double = 0.0
    
    private var audioPlayer: AVAudioPlayer?
    private var statusPollTimer: Timer?
    private var playbackTimer: Timer?
    
    override init() {
        super.init()
        checkStatus()
    }

    func voice(for id: String) -> TTSVoice? {
        return availableVoices.first(where: { $0.id == id }) ?? TTSVoice.defaultCatalog.first(where: { $0.id == id })
    }

    func resetPacingDefaults() {
        expressiveness = 0.15
        sentencePause = 0.25
        clausePause = 0.10
        playbackSpeed = 1.0
        continuousProsody = false
    }

    // MARK: - Timeline Seeking
    func seek(toProgress progress: Double) {
        guard let player = audioPlayer, duration > 0 else { return }
        let clamped = max(0.0, min(1.0, progress))
        let targetTime = clamped * duration
        player.currentTime = targetTime
        currentTime = targetTime
        playbackProgress = clamped
    }

    func seek(toTime time: Double) {
        guard let player = audioPlayer, duration > 0 else { return }
        let clamped = max(0.0, min(duration, time))
        player.currentTime = clamped
        currentTime = clamped
        playbackProgress = duration > 0 ? clamped / duration : 0.0
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.audioPlayer else { return }
                if player.isPlaying {
                    self.currentTime = player.currentTime
                    if self.duration > 0 {
                        self.playbackProgress = max(0.0, min(1.0, player.currentTime / self.duration))
                    }
                }
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    // MARK: - Selected Text Capture
    
    func captureSelectedText() -> String? {
        // Method 1: macOS Accessibility API (Non-destructive)
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        
        if result == .success, let app = focusedApp {
            let appElement = app as! AXUIElement
            var focusedUIElement: AnyObject?
            let elementResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedUIElement)
            
            if elementResult == .success, let uiElement = focusedUIElement {
                let target = uiElement as! AXUIElement
                var selectedTextValue: AnyObject?
                let textResult = AXUIElementCopyAttributeValue(target, kAXSelectedTextAttribute as CFString, &selectedTextValue)
                
                if textResult == .success, let str = selectedTextValue as? String, !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return str.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        // Method 2: Fast Clipboard Snapshot + Cmd+C Fallback (Works across Electron/Chromium)
        let backup = EngineClient.ClipboardBackup.snapshot()
        let pb = NSPasteboard.general
        let prevCount = pb.changeCount
        
        // Simulate Cmd+C
        let src = CGEventSource(stateID: .combinedSessionState)
        let cDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true) // 'C'
        let cUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        cDown?.flags = .maskCommand
        cUp?.flags = .maskCommand
        cDown?.post(tap: .cghidEventTap)
        cUp?.post(tap: .cghidEventTap)
        
        // Brief run loop wait to allow target app to copy
        let waitDeadline = Date().addingTimeInterval(0.25)
        while Date() < waitDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            if pb.changeCount != prevCount {
                break
            }
        }
        
        let copiedText = pb.string(forType: .string)
        
        // Restore prior clipboard contents so user's clipboard history remains intact
        backup?.restore()
        
        if let text = copiedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    // MARK: - Text-to-Speech Synthesis
    
    func speakSelection() {
        guard let text = captureSelectedText(), !text.isEmpty else {
            NSSound.beep()
            return
        }
        speak(text: text)
    }
    
    func speak(text: String, overrideVoice: String? = nil, forceSingleVoice: Bool = false) {
        stop()
        
        currentText = text
        isGenerating = true
        FloatingAudioHUDWindow.shared.show(ttsManager: self)
        
        Task {
            do {
                let url = EngineEndpoint.shared.url("/tts/speak")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 30
                
                let voiceToUse = overrideVoice ?? selectedVoice
                var body: [String: Any] = [
                    "text": text,
                    "voice": voiceToUse,
                    "speed": playbackSpeed,
                    "expressiveness": expressiveness,
                    "sentence_pause": sentencePause,
                    "clause_pause": clausePause,
                    "continuous": continuousProsody,
                    "save_record": saveRecordings
                ]
                if !forceSingleVoice && isBlendingEnabled && !blendVoice.isEmpty && blendVoice != voiceToUse {
                    body["blend_voice"] = blendVoice
                    body["blend_ratio"] = blendRatio
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
                let (data, response) = try await EngineEndpoint.shared.session.data(for: request)
                
                guard let httpResp = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                
                if httpResp.statusCode == 404 {
                    // Model not installed yet!
                    self.isGenerating = false
                    if voiceToUse.hasPrefix("silero:") || voiceToUse.hasPrefix("piper:") {
                        self.startVoiceDownload(voiceToUse)
                    } else {
                        self.isModelInstalled = false
                        self.startModelDownload()
                    }
                    return
                }
                
                guard httpResp.statusCode == 200 else {
                    throw NSError(domain: "TTS", code: httpResp.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error \(httpResp.statusCode)"])
                }
                
                self.audioPlayer = try AVAudioPlayer(data: data)
                self.audioPlayer?.delegate = self
                self.audioPlayer?.prepareToPlay()
                self.duration = self.audioPlayer?.duration ?? 0.0
                self.currentTime = 0.0
                self.playbackProgress = 0.0
                self.audioPlayer?.play()
                self.startPlaybackTimer()
                
                self.isGenerating = false
                self.isSpeaking = true
                self.isPaused = false
            } catch {
                print("TTS Speak Error: \(error)")
                self.isGenerating = false
                self.stop()
            }
        }
    }
    
    func togglePlayPause() {
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.pause()
            isPaused = true
        } else {
            player.play()
            isPaused = false
            startPlaybackTimer()
        }
    }
    
    func stop() {
        stopPlaybackTimer()
        audioPlayer?.stop()
        audioPlayer = nil
        currentTime = 0.0
        playbackProgress = 0.0
        duration = 0.0
        isSpeaking = false
        isPaused = false
        isGenerating = false
        FloatingAudioHUDWindow.shared.hide()
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }
    
    // MARK: - Model Status & Download
    
    func checkStatus() {
        Task {
            let url = EngineEndpoint.shared.url("/tts/status")
            do {
                let (data, _) = try await EngineEndpoint.shared.session.data(from: url)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.isModelInstalled = json["installed"] as? Bool ?? false
                    if let voicesRaw = json["voices"],
                       let voicesData = try? JSONSerialization.data(withJSONObject: voicesRaw),
                       let decoded = try? JSONDecoder().decode([TTSVoice].self, from: voicesData) {
                        self.availableVoices = decoded
                    }
                    if let dl = json["download"] as? [String: Any] {
                        let status = dl["status"] as? String ?? "idle"
                        self.isDownloading = (status == "downloading")
                        self.downloadProgress = (dl["percent"] as? Double ?? 0.0) / 100.0
                        self.downloadStatusMessage = dl["message"] as? String ?? ""
                        if self.isDownloading {
                            self.lastDownloadError = nil
                            if let vid = dl["voice_id"] as? String, !vid.isEmpty {
                                self.downloadingVoiceId = vid
                            }
                            if let lk = dl["lang_key"] as? String, !lk.isEmpty {
                                self.downloadingLangKey = lk
                            }
                        } else if status == "failed" || status == "error" {
                            self.lastDownloadError = self.downloadStatusMessage.isEmpty ? "Download failed." : self.downloadStatusMessage
                            self.downloadingVoiceId = nil
                            self.downloadingLangKey = nil
                        } else if status == "completed" || status == "idle" {
                            self.downloadingVoiceId = nil
                            self.downloadingLangKey = nil
                        }
                    }
                }
            } catch {
                // Engine might still be booting up
            }
        }
    }
    
    func startModelDownload() {
        Task {
            let url = EngineEndpoint.shared.url("/tts/download")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            _ = try? await EngineEndpoint.shared.session.data(for: request)
            self.isDownloading = true
            self.downloadProgress = 0.02
            self.startPollingDownloadStatus()
        }
    }
    
    func startVoiceDownload(_ voiceId: String) {
        self.downloadingVoiceId = voiceId
        self.isDownloading = true
        self.downloadProgress = 0.02
        self.lastDownloadError = nil
        Task {
            let url = EngineEndpoint.shared.url("/tts/download")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["voice_id": voiceId])
            _ = try? await EngineEndpoint.shared.session.data(for: request)
            self.startPollingDownloadStatus()
        }
    }
    
    func deleteVoice(_ voiceId: String) {
        Task {
            let url = EngineEndpoint.shared.url("/tts/voice/delete")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["voice_id": voiceId])
            _ = try? await EngineEndpoint.shared.session.data(for: request)
            self.checkStatus()
        }
    }
    
    private func startPollingDownloadStatus() {
        statusPollTimer?.invalidate()
        statusPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.checkStatus()
                if !self.isDownloading && (self.downloadProgress >= 1.0 || self.lastDownloadError != nil) {
                    self.statusPollTimer?.invalidate()
                    self.statusPollTimer = nil
                }
            }
        }
    }
}
