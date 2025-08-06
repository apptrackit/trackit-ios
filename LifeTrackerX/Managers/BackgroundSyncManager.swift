import Foundation
import UIKit
import BackgroundTasks
import os.log

// MARK: - Background Sync Manager
/// Handles background sync operations and app lifecycle events
@MainActor
class BackgroundSyncManager: ObservableObject {
    static let shared = BackgroundSyncManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "BackgroundSync")
    private let healthManager = NewHealthManager.shared
    private let syncManager = NewSyncManager.shared
    
    // Background task identifiers
    private let backgroundSyncTaskIdentifier = "com.lifetrackerx.sync"
    private let healthKitSyncTaskIdentifier = "com.lifetrackerx.healthkit-sync"
    
    @Published var backgroundSyncStatus: String = "Idle"
    
    private init() {
        registerBackgroundTasks()
        setupNotificationObservers()
    }
    
    // MARK: - Background Task Registration
    
    private func registerBackgroundTasks() {
        // Register background app refresh task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundSyncTaskIdentifier, using: nil) { [weak self] task in
            guard let self = self else { return }
            self.handleBackgroundSync(task: task as! BGAppRefreshTask)
        }
        
        // Register background processing task for HealthKit sync
        BGTaskScheduler.shared.register(forTaskWithIdentifier: healthKitSyncTaskIdentifier, using: nil) { [weak self] task in
            guard let self = self else { return }
            self.handleHealthKitBackgroundSync(task: task as! BGProcessingTask)
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
        
        logger.info("App lifecycle observers setup")
    }
    
    // MARK: - App Lifecycle Handlers
    
    @objc private func appWillEnterForeground() {
        logger.info("App entering foreground - performing sync")
        backgroundSyncStatus = "Foreground sync"
        
        Task {
            // Check for HealthKit changes
            if healthManager.isAuthorized {
                await healthManager.forceSyncFromHealthKit()
            }
            
            // Sync pending operations to backend
            await syncManager.processPendingOperations()
            
            // Pull any updates from backend
            await syncManager.syncFromBackend()
            
            backgroundSyncStatus = "Idle"
        }
    }
    
    @objc private func appDidEnterBackground() {
        logger.info("App entering background - scheduling background tasks")
        scheduleBackgroundTasks()
        
        // Perform a quick sync before going to background
        Task {
            await performQuickBackgroundSync()
        }
    }
    
    @objc private func appWillTerminate() {
        logger.info("App terminating - performing final sync")
        
        // Note: We have very limited time here, so only do critical operations
        Task {
            await performQuickBackgroundSync()
        }
    }
    
    // MARK: - Background Task Scheduling
    
    private func scheduleBackgroundTasks() {
        scheduleBackgroundSync()
        scheduleHealthKitSync()
    }
    
    private func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundSyncTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled background sync task")
        } catch {
            logger.error("Failed to schedule background sync: \(error.localizedDescription)")
        }
    }
    
    private func scheduleHealthKitSync() {
        let request = BGProcessingTaskRequest(identifier: healthKitSyncTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled HealthKit sync task")
        } catch {
            logger.error("Failed to schedule HealthKit sync: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Background Task Handlers
    
    private func handleBackgroundSync(task: BGAppRefreshTask) {
        logger.info("Starting background app refresh sync")
        backgroundSyncStatus = "Background sync"
        
        // Schedule next background sync
        scheduleBackgroundSync()
        
        task.expirationHandler = {
            self.logger.warning("Background sync task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            do {
                // Sync pending operations (quick operations only)
                await syncManager.processPendingOperations()
                
                backgroundSyncStatus = "Idle"
                task.setTaskCompleted(success: true)
                logger.info("Background sync completed successfully")
                
            } catch {
                logger.error("Background sync failed: \(error.localizedDescription)")
                backgroundSyncStatus = "Idle"
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    private func handleHealthKitBackgroundSync(task: BGProcessingTask) {
        logger.info("Starting background HealthKit sync")
        backgroundSyncStatus = "Background HealthKit sync"
        
        // Schedule next HealthKit sync
        scheduleHealthKitSync()
        
        task.expirationHandler = {
            self.logger.warning("Background HealthKit sync task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            do {
                // Sync from HealthKit
                if healthManager.isAuthorized {
                    await healthManager.forceSyncFromHealthKit()
                }
                
                // Sync to backend
                await syncManager.processPendingOperations()
                
                // Sync from backend
                await syncManager.syncFromBackend()
                
                backgroundSyncStatus = "Idle"
                task.setTaskCompleted(success: true)
                logger.info("Background HealthKit sync completed successfully")
                
            } catch {
                logger.error("Background HealthKit sync failed: \(error.localizedDescription)")
                backgroundSyncStatus = "Idle"
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    // MARK: - Quick Sync Operations
    
    private func performQuickBackgroundSync() async {
        logger.info("Performing quick background sync")
        backgroundSyncStatus = "Quick sync"
        
        // Only sync pending operations (don't pull from backend to save time/battery)
        await syncManager.processPendingOperations()
        
        backgroundSyncStatus = "Idle"
        logger.info("Quick background sync completed")
    }
    
    // MARK: - Public Interface
    
    /// Force trigger background sync (for testing or manual operation)
    func triggerBackgroundSync() async {
        logger.info("Manual background sync triggered")
        backgroundSyncStatus = "Manual sync"
        
        // Comprehensive sync
        if healthManager.isAuthorized {
            await healthManager.forceSyncFromHealthKit()
        }
        
        await syncManager.processPendingOperations()
        await syncManager.syncFromBackend()
        
        backgroundSyncStatus = "Idle"
        logger.info("Manual background sync completed")
    }
    
    /// Get status of background operations
    func getBackgroundSyncStatus() -> String {
        let pendingCount = syncManager.pendingSyncCount
        let isOnline = syncManager.isOnline
        let lastSync = syncManager.lastSyncDate
        
        return """
        🔄 Background Sync Status:
        • Status: \(backgroundSyncStatus)
        • Network: \(isOnline ? "Online" : "Offline")
        • Pending operations: \(pendingCount)
        • Last sync: \(lastSync?.formatted() ?? "Never")
        • HealthKit authorized: \(healthManager.isAuthorized)
        """
    }
    
    // MARK: - Configuration
    
    /// Configure sync intervals and behavior
    func configureBackgroundSync(
        quickSyncEnabled: Bool = true,
        backgroundRefreshInterval: TimeInterval = 15 * 60, // 15 minutes
        healthKitSyncInterval: TimeInterval = 30 * 60 // 30 minutes
    ) {
        logger.info("""
        Configuring background sync:
        • Quick sync: \(quickSyncEnabled)
        • Background refresh: \(backgroundRefreshInterval/60) minutes
        • HealthKit sync: \(healthKitSyncInterval/60) minutes
        """)
        
        // This could store preferences and modify scheduling behavior
    }
    
    // MARK: - Debug and Testing
    
    /// Test background sync functionality (for development)
    func testBackgroundSync() async {
        logger.info("Testing background sync functionality")
        await triggerBackgroundSync()
    }
}

// MARK: - App Integration Helper
extension BackgroundSyncManager {
    /// Call this from AppDelegate or App struct to initialize background sync
    func setupBackgroundSync() {
        logger.info("Initializing background sync manager")
        
        // Perform initial sync if needed
        Task {
            await triggerBackgroundSync()
        }
    }
    
    /// Handle background URL sessions (if needed for file uploads/downloads)
    func handleBackgroundURLSession(
        identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        logger.info("Handling background URL session: \(identifier)")
        // Handle any background URL session tasks here
        completionHandler()
    }
}

// MARK: - Notification Extensions
extension BackgroundSyncManager {
    /// Handle push notification that might trigger sync
    func handleSyncNotification(_ userInfo: [AnyHashable: Any]) async {
        logger.info("Handling sync notification")
        
        if let syncType = userInfo["syncType"] as? String {
            switch syncType {
            case "healthkit":
                if healthManager.isAuthorized {
                    await healthManager.forceSyncFromHealthKit()
                }
            case "backend":
                await syncManager.syncFromBackend()
            case "full":
                await triggerBackgroundSync()
            default:
                await syncManager.processPendingOperations()
            }
        } else {
            // Default to processing pending operations
            await syncManager.processPendingOperations()
        }
    }
}