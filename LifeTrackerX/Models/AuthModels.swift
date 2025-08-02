import Foundation

struct LoginRequest: Codable {
    let username: String
    let password: String
}

struct RegisterRequest: Codable {
    let username: String
    let email: String
    let password: String
}

struct ErrorResponse: Codable {
    let success: Bool
    let message: String?
    let error: String?
}

struct RegisterResponse: Codable {
    let success: Bool
    let authenticated: Bool
    let message: String
    let accessToken: String
    let refreshToken: String
    let deviceId: String
    let user: User
    
    enum CodingKeys: String, CodingKey {
        case success, authenticated, message
        case accessToken = "accessToken"
        case refreshToken = "refreshToken"
        case deviceId = "deviceId"
        case user
    }
}

struct LoginResponse: Codable {
    let success: Bool
    let authenticated: Bool
    let message: String
    let accessToken: String
    let refreshToken: String
    let deviceId: String
    let user: User
    
    enum CodingKeys: String, CodingKey {
        case success, authenticated, message
        case accessToken = "accessToken"
        case refreshToken = "refreshToken"
        case deviceId = "deviceId"
        case user
    }
}

struct User: Codable {
    let id: Int
    let username: String
    let email: String
}

struct SessionCheckResponse: Codable {
    let success: Bool
    let isAuthenticated: Bool
    let message: String
    let deviceId: String?
    let user: User?
}

struct RefreshTokenRequest: Codable {
    let refreshToken: String
    let deviceId: String
}

struct RefreshTokenResponse: Codable {
    let success: Bool
    let accessToken: String
    let refreshToken: String
    let deviceId: String
}

struct LogoutRequest: Codable {
    let deviceId: String
    let userId: Int
}

struct LogoutResponse: Codable {
    let success: Bool
    let message: String
} 