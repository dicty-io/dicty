import AppKit
import Foundation
import CoreAudio
import AudioToolbox

private final class AtomicBool: @unchecked Sendable {
    private let lock = NSLock()
    private var val: Bool
    
    init(_ initial: Bool = false) {
        self.val = initial
    }
    
    /// Sets value to true and returns the previous value
    func testAndSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let prev = val
        val = true
        return prev
    }
}

// MARK: - MediaRemote Framework Bridge

/// Thread-safe singleton that dynamically links to macOS MediaRemote.framework
/// and maintains persistent subscription to system Now Playing events.
private final class MediaRemoteBridge: @unchecked Sendable {
    static let shared = MediaRemoteBridge()
    
    typealias MRGetStateFn = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
    typealias MRGetInfoFn = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
    typealias MRSendCmdFn = @convention(c) (Int32, CFDictionary?) -> Bool
    typealias MRRegisterFn = @convention(c) (DispatchQueue) -> Void
    
    let getStateFn: MRGetStateFn?
    let getInfoFn: MRGetInfoFn?
    let sendCmdFn: MRSendCmdFn?
    let registerFn: MRRegisterFn?
    
    private init() {
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")) else {
            MediaLogger.shared.log("[MediaRemoteBridge] Failed to load MediaRemote.framework")
            self.getStateFn = nil
            self.getInfoFn = nil
            self.sendCmdFn = nil
            self.registerFn = nil
            return
        }
        
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationPlaybackState" as CFString) {
            self.getStateFn = unsafeBitCast(ptr, to: MRGetStateFn.self)
        } else {
            self.getStateFn = nil
        }
        
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) {
            self.getInfoFn = unsafeBitCast(ptr, to: MRGetInfoFn.self)
        } else {
            self.getInfoFn = nil
        }
        
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            self.sendCmdFn = unsafeBitCast(ptr, to: MRSendCmdFn.self)
        } else {
            self.sendCmdFn = nil
        }
        
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) {
            self.registerFn = unsafeBitCast(ptr, to: MRRegisterFn.self)
        } else {
            self.registerFn = nil
        }
        
        // Register immediately on a background queue so mediaremoted keeps Dicty's cache warm.
        self.registerFn?(DispatchQueue.global(qos: .utility))
        MediaLogger.shared.log("[MediaRemoteBridge] Initialized and registered for NowPlaying notifications.")
    }
}

/// Singleton class responsible for pausing, lowering (ducking), muting, and resuming background media players
/// (such as Apple Music, Spotify, Podcasts, TV, and browsers like Google Chrome) during voice recording sessions.
@MainActor
class MediaPlaybackManager {
    static let shared = MediaPlaybackManager()
    
    /// Keeps track of which applications were actively paused by Dicty so we only resume those specific apps.
    private var pausedApps: [String] = []
    
    /// Tracks when the last recording stopped to prevent our own stop beeps from causing false positive music detection.
    nonisolated(unsafe) static var lastStopRecordingTime = Date.distantPast
    
    /// Tracks if we explicitly resumed MediaRemote at the end of the last dictation.
    /// Used for rapid back-to-back dictations.
    nonisolated(unsafe) static var didResumeMediaRemoteOnLastStop = false
    
    /// Tracks the exact time we last sent a Play command to MediaRemote.
    /// The back-to-back check only fires within 2.0 seconds of this time to prevent ghost resumes.
    nonisolated(unsafe) static var lastMediaResumeTime = Date.distantPast
    
    /// How long our own stop sound may keep the output device busy. The unconditional back-to-back
    /// rule covers [0, window) and the hardware rule covers [window, 30 s), leaving no blind gap.
    nonisolated static let stopBeepWindow: TimeInterval = 2.5
    
    /// Tracks the active recording session to invalidate background tasks that complete after recording stops.
    private var currentRecordingSessionId = UUID()
    
    /// Remembers previous volume and mute levels for "lower" (ducking) and "mute" modes
    private var originalVolume: Float? = nil
    private var originalMuteState: Bool? = nil
    private var activeControlMode: String = "pause"
    
    private init() {
        // Force early initialization and registration of MediaRemote bridge
        _ = MediaRemoteBridge.shared
    }
    
    // MARK: - System Audio & Volume Helpers
    
    /// Gets current system master output volume (0.0 to 1.0)
    nonisolated static func getSystemOutputVolume() -> Float {
        var defaultDeviceID = AudioDeviceID(0)
        var defaultDeviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, 0, nil, &defaultDeviceIDSize, &defaultDeviceID)
        if status == noErr {
            var volume: Float = 1.0
            var volumeSize = UInt32(MemoryLayout<Float>.size)
            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            let volStatus = AudioObjectGetPropertyData(defaultDeviceID, &volumeAddress, 0, nil, &volumeSize, &volume)
            if volStatus == noErr { return volume }
        }
        
        // Fallback: AppleScript
        if let script = runAppleScript("output volume of (get volume settings)") {
            if let val = Float(script) { return val / 100.0 }
        }
        return 1.0
    }
    
    /// Sets system master output volume (0.0 to 1.0)
    nonisolated static func setSystemOutputVolume(_ volume: Float) {
        var defaultDeviceID = AudioDeviceID(0)
        var defaultDeviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, 0, nil, &defaultDeviceIDSize, &defaultDeviceID)
        if status == noErr {
            var vol = volume
            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            let volStatus = AudioObjectSetPropertyData(defaultDeviceID, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float>.size), &vol)
            if volStatus == noErr { return }
        }
        
        // Fallback: AppleScript
        let volInt = Int(max(0.0, min(1.0, volume)) * 100)
        _ = runAppleScript("set volume output volume \(volInt)")
    }
    
    /// Gets current system output mute state
    nonisolated static func isSystemMuted() -> Bool {
        var defaultDeviceID = AudioDeviceID(0)
        var defaultDeviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, 0, nil, &defaultDeviceIDSize, &defaultDeviceID)
        if status == noErr {
            var muted: UInt32 = 0
            var muteSize = UInt32(MemoryLayout<UInt32>.size)
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            let muteStatus = AudioObjectGetPropertyData(defaultDeviceID, &muteAddress, 0, nil, &muteSize, &muted)
            if muteStatus == noErr { return muted != 0 }
        }
        
        if let script = runAppleScript("output muted of (get volume settings)") {
            return script.lowercased() == "true"
        }
        return false
    }
    
    /// Sets system output mute state
    nonisolated static func setSystemMuted(_ muted: Bool) {
        var defaultDeviceID = AudioDeviceID(0)
        var defaultDeviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, 0, nil, &defaultDeviceIDSize, &defaultDeviceID)
        if status == noErr {
            var m: UInt32 = muted ? 1 : 0
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectSetPropertyData(defaultDeviceID, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        }
        _ = runAppleScript("set volume output muted \(muted)")
    }
    
    /// Checks CoreAudio hardware to determine if the default output device is actively rendering audio
    nonisolated static func isSystemAudioPlaying() -> Bool {
        var defaultDeviceID = AudioDeviceID(0)
        var defaultDeviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            0,
            nil,
            &defaultDeviceIDSize,
            &defaultDeviceID
        )
        guard status == noErr else { return false }
        
        var isRunning: UInt32 = 0
        var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
        var isRunningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let isRunningResult = AudioObjectGetPropertyData(
            defaultDeviceID,
            &isRunningAddress,
            0,
            nil,
            &isRunningSize,
            &isRunning
        )
        return isRunningResult == noErr && isRunning > 0
    }
    
    /// True if any process is capturing from the default input device. Call BEFORE Dicty opens the mic:
    /// at that point a busy input means another app (Zoom, Meet, FaceTime...) is using it.
    nonisolated static func isSystemInputInUse() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr else {
            return false
        }
        var isRunning: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectGetPropertyData(deviceID, &runningAddress, 0, nil, &runningSize, &isRunning) == noErr && isRunning > 0
    }
    
    /// Fetches global playback state from macOS Now Playing framework with a timeout safety net
    /// 1 = Playing, 2 = Paused, 3 = Stopped, 4 = Interrupted, 0 = Unknown
    nonisolated static func getPlaybackState() async -> Int32 {
        guard let fn = MediaRemoteBridge.shared.getStateFn else { return 0 }
        return await withCheckedContinuation { continuation in
            let flag = AtomicBool(false)
            let queue = DispatchQueue.global(qos: .userInitiated)
            
            queue.asyncAfter(deadline: .now() + 0.3) {
                if !flag.testAndSet() {
                    continuation.resume(returning: 0)
                }
            }
            
            fn(queue) { state in
                if !flag.testAndSet() {
                    continuation.resume(returning: state)
                }
            }
        }
    }
    
    /// Fetches the precise playback rate and elapsed time from Now Playing info with timeout safety net
    nonisolated static func getNowPlayingInfo() async -> (rate: Double, elapsedTime: Double?) {
        guard let fn = MediaRemoteBridge.shared.getInfoFn else { return (0.0, nil) }
        return await withCheckedContinuation { continuation in
            let flag = AtomicBool(false)
            let queue = DispatchQueue.global(qos: .userInitiated)
            
            queue.asyncAfter(deadline: .now() + 0.3) {
                if !flag.testAndSet() {
                    continuation.resume(returning: (0.0, nil))
                }
            }
            
            fn(queue) { cfDict in
                if !flag.testAndSet() {
                    guard let dict = cfDict as? [String: Any] else {
                        continuation.resume(returning: (0.0, nil))
                        return
                    }
                    let rate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0.0
                    let elapsedTime = dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double
                    continuation.resume(returning: (rate, elapsedTime))
                }
            }
        }
    }
    
    /// Checks if native desktop media players (Music, Spotify, TV, Podcasts) are actively playing audio.
    nonisolated static func isNativeMusicOrSpotifyPlaying() -> Bool {
        let standardMediaApps: [(name: String, bundleId: String)] = [
            ("Music", "com.apple.Music"),
            ("Spotify", "com.spotify.client"),
            ("TV", "com.apple.TV")
        ]
        
        for (app, bundleId) in standardMediaApps {
            guard isAppRunning(name: app, bundleId: bundleId) else { continue }
            let script = "tell application \"\(app)\" to return (player state is playing) as string"
            if let res = runAppleScript(script), res.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true" {
                return true
            }
        }
        
        if isAppRunning(name: "Podcasts", bundleId: "com.apple.podcasts") {
            let script = "tell application \"Podcasts\" to return (playing is true) as string"
            if let res = runAppleScript(script), res.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true" {
                return true
            }
        }
        
        return false
    }
    
    /// Checks via Swift NSWorkspace if an application is currently running in memory.
    nonisolated private static func isAppRunning(name: String, bundleId: String) -> Bool {
        for app in NSWorkspace.shared.runningApplications {
            if app.bundleIdentifier == bundleId || app.localizedName == name {
                return true
            }
        }
        return false
    }
    
    /// Executes an AppleScript and returns the string result, if any.
    nonisolated private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: source) {
            let output = scriptObject.executeAndReturnError(&error)
            if error != nil {
                return nil
            }
            return output.stringValue
        }
        return nil
    }
    
    /// Sends an explicit MediaRemote command (0 = Play, 1 = Pause, 2 = TogglePlayPause)
    nonisolated private static func sendMediaRemoteCommand(command: Int32) {
        guard let fn = MediaRemoteBridge.shared.sendCmdFn else { return }
        _ = fn(command, nil)
    }
    
    /// Simulates hardware keyboard Play/Pause media key (NX_KEYTYPE_PLAY = 16)
    nonisolated private static func sendSystemMediaKey(key: Int32 = 16) {
        func doKey(down: Bool) {
            let state = down ? 0xa : 0xb
            let flags = down ? 0xa00 : 0xb00
            let data1 = Int((key << 16) | (Int32(state) << 8))
            let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
        doKey(down: true)
        doKey(down: false)
    }
    
    /// Checks MediaRemote, native desktop media players, and CoreAudio hardware to determine
    /// if audio (native app or browser tab like YouTube) was actively playing before recording began.
    nonisolated static func isAudioPlayingAnywhere(hardwarePlayingOverride: Bool? = nil, inputBusyElsewhere: Bool? = nil) async -> Bool {
        // 1. Rapid back-to-back dictation check:
        // If Dicty explicitly resumed media within the beep window, keep playing flag active.
        let timeSinceResume = Date().timeIntervalSince(Self.lastMediaResumeTime)
        if Self.didResumeMediaRemoteOnLastStop && timeSinceResume < Self.stopBeepWindow {
            MediaLogger.shared.log("[MediaPlaybackManager] Back-to-back dictation detected (\(String(format: "%.2f", timeSinceResume))s since resume). Inferring still playing.")
            return true
        }
        
        // Hardware snapshot taken BEFORE our start chime. Right after a stop our own stop sound
        // (system sounds run up to ~2.2 s) keeps the output device busy, so distrust hardware then.
        let isHardwareRunning = hardwarePlayingOverride ?? isSystemAudioPlaying()
        let stoppedRecently = Date().timeIntervalSince(Self.lastStopRecordingTime) < Self.stopBeepWindow
        
        // 1b. We resumed the media ourselves recently and audio is still coming out of the speakers:
        // browsers (Chrome/YouTube) update their MediaRemote state lazily and keep reporting
        // "paused" for several seconds after our Play command, so trust the hardware here.
        if Self.didResumeMediaRemoteOnLastStop && timeSinceResume < 30.0 && isHardwareRunning && !stoppedRecently {
            MediaLogger.shared.log("[MediaPlaybackManager] Media resumed by Dicty \(String(format: "%.1f", timeSinceResume))s ago and output hardware is active. Inferring still playing (ignoring possibly stale MediaRemote state).")
            return true
        }
        
        // 2. Query MediaRemote playback state & rate in parallel (previously sequential: up to 2 × 300ms)
        async let stateTask = getPlaybackState()
        async let infoTask = getNowPlayingInfo()
        let (state, info) = await (stateTask, infoTask)
        
        // If state is explicitly Playing (1) or playback rate > 0, media is actively playing!
        if state == 1 || info.rate > 0.0 {
            MediaLogger.shared.log("[MediaPlaybackManager] Media is playing (MediaRemote state: \(state), rate: \(info.rate))")
            return true
        }
        
        // 3. Check native desktop media apps (Music, Spotify, TV, Podcasts)
        if isNativeMusicOrSpotifyPlaying() {
            MediaLogger.shared.log("[MediaPlaybackManager] Native media player is actively playing.")
            return true
        }
        
        // 4. Check CoreAudio hardware output device (pre-chime snapshot, see above):
        // If hardware is running and it wasn't triggered by our own recent stop beep:
        if isHardwareRunning && !stoppedRecently {
            // macOS 15.4+ blocks third-party apps from READING Now Playing state (commands still work):
            // MediaRemote then always reports a stale "paused" (state 2, rate 0) even while music plays.
            // So a non-playing MediaRemote answer is not evidence; the speaker hardware is.
            // Exception: another app holding the mic (a call) also keeps the output busy, and resuming
            // then would start music the user had paused themselves.
            if inputBusyElsewhere == true {
                MediaLogger.shared.log("[MediaPlaybackManager] Output active but another app is using the microphone (likely a call). Not inferring music (MediaRemote state: \(state)).")
                return false
            }
            MediaLogger.shared.log("[MediaPlaybackManager] Output hardware active before recording (MediaRemote state: \(state), rate: \(info.rate), unreliable on macOS 15.4+). Inferring media playing.")
            return true
        }
        
        MediaLogger.shared.log("[MediaPlaybackManager] No active media playback detected (state: \(state), rate: \(info.rate), hardware: \(isHardwareRunning), stoppedRecently: \(stoppedRecently)).")
        return false
    }
    
    // MARK: - Main Control Entry Points
    
    /// Handles background media/music playback according to user preference ("pause", "keep_playing", "lower", "mute")
    func pauseMediaIfNeeded(wasAudioPlaying: Bool, mode: String, setting: String) {
        MediaLogger.shared.log("[MediaPlaybackManager] -> pauseMediaIfNeeded called. wasAudioPlaying: \(wasAudioPlaying), Mode: '\(mode)', Setting: '\(setting)'")
        
        if DictyAudioRecorder.isSystemAudioMode(mode) {
            MediaLogger.shared.log("[MediaPlaybackManager] <- Aborting: system audio modes (meeting, focused_meeting) never pause or duck media audio")
            return
        }
        
        if setting == "never" || setting == "keep_playing" {
            MediaLogger.shared.log("[MediaPlaybackManager] <- Aborting: setting is 'keep_playing'")
            return
        }
        
        let sessionId = UUID()
        self.currentRecordingSessionId = sessionId
        self.activeControlMode = setting
        pausedApps.removeAll()
        Self.didResumeMediaRemoteOnLastStop = false
        
        if setting == "lower" {
            // Mode: Volume Ducking (Lower volume to 20% of current)
            let currVol = Self.getSystemOutputVolume()
            self.originalVolume = currVol
            let duckedVol = max(0.05, currVol * 0.20)
            Self.setSystemOutputVolume(duckedVol)
            MediaLogger.shared.log("[MediaPlaybackManager] Ducked system volume from \(currVol) to \(duckedVol)")
            return
        }
        
        if setting == "mute" {
            // Mode: Mute System Audio
            self.originalMuteState = Self.isSystemMuted()
            self.originalVolume = Self.getSystemOutputVolume()
            Self.setSystemMuted(true)
            MediaLogger.shared.log("[MediaPlaybackManager] Muted system audio during recording")
            return
        }
        
        // Pause Mode ("pause", "auto", "always"):
        // 1. ALWAYS pause global MediaRemote immediately on MainActor synchronously.
        // This ensures background media (YouTube in Chrome/Safari, Spotify, Music) STOPS PLAYING
        // immediately when the user starts speaking into the microphone!
        Self.sendMediaRemoteCommand(command: 1)
        MediaLogger.shared.log("[MediaPlaybackManager] Paused global MediaRemote immediately (command 1).")
        
        // 2. Only queue GlobalMediaKey for resumption IF audio was actually playing before recording started!
        // This guarantees that if the user manually paused music 5 minutes ago, it will NOT auto-resume on stop.
        if wasAudioPlaying || setting == "always" {
            self.pausedApps = ["GlobalMediaKey"]
            MediaLogger.shared.log("[MediaPlaybackManager] Audio was actively playing prior to record. Added GlobalMediaKey to resume list.")
        } else {
            MediaLogger.shared.log("[MediaPlaybackManager] Audio was NOT actively playing prior to record. Will not auto-resume.")
        }
        
        // 3. In parallel, also check and pause native desktop apps (Music, Spotify, Podcasts, TV)
        Task.detached(priority: .userInitiated) { [sessionId] in
            var newlyPausedNativeApps: [String] = []
            
            let standardMediaApps: [(name: String, bundleId: String)] = [
                ("Music", "com.apple.Music"),
                ("Spotify", "com.spotify.client"),
                ("TV", "com.apple.TV")
            ]
            
            for (app, bundleId) in standardMediaApps {
                guard Self.isAppRunning(name: app, bundleId: bundleId) else { continue }
                let script = """
                tell application "\(app)"
                    try
                        if player state is playing then
                            pause
                            return "paused"
                        end if
                    end try
                end tell
                return "not_playing"
                """
                if let res = Self.runAppleScript(script), res.contains("paused") {
                    newlyPausedNativeApps.append(app)
                }
            }
            
            if Self.isAppRunning(name: "Podcasts", bundleId: "com.apple.podcasts") {
                let podcastsScript = """
                tell application "Podcasts"
                    try
                        if playing is true then
                            pause
                            return "paused"
                        end if
                    end try
                end tell
                return "not_playing"
                """
                if let result = Self.runAppleScript(podcastsScript), result.contains("paused") {
                    newlyPausedNativeApps.append("Podcasts")
                }
            }
            
            await MainActor.run {
                // Ensure this recording session is still active before updating pausedApps.
                // If resumeMediaIfNeeded was already called, discard to avoid resurrecting paused state!
                guard MediaPlaybackManager.shared.currentRecordingSessionId == sessionId else {
                    MediaLogger.shared.log("[MediaPlaybackManager] Session ended before native apps finished pausing. Discarding native pause list.")
                    return
                }
                var current = Set(MediaPlaybackManager.shared.pausedApps)
                for app in newlyPausedNativeApps { current.insert(app) }
                MediaPlaybackManager.shared.pausedApps = Array(current)
                MediaLogger.shared.log("[MediaPlaybackManager] Active pausedApps updated: \(MediaPlaybackManager.shared.pausedApps)")
            }
        }
    }
    
    /// Restores media playback, volume levels, or mute states after recording stops.
    func resumeMediaIfNeeded(shouldResume: Bool) {
        Self.lastStopRecordingTime = Date()
        self.currentRecordingSessionId = UUID() // Invalidate any running pause task immediately
        
        if activeControlMode == "lower" {
            if let origVol = originalVolume {
                Self.setSystemOutputVolume(origVol)
                MediaLogger.shared.log("[MediaPlaybackManager] Restored system volume to \(origVol)")
            }
            originalVolume = nil
            return
        }
        
        if activeControlMode == "mute" {
            if let origMute = originalMuteState {
                Self.setSystemMuted(origMute)
                MediaLogger.shared.log("[MediaPlaybackManager] Restored system mute state to \(origMute)")
            } else {
                Self.setSystemMuted(false)
            }
            originalMuteState = nil
            originalVolume = nil
            return
        }
        
        guard shouldResume, !pausedApps.isEmpty else {
            MediaLogger.shared.log("[MediaPlaybackManager] resumeMediaIfNeeded: shouldResume=\(shouldResume), pausedApps=\(pausedApps). Nothing to resume.")
            pausedApps.removeAll()
            return
        }
        
        let appsToResume = pausedApps
        pausedApps.removeAll()
        
        // 1. Immediately resume global MediaRemote synchronously if Dicty paused it.
        if appsToResume.contains("GlobalMediaKey") {
            Self.didResumeMediaRemoteOnLastStop = true
            Self.lastMediaResumeTime = Date()
            Self.sendMediaRemoteCommand(command: 0)
            MediaLogger.shared.log("[MediaPlaybackManager] Resumed media via explicit MediaRemote Play command (command 0).")
            // NOTE: no "media key fallback" here. NX_KEYTYPE_PLAY is the keyboard play/pause key, i.e. a
            // TOGGLE. The old fallback fired whenever MediaRemote didn't report "playing" ~150 ms later,
            // which on macOS 15.4+ is always (third-party apps can't read Now Playing state), so it
            // re-paused the music right after resuming it.
        }
        
        // 2. Resume any native media players in the background.
        let nativeAppsToResume = appsToResume.filter { $0 != "GlobalMediaKey" }
        if !nativeAppsToResume.isEmpty {
            Task.detached(priority: .userInitiated) {
                for app in nativeAppsToResume {
                    let script = """
                    tell application "\(app)"
                        try
                            play
                        end try
                    end tell
                    """
                    _ = Self.runAppleScript(script)
                    MediaLogger.shared.log("[MediaPlaybackManager] Resumed media in: \(app)")
                }
            }
        }
    }
}
