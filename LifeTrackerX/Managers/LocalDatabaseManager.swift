import Foundation
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

// MARK: - Temporary HealthMetric Struct (until Core Data is set up)
struct TempHealthMetric {
    let uuid: UUID
    let metricTypeId: Int
    let value: Double
    let date: Date
    let source: DataSource
    let healthkitId: String?
    let backendId: Int?
    let syncStatus: SyncStatus
    let deletedLocally: Bool
    let modifiedAt: Date
    
    init(uuid: UUID = UUID(), metricTypeId: Int, value: Double, date: Date, source: DataSource, healthkitId: String? = nil, backendId: Int? = nil, syncStatus: SyncStatus = .pendingCreate) {
        self.uuid = uuid
        self.metricTypeId = metricTypeId
        self.value = value
        self.date = date
        self.source = source
        self.healthkitId = healthkitId
        self.backendId = backendId
        self.syncStatus = syncStatus
        self.deletedLocally = false
        self.modifiedAt = Date()
    }
    
    var syncStatusEnum: SyncStatus {
        return syncStatus
    }
    
    var sourceEnum: DataSource {
        return source
    }
    
    var backendIdInt: Int? {
        return backendId
    }
    
    /// Convert to StatEntry for compatibility with existing views
    func toStatEntry() -> StatEntry? {
        guard let statType = StatType.from(metricTypeId: metricTypeId) else {
            return nil
        }
        
        let statSource: StatSource = sourceEnum == .healthKit ? .appleHealth : .manual
        
        return StatEntry(
            id: uuid,
            date: date,
            value: value,
            type: statType,
            source: statSource,
            backendId: backendIdInt
        )
    }
}

// MARK: - Simplified Local Database Manager (UserDefaults-based for now)
@MainActor
class LocalDatabaseManager: ObservableObject {
    static let shared = LocalDatabaseManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "LocalDB")
    private let storageKey = "TempHealthMetrics"
    
    private init() {}
    
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
    ) -> TempHealthMetric? {
        let entry = TempHealthMetric(
            uuid: uuid,
            metricTypeId: metricTypeId,
            value: value,
            date: date,
            source: source,
            healthkitId: healthkitId,
            backendId: backendId,
            syncStatus: syncStatus
        )
        
        var entries = getAllEntries(includeDeleted: true)
        entries.append(entry)
        saveEntries(entries)
        
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
        var entries = getAllEntries(includeDeleted: true)
        
        guard let index = entries.firstIndex(where: { $0.uuid == uuid }) else {
            logger.warning("Entry not found for UUID: \(uuid)")
            return false
        }
        
        var entry = entries[index]
        var wasModified = false
        
        if let value = value {
            entry = TempHealthMetric(
                uuid: entry.uuid,
                metricTypeId: entry.metricTypeId,
                value: value,
                date: entry.date,
                source: entry.source,
                healthkitId: entry.healthkitId,
                backendId: entry.backendId,
                syncStatus: syncStatus ?? .pendingUpdate
            )
            wasModified = true
        }
        
        if let date = date {
            entry = TempHealthMetric(
                uuid: entry.uuid,
                metricTypeId: entry.metricTypeId,
                value: entry.value,
                date: date,
                source: entry.source,
                healthkitId: entry.healthkitId,
                backendId: entry.backendId,
                syncStatus: syncStatus ?? .pendingUpdate
            )
            wasModified = true
        }
        
        if let backendId = backendId {
            entry = TempHealthMetric(
                uuid: entry.uuid,
                metricTypeId: entry.metricTypeId,
                value: entry.value,
                date: entry.date,
                source: entry.source,
                healthkitId: entry.healthkitId,
                backendId: backendId,
                syncStatus: syncStatus ?? entry.syncStatus
            )
            wasModified = true
        }
        
        if let healthkitId = healthkitId {
            entry = TempHealthMetric(
                uuid: entry.uuid,
                metricTypeId: entry.metricTypeId,
                value: entry.value,
                date: entry.date,
                source: entry.source,
                healthkitId: healthkitId,
                backendId: entry.backendId,
                syncStatus: syncStatus ?? entry.syncStatus
            )
            wasModified = true
        }
        
        if let syncStatus = syncStatus {
            entry = TempHealthMetric(
                uuid: entry.uuid,
                metricTypeId: entry.metricTypeId,
                value: entry.value,
                date: entry.date,
                source: entry.source,
                healthkitId: entry.healthkitId,
                backendId: entry.backendId,
                syncStatus: syncStatus
            )
            wasModified = true
        }
        
        if wasModified {
            entries[index] = entry
            saveEntries(entries)
            logger.info("Updated entry: uuid=\(uuid)")
        }
        
        return true
    }
    
    /// Mark an entry for deletion (soft delete)
    func markEntryForDeletion(uuid: UUID) -> Bool {
        var entries = getAllEntries(includeDeleted: true)
        
        guard let index = entries.firstIndex(where: { $0.uuid == uuid }) else {
            logger.warning("Entry not found for deletion: \(uuid)")
            return false
        }
        
        var entry = entries[index]
        entry = TempHealthMetric(
            uuid: entry.uuid,
            metricTypeId: entry.metricTypeId,
            value: entry.value,
            date: entry.date,
            source: entry.source,
            healthkitId: entry.healthkitId,
            backendId: entry.backendId,
            syncStatus: .pendingDelete
        )
        
        entries[index] = entry
        saveEntries(entries)
        
        logger.info("Marked entry for deletion: uuid=\(uuid)")
        return true
    }
    
    /// Permanently delete an entry (after successful backend sync)
    func permanentlyDeleteEntry(uuid: UUID) -> Bool {
        var entries = getAllEntries(includeDeleted: true)
        
        guard let index = entries.firstIndex(where: { $0.uuid == uuid }) else {
            logger.warning("Entry not found for permanent deletion: \(uuid)")
            return false
        }
        
        entries.remove(at: index)
        saveEntries(entries)
        
        logger.info("Permanently deleted entry: uuid=\(uuid)")
        return true
    }
    
    // MARK: - Query Operations
    
    /// Get all entries for a specific metric type
    func getEntries(metricTypeId: Int, includeDeleted: Bool = false) -> [TempHealthMetric] {
        let allEntries = getAllEntries(includeDeleted: includeDeleted)
        return allEntries.filter { $0.metricTypeId == metricTypeId }.sorted { $0.date > $1.date }
    }
    
    /// Get entries with pending sync operations
    func getPendingSyncEntries() -> [Any] {
        let allEntries = getAllEntries(includeDeleted: false)
        let pendingEntries = allEntries.filter { $0.syncStatus.isPending }
        logger.info("Found \(pendingEntries.count) entries pending sync")
        return pendingEntries
    }
    
    /// Check if entry exists by HealthKit ID (for deduplication)
    func entryExists(healthkitId: String) -> Bool {
        let allEntries = getAllEntries(includeDeleted: false)
        return allEntries.contains { $0.healthkitId == healthkitId }
    }
    
    /// Get entry by UUID
    func getEntry(uuid: UUID) -> TempHealthMetric? {
        let allEntries = getAllEntries(includeDeleted: false)
        return allEntries.first { $0.uuid == uuid }
    }
    
    /// Get entry by backend ID
    func getEntry(backendId: Int) -> TempHealthMetric? {
        let allEntries = getAllEntries(includeDeleted: false)
        return allEntries.first { $0.backendId == backendId }
    }
    
    /// Get all entries
    func getAllEntries(includeDeleted: Bool = false) -> [TempHealthMetric] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([TempHealthMetric].self, from: data) else {
            return []
        }
        
        if includeDeleted {
            return entries.sorted { $0.date > $1.date }
        } else {
            return entries.filter { !$0.deletedLocally }.sorted { $0.date > $1.date }
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
        UserDefaults.standard.removeObject(forKey: storageKey)
        logger.info("Cleared all local database data")
    }
    
    /// Get statistics about local data
    func getDataStatistics() -> String {
        let allEntries = getAllEntries(includeDeleted: true)
        let activeEntries = getAllEntries(includeDeleted: false)
        let pendingEntries = getPendingSyncEntries()
        
        let healthKitEntries = allEntries.filter { $0.source == .healthKit }
        let localAppEntries = allEntries.filter { $0.source == .localApp }
        
        return """
        📊 Local Database Statistics:
        • Total entries: \(allEntries.count)
        • Active entries: \(activeEntries.count)
        • Pending sync: \(pendingEntries.count)
        • HealthKit entries: \(healthKitEntries.count)
        • Local app entries: \(localAppEntries.count)
        """
    }
    
    // MARK: - Private Methods
    
    private func saveEntries(_ entries: [TempHealthMetric]) {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            logger.error("Failed to save entries: \(error.localizedDescription)")
        }
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

// MARK: - Codable Extension for TempHealthMetric
extension TempHealthMetric: Codable {}