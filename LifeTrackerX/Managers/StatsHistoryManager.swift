import Foundation
import SwiftUI

class StatsHistoryManager: ObservableObject {
    // Shared singleton instance
    static let shared = StatsHistoryManager()
    
    @Published var entries: [StatEntry] = []
    // Add a refresh trigger to force view updates
    @Published var refreshTrigger: UUID = UUID()
    private let saveKey = "StatsHistory"
    private let lastSyncKey = "MetricsLastServerSyncTimestamp"
    
    // Flag to track if Apple Health entries have been synced to backend
    private var appleHealthEntriesSynced = false
    
    // Reference to HealthManager and MetricSyncManager
    private let healthManager = HealthManager()
    private let metricSyncManager = MetricSyncManager.shared
    
    // Make init private to enforce singleton pattern
    private init() {
        loadEntries()
        // Reset sync flag on app start to ensure fresh sync
        appleHealthEntriesSynced = false
    }
    
    // Add this method to force UI updates
    func triggerUpdate() {
        DispatchQueue.main.async {
            self.refreshTrigger = UUID()
            self.objectWillChange.send()
        }
    }
    
    // Last server sync timestamp for incremental sync
    var lastServerSyncTimestamp: Date? {
        get {
            if let isoString = UserDefaults.standard.string(forKey: lastSyncKey) {
                if let date = DateCoding.iso8601.date(from: isoString) ?? DateCoding.iso8601NoFraction.date(from: isoString) {
                    return date
                }
            }
            return nil
        }
        set {
            if let newValue = newValue {
                let iso = DateCoding.iso8601.string(from: newValue)
                UserDefaults.standard.set(iso, forKey: lastSyncKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastSyncKey)
            }
        }
    }
    
    // Function to sync all manual entries to Apple Health
    func syncManualEntriesToHealthKit() {
        guard healthManager.isWriteAuthorized else { 
            print("⚠️ Cannot sync manual entries to HealthKit - write access not available")
            return 
        }
        
        print("📤 Starting sync of all manual entries to Apple Health")
        
        // Get all manual entries that aren't BMI (since BMI is calculated)
        let manualEntries = entries.filter { $0.source == .manual && $0.type != .bmi && !$0.isDeleted }
        print("📤 Found \(manualEntries.count) manual entries to sync")
        
        for entry in manualEntries {
            healthManager.saveToHealthKit(entry) { success, error in
                if success {
                    print("✅ Successfully synced historical \(entry.type) to Apple Health")
                } else if let error = error {
                    print("❌ Error syncing historical data to Apple Health: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Function to sync Apple Health entries to backend
    func syncAppleHealthEntriesToBackend() {
        // Check if we've already synced Apple Health entries
        if appleHealthEntriesSynced {
            print("📤 Apple Health entries already synced to backend, skipping")
            return
        }
        
        print("📤 Starting sync of Apple Health entries to backend")
        
        // Get all Apple Health entries that aren't calculated
        let appleHealthEntries = entries.filter { $0.source == .appleHealth && !$0.type.isCalculated && !$0.isDeleted }
        print("📤 Found \(appleHealthEntries.count) Apple Health entries to sync to backend")
        
        for entry in appleHealthEntries {
            Task { @MainActor in
                metricSyncManager.syncEntry(entry, operation: .create)
            }
        }
        
        // Mark as synced
        appleHealthEntriesSynced = true
    }
    
    // Function to sync all entries to backend database
    func syncAllEntriesToBackend() {
        print("📤 Starting sync of all entries to backend database")
        
        // Get all non-calculated entries
        let entriesToSync = entries.filter { !$0.type.isCalculated && !$0.isDeleted }
        print("📤 Found \(entriesToSync.count) entries to sync to backend")
        
        Task { @MainActor in
            metricSyncManager.syncAllEntries(entriesToSync)
        }
    }
    
    // Function to reset Apple Health sync flag (for debugging)
    func resetAppleHealthSyncFlag() {
        appleHealthEntriesSynced = false
        print("🔄 Apple Health sync flag reset")
    }
    
    private func recalculateAllDerivedValues() {
        print("🔄 Recalculating all derived values...")
        
        // Get all entries sorted by date
        let weightEntries = entries.filter { $0.type == .weight && !$0.isDeleted }.sorted { $0.date < $1.date }
        let heightEntries = entries.filter { $0.type == .height && !$0.isDeleted }.sorted { $0.date < $1.date }
        let bodyFatEntries = entries.filter { $0.type == .bodyFat && !$0.isDeleted }.sorted { $0.date < $1.date }
        
        // Remove all existing calculated entries
        entries.removeAll { $0.type.isCalculated }
        
        // For each weight entry, calculate all possible derived values
        for weightEntry in weightEntries {
            let date = weightEntry.date
            let weight = weightEntry.value
            
            // Find the most recent height and body fat at this time
            if let height = heightEntries.last(where: { $0.date <= date })?.value {
                // Calculate BMI
                let heightInMeters = height / 100
                let bmi = weight / (heightInMeters * heightInMeters)
                entries.append(StatEntry(
                    date: date,
                    value: bmi,
                    type: .bmi,
                    source: .automated
                ))
                
                // If we have body fat, calculate LBM, FM, FFMI, BMR
                if let bodyFat = bodyFatEntries.last(where: { $0.date <= date })?.value {
                    // Calculate LBM
                    let lbm = weight * (1 - bodyFat / 100)
                    entries.append(StatEntry(
                        date: date,
                        value: lbm,
                        type: .lbm,
                        source: .automated
                    ))
                    
                    // Calculate FM
                    let fm = weight * (bodyFat / 100)
                    entries.append(StatEntry(
                        date: date,
                        value: fm,
                        type: .fm,
                        source: .automated
                    ))
                    
                    // Calculate FFMI
                    let ffmi = lbm / (heightInMeters * heightInMeters)
                    entries.append(StatEntry(
                        date: date,
                        value: ffmi,
                        type: .ffmi,
                        source: .automated
                    ))
                    
                    // Calculate BMR
                    let bmr = 370 + (21.6 * lbm)
                    entries.append(StatEntry(
                        date: date,
                        value: bmr,
                        type: .bmr,
                        source: .automated
                    ))
                }
                
                // Calculate BSA
                let bsa = sqrt((height * weight) / 3600)
                entries.append(StatEntry(
                    date: date,
                    value: bsa,
                    type: .bsa,
                    source: .automated
                ))
            }
        }
        
        // Sort entries by date (newest first)
        entries.sort { $0.date > $1.date }
        saveEntries()
        
        // Force UI refresh
        triggerUpdate()
    }
    
    func addEntry(_ entry: StatEntry) {
        // Need to ensure we're on the main thread when modifying @Published properties
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.addEntry(entry)
            }
            return
        }
        
        var newEntry = entry
        newEntry.lastUpdatedAt = Date()
        newEntry.syncedWithBackend = false
        
        // Only replace if the entry has the same date, type and source
        if let index = entries.firstIndex(where: {
            Calendar.current.isDate($0.date, inSameDayAs: newEntry.date) &&
            $0.type == newEntry.type &&
            $0.source == newEntry.source &&
            !$0.isDeleted
        }) {
            entries[index] = newEntry
        } else {
            entries.append(newEntry)
            
            // If this is a new Apple Health entry, reset the sync flag
            if newEntry.source == .appleHealth {
                appleHealthEntriesSynced = false
            }
        }
        
        // Sort entries by date (newest first)
        entries.sort { $0.date > $1.date }
        
        // If this is a weight, height, or body fat entry, recalculate all derived values
        if newEntry.type == .weight || newEntry.type == .height || newEntry.type == .bodyFat {
            recalculateAllDerivedValues()
        } else {
            saveEntries()
        }
        
        // Sync to backend database (for all non-calculated metrics, but not Apple Health entries during import)
        if !newEntry.type.isCalculated && newEntry.source != .appleHealth && !newEntry.isDeleted {
            print("📤 Syncing entry to backend: \(newEntry.type)")
            Task { @MainActor in
                metricSyncManager.syncEntry(newEntry, operation: .create)
            }
        }
        
        // If this is a manual entry and not from Apple Health, sync to HealthKit
        if newEntry.source == .manual && !newEntry.type.isCalculated {
            if healthManager.isWriteAuthorized {
                healthManager.saveToHealthKit(newEntry) { success, error in
                    if success {
                        print("✅ Synced \(newEntry.type) to Apple Health")
                    } else if let error = error {
                        print("❌ Error syncing to Apple Health: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Force UI refresh
        triggerUpdate()
    }

    func addEntries(_ newEntries: [StatEntry]) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.addEntries(newEntries)
            }
            return
        }

        var hasAppleHealthEntries = false
        
        for var entry in newEntries {
            // Ensure sync metadata exists
            entry.lastUpdatedAt = entry.lastUpdatedAt
            
            if let index = entries.firstIndex(where: {
                ($0.uuid != nil && $0.uuid == entry.uuid) ||
                (Calendar.current.isDate($0.date, inSameDayAs: entry.date) && $0.type == entry.type && $0.source == entry.source)
            }) {
                entries[index] = entry
            } else {
                entries.append(entry)
                if entry.source == .appleHealth {
                    appleHealthEntriesSynced = false
                    hasAppleHealthEntries = true
                }
            }
        }

        entries.sort { $0.date > $1.date }
        recalculateAllDerivedValues()
        
        // If we added Apple Health entries, sync them to backend after all entries are added
        if hasAppleHealthEntries {
            syncAppleHealthEntriesToBackend()
        }
        
        triggerUpdate()
    }
    
    func removeEntry(_ entry: StatEntry) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.removeEntry(entry)
            }
            return
        }
        
        // Soft delete: mark as deleted but keep for sync
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].isDeleted = true
            entries[index].lastUpdatedAt = Date()
            entries[index].syncedWithBackend = false
            
            let deletedEntry = entries[index]
            
            // Sync to backend database (for all non-calculated metrics)
            if !deletedEntry.type.isCalculated {
                print("📤 Syncing deleted entry to backend: \(deletedEntry.type)")
                Task { @MainActor in
                    metricSyncManager.syncEntry(deletedEntry, operation: .delete)
                }
            }
            
            // If this was a manual entry that we previously wrote to HealthKit, attempt to delete it there
            if deletedEntry.source == .manual && healthManager.isWriteAuthorized && deletedEntry.syncedWithHealth {
                healthManager.deleteFromHealthKit(deletedEntry) { success, error in
                    if success {
                        print("Successfully deleted \(deletedEntry.type) from Apple Health")
                    } else if let error = error {
                        print("Error deleting from Apple Health: \(error.localizedDescription)")
                    }
                }
            } else if deletedEntry.source == .manual && !healthManager.isWriteAuthorized {
                print("⚠️ Cannot delete from HealthKit - write access not available")
            }
        }
        
        saveEntries()
        triggerUpdate()
    }
    
    func updateEntry(_ entry: StatEntry) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.updateEntry(entry)
            }
            return
        }
        
        print("📝 Updating entry: type=\(entry.type), source=\(entry.source), value=\(entry.value)")
        
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            var updatedEntry = entry
            updatedEntry.lastUpdatedAt = Date()
            updatedEntry.syncedWithBackend = false
            
            let oldEntry = entries[index]
            entries[index] = updatedEntry
            
            // Sync to backend database (for all non-calculated metrics)
            if !updatedEntry.type.isCalculated {
                if updatedEntry.isDeleted {
                    print("📤 Syncing soft-deleted entry to backend: \(updatedEntry.type)")
                    Task { @MainActor in
                        metricSyncManager.syncEntry(updatedEntry, operation: .delete)
                    }
                } else {
                    print("📤 Syncing updated entry to backend: \(updatedEntry.type)")
                    Task { @MainActor in
                        metricSyncManager.syncEntry(updatedEntry, operation: .update)
                    }
                }
            }
            
            // If this is a manual entry and we're authorized, update in HealthKit
            if oldEntry.source == .manual && updatedEntry.type != .bmi && healthManager.isWriteAuthorized {
                print("📤 Syncing updated entry to Apple Health")
                
                // First delete the old entry from HealthKit
                healthManager.deleteFromHealthKit(oldEntry) { success, error in
                    if success {
                        print("✅ Successfully deleted old entry from Apple Health")
                        // Then save the new entry to HealthKit
                        self.healthManager.saveToHealthKit(updatedEntry) { success, error in
                            if success {
                                print("✅ Successfully saved updated entry to Apple Health")
                            } else if let error = error {
                                print("❌ Error saving updated entry to Apple Health: \(error.localizedDescription)")
                            }
                        }
                    } else if let error = error {
                        print("❌ Error deleting old entry from Apple Health: \(error.localizedDescription)")
                    }
                }
            }
            
            // If this is a weight or height entry, recalculate BMI entries
            if updatedEntry.type == .weight || updatedEntry.type == .height {
                recalculateAllDerivedValues()
            }
            
            saveEntries()
            triggerUpdate()
        }
    }
    
    func getLatestValue(for type: StatType) -> Double? {
        let typeEntries = entries.filter { $0.type == type && !$0.isDeleted }
        if let latest = typeEntries.sorted(by: { $0.date > $1.date }).first {
            return latest.value
        }
        return nil
    }
    
    func getEntries(for type: StatType) -> [StatEntry] {
        return entries.filter { $0.type == type && !$0.isDeleted }.sorted(by: { $0.date > $1.date })
    }
    
    func getEntries(for type: StatType, source: StatSource) -> [StatEntry] {
        return entries.filter { $0.type == type && $0.source == source && !$0.isDeleted }.sorted(by: { $0.date > $1.date })
    }
    
    func getEntriesAt(date: Date) -> [StatEntry] {
        var result: [StatEntry] = []
        
        let relevantTypes: [StatType] = [.weight, .height, .bodyFat, .bicep, .chest, .waist, .thigh, .shoulder, .glutes]
        
        for type in relevantTypes {
            // Find the most recent entry for this type on or before the given date
            if let latestEntry = entries.filter({ $0.type == type && $0.date <= date && !$0.isDeleted })
                .sorted(by: { $0.date > $1.date })
                .first {
                result.append(latestEntry)
            }
        }
        
        return result
    }
    
    private func saveEntries() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func loadEntries() {
        print("📱 Loading entries from storage...")
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([StatEntry].self, from: data) {
            entries = decoded
            print("📱 Loaded \(entries.count) total entries")
            print("📱 Weight entries: \(entries.filter { $0.type == .weight && !$0.isDeleted }.count)")
            print("📱 Height entries: \(entries.filter { $0.type == .height && !$0.isDeleted }.count)")
            print("📱 BMI entries: \(entries.filter { $0.type == .bmi && !$0.isDeleted }.count)")
            print("📱 Body Fat entries: \(entries.filter { $0.type == .bodyFat && !$0.isDeleted }.count)")
            
            // Recalculate BMI entries when loading data
            recalculateAllDerivedValues()
        } else {
            print("📱 No entries found in storage or failed to decode")
        }
    }
    
    // Debug function to clear all entries
    func clearAllEntries() {
        entries.removeAll()
        saveEntries()
        triggerUpdate()
    }
    
    // Function to clear only entries from a specific source
    func clearEntries(from source: StatSource) {
        entries.removeAll { $0.source == source }
        
        // Reset sync flag if Apple Health entries were cleared
        if source == .appleHealth {
            appleHealthEntriesSynced = false
        }
        
        // Recalculate BMI entries after clearing data
        recalculateAllDerivedValues()
        saveEntries()
        triggerUpdate()
    }
    
    // MARK: - Server Data Loading
    func loadMetricsFromServer() async {
        print("📱 Loading metrics from server...")
        
        do {
            if let since = lastServerSyncTimestamp {
                let sinceParam = DateCoding.iso8601.string(from: since)
                let url = "/api/metrics/sync/changes?since_timestamp=\(sinceParam)"
                let (data, httpResponse) = try await NetworkManager.shared.makeAuthenticatedRawRequest(url, method: "GET")
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw AuthError.unknown
                }
                let decoder = JSONDecoder()
                let response = try decoder.decode(SyncChangesResponseV2.self, from: data)
                
                await MainActor.run {
                    for dto in response.entries {
                        applyServerChange(dto)
                    }
                    // Save and update last sync time
                    saveEntries()
                    if let serverTime = DateCoding.iso8601.date(from: response.server_timestamp) ?? DateCoding.iso8601NoFraction.date(from: response.server_timestamp) {
                        lastServerSyncTimestamp = serverTime
                    }
                    triggerUpdate()
                }
                print("📱 Successfully merged \(response.entries.count) changes from server")
            } else {
                // Fallback initial load using legacy endpoint
                let serverEntries = try await MetricSyncManager.shared.fetchUserMetrics()
                await MainActor.run {
                    entries = serverEntries
                    recalculateAllDerivedValues()
                    saveEntries()
                    triggerUpdate()
                }
                print("📱 Successfully loaded \(serverEntries.count) metrics from server")
            }
        } catch {
            print("❌ Failed to load metrics from server: \(error.localizedDescription)")
            // Don't throw error - just log it and continue with existing data
        }
    }
    
    // Merge strategy per mobile sync rules
    private func applyServerChange(_ dto: MobileMetricEntryDTO) {
        // Map DTO to StatEntry
        let metricTypeName = dto.metric_type?.lowercased()
        let statType: StatType = {
            if let id = dto.metric_type_id, let backendType = BackendMetricType(rawValue: id) { return backendType.toStatType() }
            switch metricTypeName {
            case "weight": return .weight
            case "height": return .height
            case "body_fat": return .bodyFat
            case "waist": return .waist
            case "bicep": return .bicep
            case "chest": return .chest
            case "thigh": return .thigh
            case "shoulder": return .shoulder
            case "glutes": return .glutes
            case "calf": return .calf
            case "neck": return .neck
            case "forearm": return .forearm
            default: return .weight
            }
        }()
        
        let source: StatSource = (dto.source == "apple_health") ? .appleHealth : .manual
        
        let timestampString = dto.timestamp ?? dto.date
        let date: Date = {
            if let ts = timestampString {
                return DateCoding.iso8601.date(from: ts) ?? DateCoding.iso8601NoFraction.date(from: ts) ?? Date()
            }
            if let d = dto.date {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                return fmt.date(from: d) ?? Date()
            }
            return Date()
        }()
        
        let serverUpdatedAt: Date = {
            if let lu = dto.last_updated_at {
                return DateCoding.iso8601.date(from: lu) ?? DateCoding.iso8601NoFraction.date(from: lu) ?? Date()
            }
            return Date()
        }()
        
        let isDeleted = dto.is_deleted ?? false
        
        // Find local entry by UUID or date/type/source
        if let index = entries.firstIndex(where: { ($0.uuid == dto.id) || (Calendar.current.isDate($0.date, inSameDayAs: date) && $0.type == statType && $0.source == source) }) {
            var local = entries[index]
            // Conflict resolution: server wins if newer
            if serverUpdatedAt > local.lastUpdatedAt || local.isDeleted {
                local.value = dto.value
                local.unit = dto.unit ?? local.unit
                local.date = date
                local.uuid = dto.id
                local.lastUpdatedAt = serverUpdatedAt
                local.isDeleted = isDeleted
                local.syncedWithBackend = true
                entries[index] = local
            }
        } else {
            // New entry from server
            var entry = StatEntry(
                id: UUID(),
                date: date,
                value: dto.value,
                type: statType,
                source: source,
                backendId: nil,
                uuid: dto.id,
                lastUpdatedAt: serverUpdatedAt,
                syncedWithHealth: source == .appleHealth,
                syncedWithBackend: true,
                isDeleted: isDeleted,
                unit: dto.unit
            )
            entries.append(entry)
        }
        
        // Maintain calculated values after merging
        // (We will recalculate at the end of batch in caller)
    }
}
