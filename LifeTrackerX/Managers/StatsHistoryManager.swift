import Foundation
import SwiftUI

class StatsHistoryManager: ObservableObject {
    // Shared singleton instance
    static let shared = StatsHistoryManager()
    
    @Published var entries: [StatEntry] = []
    // Add a refresh trigger to force view updates
    @Published var refreshTrigger: UUID = UUID()
    private let saveKey = "StatsHistory"
    
    // Flag to track if Apple Health entries have been synced to backend
    private var appleHealthEntriesSynced = false
    
    // Reference to HealthManager and MetricSyncManager
    private let healthManager = HealthManager()
    private var metricSyncManager: MetricSyncManager {
        MetricSyncManager.shared
    }
    
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
    
    // Function to sync all manual entries to Apple Health
    func syncManualEntriesToHealthKit() {
        guard healthManager.isWriteAuthorized else { 
            print("⚠️ Cannot sync manual entries to HealthKit - write access not available")
            return 
        }
        
        print("📤 Starting sync of all manual entries to Apple Health")
        
        // Get all manual entries that aren't BMI (since BMI is calculated)
        let manualEntries = entries.filter { $0.source == .manual && $0.type != .bmi }
        print("📤 Found \(manualEntries.count) manual entries to sync")
        
        for entry in manualEntries {
            healthManager.saveToHealthKit(entry) { success, error, _ in
                if success {
                    print("✅ Successfully synced historical \(entry.type) to Apple Health")
                } else if let error = error {
                    print("❌ Error syncing historical data to Apple Health: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Prevent concurrent or repeated syncs
    private var isAppleHealthSyncInProgress = false

    // Function to sync Apple Health entries to backend
    @MainActor
    func syncAppleHealthEntriesToBackend() {
        // Avoid concurrent/infinite sync loops
        if isAppleHealthSyncInProgress {
            print("⏳ Apple Health sync already in progress, skipping")
            return
        }

        // Check if we've already synced Apple Health entries
        if appleHealthEntriesSynced {
            print("📤 Apple Health entries already synced to backend, skipping")
            return
        }
        
        isAppleHealthSyncInProgress = true
        print("📤 Starting sync of Apple Health entries to backend")
        
        // Get all Apple Health entries that aren't calculated and not yet associated to backend
        // Also skip entries that are already queued for creation to avoid duplicates
        let pending = MetricSyncManager.shared.getPendingOperations()
        let pendingClientUUIDs = Set(pending.filter { $0.operationType == .create }.map { $0.entryId })
        let appleHealthEntries = entries.filter {
            $0.source == .appleHealth && !$0.type.isCalculated && $0.backendId == nil && !pendingClientUUIDs.contains($0.id)
        }
        print("📤 Found \(appleHealthEntries.count) Apple Health entries to sync to backend (backendId == nil)")
        
        for entry in appleHealthEntries {
            Task { @MainActor in
                metricSyncManager.syncEntry(entry, operation: .create)
            }
        }
        
        // Mark as synced for this session; will be reset if new Apple Health entries arrive
        appleHealthEntriesSynced = true
        isAppleHealthSyncInProgress = false
    }
    
    // Function to sync all entries to backend database
    func syncAllEntriesToBackend() {
        print("📤 Starting sync of all entries to backend database")
        
        // Get all non-calculated entries
        let entriesToSync = entries.filter { !$0.type.isCalculated }
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
        let weightEntries = entries.filter { $0.type == .weight }.sorted { $0.date < $1.date }
        let heightEntries = entries.filter { $0.type == .height }.sorted { $0.date < $1.date }
        let bodyFatEntries = entries.filter { $0.type == .bodyFat }.sorted { $0.date < $1.date }
        
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
        
        // Use client UUID as identity: replace if same id
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
            if entry.source == .appleHealth {
                appleHealthEntriesSynced = false
            }
        }
        
        // Sort entries by date (newest first)
        entries.sort { $0.date > $1.date }
        
        // If this is a weight, height, or body fat entry, recalculate all derived values
        if entry.type == .weight || entry.type == .height || entry.type == .bodyFat {
            recalculateAllDerivedValues()
        } else {
            saveEntries()
        }
        
        // Queue create for backend for non-calculated metrics; don't skip Apple Health (server dedup via client_uuid)
        if !entry.type.isCalculated {
            print("📤 Queue create to backend: \(entry.type)")
            Task { @MainActor in
                metricSyncManager.syncEntry(entry, operation: .create)
            }
        }
        
        // If manual entry and authorized, save to HealthKit; update id to HK uuid returned
        if entry.source == .manual && !entry.type.isCalculated && healthManager.isWriteAuthorized {
            healthManager.saveToHealthKit(entry) { success, error, healthKitUUID in
                if success, let hkId = healthKitUUID {
                    print("✅ Synced \(entry.type) to Apple Health with UUID \(hkId.uuidString)")
                    // For entries saved to HK, adopt HealthKit's UUID as client_uuid per spec
                    // Need to replace the original entry (with entry.id) with the new HealthKit UUID
                    if let idx = self.entries.firstIndex(where: { $0.id == entry.id }) {
                        var updated = self.entries[idx]
                        updated.id = hkId
                        self.entries[idx] = updated
                        self.saveEntries()
                        self.triggerUpdate()
                    }
                } else if let error = error {
                    print("❌ Error syncing to Apple Health: \(error.localizedDescription)")
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
        
        for entry in newEntries {
            if let index = entries.firstIndex(where: {
                Calendar.current.isDate($0.date, inSameDayAs: entry.date) &&
                $0.type == entry.type &&
                $0.source == entry.source
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
            Task { @MainActor in
                self.syncAppleHealthEntriesToBackend()
            }
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
        
        entries.removeAll { $0.id == entry.id }
        
        // Sync to backend database (for all non-calculated metrics)
        if !entry.type.isCalculated {
            print("📤 Syncing deleted entry to backend: \(entry.type)")
            Task { @MainActor in
                metricSyncManager.syncEntry(entry, operation: .delete)
            }
        }
        
        // If this is a weight or height entry, recalculate BMI entries
        if entry.type == .weight || entry.type == .height {
            recalculateAllDerivedValues()
        }
        
        // If this was a manual entry written to HealthKit, delete by UUID if possible
        if entry.source == .manual && healthManager.isWriteAuthorized {
            healthManager.deleteFromHealthKit(byUUID: entry.id, type: entry.type) { success, error in
                if success {
                    print("Successfully deleted \(entry.type) from Apple Health by UUID")
                } else if let error = error {
                    print("Error deleting from Apple Health: \(error.localizedDescription)")
                }
            }
        } else if entry.source == .manual && !healthManager.isWriteAuthorized {
            print("⚠️ Cannot delete from HealthKit - write access not available")
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
            let oldEntry = entries[index]
            var updated = entry
            
            // Increment version for manual/Android edits; Apple Health edits may change id externally
            if oldEntry.source != .appleHealth {
                updated.version = oldEntry.version + 1
            }
            entries[index] = updated
            
            // Sync to backend database (for all non-calculated metrics)
            if !updated.type.isCalculated {
                print("📤 Queue update to backend: \(updated.type)")
                Task { @MainActor in
                    metricSyncManager.syncEntry(updated, operation: .update)
                }
            }
            
            // If this is a manual entry and we're authorized, update in HealthKit
            if oldEntry.source == .manual && updated.type != .bmi && healthManager.isWriteAuthorized {
                print("📤 Syncing updated entry to Apple Health")
                // Delete old by UUID then save new; adopt new UUID
                healthManager.deleteFromHealthKit(byUUID: oldEntry.id, type: updated.type) { success, error in
                    if success {
                        self.healthManager.saveToHealthKit(updated) { success, error, healthKitUUID in
                            if success, let hkId = healthKitUUID {
                                // Update the entry in place with the new HealthKit UUID
                                if let idx = self.entries.firstIndex(where: { $0.id == updated.id }) {
                                    self.entries[idx].id = hkId
                                    self.saveEntries()
                                    self.triggerUpdate()
                                }
                                print("✅ Successfully saved updated entry to Apple Health with new UUID")
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
            if updated.type == .weight || updated.type == .height {
                recalculateAllDerivedValues()
            }
            
            saveEntries()
            triggerUpdate()
        }
    }


    
    func getLatestValue(for type: StatType) -> Double? {
        let typeEntries = entries.filter { $0.type == type }
        if let latest = typeEntries.sorted(by: { $0.date > $1.date }).first {
            return latest.value
        }
        return nil
    }
    
    func getEntries(for type: StatType) -> [StatEntry] {
        return entries.filter { $0.type == type }.sorted(by: { $0.date > $1.date })
    }
    
    func getEntries(for type: StatType, source: StatSource) -> [StatEntry] {
        return entries.filter { $0.type == type && $0.source == source }.sorted(by: { $0.date > $1.date })
    }
    
    func getEntriesAt(date: Date) -> [StatEntry] {
        var result: [StatEntry] = []
        
        let relevantTypes: [StatType] = [.weight, .height, .bodyFat, .bicep, .chest, .waist, .thigh, .shoulder, .glutes]
        
        for type in relevantTypes {
            // Find the most recent entry for this type on or before the given date
            if let latestEntry = entries.filter({ $0.type == type && $0.date <= date })
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

    // MARK: - Backend ID persistence helper
    func setBackendId(forClientUUID clientUUID: UUID, backendId: Int) {
        if let idx = entries.firstIndex(where: { $0.id == clientUUID }) {
            entries[idx].backendId = backendId
            saveEntries()
            triggerUpdate()
        }
    }
    
    private func loadEntries() {
        print("📱 Loading entries from storage...")
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([StatEntry].self, from: data) {
            entries = decoded
            print("📱 Loaded \(entries.count) total entries")
            print("📱 Weight entries: \(entries.filter { $0.type == .weight }.count)")
            print("📱 Height entries: \(entries.filter { $0.type == .height }.count)")
            print("📱 BMI entries: \(entries.filter { $0.type == .bmi }.count)")
            print("📱 Body Fat entries: \(entries.filter { $0.type == .bodyFat }.count)")
            
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
            let serverEntries = try await MetricSyncManager.shared.fetchUserMetrics()
            
            // Update UI on main thread
            await MainActor.run {
                // Clear existing entries and add server entries
                entries = serverEntries
                
                // Recalculate BMI entries
                recalculateAllDerivedValues()
                
                // Save to local storage
                saveEntries()
                
                // Trigger UI update
                triggerUpdate()
            }
            
            print("📱 Successfully loaded \(serverEntries.count) metrics from server")
        } catch {
            print("❌ Failed to load metrics from server: \(error.localizedDescription)")
            // Don't throw error - just log it and continue with empty data
            // This allows the app to work even if the endpoint doesn't exist yet
        }
    }
}
