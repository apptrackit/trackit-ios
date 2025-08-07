import Foundation
import Combine
import os.log

// MARK: - Stats History Manager (Updated for compatibility)
@MainActor
class StatsHistoryManager: ObservableObject {
    static let shared = StatsHistoryManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "StatsHistory")
    private let localDatabase = LocalDatabaseManager.shared
    private let userActionHandler = UserActionHandler.shared
    
    // MARK: - Published Properties
    @Published var entries: [StatEntry] = []
    @Published var isLoading = false
    @Published var lastUpdated = Date()
    @Published var hasAppleHealthData = false
    @Published var hasSyncedToHealthKit = false
    @Published var hasSyncedToBackend = false
    
    // MARK: - Filtering and Statistics
    @Published var activeTimeFrame: TimeFrame = .all
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        setupObservers()
        loadEntries()
        
        // Attempt migration on first launch if no entries
        if entries.isEmpty {
            migrateFromOldSystem()
        }
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Observe changes to local database
        NotificationCenter.default
            .publisher(for: NSNotification.Name("LocalDatabaseChanged"))
            .sink { [weak self] _ in
                self?.loadEntries()
            }
            .store(in: &cancellables)
        
        // Observe sync status changes
        userActionHandler.$syncStatus
            .sink { [weak self] status in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        logger.info("StatsHistoryManager observers setup completed")
    }
    
    // MARK: - Data Loading
    
    func loadEntries() {
        isLoading = true
        logger.info("Loading entries from local database")
        
        // Get all entries from local database
        let dbEntries = localDatabase.getAllEntries(includeDeleted: false)
        
        // Convert to StatEntry format
        var statEntries: [StatEntry] = []
        for dbEntry in dbEntries {
            if let statEntry = dbEntry.toStatEntry() {
                statEntries.append(statEntry)
            }
        }
        
        // Add derived metrics (BMI, LBM, etc.)
        let entriesWithDerived = addDerivedMetrics(to: statEntries)
        
        // Sort by date (newest first)
        entries = entriesWithDerived.sorted { $0.date > $1.date }
        
        lastUpdated = Date()
        isLoading = false
        
        // Update status flags
        hasAppleHealthData = entries.contains { $0.source == .appleHealth }
        
        logger.info("Loaded \(entries.count) entries (\(statEntries.count) base + derived)")
    }
    
    // MARK: - Entry Management
    
    func addEntry(_ entry: StatEntry) {
        logger.info("Adding entry: \(entry.type.rawValue) = \(entry.value)")
        
        userActionHandler.handleUserAdd(entry) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.logger.info("Entry added successfully")
                    self?.loadEntries() // Reload to get the new entry
                } else {
                    self?.logger.error("Failed to add entry: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    func updateEntry(_ entry: StatEntry) {
        logger.info("Updating entry: \(entry.id) = \(entry.value)")
        
        userActionHandler.handleUserEdit(entry) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.logger.info("Entry updated successfully")
                    self?.loadEntries() // Reload to get the updated entry
                } else {
                    self?.logger.error("Failed to update entry: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    func removeEntry(_ entry: StatEntry) {
        logger.info("Removing entry: \(entry.id)")
        
        userActionHandler.handleUserDelete(entry) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.logger.info("Entry removed successfully")
                    self?.loadEntries() // Reload to reflect the removal
                } else {
                    self?.logger.error("Failed to remove entry: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    func addEntries(_ newEntries: [StatEntry]) {
        logger.info("Adding \(newEntries.count) entries in batch")
        
        let mappedEntries = newEntries.map { entry in
            (metricTypeId: entry.type.metricTypeId, value: entry.value, date: entry.date)
        }
        
        userActionHandler.handleBatchAdd(entries: mappedEntries) { [weak self] successCount, totalCount, error in
            DispatchQueue.main.async {
                self?.logger.info("Batch add completed: \(successCount)/\(totalCount) successful")
                self?.loadEntries() // Reload to get the new entries
                
                if let error = error {
                    self?.logger.error("Batch add error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Derived Metrics Calculation
    
    private func addDerivedMetrics(to baseEntries: [StatEntry]) -> [StatEntry] {
        var allEntries = baseEntries
        
        // Calculate BMI
        let bmiEntries = calculateBMI(from: baseEntries)
        allEntries.append(contentsOf: bmiEntries)
        
        // Calculate Lean Body Mass
        let lbmEntries = calculateLBM(from: baseEntries)
        allEntries.append(contentsOf: lbmEntries)
        
        // Calculate Body Fat Mass
        let bfmEntries = calculateBFM(from: baseEntries)
        allEntries.append(contentsOf: bfmEntries)
        
        return allEntries
    }
    
    private func calculateBMI(from entries: [StatEntry]) -> [StatEntry] {
        let weights = entries.filter { $0.type == .weight }.sorted { $0.date < $1.date }
        let heights = entries.filter { $0.type == .height }.sorted { $0.date < $1.date }
        
        guard !weights.isEmpty && !heights.isEmpty else { return [] }
        
        var bmiEntries: [StatEntry] = []
        
        for weight in weights {
            // Find the most recent height before or on the weight date
            let relevantHeight = heights.last { $0.date <= weight.date } ?? heights.first
            
            if let height = relevantHeight {
                let heightInMeters = height.value / 100.0 // Convert cm to m
                let bmi = weight.value / (heightInMeters * heightInMeters)
                
                let bmiEntry = StatEntry(
                    id: UUID(),
                    date: weight.date,
                    value: bmi,
                    type: .bmi,
                    source: .automated,
                    backendId: nil
                )
                
                bmiEntries.append(bmiEntry)
            }
        }
        
        return bmiEntries
    }
    
    private func calculateLBM(from entries: [StatEntry]) -> [StatEntry] {
        let weights = entries.filter { $0.type == .weight }.sorted { $0.date < $1.date }
        let bodyFats = entries.filter { $0.type == .bodyFat }.sorted { $0.date < $1.date }
        
        guard !weights.isEmpty && !bodyFats.isEmpty else { return [] }
        
        var lbmEntries: [StatEntry] = []
        
        for weight in weights {
            // Find the most recent body fat % before or on the weight date
            let relevantBodyFat = bodyFats.last { $0.date <= weight.date } ?? bodyFats.first
            
            if let bodyFat = relevantBodyFat {
                let lbm = weight.value * (1 - bodyFat.value / 100.0)
                
                let lbmEntry = StatEntry(
                    id: UUID(),
                    date: weight.date,
                    value: lbm,
                    type: .leanBodyMass,
                    source: .automated,
                    backendId: nil
                )
                
                lbmEntries.append(lbmEntry)
            }
        }
        
        return lbmEntries
    }
    
    private func calculateBFM(from entries: [StatEntry]) -> [StatEntry] {
        let weights = entries.filter { $0.type == .weight }.sorted { $0.date < $1.date }
        let bodyFats = entries.filter { $0.type == .bodyFat }.sorted { $0.date < $1.date }
        
        guard !weights.isEmpty && !bodyFats.isEmpty else { return [] }
        
        var bfmEntries: [StatEntry] = []
        
        for weight in weights {
            // Find the most recent body fat % before or on the weight date
            let relevantBodyFat = bodyFats.last { $0.date <= weight.date } ?? bodyFats.first
            
            if let bodyFat = relevantBodyFat {
                let bfm = weight.value * (bodyFat.value / 100.0)
                
                let bfmEntry = StatEntry(
                    id: UUID(),
                    date: weight.date,
                    value: bfm,
                    type: .bodyFatMass,
                    source: .automated,
                    backendId: nil
                )
                
                bfmEntries.append(bfmEntry)
            }
        }
        
        return bfmEntries
    }
    
    // MARK: - Data Import and Sync
    
    func startHealthKitImport() {
        logger.info("Starting HealthKit import")
        isLoading = true
        
        userActionHandler.handleHealthKitImport { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if success {
                    self?.logger.info("HealthKit import completed successfully")
                    self?.hasAppleHealthData = true
                    self?.loadEntries()
                } else {
                    self?.logger.error("HealthKit import failed: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    func forceSyncToBackend() async {
        logger.info("Force syncing to backend")
        await userActionHandler.forceSyncAll()
        hasSyncedToBackend = true
        
        // Reload entries to reflect any sync status changes
        loadEntries()
    }
    
    func forceSyncFromBackend() async {
        logger.info("Force syncing from backend")
        await userActionHandler.forceSyncFromBackend()
        
        // Reload entries to get any new data from backend
        loadEntries()
    }
    
    // MARK: - Data Migration
    
    func migrateFromOldSystem() {
        logger.info("Attempting migration from old UserDefaults system")
        
        // Check if we have data in the old system
        let oldStorageKey = "statEntries"
        guard let data = UserDefaults.standard.data(forKey: oldStorageKey),
              let oldEntries = try? JSONDecoder().decode([StatEntry].self, from: data),
              !oldEntries.isEmpty else {
            logger.info("No old data found to migrate")
            return
        }
        
        logger.info("Found \(oldEntries.count) entries to migrate")
        
        // Add entries through the new system
        addEntries(oldEntries)
        
        // Clear old data after successful migration
        UserDefaults.standard.removeObject(forKey: oldStorageKey)
        UserDefaults.standard.removeObject(forKey: "hasImportedFromAppleHealth")
        UserDefaults.standard.removeObject(forKey: "hasSyncedManualEntriesToHealthKit")
        UserDefaults.standard.removeObject(forKey: "hasSyncedAppleHealthEntriesToBackend")
        
        logger.info("Migration completed and old data cleared")
    }
    
    // MARK: - Filtering and Queries
    
    func getEntries(for type: StatType) -> [StatEntry] {
        return entries.filter { $0.type == type }
    }
    
    func getEntriesInTimeFrame(_ timeFrame: TimeFrame) -> [StatEntry] {
        let now = Date()
        let calendar = Calendar.current
        
        let startDate: Date
        switch timeFrame {
        case .week:
            startDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths:
            startDate = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .sixMonths:
            startDate = calendar.date(byAdding: .month, value: -6, to: now) ?? now
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .all:
            return entries
        }
        
        return entries.filter { $0.date >= startDate }
    }
    
    func getLatestEntry(for type: StatType) -> StatEntry? {
        return entries.filter { $0.type == type }.max { $0.date < $1.date }
    }
    
    // MARK: - Statistics
    
    func getStatistics() -> String {
        let totalEntries = entries.count
        let baseEntries = entries.filter { !$0.type.isCalculated }.count
        let derivedEntries = entries.filter { $0.type.isCalculated }.count
        let healthKitEntries = entries.filter { $0.source == .appleHealth }.count
        let manualEntries = entries.filter { $0.source == .manual }.count
        
        return """
        📊 Data Statistics:
        • Total entries: \(totalEntries)
        • Base entries: \(baseEntries)
        • Derived entries: \(derivedEntries)
        • HealthKit entries: \(healthKitEntries)
        • Manual entries: \(manualEntries)
        • Last updated: \(lastUpdated.formatted())
        
        \(userActionHandler.getSyncStatus())
        """
    }
    
    // MARK: - Legacy Methods for Backward Compatibility
    
    func syncManualEntriesToHealthKit() {
        logger.info("Legacy method: syncManualEntriesToHealthKit - calling startHealthKitImport")
        startHealthKitImport()
    }
    
    func syncAppleHealthEntriesToBackend() {
        logger.info("Legacy method: syncAppleHealthEntriesToBackend - calling forceSyncToBackend")
        Task {
            await forceSyncToBackend()
        }
    }
    
    func syncAllEntriesToBackend() {
        logger.info("Legacy method: syncAllEntriesToBackend - calling forceSyncToBackend")
        Task {
            await forceSyncToBackend()
        }
    }
    
    func resetAppleHealthSyncFlag() {
        logger.info("Legacy method: resetAppleHealthSyncFlag - calling startHealthKitImport")
        startHealthKitImport()
    }
    
    func loadMetricsFromServer() async {
        logger.info("Legacy method: loadMetricsFromServer - calling forceSyncFromBackend")
        await forceSyncFromBackend()
    }
    
    private func recalculateAllDerivedValues() {
        logger.info("Legacy method: recalculateAllDerivedValues - calling loadEntries")
        loadEntries()
    }
    
    // Legacy properties and methods that may be used by views
    func saveEntries() {
        logger.info("Legacy method: saveEntries - data is automatically saved")
        // Data is now automatically saved through LocalDatabaseManager
    }
    
    func clearAllEntries() {
        logger.info("Clearing all entries")
        localDatabase.clearAllData()
        loadEntries()
    }
    
    func clearEntries(for type: StatType) {
        logger.info("Clearing entries for type: \(type.rawValue)")
        let entriesToClear = entries.filter { $0.type == type && !$0.type.isCalculated }
        
        for entry in entriesToClear {
            removeEntry(entry)
        }
    }
}
