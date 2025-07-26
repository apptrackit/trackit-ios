import Foundation
import os.log

enum AuthError: Error {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case unauthorized
    case unknown
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized access"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

class AuthService {
    static let shared = AuthService()
    private let baseURL = "http://dev.ballabotond.com:3000"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AuthService")
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10 // 10 seconds timeout
        config.timeoutIntervalForResource = 30 // 30 seconds timeout for the entire resource
        config.waitsForConnectivity = true // Wait for connectivity if offline
        self.session = URLSession(configuration: config)
    }
    
    func createRequest(_ endpoint: String, method: String, body: Data? = nil, headers: [String: String] = [:]) -> URLRequest? {
        let fullURL = baseURL + endpoint
        logger.debug("Creating request to: \(fullURL)")
        
        guard let url = URL(string: fullURL) else {
            logger.error("Failed to create URL from: \(fullURL)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10 // 10 seconds timeout for this specific request
        
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        // Log request details
        logger.debug("Request method: \(method)")
        logger.debug("Request headers: \(headers)")
        if let body = body, let bodyString = String(data: body, encoding: .utf8) {
            logger.debug("Request body: \(bodyString)")
        }
        
        return request
    }
    
    func login(username: String, password: String) async throws -> LoginResponse {
        logger.info("Attempting login for username: \(username)")
        
        let loginRequest = LoginRequest(username: username, password: password)
        let encoder = JSONEncoder()
        let data = try encoder.encode(loginRequest)
        
        guard let request = createRequest("/auth/login", method: "POST", body: data) else {
            logger.error("Failed to create login request")
            throw AuthError.invalidURL
        }
        
        do {
            let (responseData, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response type")
                throw AuthError.invalidResponse
            }
            
            logger.debug("Login response status code: \(httpResponse.statusCode)")
            
            if let responseString = String(data: responseData, encoding: .utf8) {
                logger.debug("Login response body: \(responseString)")
            }
            
            guard httpResponse.statusCode == 200 else {
                logger.error("Login failed with status code: \(httpResponse.statusCode)")
                throw AuthError.unauthorized
            }
            
            let decoder = JSONDecoder()
            let loginResponse = try decoder.decode(LoginResponse.self, from: responseData)
            logger.info("Login successful for user: \(loginResponse.user.username)")
            return loginResponse
        } catch let error as URLError {
            logger.error("Network error during login: \(error.localizedDescription)")
            switch error.code {
            case .notConnectedToInternet:
                throw AuthError.networkError(error)
            case .timedOut:
                throw AuthError.networkError(error)
            case .cannotConnectToHost:
                throw AuthError.networkError(error)
            default:
                throw AuthError.networkError(error)
            }
        } catch let error as DecodingError {
            logger.error("Failed to decode login response: \(error.localizedDescription)")
            throw AuthError.decodingError(error)
        } catch {
            logger.error("Login request failed: \(error.localizedDescription)")
            throw AuthError.networkError(error)
        }
    }
    
    func checkSession(accessToken: String) async throws -> SessionCheckResponse {
        let headers = [
            "Authorization": "Bearer \(accessToken)"
        ]
        
        guard let request = createRequest("/auth/check", method: "GET", headers: headers) else {
            throw AuthError.invalidURL
        }
        
        do {
            let (responseData, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw AuthError.unauthorized
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode(SessionCheckResponse.self, from: responseData)
        } catch let error as URLError {
            logger.error("Network error during session check: \(error.localizedDescription)")
            switch error.code {
            case .notConnectedToInternet:
                throw AuthError.networkError(error)
            case .timedOut:
                throw AuthError.networkError(error)
            case .cannotConnectToHost:
                throw AuthError.networkError(error)
            default:
                throw AuthError.networkError(error)
            }
        } catch let error as DecodingError {
            throw AuthError.decodingError(error)
        } catch {
            throw AuthError.networkError(error)
        }
    }
    
    func refreshToken(refreshToken: String, deviceId: String) async throws -> RefreshTokenResponse {
        let refreshRequest = RefreshTokenRequest(refreshToken: refreshToken, deviceId: deviceId)
        let encoder = JSONEncoder()
        let data = try encoder.encode(refreshRequest)
        
        guard let request = createRequest("/auth/refresh", method: "POST", body: data) else {
            throw AuthError.invalidURL
        }
        
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw AuthError.unauthorized
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode(RefreshTokenResponse.self, from: responseData)
        } catch let error as DecodingError {
            throw AuthError.decodingError(error)
        } catch {
            throw AuthError.networkError(error)
        }
    }
    
    func logout(deviceId: String, userId: Int) async throws -> LogoutResponse {
        let logoutRequest = LogoutRequest(deviceId: deviceId, userId: userId)
        let encoder = JSONEncoder()
        let data = try encoder.encode(logoutRequest)
        
        let headers: [String: String] = [:]
        
        guard let request = createRequest("/auth/logout", method: "POST", body: data, headers: headers) else {
            throw AuthError.invalidURL
        }
        
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw AuthError.unauthorized
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode(LogoutResponse.self, from: responseData)
        } catch let error as DecodingError {
            throw AuthError.decodingError(error)
        } catch {
            throw AuthError.networkError(error)
        }
    }
} 