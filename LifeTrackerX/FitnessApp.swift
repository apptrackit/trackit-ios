import SwiftUI

// App Delegate to handle orientation lock
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

@main
struct FitnessApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate: AppDelegate
    
    init() {
        // Force portrait orientation for the entire app
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        AppDelegate.orientationLock = .portrait
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
