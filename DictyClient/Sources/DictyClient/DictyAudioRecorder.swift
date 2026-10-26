import Foundation
import ScreenCaptureKit
import AVFoundation
import Network

class DictyAudioRecorder: NSObject, ObservableObject, @unchecked Sendable {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var outputFileUrl: URL?
    
    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var udpConnection: NWConnection?
    private var isMicMuted: Bool = false
    
    static func isSystemAudioMode(_ mode: String) -> Bool {
        return mode == "meeting" || mode == "focused_meeting"
    }
    
    @Published var isRecording = false
    @Published var isPaused = false
    
    @MainActor
    private func setRecording(_ state: Bool) {
        self.isRecording = state
    }
    
    @MainActor
    func pause() {
        self.isPaused = true
        self.audioRecorder?.pause()
    }
    
    @MainActor
    func resume() {
        self.isPaused = false
        self.audioRecorder?.record()
    }
    
    func setMuted(_ muted: Bool) {
        self.isMicMuted = muted
    }
    
    /// Native macOS microphone recording directly inside the Swift process (`DictyClient` / `Dicty.app`).
    /// Why: macOS TCC grants Microphone permission to the GUI app (`Dicty`), NOT to unsigned/rebuilt Python
    /// child processes (`dicty_engine` / `python3`), which macOS silently feeds all-zero (`0.0000`) audio!
    /// Recording the microphone natively via `AVAudioRecorder` in Swift guarantees macOS TCC always allows
    /// real mic audio, while streaming live volume meters to the overlay on UDP 55555.
    func startMicRecording() throws -> URL {
        stopMicRecording()
        let tempDir = FileManager.default.temporaryDirectory
        let fileUrl = tempDir.appendingPathComponent("dicty_mic_\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let rec = try AVAudioRecorder(url: fileUrl, settings: settings)
        rec.isMeteringEnabled = true
        rec.prepareToRecord()
        guard rec.record() else {
            throw NSError(domain: "DictyAudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "AVAudioRecorder.record() returned false"])
        }
        self.audioRecorder = rec
        startVolumeMetering()
        return fileUrl
    }
    
    func stopMicRecording() -> URL? {
        stopVolumeMetering()
        guard let rec = self.audioRecorder else { return nil }
        let url = rec.url
        rec.stop()
        self.audioRecorder = nil
        return url
    }
    
    private func startVolumeMetering() {
        stopVolumeMetering()
        let conn = NWConnection(host: "127.0.0.1", port: 55555, using: .udp)
        conn.start(queue: .global(qos: .userInteractive))
        self.udpConnection = conn
        DispatchQueue.main.async { [weak self] in
            self?.meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self, let rec = self.audioRecorder else { return }
                let vol: Float
                if self.isPaused || self.isMicMuted || !rec.isRecording {
                    vol = 0.0
                } else {
                    rec.updateMeters()
                    let db = rec.averagePower(forChannel: 0) // -160 .. 0 dB
                    let linear = powf(10.0, db / 20.0)
                    vol = min(1.0, max(0.0, linear * 3.2))
                }
                if let data = String(format: "%.4f", vol).data(using: .utf8) {
                    self.udpConnection?.send(content: data, completion: .idempotent)
                }
            }
        }
    }
    
    private func stopVolumeMetering() {
        DispatchQueue.main.async { [weak self] in
            self?.meterTimer?.invalidate()
            self?.meterTimer = nil
        }
        udpConnection?.cancel()
        udpConnection = nil
    }
    
    func startRecording(mode: String) async throws {
        if isRecording { return }
        await MainActor.run { self.isPaused = false }
        
        let tempDir = FileManager.default.temporaryDirectory
        // Use wav for SCKit and AVAudioRecorder so Whisper.cpp can process it natively
        let ext = "wav"
        let fileUrl = tempDir.appendingPathComponent(UUID().uuidString + ".\(ext)")
        self.outputFileUrl = fileUrl
        
        if Self.isSystemAudioMode(mode) {
            if !CGPreflightScreenCaptureAccess() {
                _ = CGRequestScreenCaptureAccess()
                throw NSError(domain: "SCStreamErrorDomain", code: -3801, userInfo: [NSLocalizedDescriptionKey: "Screen & System Audio Recording permission not granted."])
            }
            try await startScreenCaptureKitRecording(to: fileUrl, mode: mode)
        }
        
        await setRecording(true)
    }
    
    func stopRecording() async throws -> URL? {
        if !isRecording { return nil }
        await setRecording(false)
        await MainActor.run { self.isPaused = false }
        
        if stream != nil {
            try await stream?.stopCapture()
            stream = nil
            if let writer = assetWriter {
                if writer.status == .writing {
                    audioInput?.markAsFinished()
                    await writer.finishWriting()
                }
            }
            assetWriter = nil
            audioInput = nil
        }
        
        return outputFileUrl
    }
    
    // MARK: - Meeting Mode (ScreenCaptureKit)
    private func startScreenCaptureKitRecording(to url: URL, mode: String) async throws {
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = availableContent.displays.first else {
            throw NSError(domain: "DictyError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }
        
        let filter: SCContentFilter
        if mode == "focused_meeting" {
            let selectedAppStr = UserDefaults.standard.string(forKey: "selectedMeetingApps") ?? ""
            let selectedIDs = Set(selectedAppStr.split(separator: ",").map(String.init))
            let selectedApps = availableContent.applications.filter { selectedIDs.contains($0.bundleIdentifier) }
            if selectedApps.isEmpty {
                MediaLogger.shared.log("[DictyAudioRecorder] No target apps configured or running for Focused Meeting; capturing all system audio.")
                filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, including: selectedApps, exceptingWindows: [])
            }
        } else {
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        }
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true // Don't record Dicty's own UI sounds
        
        // Setup AVAssetWriter
        assetWriter = try AVAssetWriter(url: url, fileType: .wav)
        
        let audioSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true
        if let audioInput = audioInput, let assetWriter = assetWriter, assetWriter.canAdd(audioInput) {
            assetWriter.add(audioInput)
        }
        
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        // Using an unchecked Sendable wrapper for the recorder so we can pass it to the output queue
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.dicty.audioQueue"))
        try await stream?.startCapture()
    }
}

extension DictyAudioRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        MediaLogger.shared.log("[DictyAudioRecorder] SCStream stopped with error: \(error)")
    }
}

extension DictyAudioRecorder: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        autoreleasepool {
            guard type == .audio, !self.isPaused, let assetWriter = self.assetWriter, let audioInput = self.audioInput else { return }
            
            if assetWriter.status == .unknown {
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                assetWriter.startWriting()
                assetWriter.startSession(atSourceTime: presentationTime)
            }
            
            if assetWriter.status == .writing && audioInput.isReadyForMoreMediaData {
                let appended = audioInput.append(sampleBuffer)
                if !appended, let error = assetWriter.error {
                    MediaLogger.shared.log("[DictyAudioRecorder] Failed to append sampleBuffer: \(error)")
                }
            } else if assetWriter.status == .failed, let error = assetWriter.error {
                MediaLogger.shared.log("[DictyAudioRecorder] AVAssetWriter failed: \(error)")
            }
        }
    }
}
