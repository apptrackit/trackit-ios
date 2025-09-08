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

    // MARK: - Multipart Upload (Images)
    func uploadImage(endpoint: String = "/api/images", imageData: Data, imageTypeId: Int, uploadedAtISO8601: String?) async throws -> ImageUploadResponse {
        // Preflight size check: 10 MB
        let maxBytes = 10 * 1024 * 1024
        if imageData.count > maxBytes {
            throw NSError(domain: "ImageUpload", code: 413, userInfo: [NSLocalizedDescriptionKey: "Image exceeds 10MB limit"])
        }

        guard let accessToken = secureStorage.getAccessToken() else {
            throw AuthError.unauthorized
        }

        // Build multipart/form-data body
        let boundary = "Boundary-\(UUID().uuidString)"
        var requestBody = Data()
        func appendField(name: String, value: String) {
            if let fieldData = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8) {
                requestBody.append(fieldData)
            }
        }
        func appendFileField(name: String, filename: String, mimeType: String, data: Data) {
            if let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8) {
                requestBody.append(header)
            }
            requestBody.append(data)
            if let tail = "\r\n".data(using: .utf8) { requestBody.append(tail) }
        }

        appendField(name: "imageTypeId", value: String(imageTypeId))
        if let uploadedAtISO8601 = uploadedAtISO8601 { appendField(name: "uploadedAt", value: uploadedAtISO8601) }
        appendFileField(name: "file", filename: "image.jpg", mimeType: "image/jpeg", data: imageData)
        if let closing = "--\(boundary)--\r\n".data(using: .utf8) { requestBody.append(closing) }

        guard var request = authService.createRequest(endpoint, method: "POST", body: requestBody, headers: [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": "multipart/form-data; boundary=\(boundary)"
        ]) else {
            throw AuthError.invalidURL
        }

        // Use longer timeout for uploads
        request.timeoutInterval = 60

        logger.debug("Uploading image to: \(endpoint) with typeId: \(imageTypeId), size: \(imageData.count) bytes")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.invalidResponse }

        // If unauthorized, try token refresh then retry once
        if httpResponse.statusCode == 401,
           let refreshToken = secureStorage.getRefreshToken(),
           let deviceId = secureStorage.getDeviceId() {
            let refreshResponse = try await authService.refreshToken(refreshToken: refreshToken, deviceId: deviceId)
            secureStorage.saveAccessToken(refreshResponse.accessToken)
            secureStorage.saveRefreshToken(refreshResponse.refreshToken)
            return try await uploadImage(endpoint: endpoint, imageData: imageData, imageTypeId: imageTypeId, uploadedAtISO8601: uploadedAtISO8601)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to decode error response
            if let decoded = try? JSONDecoder().decode(ImageUploadResponse.self, from: responseData) {
                return decoded
            }
            throw AuthError.unknown
        }

        let decoded = try JSONDecoder().decode(ImageUploadResponse.self, from: responseData)
        return decoded
    }

    func listImages(limit: Int = 100, offset: Int = 0) async throws -> ImagesListResponse {
        let endpoint = "/api/images?limit=\(limit)&offset=\(offset)"
        return try await makeAuthenticatedRequest(endpoint, method: "GET")
    }

    func deleteImage(id: Int) async throws -> BasicResponse {
        return try await makeAuthenticatedRequest("/api/images/\(id)", method: "DELETE")
    }

    func downloadImage(id: Int) async throws -> Data {
        guard let accessToken = secureStorage.getAccessToken() else {
            throw AuthError.unauthorized
        }
        guard let request = authService.createRequest("/api/images/\(id)/download", method: "GET", headers: [
            "Authorization": "Bearer \(accessToken)"
        ]) else { throw AuthError.invalidURL }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.unknown
        }
        return data
    }
} 