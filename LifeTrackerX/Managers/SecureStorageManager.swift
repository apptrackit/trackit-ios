import Foundation
import Security
import os.log

class SecureStorageManager {
    static let shared = SecureStorageManager()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SecureStorage")
    
    // Dedicated service identifier for Keychain items
    private let keychainService = Bundle.main.bundleIdentifier! + ".keychain"
    
    private init() {}
    
    enum KeychainError: Error {
        case duplicateEntry
        case unknown(OSStatus)
        case itemNotFound
    }
    
    // MARK: - Keychain Operations
    
    private func saveToKeychain(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrService as String: keychainService,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // First try to delete any existing item
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            logger.debug("Successfully saved data to Keychain for key: \(key)")
            return true
        } else {
            logger.error("Failed to save data to Keychain for key: \(key), status: \(status)")
            return false
        }
    }
    
    private func loadFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            logger.debug("Successfully loaded data from Keychain for key: \(key)")
            return result as? Data
        } else {
            logger.error("Failed to load data from Keychain for key: \(key), status: \(status)")
            return nil
        }
    }
    
    private func deleteFromKeychain(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: keychainService
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            logger.info("Successfully deleted data from Keychain for key: \(key)")
            return true
        } else {
            logger.error("Failed to delete data from Keychain for key: \(key), status: \(status)")
            return false
        }
    }
    
    // MARK: - Token Management
    
    func saveTokens(accessToken: String, refreshToken: String) {
        logger.info("Saving tokens to Keychain")
        
        let encoder = JSONEncoder()
        let tokens = ["accessToken": accessToken, "refreshToken": refreshToken]
        
        do {
            let data = try encoder.encode(tokens)
            if saveToKeychain(key: "auth_tokens", data: data) {
                logger.info("Tokens saved successfully")
            } else {
                logger.error("Failed to save tokens")
            }
        } catch {
            logger.error("Failed to encode tokens: \(error.localizedDescription)")
        }
    }
    
    func getTokens() -> (accessToken: String?, refreshToken: String?)? {
        logger.info("Retrieving tokens from Keychain")
        
        guard let data = loadFromKeychain(key: "auth_tokens") else {
            logger.error("No tokens found in Keychain")
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let tokens = try decoder.decode([String: String].self, from: data)
            logger.info("Tokens retrieved successfully")
            return (tokens["accessToken"], tokens["refreshToken"])
        } catch {
            logger.error("Failed to decode tokens: \(error.localizedDescription)")
            return nil
        }
    }
    
    func clearTokens() {
        logger.info("Clearing tokens from Keychain")
        if deleteFromKeychain(key: "auth_tokens") {
            logger.info("Tokens cleared successfully")
        } else {
            logger.error("Failed to clear tokens")
        }
    }
    
    // MARK: - User Data Management
    
    func saveUserData(_ user: User) {
        logger.info("Saving user data to Keychain")
        
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(user)
            if saveToKeychain(key: "user_data", data: data) {
                logger.info("User data saved successfully")
            } else {
                logger.error("Failed to save user data")
            }
        } catch {
            logger.error("Failed to encode user data: \(error.localizedDescription)")
        }
    }
    
    func getUserData() -> User? {
        logger.info("Retrieving user data from Keychain")
        
        guard let data = loadFromKeychain(key: "user_data") else {
            logger.error("No user data found in Keychain")
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let user = try decoder.decode(User.self, from: data)
            logger.info("User data retrieved successfully")
            return user
        } catch {
            logger.error("Failed to decode user data: \(error.localizedDescription)")
            return nil
        }
    }
    
    func clearUserData() {
        logger.info("Clearing user data from Keychain")
        if deleteFromKeychain(key: "user_data") {
            logger.info("User data cleared successfully")
        } else {
            logger.error("Failed to clear user data")
        }
    }
    
    // MARK: - Device ID Management
    
    func saveDeviceId(_ deviceId: String) {
        logger.info("Saving device ID to Keychain")
        if let data = deviceId.data(using: .utf8) {
            if saveToKeychain(key: "device_id", data: data) {
                logger.info("Device ID saved successfully")
            } else {
                logger.error("Failed to save device ID")
            }
        }
    }
    
    func getDeviceId() -> String? {
        logger.info("Retrieving device ID from Keychain")
        
        guard let data = loadFromKeychain(key: "device_id") else {
            logger.error("No device ID found in Keychain")
            return nil
        }
        
        if let deviceId = String(data: data, encoding: .utf8) {
            logger.info("Device ID retrieved successfully")
            return deviceId
        } else {
            logger.error("Failed to decode device ID")
            return nil
        }
    }
    
    func clearDeviceId() {
        logger.info("Clearing device ID from Keychain")
        if deleteFromKeychain(key: "device_id") {
            logger.info("Device ID cleared successfully")
        } else {
            logger.error("Failed to clear device ID")
        }
    }
    
    // MARK: - Clear All Data
    
    func clearAllData() {
        logger.info("Clearing all data from Keychain")
        clearTokens()
        clearUserData()
        clearDeviceId()
        logger.info("All data cleared successfully")
    }
    
    // MARK: - Public Methods
    
    func saveAuthData(_ authData: LoginResponse) {
        logger.info("Saving auth data to Keychain")
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(authData)
            if saveToKeychain(key: "authData", data: data) {
                logger.info("Auth data saved successfully")
            } else {
                logger.error("Failed to save auth data")
            }
        } catch {
            logger.error("Failed to encode auth data: \(error.localizedDescription)")
        }
    }
    
    func getAuthData() -> LoginResponse? {
        logger.info("Retrieving auth data from Keychain")
        guard let data = loadFromKeychain(key: "authData") else {
            logger.error("No auth data found in Keychain")
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let authData = try decoder.decode(LoginResponse.self, from: data)
            logger.info("Auth data retrieved successfully")
            return authData
        } catch {
            logger.error("Failed to decode auth data: \(error.localizedDescription)")
            return nil
        }
    }
    
    func clearAuthData() {
        logger.info("Clearing auth data from Keychain")
        
        // List of all auth-related keys to delete
        let keysToDelete = [
            "authData",
            "accessToken",
            "refreshToken",
            "deviceId",
            "apiKey"
        ]
        
        var success = true
        for key in keysToDelete {
            if !deleteFromKeychain(key: key) {
                logger.error("Failed to delete data from Keychain for key: \(key)")
                success = false
            }
        }
        
        if success {
            logger.info("Successfully cleared all authentication data")
        } else {
            logger.error("Failed to clear some authentication data")
        }
    }
    
    func saveAccessToken(_ token: String) {
        logger.info("Saving access token to Keychain")
        if let data = token.data(using: .utf8) {
            if saveToKeychain(key: "accessToken", data: data) {
                logger.info("Access token saved successfully")
            } else {
                logger.error("Failed to save access token")
            }
        }
    }
    
    func getAccessToken() -> String? {
        logger.info("Retrieving access token from Keychain")
        guard let data = loadFromKeychain(key: "accessToken") else {
            logger.error("No access token found in Keychain")
            return nil
        }
        
        if let token = String(data: data, encoding: .utf8) {
            logger.info("Access token retrieved successfully")
            return token
        } else {
            logger.error("Failed to decode access token")
            return nil
        }
    }
    
    func saveRefreshToken(_ token: String) {
        logger.info("Saving refresh token to Keychain")
        if let data = token.data(using: .utf8) {
            if saveToKeychain(key: "refreshToken", data: data) {
                logger.info("Refresh token saved successfully")
            } else {
                logger.error("Failed to save refresh token")
            }
        }
    }
    
    func getRefreshToken() -> String? {
        logger.info("Retrieving refresh token from Keychain")
        guard let data = loadFromKeychain(key: "refreshToken") else {
            logger.error("No refresh token found in Keychain")
            return nil
        }
        
        if let token = String(data: data, encoding: .utf8) {
            logger.info("Refresh token retrieved successfully")
            return token
        } else {
            logger.error("Failed to decode refresh token")
            return nil
        }
    }
    
    func saveApiKey(_ apiKey: String) {
        logger.info("Saving API key to Keychain")
        if let data = apiKey.data(using: .utf8) {
            if saveToKeychain(key: "apiKey", data: data) {
                logger.info("API key saved successfully")
            } else {
                logger.error("Failed to save API key")
            }
        }
    }
    
    func getApiKey() -> String? {
        logger.info("Retrieving API key from Keychain")
        guard let data = loadFromKeychain(key: "apiKey") else {
            logger.error("No API key found in Keychain")
            return nil
        }
        
        if let apiKey = String(data: data, encoding: .utf8) {
            logger.info("API key retrieved successfully")
            return apiKey
        } else {
            logger.error("Failed to decode API key")
            return nil
        }
    }
} 