import Foundation
import Combine
import Network

class BackendSyncManager: ObservableObject {
    static let shared = BackendSyncManager()
    
    private let storage = LocalStorageManager.shared
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isOnline = true
    @Published var syncingStatus: String = "Ready"
    @Published var lastError: String?
    @Published var isAuthenticated = false
    
    // Configuration
    private let baseURL: String
    private let syncQueue = DispatchQueue(label: "com.trackit.backend.sync", qos: .utility)
    private var isSyncing = false
    
    // Authentication
    private var accessToken: String?
    private var refreshToken: String?
    private var deviceId: String
    private var userId: Int?
    
    // Retry logic
    private var retryAttempts: [String: Int] = [:] // Track retry attempts per endpoint
    private let maxRetryAttempts = 3
    private let retryDelays: [TimeInterval] = [1, 3, 9] // Exponential backoff
    
    private init() {
        // Set your backend URL here
        self.baseURL = ProcessInfo.processInfo.environment["BACKEND_URL"] ?? "http://localhost:3000"
        self.deviceId = getOrCreateDeviceId()
        
        setupNetworkMonitoring()
        loadAuthTokens()
        
        print("🌐 Backend sync manager initialized with baseURL: \(baseURL)")
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            
            DispatchQueue.main.async {
                if self?.isOnline != isOnline {
                    self?.isOnline = isOnline
                    self?.storage.syncStatus.isOnline = isOnline
                    
                    if isOnline {
                        print("🌐 Network connection restored")
                        self?.syncingStatus = "Connected"
                        // Trigger sync when connection is restored
                        Task {
                            await self?.performIncrementalSync()
                        }
                    } else {
                        print("🌐 Network connection lost")
                        self?.syncingStatus = "Offline"
                    }
                }
            }
        }
        
        networkMonitor.start(queue: networkQueue)
    }
    
    // MARK: - Device ID Management
    
    private func getOrCreateDeviceId() -> String {
        let key = "TrackIt.DeviceId"
        
        if let existingId = UserDefaults.standard.string(forKey: key) {
            return existingId
        }
        
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
    
    // MARK: - Authentication
    
    func login(username: String, password: String) async -> Bool {
        let endpoint = "/auth/login"
        let body = [
            "username": username,
            "password": password,
            "deviceId": deviceId
        ]
        
        do {
            let response = try await makeRequest(endpoint: endpoint, method: "POST", body: body, requiresAuth: false)
            
            if let data = response["data"] as? [String: Any],
               let accessToken = data["accessToken"] as? String,
               let refreshToken = data["refreshToken"] as? String,
               let user = data["user"] as? [String: Any],
               let userId = user["id"] as? Int {
                
                await MainActor.run {
                    self.accessToken = accessToken
                    self.refreshToken = refreshToken
                    self.userId = userId
                    self.isAuthenticated = true
                    self.syncingStatus = "Authenticated"
                    self.lastError = nil
                }
                
                saveAuthTokens()
                print("✅ Authentication successful for user: \(username)")
                return true
            }
        } catch {
            await MainActor.run {
                self.lastError = "Login failed: \(error.localizedDescription)"
                self.isAuthenticated = false
            }
            print("❌ Login failed: \(error)")
        }
        
        return false
    }
    
    func logout() async {
        guard let accessToken = accessToken else { return }
        
        let endpoint = "/auth/logout"
        let body = ["deviceId": deviceId]
        
        do {
            _ = try await makeRequest(endpoint: endpoint, method: "POST", body: body, requiresAuth: true)
            print("✅ Logout successful")
        } catch {
            print("⚠️ Logout request failed: \(error)")
        }
        
        await MainActor.run {
            self.clearAuth()
        }
    }
    
    private func clearAuth() {
        accessToken = nil
        refreshToken = nil
        userId = nil
        isAuthenticated = false
        syncingStatus = "Not authenticated"
        
        // Clear stored tokens
        UserDefaults.standard.removeObject(forKey: "TrackIt.AccessToken")
        UserDefaults.standard.removeObject(forKey: "TrackIt.RefreshToken")
        UserDefaults.standard.removeObject(forKey: "TrackIt.UserId")
    }
    
    private func loadAuthTokens() {
        accessToken = UserDefaults.standard.string(forKey: "TrackIt.AccessToken")
        refreshToken = UserDefaults.standard.string(forKey: "TrackIt.RefreshToken")
        userId = UserDefaults.standard.object(forKey: "TrackIt.UserId") as? Int
        
        isAuthenticated = (accessToken != nil && refreshToken != nil && userId != nil)
        
        if isAuthenticated {
            print("🔑 Loaded existing authentication tokens")
            syncingStatus = "Authenticated"
        }
    }
    
    private func saveAuthTokens() {
        UserDefaults.standard.set(accessToken, forKey: "TrackIt.AccessToken")
        UserDefaults.standard.set(refreshToken, forKey: "TrackIt.RefreshToken")
        UserDefaults.standard.set(userId, forKey: "TrackIt.UserId")
    }
    
    private func refreshAccessToken() async -> Bool {
        guard let refreshToken = refreshToken else { return false }
        
        let endpoint = "/auth/refresh"
        let body = [
            "refreshToken": refreshToken,
            "deviceId": deviceId
        ]
        
        do {
            let response = try await makeRequest(endpoint: endpoint, method: "POST", body: body, requiresAuth: false)
            
            if let data = response["data"] as? [String: Any],
               let newAccessToken = data["accessToken"] as? String,
               let newRefreshToken = data["refreshToken"] as? String {
                
                await MainActor.run {
                    self.accessToken = newAccessToken
                    self.refreshToken = newRefreshToken
                }
                
                saveAuthTokens()
                print("✅ Access token refreshed")
                return true
            }
        } catch {
            print("❌ Token refresh failed: \(error)")
            await MainActor.run {
                self.clearAuth()
            }
        }
        
        return false
    }
    
    // MARK: - Sync Operations
    
    func performFullSync() async -> Bool {
        guard isAuthenticated else {
            await MainActor.run {
                self.lastError = "Authentication required"
            }
            return false
        }
        
        guard isOnline else {
            await MainActor.run {
                self.lastError = "No network connection"
            }
            return false
        }
        
        guard !isSyncing else {
            print("⚠️ Sync already in progress")
            return false
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        await MainActor.run {
            self.syncingStatus = "Syncing with backend..."
            self.lastError = nil
        }
        
        return await syncQueue.runAsync {
            let success = await self.performSyncOperations(isFullSync: true)
            
            await MainActor.run {
                if success {
                    self.syncingStatus = "Sync completed successfully"
                    self.storage.setSyncTimestamp(backend: Date())
                } else {
                    self.syncingStatus = "Sync completed with errors"
                }
            }
            
            return success
        }
    }
    
    func performIncrementalSync() async -> Bool {
        guard isAuthenticated && isOnline else { return false }
        
        return await syncQueue.runAsync {
            await self.performSyncOperations(isFullSync: false)
        }
    }
    
    private func performSyncOperations(isFullSync: Bool) async -> Bool {
        var allSuccess = true
        
        // Step 1: Push local changes to backend
        let pushSuccess = await pushLocalChangesToBackend()
        if !pushSuccess {
            allSuccess = false
        }
        
        // Step 2: Pull changes from backend
        let pullSuccess = await pullChangesFromBackend(isFullSync: isFullSync)
        if !pullSuccess {
            allSuccess = false
        }
        
        return allSuccess
    }
    
    // MARK: - Push Operations (Local → Backend)
    
    private func pushLocalChangesToBackend() async -> Bool {
        print("📤 Pushing local changes to backend")
        
        let unsyncedMetrics = storage.getUnsyncedBackendMetrics()
        guard !unsyncedMetrics.isEmpty else {
            print("📤 No unsynced metrics to push")
            return true
        }
        
        var successCount = 0
        var failureCount = 0
        
        for metric in unsyncedMetrics {
            let success = await pushSingleMetric(metric)
            if success {
                successCount += 1
            } else {
                failureCount += 1
            }
        }
        
        print("📤 Push completed: \(successCount) successful, \(failureCount) failed")
        return failureCount == 0
    }
    
    private func pushSingleMetric(_ metric: Metric) async -> Bool {
        do {
            if metric.isDeleted {
                return await deleteMetricOnBackend(metric)
            } else if metric.backendId != nil {
                return await updateMetricOnBackend(metric)
            } else {
                return await createMetricOnBackend(metric)
            }
        }
    }
    
    private func createMetricOnBackend(_ metric: Metric) async -> Bool {
        let endpoint = "/api/metrics"
        let body = [
            "id": metric.id.uuidString,
            "metric_type": metric.type.rawValue,
            "value": metric.value,
            "unit": metric.unit,
            "timestamp": ISO8601DateFormatter().string(from: metric.date),
            "source": metric.source.rawValue
        ] as [String: Any]
        
        do {
            let response = try await makeRequest(endpoint: endpoint, method: "POST", body: body)
            
            if let data = response["data"] as? [String: Any],
               let backendId = data["id"] as? String {
                
                // Update local metric with backend ID
                var updatedMetric = metric
                updatedMetric.backendId = backendId
                updatedMetric.syncedWithBackend = true
                updatedMetric.userId = userId
                
                _ = storage.updateMetric(updatedMetric)
                
                print("✅ Created metric on backend: \(metric.type)")
                return true
            }
        } catch {
            print("❌ Failed to create metric on backend: \(error)")
            await handleSyncError(error, for: "create")
        }
        
        return false
    }
    
    private func updateMetricOnBackend(_ metric: Metric) async -> Bool {
        guard let backendId = metric.backendId else { return false }
        
        let endpoint = "/api/metrics/\(backendId)"
        let body = [
            "value": metric.value,
            "unit": metric.unit,
            "timestamp": ISO8601DateFormatter().string(from: metric.date),
            "source": metric.source.rawValue,
            "client_last_updated_at": ISO8601DateFormatter().string(from: metric.lastUpdatedAt)
        ] as [String: Any]
        
        do {
            let response = try await makeRequest(endpoint: endpoint, method: "PUT", body: body)
            
            // Update sync status
            var updatedMetric = metric
            updatedMetric.syncedWithBackend = true
            _ = storage.updateMetric(updatedMetric)
            
            print("✅ Updated metric on backend: \(metric.type)")
            return true
            
        } catch let error as BackendError {
            switch error {
            case .conflict:
                // Server has newer data - fetch and resolve conflict
                print("🔄 Conflict detected for \(metric.type) - resolving")
                return await resolveConflict(for: backendId, localMetric: metric)
                
            case .gone:
                // Metric was deleted on server
                print("🗑️ Metric was deleted on server: \(metric.type)")
                var deletedMetric = metric
                deletedMetric.isDeleted = true
                deletedMetric.syncedWithBackend = true
                _ = storage.updateMetric(deletedMetric)
                return true
                
            default:
                print("❌ Failed to update metric on backend: \(error)")
            }
        } catch {
            print("❌ Failed to update metric on backend: \(error)")
        }
        
        return false
    }
    
    private func deleteMetricOnBackend(_ metric: Metric) async -> Bool {
        guard let backendId = metric.backendId else {
            // If there's no backend ID, just mark as synced
            var updatedMetric = metric
            updatedMetric.syncedWithBackend = true
            _ = storage.updateMetric(updatedMetric)
            return true
        }
        
        let endpoint = "/api/metrics/\(backendId)"
        
        do {
            _ = try await makeRequest(endpoint: endpoint, method: "DELETE")
            
            // Update sync status
            var updatedMetric = metric
            updatedMetric.syncedWithBackend = true
            _ = storage.updateMetric(updatedMetric)
            
            print("✅ Deleted metric on backend: \(metric.type)")
            return true
            
        } catch {
            print("❌ Failed to delete metric on backend: \(error)")
        }
        
        return false
    }
    
    // MARK: - Pull Operations (Backend → Local)
    
    private func pullChangesFromBackend(isFullSync: Bool) async -> Bool {
        print("📥 Pulling changes from backend")
        
        let sinceTimestamp = isFullSync ? nil : storage.syncStatus.lastBackendSync
        
        do {
            let changes = try await fetchChangesFromBackend(since: sinceTimestamp)
            return await processBackendChanges(changes)
        } catch {
            print("❌ Failed to pull changes from backend: \(error)")
            return false
        }
    }
    
    private func fetchChangesFromBackend(since: Date?) -> async throws -> BackendSyncResponse {
        var endpoint = "/api/metrics/sync/changes"
        
        if let sinceTimestamp = since {
            let formatter = ISO8601DateFormatter()
            endpoint += "?since_timestamp=\(formatter.string(from: sinceTimestamp))"
        }
        
        let response = try await makeRequest(endpoint: endpoint, method: "GET")
        
        guard let data = response["data"] as? [String: Any] else {
            throw BackendError.invalidResponse
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(BackendSyncResponse.self, from: jsonData)
    }
    
    private func processBackendChanges(_ changes: BackendSyncResponse) async -> Bool {
        print("📥 Processing \(changes.entries.count) changes from backend")
        
        var successCount = 0
        var conflictCount = 0
        
        for backendMetric in changes.entries {
            let result = await processSingleBackendChange(backendMetric)
            
            switch result {
            case .success:
                successCount += 1
            case .conflict:
                conflictCount += 1
            case .failed:
                break
            }
        }
        
        // Update last sync timestamp
        if let serverTimestamp = ISO8601DateFormatter().date(from: changes.serverTimestamp) {
            storage.setSyncTimestamp(backend: serverTimestamp)
        }
        
        print("📥 Processed backend changes: \(successCount) successful, \(conflictCount) conflicts")
        return true
    }
    
    private enum ProcessResult {
        case success
        case conflict
        case failed
    }
    
    private func processSingleBackendChange(_ backendMetric: BackendMetric) async -> ProcessResult {
        guard let serverMetric = Metric.fromBackendMetric(backendMetric) else {
            print("❌ Failed to convert backend metric")
            return .failed
        }
        
        // Try to find existing metric by backend ID first
        var existingMetric = backendMetric.id.flatMap { storage.getMetric(by: $0) }
        
        // If not found by backend ID, try to find by UUID or duplicate detection
        if existingMetric == nil {
            // Check for duplicates by type, date, and source
            existingMetric = storage.findDuplicateMetric(
                type: serverMetric.type,
                date: serverMetric.date,
                source: serverMetric.source
            )
        }
        
        if let existing = existingMetric {
            // Resolve conflict using timestamps
            let resolved = storage.resolveConflict(localMetric: existing, remoteMetric: serverMetric)
            
            if resolved.id == serverMetric.id {
                // Server wins - update local
                var updatedMetric = serverMetric
                updatedMetric.id = existing.id // Keep local ID
                updatedMetric.syncedWithBackend = true
                
                _ = storage.updateMetric(updatedMetric)
                return .success
            } else {
                // Local wins - need to push to server later
                var updatedMetric = existing
                updatedMetric.syncedWithBackend = false
                _ = storage.updateMetric(updatedMetric)
                return .conflict
            }
        } else {
            // New metric from server
            if serverMetric.isDeleted {
                // Don't create deleted metrics
                return .success
            }
            
            var newMetric = serverMetric
            newMetric.syncedWithBackend = true
            
            _ = storage.createMetric(newMetric)
            return .success
        }
    }
    
    // MARK: - Conflict Resolution
    
    private func resolveConflict(for backendId: String, localMetric: Metric) async -> Bool {
        // Fetch the current server version
        let endpoint = "/api/metrics/\(backendId)"
        
        do {
            let response = try await makeRequest(endpoint: endpoint, method: "GET")
            
            if let data = response["data"] as? [String: Any] {
                let jsonData = try JSONSerialization.data(withJSONObject: data)
                let backendMetric = try JSONDecoder().decode(BackendMetric.self, from: jsonData)
                
                if let serverMetric = Metric.fromBackendMetric(backendMetric) {
                    // Resolve conflict using timestamps
                    let resolved = storage.resolveConflict(localMetric: localMetric, remoteMetric: serverMetric)
                    
                    var finalMetric = resolved
                    finalMetric.id = localMetric.id // Keep local ID
                    finalMetric.syncedWithBackend = true
                    
                    _ = storage.updateMetric(finalMetric)
                    
                    print("🔄 Conflict resolved for \(localMetric.type)")
                    return true
                }
            }
        } catch {
            print("❌ Failed to resolve conflict: \(error)")
        }
        
        return false
    }
    
    // MARK: - Network Requests
    
    private func makeRequest(
        endpoint: String,
        method: String,
        body: [String: Any]? = nil,
        requiresAuth: Bool = true
    ) async throws -> [String: Any] {
        
        let url = URL(string: baseURL + endpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication if required
        if requiresAuth {
            guard let accessToken = accessToken else {
                throw BackendError.notAuthenticated
            }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        
        // Add body if provided
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendError.networkError
            }
            
            // Handle authentication errors
            if httpResponse.statusCode == 401 {
                // Try to refresh token once
                if requiresAuth && await refreshAccessToken() {
                    // Retry with new token
                    request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
                    let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
                    
                    guard let retryHttpResponse = retryResponse as? HTTPURLResponse else {
                        throw BackendError.networkError
                    }
                    
                    return try handleHttpResponse(retryHttpResponse, data: retryData)
                } else {
                    throw BackendError.notAuthenticated
                }
            }
            
            return try handleHttpResponse(httpResponse, data: data)
            
        } catch let error as BackendError {
            throw error
        } catch {
            throw BackendError.networkError
        }
    }
    
    private func handleHttpResponse(_ response: HTTPURLResponse, data: Data) throws -> [String: Any] {
        switch response.statusCode {
        case 200...299:
            if data.isEmpty {
                return ["success": true]
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BackendError.invalidResponse
            }
            return json
            
        case 401:
            throw BackendError.notAuthenticated
        case 409:
            throw BackendError.conflict
        case 410:
            throw BackendError.gone
        default:
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = json["error"] as? String {
                throw BackendError.serverError(errorMessage)
            } else {
                throw BackendError.serverError("HTTP \(response.statusCode)")
            }
        }
    }
    
    private func handleSyncError(_ error: Error, for operation: String) async {
        let errorMessage = error.localizedDescription
        
        await MainActor.run {
            self.lastError = "\(operation.capitalized) failed: \(errorMessage)"
        }
        
        // Implement exponential backoff for retries
        let key = operation
        let currentAttempts = retryAttempts[key, default: 0]
        
        if currentAttempts < maxRetryAttempts {
            retryAttempts[key] = currentAttempts + 1
            let delay = retryDelays[min(currentAttempts, retryDelays.count - 1)]
            
            print("⏰ Retrying \(operation) in \(delay) seconds (attempt \(currentAttempts + 1))")
            
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } else {
            // Max retries exceeded
            retryAttempts.removeValue(forKey: key)
            print("❌ Max retry attempts exceeded for \(operation)")
        }
    }
}

// MARK: - Backend Errors

enum BackendError: Error, LocalizedError {
    case networkError
    case notAuthenticated
    case invalidResponse
    case conflict
    case gone
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection error"
        case .notAuthenticated:
            return "Authentication required"
        case .invalidResponse:
            return "Invalid server response"
        case .conflict:
            return "Data conflict - server has newer version"
        case .gone:
            return "Resource was deleted"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

// MARK: - Extensions

extension DispatchQueue {
    func runAsync<T>(_ operation: @escaping @Sendable () async -> T) async -> T {
        await withCheckedContinuation { continuation in
            self.async {
                Task {
                    let result = await operation()
                    continuation.resume(returning: result)
                }
            }
        }
    }
}