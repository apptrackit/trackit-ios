import Foundation
import CoreData
import os.log

// MARK: - Sync Status Enum
enum SyncStatus: String, CaseIterable {
    case pendingCreate = "pendingCreate"
    case pendingUpdate = "pendingUpdate" 
    case pendingDelete = "pendingDelete"
    case synced = "synced"
    
    var isPending: Bool {
        switch self {
        case .pendingCreate, .pendingUpdate, .pendingDelete:
            return true
        case .synced:
            return false
        }
    }
}

// MARK: - Source Enum
enum DataSource: String, CaseIterable {
    case localApp = "localApp"
    case healthKit = "healthKit"
}

// MARK: - Local Database Manager
@MainActor
class LocalDatabaseManager: ObservableObject {
    static let shared = LocalDatabaseManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "LocalDB")
    
    // MARK: - Core Data Stack
    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "HealthMetric")
        container.loadPersistentStores { _, error in
            if let error = error {
                self.logger.error("Failed to load Core Data: \(error.localizedDescription)")
                fatalError("Failed to load Core Data: \(error)")
            }
        }
        
        // Enable automatic merging for background context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        
        return container
    }()
    
    private var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    private init() {}
    
    // MARK: - Save Context
    private func saveContext() {
        if viewContext.hasChanges {
            do {
                try viewContext.save()
                logger.info("Successfully saved Core Data context")
            } catch {
                logger.error("Failed to save Core Data context: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - CRUD Operations
    
    /// Create a new HealthMetric entry
    func createEntry(
        uuid: UUID = UUID(),
        metricTypeId: Int,
        value: Double,
        date: Date,
        source: DataSource,
        healthkitId: String? = nil,
        backendId: Int? = nil,
        syncStatus: SyncStatus = .pendingCreate
    ) -> HealthMetric? {
        let entry = HealthMetric(context: viewContext)
        entry.uuid = uuid
        entry.metricTypeId = Int32(metricTypeId)
        entry.value = value
        entry.date = date
        entry.source = source.rawValue
        entry.healthkitId = healthkitId
        entry.backendId = backendId != nil ? Int32(backendId!) : nil
        entry.syncStatus = syncStatus.rawValue
        entry.deletedLocally = false
        entry.modifiedAt = Date()
        
        saveContext()
        logger.info("Created new entry: type=\(metricTypeId), source=\(source.rawValue), uuid=\(uuid)")
        
        return entry
    }
    
    /// Update an existing HealthMetric entry
    func updateEntry(
        uuid: UUID,
        value: Double? = nil,
        date: Date? = nil,
        backendId: Int? = nil,
        healthkitId: String? = nil,
        syncStatus: SyncStatus? = nil
    ) -> Bool {
        let request: NSFetchRequest<HealthMetric> = HealthMetric.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
        
        do {
            let entries = try viewContext.fetch(request)
            guard let entry = entries.first else {
                logger.warning("Entry not found for UUID: \(uuid)")
                return false
            }
            
            var wasModified = false
            
            if let value = value {
                entry.value = value
                wasModified = true
            }
            
            if let date = date {
                entry.date = date
                wasModified = true
            }
            
            if let backendId = backendId {
                entry.backendId = Int32(backendId)
                wasModified = true
            }
            
            if let healthkitId = healthkitId {
                entry.healthkitId = healthkitId
                wasModified = true
            }
            
            if let syncStatus = syncStatus {
                entry.syncStatus = syncStatus.rawValue
                wasModified = true
            }
            
            if wasModified {
                entry.modifiedAt = Date()
                
                // If we're updating data (not just sync status), mark as pending update
                if value != nil || date != nil {
                    entry.syncStatus = SyncStatus.pendingUpdate.rawValue
                }
                
                saveContext()
                logger.info("Updated entry: uuid=\(uuid)")
            }
            
            return true
        } catch {
            logger.error("Failed to update entry: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Mark an entry for deletion (soft delete)
    func markEntryForDeletion(uuid: UUID) -> Bool {
        let request: NSFetchRequest<HealthMetric> = HealthMetric.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
        
        do {
            let entries = try viewContext.fetch(request)
            guard let entry = entries.first else {
                logger.warning("Entry not found for deletion: \(uuid)")
                return false
            }
            
            entry.deletedLocally = true
            entry.syncStatus = SyncStatus.pendingDelete.rawValue
            entry.modifiedAt = Date()
            
            saveContext()
            logger.info("Marked entry for deletion: uuid=\(uuid)")
            return true
        } catch {
            logger.error("Failed to mark entry for deletion: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Permanently delete an entry (after successful backend sync)
    func permanentlyDeleteEntry(uuid: UUID) -> Bool {
        let request: NSFetchRequest<HealthMetric> = HealthMetric.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
        
        do {
            let entries = try viewContext.fetch(request)
            guard let entry = entries.first else {
                logger.warning("Entry not found for permanent deletion: \(uuid)")
                return false
            }
            
            viewContext.delete(entry)
            saveContext()
            logger.info("Permanently deleted entry: uuid=\(uuid)")
            return true
        } catch {
            logger.error("Failed to permanently delete entry: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Query Operations
    
    /// Get all entries for a specific metric type
    func getEntries(metricTypeId: Int, includeDeleted: Bool = false) -> [HealthMetric] {
        let request: NSFetchRequest<HealthMetric> = HealthMetric.fetchRequest()
        
        var predicates = [NSPredicate(format: "metricTypeId == %d", metricTypeId)]
        if !includeDeleted {
            predicates.append(NSPredicate(format: "deletedLocally == NO"))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \HealthMetric.date, ascending: false)]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            logger.error("Failed to fetch entries: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Get entries with pending sync operations
    func getPendingSyncEntries() -> [HealthMetric] {
        let request: NSFetchRequest<HealthMetric> = HealthMetric.fetchRequest()
        request.predicate = NSPredicate(format: "syncStatus IN %@", [
            SyncStatus.pendingCreate.rawValue,
            SyncStatus.pendingUpdate.rawValue,
            SyncStatus.pendingDelete.rawValue
        ])
        request.sortDescriptors = [NSSortDescriptor(keyPath: \HealthMetric.modifiedAt, ascending: true)]
        
        do {
            let entries = try viewContext.fetch(request)
            logger.info("Found \(entries.count) entries pending sync")
            return entries
        } catch {
            logger.error("Failed to fetch pending sync entries: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Check if entry exists by HealthKit ID (for deduplication)
    func entryExists(healthkitId: String) -> Bool {
        let request: NSFetchRequest<HealthMetric> = HealthMetric.fetchRequest()
        request.predicate = NSPredicate(format: "healthkitId == %@ AND deletedLocally == NO", healthkitId)
        request.fetchLimit = 1
        
        do {
            let count = try viewContext.count(for: request)
            return count > 0
        } catch {
            logger.error("Failed to check if entry exists: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Get entry by UUID
    func getEntry(uuid: UUID) -> HealthMetric? {
        let request: NSFetchRequest<HealthMetric> = HealthMetric.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
        request.fetchLimit = 1
        
        do {
            return try viewContext.fetch(request).first
        } catch {
            logger.error("Failed to fetch entry by UUID: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Get entry by backend ID
    func getEntry(backendId: Int) -> HealthMetric? {
        let request: NSFetchRequest<HealthMetric> = HealthMetric.fetchRequest()
        request.predicate = NSPredicate(format: "backendId == %d AND deletedLocally == NO", backendId)
        request.fetchLimit = 1
        
        do {
            return try viewContext.fetch(request).first
        } catch {
            logger.error("Failed to fetch entry by backend ID: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Get all entries (for debugging)
    func getAllEntries(includeDeleted: Bool = false) -> [HealthMetric] {
        let request: NSFetchRequest<HealthMetric> = HealthMetric.fetchRequest()
        
        if !includeDeleted {
            request.predicate = NSPredicate(format: "deletedLocally == NO")
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \HealthMetric.date, ascending: false)]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            logger.error("Failed to fetch all entries: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Sync Management
    
    /// Update sync status for an entry
    func updateSyncStatus(uuid: UUID, status: SyncStatus, backendId: Int? = nil) -> Bool {
        return updateEntry(uuid: uuid, backendId: backendId, syncStatus: status)
    }
    
    /// Get the last sync timestamp for HealthKit anchoring
    func getLastHealthKitSyncDate() -> Date? {
        let key = "LastHealthKitSyncDate"
        return UserDefaults.standard.object(forKey: key) as? Date
    }
    
    /// Update the last sync timestamp for HealthKit anchoring
    func updateLastHealthKitSyncDate(_ date: Date) {
        let key = "LastHealthKitSyncDate"
        UserDefaults.standard.set(date, forKey: key)
        logger.info("Updated last HealthKit sync date: \(date)")
    }
    
    // MARK: - Utility
    
    /// Clear all data (for debugging/reset)
    func clearAllData() {
        let request: NSFetchRequest<NSFetchRequestResult> = HealthMetric.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        
        do {
            try viewContext.execute(deleteRequest)
            saveContext()
            logger.info("Cleared all local database data")
        } catch {
            logger.error("Failed to clear all data: \(error.localizedDescription)")
        }
    }
    
    /// Get statistics about local data
    func getDataStatistics() -> String {
        let allEntries = getAllEntries(includeDeleted: true)
        let activeEntries = getAllEntries(includeDeleted: false)
        let pendingEntries = getPendingSyncEntries()
        
        let healthKitEntries = allEntries.filter { $0.source == DataSource.healthKit.rawValue }
        let localAppEntries = allEntries.filter { $0.source == DataSource.localApp.rawValue }
        
        return """
        📊 Local Database Statistics:
        • Total entries: \(allEntries.count)
        • Active entries: \(activeEntries.count)
        • Pending sync: \(pendingEntries.count)
        • HealthKit entries: \(healthKitEntries.count)
        • Local app entries: \(localAppEntries.count)
        """
    }
}

// MARK: - Core Data Model Extensions
extension HealthMetric {
    var syncStatusEnum: SyncStatus {
        get {
            return SyncStatus(rawValue: syncStatus ?? "pendingCreate") ?? .pendingCreate
        }
        set {
            syncStatus = newValue.rawValue
        }
    }
    
    var sourceEnum: DataSource {
        get {
            return DataSource(rawValue: source ?? "localApp") ?? .localApp
        }
        set {
            source = newValue.rawValue
        }
    }
    
    var backendIdInt: Int? {
        return backendId != nil ? Int(backendId!) : nil
    }
    
    /// Convert to StatEntry for compatibility with existing views
    func toStatEntry() -> StatEntry? {
        guard let statType = StatType.from(metricTypeId: Int(metricTypeId)) else {
            return nil
        }
        
        let statSource: StatSource = sourceEnum == .healthKit ? .appleHealth : .manual
        
        return StatEntry(
            id: uuid!,
            date: date!,
            value: value,
            type: statType,
            source: statSource,
            backendId: backendIdInt
        )
    }
}

// MARK: - StatType Extension for Metric Type ID Mapping
extension StatType {
    static func from(metricTypeId: Int) -> StatType? {
        switch metricTypeId {
        case 1: return .weight
        case 2: return .height
        case 3: return .bodyFat
        case 4: return .waist
        case 5: return .bicep
        case 6: return .chest
        case 7: return .thigh
        case 8: return .shoulder
        case 9: return .glutes
        case 10: return .calf
        case 11: return .neck
        case 12: return .forearm
        default: return nil
        }
    }
    
    var metricTypeId: Int {
        switch self {
        case .weight: return 1
        case .height: return 2
        case .bodyFat: return 3
        case .waist: return 4
        case .bicep: return 5
        case .chest: return 6
        case .thigh: return 7
        case .shoulder: return 8
        case .glutes: return 9
        case .calf: return 10
        case .neck: return 11
        case .forearm: return 12
        default: return 0 // For calculated metrics
        }
    }
}