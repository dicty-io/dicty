import Foundation
import Combine

struct BackendUpdateResponse: Codable {
    let hasUpdate: Bool
    let latestVersion: String
    let releaseNotes: String
    let downloadUrl: String?
    let assetName: String?
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case hasUpdate = "has_update"
        case latestVersion = "latest_version"
        case releaseNotes = "release_notes"
        case downloadUrl = "download_url"
        case assetName = "asset_name"
        case error = "error"
    }
}

// GitHub API Models for direct fallback
private struct GitHubRelease: Codable {
    let tagName: String
    let body: String?
    let assets: [GitHubAsset]
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }
}

private struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}

@MainActor
class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var releaseNotes: String = ""
    @Published var downloadURL: String? = nil
    @Published var assetName: String? = nil
    
    @Published var isChecking: Bool = false
    @Published var isApplying: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var lastCheckError: String? = nil
    
    private let engineUpdateCheckURL = EngineEndpoint.shared.url("/update/check")
    private let engineUpdateApplyURL = EngineEndpoint.shared.url("/update/apply")
    private let engineUpdateProgressURL = EngineEndpoint.shared.url("/update/progress")
    private var progressTimer: Timer?
    private var downloadCompletedSince: Date? = nil
    
    private static func parseVersion(_ version: String) -> (Int, Int, Int, Int) {
        let clean = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        var serial = 0
        var base = clean
        if clean.contains("-") {
            let parts = clean.split(separator: "-", maxSplits: 1)
            base = String(parts[0])
            let suffix = String(parts[1])
            var digits = ""
            for ch in suffix {
                if ch.isNumber { digits.append(ch) } else { break }
            }
            serial = Int(digits) ?? 0
        }
        let parts = base.split(separator: ".").compactMap { Int($0) }
        let p0 = parts.count > 0 ? parts[0] : 0
        let p1 = parts.count > 1 ? parts[1] : 0
        let p2 = parts.count > 2 ? parts[2] : 0
        return (p0, p1, p2, serial)
    }

    private static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let p1 = parseVersion(v1)
        let p2 = parseVersion(v2)
        if p1.0 != p2.0 { return p1.0 > p2.0 }
        if p1.1 != p2.1 { return p1.1 > p2.1 }
        if p1.2 != p2.2 { return p1.2 > p2.2 }
        return p1.3 > p2.3
    }
    
    var currentVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.11"
    }
    
    func checkForUpdates(manual: Bool = false) {
        if isChecking { return }
        isChecking = true
        lastCheckError = nil
        
        Task {
            // First attempt: Check via local Python engine
            do {
                guard var components = URLComponents(url: engineUpdateCheckURL, resolvingAgainstBaseURL: false) else { return }
                components.queryItems = [URLQueryItem(name: "current_version", value: currentVersion)]
                guard let url = components.url else { return }
                
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 4.0
                
                let (data, response) = try await EngineEndpoint.shared.session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    let release = try decoder.decode(BackendUpdateResponse.self, from: data)
                    
                    // If the backend has an update but missing downloadUrl, fall through to direct GitHub
                    if release.error == nil && (!release.hasUpdate || release.downloadUrl != nil) {
                        self.latestVersion = release.latestVersion
                        self.releaseNotes = release.releaseNotes
                        self.downloadURL = release.downloadUrl
                        self.assetName = release.assetName
                        self.updateAvailable = release.hasUpdate && (release.downloadUrl != nil)
                        self.isChecking = false
                        return
                    }
                }
            } catch {
                print("[UpdateChecker] Local engine update check failed, trying direct GitHub API fallback...")
            }
            
            // Second attempt (Fallback): Check directly via GitHub Releases API
            await checkDirectGitHub(manual: manual)
        }
    }
    
    private func checkDirectGitHub(manual: Bool) async {
        let githubUrls = [
            "https://api.github.com/repos/dicty-io/dicty/releases?per_page=30",
            "https://api.github.com/repos/kazminv/dicty-releases/releases?per_page=30",
            "https://api.github.com/repos/vkazmin1/dicty/releases?per_page=30",
            "https://api.github.com/repos/dicty-io/dicty/releases/latest",
            "https://api.github.com/repos/kazminv/dicty-releases/releases/latest"
        ]
        
        for urlString in githubUrls {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.setValue("DictyApp/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 6.0
            
            do {
                let (data, response) = try await EngineEndpoint.shared.session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    continue
                }
                
                var releases: [GitHubRelease] = []
                if let list = try? JSONDecoder().decode([GitHubRelease].self, from: data) {
                    releases = list
                } else if let single = try? JSONDecoder().decode(GitHubRelease.self, from: data) {
                    releases = [single]
                } else {
                    continue
                }
                
                if releases.isEmpty { continue }
                
                // Sort releases descending by semver
                releases.sort { UpdateChecker.isVersion($0.tagName, greaterThan: $1.tagName) }
                
                // Find latest release with macOS DMG
                for release in releases {
                    if let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") || $0.name.hasSuffix(".pkg") }) {
                        let latestVer = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                        let currentClean = currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                        let hasUpdate = UpdateChecker.isVersion(latestVer, greaterThan: currentClean)
                        
                        self.latestVersion = latestVer
                        self.releaseNotes = release.body ?? ""
                        self.downloadURL = dmgAsset.browserDownloadUrl
                        self.assetName = dmgAsset.name
                        self.updateAvailable = hasUpdate
                        self.lastCheckError = nil
                        self.isChecking = false
                        return
                    }
                }
            } catch {
                print("[UpdateChecker] Direct GitHub check failed for \(urlString): \(error)")
            }
        }
        
        self.lastCheckError = "Unable to fetch latest release information."
        self.isChecking = false
    }
    
    func applyUpdate() {
        if isApplying { return }
        
        if downloadURL == nil || assetName == nil {
            isChecking = true
            Task {
                checkForUpdates(manual: true)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    if let url = self.downloadURL, let asset = self.assetName {
                        self.executeApply(url: url, asset: asset)
                    } else {
                        self.lastCheckError = "Installer package is not available for download yet. Please try again shortly."
                    }
                }
            }
            return
        }
        
        guard let url = downloadURL, let asset = assetName else {
            self.lastCheckError = "Installer package is not available for download."
            return
        }
        executeApply(url: url, asset: asset)
    }
    
    private func executeApply(url: String, asset: String) {
        isApplying = true
        lastCheckError = nil
        downloadProgress = 0.0
        
        Task {
            do {
                guard var components = URLComponents(url: engineUpdateApplyURL, resolvingAgainstBaseURL: false) else { return }
                components.queryItems = [
                    URLQueryItem(name: "download_url", value: url),
                    URLQueryItem(name: "asset_name", value: asset)
                ]
                guard let applyUrl = components.url else { return }
                
                var request = URLRequest(url: applyUrl)
                request.httpMethod = "POST"
                request.timeoutInterval = 30.0
                
                let (data, response) = try await EngineEndpoint.shared.session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (httpResponse.statusCode == 200 || httpResponse.statusCode == 201) else {
                    throw URLError(.badServerResponse)
                }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let status = json["status"] as? String
                    let success = json["success"] as? Bool ?? (status == "success")
                    if !success {
                        let err = json["error"] as? String ?? json["message"] as? String ?? "Failed to apply update."
                        await MainActor.run {
                            self.lastCheckError = err
                            self.isApplying = false
                        }
                        return
                    }
                }
                
                // Backend confirmed update download initiated; begin polling progress
                await MainActor.run {
                    self.startPollingProgress()
                }
            } catch {
                print("[UpdateChecker] Error applying update: \(error)")
                await MainActor.run {
                    self.lastCheckError = "Update failed to execute."
                    self.isApplying = false
                }
            }
        }
    }
    
    private func startPollingProgress() {
        progressTimer?.invalidate()
        downloadCompletedSince = nil
        
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if !self.isApplying {
                    self.progressTimer?.invalidate()
                    return
                }
                do {
                    let (data, _) = try await EngineEndpoint.shared.session.data(from: self.engineUpdateProgressURL)
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let error = json["error"] as? String, !error.isEmpty {
                            self.lastCheckError = "Download failed: \(error)"
                            self.isApplying = false
                            self.progressTimer?.invalidate()
                            return
                        }
                        
                        if let progress = json["progress"] as? Double {
                            self.downloadProgress = progress
                            if progress >= 100.0 {
                                if self.downloadCompletedSince == nil {
                                    self.downloadCompletedSince = Date()
                                } else if let start = self.downloadCompletedSince, Date().timeIntervalSince(start) > 40.0 {
                                    self.lastCheckError = "Update finished downloading, but relaunch timed out. Please restart Dicty manually."
                                    self.isApplying = false
                                    self.progressTimer?.invalidate()
                                }
                            } else {
                                self.downloadCompletedSince = nil
                            }
                        }
                    }
                } catch {
                    // Ignore transient network poll errors during restart
                }
            }
        }
    }
}
