import Foundation
import AppKit

@MainActor
class DictyEngineManager {
    static let shared = DictyEngineManager()
    private var engineProcess: Process?
    
    func ensureEngineRunning() {
        Task {
            if await checkEngineActive() {
                print("[*] Backend engine is active on port \(EngineEndpoint.port).")
                return
            }
            print("[*] Launching embedded backend engine immediately...")
            launchEmbeddedEngine()
        }
    }
    
    private func checkEngineActive() async -> Bool {
        let health = EngineEndpoint.shared.request("/health", timeout: 1.0)
        do {
            let (_, response) = try await EngineEndpoint.shared.session.data(for: health)
            // Any HTTP response means something is already listening on the engine port.
            // Older builds returned 404 for /health, so do not treat that as "not running"
            // and launch a duplicate process.
            guard response is HTTPURLResponse else {
                return false
            }
        } catch {
            return false
        }

        // A previously-running engine may have written a new token before we adopted it.
        EngineEndpoint.shared.adoptRunningEngineToken()

        // Health is intentionally unauthenticated. Verify one authenticated call so the
        // client notices a stale token before the rest of the UI starts polling.
        let models = EngineEndpoint.shared.request("/models", timeout: 2.0)
        do {
            let (_, response) = try await EngineEndpoint.shared.session.data(for: models)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                EngineEndpoint.shared.noteAuthFailure()
            }
        } catch {
            // Health succeeded, so the engine is alive; never launch a duplicate process.
        }
        return true
    }
    
    /// Debug builds only: run the engine from source (`.venv/bin/python dicty_engine.py`) when the app is
    /// started from the repo so `swift run` inherits your terminal's Microphone TCC permission and runs the
    /// latest Python source directly. Set DICTY_USE_BUNDLED_ENGINE=1 to test `dist/dicty_engine` instead.
    private func sourceEngineCommand() -> (python: String, script: String, dir: String)? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["DICTY_USE_BUNDLED_ENGINE"] == "1" { return nil }
        let cwd = FileManager.default.currentDirectoryPath
        for root in [cwd, "\(cwd)/.."] {
            let dir = URL(fileURLWithPath: root).standardizedFileURL.path
            let script = "\(dir)/dicty_engine.py"
            let python = "\(dir)/.venv/bin/python"
            if FileManager.default.fileExists(atPath: script), FileManager.default.isExecutableFile(atPath: python) {
                return (python, script, dir)
            }
        }
        #endif
        return nil
    }
    
    private func launchEmbeddedEngine() {
        var enginePath: String? = nil
        var candidates: [String] = []
        var arguments: [String] = []
        var workingDir = NSHomeDirectory()
        
        if let src = sourceEngineCommand() {
            enginePath = src.python
            arguments = [src.script]
            workingDir = src.dir
            print("[*] DEBUG: launching engine from source (\(src.script)) instead of dist/ bundle")
        }
        
        // 1. Packaged App Bundle resource directory
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("dicty_engine").appendingPathComponent("dicty_engine").path)
        }
        
        // 2. Development paths (when running via 'swift run' from DictyClient or project root)
        let cwd = FileManager.default.currentDirectoryPath
        candidates.append("\(cwd)/dist/dicty_engine/dicty_engine")
        candidates.append("\(cwd)/../dist/dicty_engine/dicty_engine")
        
        // 3. Standard local application installation
        candidates.append("/Applications/Dicty.app/Contents/Resources/dicty_engine/dicty_engine")
        
        if enginePath == nil {
            for candidate in candidates {
                if FileManager.default.fileExists(atPath: candidate) {
                    enginePath = candidate
                    break
                }
            }
        }
        
        guard let executablePath = enginePath else {
            print("[!] Embedded dicty_engine binary not found (searched: \(candidates)). Running in client-only mode.")
            return
        }
        
        print("[*] Launching embedded backend engine at \(executablePath)...")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        process.arguments = arguments
        // Lets the engine's watchdog exit (and stop whisper-server) if this app dies without a clean quit.
        var env = ProcessInfo.processInfo.environment
        env["DICTY_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        for (key, value) in EngineEndpoint.shared.launchEnvironment {
            env[key] = value
        }
        process.environment = env
        
        let logDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Dicty")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logFile = logDir.appendingPathComponent("engine.log").path
        if !FileManager.default.fileExists(atPath: logFile) {
            FileManager.default.createFile(atPath: logFile, contents: nil)
        }
        if let fileHandle = FileHandle(forWritingAtPath: logFile) {
            fileHandle.seekToEndOfFile()
            process.standardOutput = fileHandle
            process.standardError = fileHandle
        }
        
        do {
            try process.run()
            self.engineProcess = process
            print("[+] Backend engine launched successfully (PID: \(process.processIdentifier)).")
        } catch {
            print("[!] Failed to launch embedded backend engine: \(error)")
        }
    }
    
    /// Stops the engine this app launched. SIGTERM lets uvicorn run its shutdown hook, which stops
    /// whisper-server. An engine started manually from a terminal is left alone.
    func stopEngine() {
        if let process = engineProcess, process.isRunning {
            process.terminate()
            engineProcess = nil
        }
    }
}
