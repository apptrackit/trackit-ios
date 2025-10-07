import Foundation
import SwiftUI
import os.log

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var isInitializing = true
    @Published var errorMessage: String?
    @Published var user: User?
    
    private let authService = AuthService.shared
    private let secureStorage = SecureStorageManager.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Auth")
    
    init() {
        logger.info("AuthViewModel initialized")
        Task {
            await checkExistingSession()
        }
    }
    
    func login(username: String, password: String) async {
        logger.info("Attempting login for user: \(username)")
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await authService.login(username: username, password: password)
            logger.info("Login successful for user: \(response.user.username)")
            
            // Log received tokens
            logger.debug("Received access token: \(response.accessToken.prefix(10))...")
            logger.debug("Received refresh token: \(response.refreshToken.prefix(10))...")
            logger.debug("Received device ID: \(response.deviceId)")
            
            // Save authentication data
            secureStorage.saveAuthData(response)
            secureStorage.saveAccessToken(response.accessToken)
            secureStorage.saveRefreshToken(response.refreshToken)
            secureStorage.saveDeviceId(response.deviceId)
            logger.info("Successfully saved all authentication data")
            
            user = response.user
            isAuthenticated = true
            logger.info("Login process completed successfully")
            
            // Load user's metrics from server in background (non-blocking)
            Task {
                await loadUserDataFromServer()
            }
        } catch {
            logger.error("Login failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func register(username: String, email: String, password: String) async {
        logger.info("Attempting registration for user: \(username)")
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await authService.register(username: username, email: email, password: password)
            logger.info("Registration successful for user: \(response.user.username)")
            
            // Log received tokens
            logger.debug("Received access token: \(response.accessToken.prefix(10))...")
            logger.debug("Received refresh token: \(response.refreshToken.prefix(10))...")
            logger.debug("Received device ID: \(response.deviceId)")
            
            // Save authentication data
            secureStorage.saveAuthData(response)
            secureStorage.saveAccessToken(response.accessToken)
            secureStorage.saveRefreshToken(response.refreshToken)
            secureStorage.saveDeviceId(response.deviceId)
            logger.info("Successfully saved all authentication data")
            
            user = response.user
            isAuthenticated = true
            logger.info("Registration process completed successfully")
            
            // Load user's metrics from server in background (non-blocking)
            Task {
                await loadUserDataFromServer()
            }
        } catch {
            logger.error("Registration failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func logout() async {
        logger.info("Attempting logout")
        isLoading = true
        errorMessage = nil
        
        // Try to logout from server (if online), but don't fail if offline
        if let deviceId = secureStorage.getDeviceId(),
           let userId = user?.id,
           let accessToken = secureStorage.getAccessToken() {
            do {
                logger.debug("Logging out with device ID: \(deviceId)")
                logger.debug("Using access token: \(accessToken.prefix(10))...")
                _ = try await authService.logout(deviceId: deviceId, userId: userId, accessToken: accessToken)
                logger.info("Server logout successful")
            } catch {
                // Log the error but continue with local cleanup
                logger.warning("Server logout failed (likely offline): \(error.localizedDescription)")
                logger.info("Continuing with local logout...")
            }
        } else {
            logger.warning("Missing auth data for server logout, proceeding with local cleanup only")
        }
        
        // Always clear all local data, regardless of server response
        await clearAllLocalData()
        
        isAuthenticated = false
        user = nil
        isLoading = false
        logger.info("Logout completed - all local data cleared")
    }
    
    private func clearAllLocalData() async {
        logger.info("Clearing all local data for logout")
        
        // Clear ALL Keychain data for the app
        secureStorage.clearAllKeychainData()
        logger.info("Cleared all Keychain data")
        
        // Clear all metric entries
        StatsHistoryManager.shared.clearAllEntries()
        logger.info("Cleared all metric entries")
        
        // Clear all progress photos
        ProgressPhotoManager.shared.clearAllPhotos()
        logger.info("Cleared all progress photos")
        
        // Clear all pending sync operations
        MetricSyncManager.shared.clearAllPendingOperations()
        logger.info("Cleared all pending sync operations")
        
        // Clear HealthKit sync timestamp
        HealthManager.shared.clearSyncData()
        logger.info("Cleared HealthKit sync data")
        
        // Clear UserDefaults for the app
        clearUserDefaults()
        logger.info("Cleared UserDefaults data")
        
        logger.info("All local data cleared successfully")
    }
    
    private func clearUserDefaults() {
        // Get all UserDefaults keys used by the app and clear them
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()
        logger.info("Removed all UserDefaults for domain: \(domain)")
    }
    
    private func loadUserDataFromServer() async {
        logger.info("Loading user data from server")
        
        // Load metrics from server - this function handles its own errors
        await StatsHistoryManager.shared.loadMetricsFromServer()
        logger.info("User data loading completed (server sync may have failed, but app continues)")
    }
    
    private func checkExistingSession() async {
        logger.info("Checking existing session")
        isInitializing = true
        
        // First, try to restore user from local storage for offline mode
        if let authData = secureStorage.getAuthData() {
            user = authData.user
            isAuthenticated = true
            logger.info("Restored user from local storage: \(authData.user.username)")
        }
        
        // Then try to validate with server (if online)
        do {
            guard let accessToken = secureStorage.getAccessToken() else {
                logger.info("No existing session found")
                isInitializing = false
                return
            }
            
            logger.debug("Found existing access token: \(accessToken.prefix(10))...")
            
            let response = try await authService.checkSession(accessToken: accessToken)
            
            if response.isAuthenticated {
                if let responseUser = response.user {
                    user = responseUser
                    isAuthenticated = true
                    logger.info("Existing session is valid for user: \(responseUser.username)")
                    
                    // Load user's metrics from server in background (non-blocking)
                    Task {
                        await loadUserDataFromServer()
                    }
                } else {
                    // Server says authenticated but no user data - this shouldn't happen
                    logger.error("Server says authenticated but no user data provided")
                    secureStorage.clearAuthData()
                    user = nil
                    isAuthenticated = false
                }
            } else {
                // Server says session is invalid, clear auth data
                secureStorage.clearAuthData()
                user = nil
                isAuthenticated = false
                logger.info("Existing session is invalid, cleared authentication data")
            }
        } catch {
            logger.error("Session check failed (likely offline): \(error.localizedDescription)")
            
            // If we have local user data, allow offline mode
            if self.user != nil {
                logger.info("Allowing offline mode for user: \(self.user?.username ?? "unknown")")
                // Don't clear auth data - let user continue in offline mode
            } else {
                // No local user data and can't reach server, clear everything
                secureStorage.clearAuthData()
                user = nil
                isAuthenticated = false
                logger.info("No local user data and server unreachable, cleared authentication data")
            }
        }
        
        isInitializing = false
    }
    
    func refreshSession() async {
        logger.info("Attempting to refresh session")
        do {
            guard let refreshToken = secureStorage.getRefreshToken(),
                  let deviceId = secureStorage.getDeviceId() else {
                logger.error("Missing refresh token or device ID")
                throw AuthError.unauthorized
            }
            
            logger.debug("Using refresh token: \(refreshToken.prefix(10))...")
            logger.debug("Using device ID: \(deviceId)")
            
            let response = try await authService.refreshToken(refreshToken: refreshToken, deviceId: deviceId)
            
            secureStorage.saveAccessToken(response.accessToken)
            secureStorage.saveRefreshToken(response.refreshToken)
            logger.info("Successfully refreshed session")
            
            isAuthenticated = true
        } catch {
            logger.error("Session refresh failed: \(error.localizedDescription)")
            isAuthenticated = false
            secureStorage.clearAuthData()
        }
    }
} 