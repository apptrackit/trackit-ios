import Foundation
import os.log

// MARK: - User Action Handler (Updated for compatibility)
/// Handles all user-initiated actions with proper sync flow through all 3 layers:
/// [1] Local Database (immediate)
/// [2] HealthKit (if authorized and supported)
/// [3] Backend API (queued for sync)
@MainActor
class UserActionHandler: ObservableObject {
    static let shared = UserActionHandler()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserActions")
    private let localDatabase = LocalDatabaseManager.shared
    private let healthManager = HealthManager.shared
    private let syncManager = MetricSyncManager.shared
    
    // MARK: - Published Properties
    @Published var syncStatus: String = "Ready"
    
    private init() {}
    
    // MARK: - User Add Action
    
    /// Handle user adding a new metric entry
    /// Flow: Local DB → HealthKit (if applicable) → Queue for backend sync
    func handleUserAdd(
        metricTypeId: Int,
        value: Double,
        date: Date,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        logger.info("User adding entry: type=\(metricTypeId), value=\(value), date=\(date)")
        
        Task { @MainActor in
            do {
                // Step 1: Save to local database immediately
                guard let localEntry = localDatabase.createEntry(
                    metricTypeId: metricTypeId,
                    value: value,
                    date: date,
                    source: .localApp,
                    syncStatus: .pendingCreate
                ) else {
                    logger.error("Failed to create entry in local database")
                    completion(false, UserActionError.localDatabaseError)
                    return
                }
                
                logger.info("✅ Step 1: Saved to local database: \(localEntry.uuid)")
                
                // Step 2: Save to HealthKit (if authorized and supported metric type)
                if healthManager.isWriteAuthorized && isHealthKitSupported(metricTypeId: metricTypeId) {
                    if let statEntry = localEntry.toStatEntry() {
                        healthManager.saveToHealthKit(statEntry) { success, error in
                            if success {
                                self.logger.info("✅ Step 2: Saved to HealthKit")
                            } else {
                                self.logger.warning("⚠️ Step 2: Failed to save to HealthKit, but continuing")
                            }
                        }
                    }
                } else {
                    logger.info("ℹ️ Step 2: Skipping HealthKit (not authorized or unsupported type)")
                }
                
                // Step 3: Queue for backend sync
                if let statEntry = localEntry.toStatEntry() {
                    syncManager.syncEntry(statEntry, operation: .create)
                    logger.info("✅ Step 3: Queued for backend sync")
                }
                
                completion(true, nil)
                
            } catch {
                logger.error("Error in user add flow: \(error.localizedDescription)")
                completion(false, error)
            }
        }
    }
    
    // MARK: - User Edit Action
    
    /// Handle user editing an existing metric entry
    /// Flow: Update Local DB → Update HealthKit (if applicable) → Queue for backend sync
    func handleUserEdit(
        entryUUID: UUID,
        newValue: Double,
        newDate: Date,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        logger.info("User editing entry: uuid=\(entryUUID), newValue=\(newValue), newDate=\(newDate)")
        
        Task { @MainActor in
            do {
                // Get the existing entry
                guard let existingEntry = localDatabase.getEntry(uuid: entryUUID) else {
                    logger.error("Entry not found for editing: \(entryUUID)")
                    completion(false, UserActionError.entryNotFound)
                    return
                }
                
                let isHealthKitEntry = existingEntry.sourceEnum == .healthKit
                
                // Step 1: Update in local database
                let updateSuccess = localDatabase.updateEntry(
                    uuid: entryUUID,
                    value: newValue,
                    date: newDate,
                    syncStatus: .pendingUpdate
                )
                
                guard updateSuccess else {
                    logger.error("Failed to update entry in local database")
                    completion(false, UserActionError.localDatabaseError)
                    return
                }
                
                logger.info("✅ Step 1: Updated in local database")
                
                // Step 2: Update in HealthKit (if applicable)
                if healthManager.isWriteAuthorized && 
                   isHealthKitSupported(metricTypeId: existingEntry.metricTypeId) {
                    
                    if let statEntry = existingEntry.toStatEntry() {
                        // For HealthKit entries, we need to be careful about the sync
                        if !isHealthKitEntry {
                            // This was a local app entry, so we can directly update HealthKit
                            healthManager.saveToHealthKit(statEntry) { success, error in
                                if success {
                                    self.logger.info("✅ Step 2: Updated in HealthKit")
                                } else {
                                    self.logger.warning("⚠️ Step 2: Failed to update in HealthKit")
                                }
                            }
                        } else {
                            // This was originally from HealthKit - need to delete old and create new
                            healthManager.deleteFromHealthKit(statEntry) { success, error in
                                if success {
                                    self.healthManager.saveToHealthKit(statEntry) { success, error in
                                        if success {
                                            self.logger.info("✅ Step 2: Replaced entry in HealthKit")
                                        } else {
                                            self.logger.warning("⚠️ Step 2: Deleted from HealthKit but failed to create new")
                                        }
                                    }
                                } else {
                                    self.logger.warning("⚠️ Step 2: Failed to delete old entry from HealthKit")
                                }
                            }
                        }
                    }
                } else {
                    logger.info("ℹ️ Step 2: Skipping HealthKit update (not authorized or unsupported)")
                }
                
                // Step 3: Queue for backend sync
                if let updatedEntry = localDatabase.getEntry(uuid: entryUUID),
                   let statEntry = updatedEntry.toStatEntry() {
                    syncManager.syncEntry(statEntry, operation: .update)
                    logger.info("✅ Step 3: Queued for backend sync")
                }
                
                completion(true, nil)
                
            } catch {
                logger.error("Error in user edit flow: \(error.localizedDescription)")
                completion(false, error)
            }
        }
    }
    
    // MARK: - User Delete Action
    
    /// Handle user deleting a metric entry
    /// Flow: Mark deleted in Local DB → Delete from HealthKit → Queue for backend deletion
    func handleUserDelete(
        entryUUID: UUID,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        logger.info("User deleting entry: uuid=\(entryUUID)")
        
        Task { @MainActor in
            do {
                // Get the entry before deleting
                guard let existingEntry = localDatabase.getEntry(uuid: entryUUID) else {
                    logger.error("Entry not found for deletion: \(entryUUID)")
                    completion(false, UserActionError.entryNotFound)
                    return
                }
                
                let isHealthKitEntry = existingEntry.sourceEnum == .healthKit
                
                // Step 1: Mark as deleted in local database (soft delete)
                let deleteSuccess = localDatabase.markEntryForDeletion(uuid: entryUUID)
                guard deleteSuccess else {
                    logger.error("Failed to mark entry for deletion in local database")
                    completion(false, UserActionError.localDatabaseError)
                    return
                }
                
                logger.info("✅ Step 1: Marked for deletion in local database")
                
                // Step 2: Delete from HealthKit (if applicable)
                if healthManager.isWriteAuthorized && 
                   isHealthKitSupported(metricTypeId: existingEntry.metricTypeId) &&
                   !isHealthKitEntry { // Only delete from HealthKit if it was originally created by our app
                    
                    if let statEntry = existingEntry.toStatEntry() {
                        healthManager.deleteFromHealthKit(statEntry) { success, error in
                            if success {
                                self.logger.info("✅ Step 2: Deleted from HealthKit")
                            } else {
                                self.logger.warning("⚠️ Step 2: Failed to delete from HealthKit")
                            }
                        }
                    }
                } else {
                    logger.info("ℹ️ Step 2: Skipping HealthKit deletion (not applicable)")
                }
                
                // Step 3: Queue for backend deletion
                if let entryToDelete = localDatabase.getEntry(uuid: entryUUID),
                   let statEntry = entryToDelete.toStatEntry() {
                    syncManager.syncEntry(statEntry, operation: .delete)
                    logger.info("✅ Step 3: Queued for backend deletion")
                }
                
                completion(true, nil)
                
            } catch {
                logger.error("Error in user delete flow: \(error.localizedDescription)")
                completion(false, error)
            }
        }
    }
    
    // MARK: - Batch Operations
    
    /// Handle user adding multiple entries (e.g., bulk import)
    func handleBatchAdd(
        entries: [(metricTypeId: Int, value: Double, date: Date)],
        completion: @escaping (Int, Int, Error?) -> Void // (success count, total count, error)
    ) {
        logger.info("User adding \(entries.count) entries in batch")
        
        Task { @MainActor in
            var successCount = 0
            let totalCount = entries.count
            
            for entry in entries {
                await withCheckedContinuation { continuation in
                    handleUserAdd(
                        metricTypeId: entry.metricTypeId,
                        value: entry.value,
                        date: entry.date
                    ) { success, error in
                        if success {
                            successCount += 1
                        }
                        continuation.resume()
                    }
                }
            }
            
            logger.info("Batch add completed: \(successCount)/\(totalCount) successful")
            completion(successCount, totalCount, nil)
        }
    }
    
    // MARK: - Data Import from HealthKit
    
    /// Handle importing data from HealthKit (when user grants permission)
    /// This is different from user-initiated actions as it processes existing HealthKit data
    func handleHealthKitImport(completion: @escaping (Bool, Error?) -> Void) {
        logger.info("Starting HealthKit data import")
        
        Task {
            do {
                // Start the HealthKit sync process
                await healthManager.startHealthKitSync()
                
                // Wait for initial sync to complete
                await healthManager.forceSyncFromHealthKit()
                
                logger.info("✅ HealthKit import completed")
                completion(true, nil)
                
            } catch {
                logger.error("HealthKit import failed: \(error.localizedDescription)")
                completion(false, error)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func isHealthKitSupported(metricTypeId: Int) -> Bool {
        // Check if the metric type is supported by HealthKit
        switch metricTypeId {
        case 1, 2, 3, 4: // weight, height, body fat, waist
            return true
        default:
            return false
        }
    }
    
    // MARK: - Public Status Methods
    
    /// Get the current sync status for display
    func getSyncStatus() -> String {
        let dbStats = localDatabase.getDataStatistics()
        let syncStats = syncManager.getSyncStatistics()
        
        return """
        \(dbStats)
        
        \(syncStats)
        
        🍎 HealthKit Status:
        • Available: \(healthManager.isHealthDataAvailable)
        • Read authorized: \(healthManager.isAuthorized)
        • Write authorized: \(healthManager.isWriteAuthorized)
        """
    }
    
    /// Force sync all pending operations
    func forceSyncAll() async {
        logger.info("User requested force sync all")
        await syncManager.forceSyncAll()
    }
    
    /// Force sync from backend
    func forceSyncFromBackend() async {
        logger.info("User requested force sync from backend")
        await syncManager.forceSyncFromBackend()
    }
}

// MARK: - Error Types
enum UserActionError: Error, LocalizedError {
    case localDatabaseError
    case healthKitError(String)
    case networkError(String)
    case entryNotFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .localDatabaseError:
            return "Failed to save to local database"
        case .healthKitError(let message):
            return "HealthKit error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .entryNotFound:
            return "Entry not found"
        case .invalidData:
            return "Invalid data provided"
        }
    }
}

// MARK: - Convenience Extensions for StatEntry Compatibility
extension UserActionHandler {
    /// Handle user add with StatEntry for compatibility with existing code
    func handleUserAdd(_ statEntry: StatEntry, completion: @escaping (Bool, Error?) -> Void) {
        handleUserAdd(
            metricTypeId: statEntry.type.metricTypeId,
            value: statEntry.value,
            date: statEntry.date,
            completion: completion
        )
    }
    
    /// Handle user edit with StatEntry for compatibility with existing code
    func handleUserEdit(_ statEntry: StatEntry, completion: @escaping (Bool, Error?) -> Void) {
        handleUserEdit(
            entryUUID: statEntry.id,
            newValue: statEntry.value,
            newDate: statEntry.date,
            completion: completion
        )
    }
    
    /// Handle user delete with StatEntry for compatibility with existing code
    func handleUserDelete(_ statEntry: StatEntry, completion: @escaping (Bool, Error?) -> Void) {
        handleUserDelete(entryUUID: statEntry.id, completion: completion)
    }
}