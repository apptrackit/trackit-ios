import Foundation

/**
 Bundle extension for easy access to app version information.
 
 This extension provides convenient access to the app's version and build number
 that are automatically synced with Xcode's project settings.
 
 To update the version and build number:
 1. Open the project in Xcode
 2. Select the project in the navigator
 3. Select the target
 4. Go to the "General" tab
 5. Update "Version" (marketing version) and "Build" (build number)
 6. Build and run the app
 
 The changes will automatically appear in the Account settings.
 */
extension Bundle {
    /// Returns the marketing version (CFBundleShortVersionString) from the app's Info.plist
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    /// Returns the build number (CFBundleVersion) from the app's Info.plist
    var buildNumber: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    /// Returns a formatted version string combining version and build number
    var versionString: String {
        return "\(appVersion) (\(buildNumber))"
    }
} 