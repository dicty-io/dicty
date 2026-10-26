import Foundation
import AppKit

/// Unified, resilient resource locator for Dicty.
///
/// In standalone macOS `.app` bundles, Swift Package Manager's auto-generated `Bundle.module`
/// can trigger a fatal assertion (`fatalError`) if the package bundle is not present at the root
/// of `Bundle.main.bundleURL`.
///
/// `DictyResources` safely searches:
/// 1. `Bundle.main` (`Contents/Resources/` in production macOS apps)
/// 2. `Contents/Resources/DictyClient_Dicty.bundle`
/// 3. App bundle root (`DictyClient_Dicty.bundle`)
/// 4. Only touches `Bundle.module` in debug/CLI mode if the target directory actually exists on disk.
enum DictyResources {
    
    /// Safely locates a resource URL without risking SPM's fatal assertion.
    static func url(forResource name: String, withExtension ext: String?) -> URL? {
        // 1. Direct resource in main bundle (Contents/Resources/)
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        
        // 2. Sub-bundle in Contents/Resources/DictyClient_Dicty.bundle
        if let subBundleURL = Bundle.main.url(forResource: "DictyClient_Dicty", withExtension: "bundle"),
           let subBundle = Bundle(url: subBundleURL),
           let url = subBundle.url(forResource: name, withExtension: ext) {
            return url
        }
        
        // 3. Sub-bundle at app root (Bundle.main.bundleURL/DictyClient_Dicty.bundle)
        let rootBundleURL = Bundle.main.bundleURL.appendingPathComponent("DictyClient_Dicty.bundle")
        if let rootBundle = Bundle(url: rootBundleURL),
           let url = rootBundle.url(forResource: name, withExtension: ext) {
            return url
        }
        
        // 4. In debug/CLI mode, verify whether Bundle.module's expected bundle path actually exists
        // before referencing Bundle.module, preventing Swift.fatalError in SPM's static accessor.
        let spmBundlePath = Bundle.main.bundleURL.appendingPathComponent("DictyClient_Dicty.bundle").path
        if FileManager.default.fileExists(atPath: spmBundlePath) {
            return Bundle.module.url(forResource: name, withExtension: ext)
        }
        
        return nil
    }
    
    /// Safely locates a resource file path without risking SPM's fatal assertion.
    static func path(forResource name: String, ofType type: String?) -> String? {
        return url(forResource: name, withExtension: type)?.path
    }
    
    /// Safely loads an NSImage from bundled resources or system/named assets.
    static func image(named name: String, extension ext: String = "png") -> NSImage? {
        if let fileURL = url(forResource: name, withExtension: ext),
           let img = NSImage(contentsOf: fileURL) {
            return img
        }
        return NSImage(named: name)
    }
}
