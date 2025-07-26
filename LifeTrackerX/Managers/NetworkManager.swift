import Foundation

class NetworkManager {
    static let shared = NetworkManager()
    private let authService = AuthService.shared
    private let secureStorage = SecureStorageManager.shared
    
    private init() {}
    
    func makeAuthenticatedRequest<T: Decodable>(_ endpoint: String, method: String = "GET", body: Data? = nil) async throws -> T {
        guard let accessToken = secureStorage.getAccessToken() else {
            throw AuthError.unauthorized
        }
        
        let headers = [
            "Authorization": "Bearer \(accessToken)"
        ]
        
        guard let request = authService.createRequest(endpoint, method: method, body: body, headers: headers) else {
            throw AuthError.invalidURL
        }
        
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
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
            
            guard httpResponse.statusCode == 200 else {
                throw AuthError.unknown
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: responseData)
        } catch let error as DecodingError {
            throw AuthError.decodingError(error)
        } catch {
            throw AuthError.networkError(error)
        }
    }
} 