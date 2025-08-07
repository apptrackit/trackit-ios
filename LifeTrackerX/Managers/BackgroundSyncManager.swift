import Foundation
import BackgroundTasks
import UIKit
import os.log

// MARK: - Background Sync Manager (Updated for compatibility)
@MainActor
class BackgroundSyncManager: ObservableObject {
    static let shared = BackgroundSyncManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "BackgroundSync")
    private let healthManager = HealthManager.shared
    private let syncManager = MetricSyncManager.shared
    
    // Background task identifiers (must be registered in Info.plist)
    private let backgroundSyncTaskIdentifier = "com.lifetrackerx.sync"
    private let healthKitSyncTaskIdentifier = "com.lifetrackerx.healthkit-sync"
    
    @Published var backgroundSyncStatus: String = "Ready"
    @Published var lastBackgroundSync: Date?
    
    private init() {
        registerBackgroundTasks()
        setupNotificationObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Background Task Registration
    
    private func registerBackgroundTasks() {
        // Register app refresh task for periodic sync
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundSyncTaskIdentifier, using: nil) { [weak self] task in
            guard let bgTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleBackgroundSync(task: bgTask)
        }
        
        // Register processing task for heavy HealthKit sync
        BGTaskScheduler.shared.register(forTaskWithIdentifier: healthKitSyncTaskIdentifier, using: nil) { [weak self] task in
            guard let processTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleHealthKitBackgroundSync(task: processTask)
        }
        
        logger.info("Background tasks registered")
    }
    
    // MARK: - App Lifecycle Observers
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        logger.info("Notification observers set up")
    }
    
    // MARK: - App Lifecycle Handlers
    
    @objc private func appWillEnterForeground() {
        logger.info("App entering foreground - starting sync")
        backgroundSyncStatus = "Syncing on foreground..."
        
        Task {
            // First, sync from HealthKit to get any new data
            await healthManager.forceSyncFromHealthKit()
            
            // Then process any pending backend operations
            await syncManager.processPendingOperations()
            
            // Finally, sync from backend to get updates from other devices
            await syncManager.syncFromBackend()
            
            backgroundSyncStatus = "Ready"
            lastBackgroundSync = Date()
            
            logger.info("Foreground sync completed")
        }
    }
    
    @objc private func appDidEnterBackground() {
        logger.info("App entering background - scheduling background tasks")
        
        // Schedule background tasks for when app is backgrounded
        scheduleBackgroundTasks()
        
        // Perform a quick sync before going to background
        Task {
            await performQuickSync()
        }
    }
    
    @objc private func appWillTerminate() {
        logger.info("App will terminate - performing final sync")
        
        // Perform one last sync attempt
        Task {
            await performQuickSync()
        }
    }
    
    // MARK: - Background Task Scheduling
    
    private func scheduleBackgroundTasks() {
        // Schedule app refresh task for basic sync
        let appRefreshRequest = BGAppRefreshTaskRequest(identifier: backgroundSyncTaskIdentifier)
        appRefreshRequest.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes from now
        
        do {
            try BGTaskScheduler.shared.submit(appRefreshRequest)
            logger.info("Scheduled background app refresh task")
        } catch {
            logger.error("Failed to schedule app refresh task: \(error.localizedDescription)")
        }
        
        // Schedule processing task for HealthKit sync (only if authorized)
        if healthManager.isAuthorized {
            let processingRequest = BGProcessingTaskRequest(identifier: healthKitSyncTaskIdentifier)
            processingRequest.requiresNetworkConnectivity = false // HealthKit works offline
            processingRequest.requiresExternalPower = false
            processingRequest.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes from now
            
            do {
                try BGTaskScheduler.shared.submit(processingRequest)
                logger.info("Scheduled background processing task")
            } catch {
                logger.error("Failed to schedule processing task: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Background Task Handlers
    
    private func handleBackgroundSync(task: BGAppRefreshTask) {
        logger.info("Background app refresh task started")
        
        // Set up timeout handler
        task.expirationHandler = {
            self.logger.warning("Background app refresh task expired")
            task.setTaskCompleted(success: false)
        }
        
        // Perform the sync
        Task {
            let success = await performBackgroundSync()
            
            // Schedule next background task
            self.scheduleBackgroundTasks()
            
            task.setTaskCompleted(success: success)
            self.logger.info("Background app refresh task completed: \(success)")
        }
    }
    
    private func handleHealthKitBackgroundSync(task: BGProcessingTask) {
        logger.info("Background HealthKit processing task started")
        
        // Set up timeout handler
        task.expirationHandler = {
            self.logger.warning("Background processing task expired")
            task.setTaskCompleted(success: false)
        }
        
        // Perform HealthKit sync
        Task {
            let success = await performHealthKitBackgroundSync()
            
            // Schedule next background task
            self.scheduleBackgroundTasks()
            
            task.setTaskCompleted(success: success)
            self.logger.info("Background HealthKit processing task completed: \(success)")
        }
    }
    
    // MARK: - Sync Operations
    
    private func performBackgroundSync() async -> Bool {
        logger.info("Performing background sync")
        
        do {
            // Quick sync of pending operations
            await syncManager.processPendingOperations()
            
            // Update status
            lastBackgroundSync = Date()
            return true
            
        } catch {
            logger.error("Background sync failed: \(error.localizedDescription)")
            return false
        }
    }
    
    private func performHealthKitBackgroundSync() async -> Bool {
        logger.info("Performing HealthKit background sync")
        
        guard healthManager.isAuthorized else {
            logger.warning("HealthKit not authorized for background sync")
            return false
        }
        
        do {
            // Sync from HealthKit
            await healthManager.forceSyncFromHealthKit()
            
            // Process any new data to backend
            await syncManager.processPendingOperations()
            
            return true
            
        } catch {
            logger.error("HealthKit background sync failed: \(error.localizedDescription)")
            return false
        }
    }
    
    private func performQuickSync() async {
        logger.info("Performing quick sync")
        
        // Only sync pending operations quickly
        await syncManager.processPendingOperations()
        
        logger.info("Quick sync completed")
    }
    
    // MARK: - Public Interface
    
    /// Call this method from your App delegate or main app setup
    func setupBackgroundSync() {
        logger.info("Background sync setup completed")
        
        // Schedule initial background tasks if needed
        scheduleBackgroundTasks()
    }
    
    /// Handle sync notification from server (if using push notifications)
    func handleSyncNotification(_ userInfo: [AnyHashable: Any]) async {
        logger.info("Handling sync notification")
        
        // Perform sync based on notification
        await syncManager.syncFromBackend()
        await syncManager.processPendingOperations()
        
        logger.info("Sync notification handled")
    }
    
    /// Force a manual background-style sync
    func forceBackgroundSync() async {
        backgroundSyncStatus = "Manual sync..."
        
        let success = await performBackgroundSync()
        
        backgroundSyncStatus = success ? "Sync completed" : "Sync failed"
        
        // Reset status after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.backgroundSyncStatus = "Ready"
        }
    }
    
    /// Get background sync statistics
    func getBackgroundSyncStatus() -> String {
        let lastSyncStr = lastBackgroundSync?.formatted() ?? "Never"
        
        return """
        🔄 Background Sync Status:
        • Status: \(backgroundSyncStatus)
        • Last background sync: \(lastSyncStr)
        • HealthKit authorized: \(healthManager.isAuthorized)
        • Network online: \(syncManager.isOnline)
        """
    }
}