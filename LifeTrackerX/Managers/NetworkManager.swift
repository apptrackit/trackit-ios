import Foundation
import os.log

class NetworkManager {
    static let shared = NetworkManager()
    private let authService = AuthService.shared
    private let secureStorage = SecureStorageManager.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NetworkManager")
    
    private init() {}
    
    func makeAuthenticatedRequest<T: Decodable>(_ endpoint: String, method: String = "GET", body: Data? = nil) async throws -> T {
        logger.debug("Making authenticated request to: \(endpoint) with method: \(method)")
        
        guard let accessToken = secureStorage.getAccessToken() else {
            throw AuthError.unauthorized
        }
        
        let headers = [
            "Authorization": "Bearer \(accessToken)"
        ]
        
        // Log request body if present
        if let body = body, let bodyString = String(data: body, encoding: .utf8) {
            logger.debug("Request body: \(bodyString)")
        }
        
        guard let request = authService.createRequest(endpoint, method: method, body: body, headers: headers) else {
            throw AuthError.invalidURL
        }
        
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            // Log response details
            logger.debug("Response status code: \(httpResponse.statusCode)")
            logger.debug("Response headers: \(httpResponse.allHeaderFields)")
            
            if let responseString = String(data: responseData, encoding: .utf8) {
                logger.debug("Response body: \(responseString)")
            }
            
            // Handle token expiration
            if httpResponse.statusCode == 401 {
                // Try to refresh the token
                if let refreshToken = secureStorage.getRefreshToken(),
                   let deviceId = secureStorage.getDeviceId() {
                    let refreshResponse = try await authService.refreshToken(refreshToken: refreshToken, deviceId: deviceId)
                    
                    // Save new tokens
                    secureStorage.saveAccessToken(refreshResponse.accessToken)
                    secureStorage.saveRefreshToken(refreshResponse.refreshToken)
                    
                    // Retry the original request with new token
                    return try await makeAuthenticatedRequest(endpoint, method: method, body: body)
                } else {
                    throw AuthError.unauthorized
                }
            }
            
            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                throw AuthError.unknown
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: responseData)
        } catch let error as DecodingError {
            logger.error("Decoding error: \(error.localizedDescription)")
            throw AuthError.decodingError(error)
        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            throw AuthError.networkError(error)
        }
    }
} 