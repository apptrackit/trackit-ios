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
    @StateObject private var authViewModel = AuthViewModel()
    @AppStorage("selectedTheme") private var selectedThemeRaw: String = "system"
    
    init() {
        // Force portrait orientation for the entire app using modern approach
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
        AppDelegate.orientationLock = .portrait
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isInitializing {
                    LoadingView()
                } else if authViewModel.isAuthenticated {
                    MainTabView()
                        .environmentObject(authViewModel)
                } else {
                    LoginView()
                        .environmentObject(authViewModel)
                }
            }
            .preferredColorScheme(selectedColorScheme)
        }
    }
}

private extension FitnessApp {
    var selectedColorScheme: ColorScheme? {
        switch selectedThemeRaw {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}
