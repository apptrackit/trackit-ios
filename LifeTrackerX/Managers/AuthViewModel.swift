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
        
        do {
            guard let deviceId = secureStorage.getDeviceId(),
                  let userId = user?.id,
                  let accessToken = secureStorage.getAccessToken() else {
                logger.error("Missing required data for logout")
                throw AuthError.unknown
            }
            
            logger.debug("Logging out with device ID: \(deviceId)")
            logger.debug("Using access token: \(accessToken.prefix(10))...")
            _ = try await authService.logout(deviceId: deviceId, userId: userId, accessToken: accessToken)
            
            // Clear stored data
            secureStorage.clearAuthData()
            logger.info("Successfully cleared authentication data")
            
            isAuthenticated = false
            user = nil
            logger.info("Logout completed successfully")
        } catch {
            logger.error("Logout failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func checkExistingSession() async {
        logger.info("Checking existing session")
        isInitializing = true
        do {
            guard let accessToken = secureStorage.getAccessToken() else {
                logger.info("No existing session found")
                isInitializing = false
                return
            }
            
            logger.debug("Found existing access token: \(accessToken.prefix(10))...")
            
            let response = try await authService.checkSession(accessToken: accessToken)
            
            if response.isAuthenticated {
                user = response.user
                isAuthenticated = true
                logger.info("Existing session is valid for user: \(response.user.username)")
            } else {
                secureStorage.clearAuthData()
                logger.info("Existing session is invalid, cleared authentication data")
            }
        } catch {
            logger.error("Session check failed: \(error.localizedDescription)")
            secureStorage.clearAuthData()
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