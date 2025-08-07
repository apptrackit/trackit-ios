import Foundation
import CoreData
import HealthKit
import Combine

// MARK: - Core Data Entity (Manual Creation)
@objc(MetricEntity)
public class MetricEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var healthKitUUID: String?
    @NSManaged public var value: Double
    @NSManaged public var typeRawValue: String
    @NSManaged public var sourceRawValue: String
    @NSManaged public var date: Date
    @NSManaged public var unit: String
    @NSManaged public var lastUpdatedAt: Date
    @NSManaged public var syncedWithHealth: Bool
    @NSManaged public var syncedWithBackend: Bool
    @NSManaged public var isDeleted: Bool
    @NSManaged public var backendId: String?
    @NSManaged public var userId: Int32
}

// MARK: - Local Storage Manager
class LocalStorageManager: ObservableObject {
    static let shared = LocalStorageManager()
    
    @Published var syncStatus = SyncStatus()
    
    private let containerName = "MetricDataModel"
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: containerName)
        
        // Create the data model programmatically since we don't have .xcdatamodeld
        let model = createDataModel()
        container = NSPersistentContainer(name: containerName, managedObjectModel: model)
        
        container.loadPersistentStores { _, error in
            if let error = error {
                print("❌ Core Data error: \(error)")
                fatalError("Core Data error: \(error)")
            }
            print("✅ Core Data loaded successfully")
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        return container
    }()
    
    private var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    private init() {
        loadSyncStatus()
    }
    
    // MARK: - Data Model Creation
    private func createDataModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        
        // Create MetricEntity
        let metricEntity = NSEntityDescription()
        metricEntity.name = "MetricEntity"
        metricEntity.managedObjectClassName = NSStringFromClass(MetricEntity.self)
        
        // Add attributes
        let attributes: [(String, NSAttributeType, Bool)] = [
            ("id", .UUIDAttributeType, false),
            ("healthKitUUID", .stringAttributeType, true),
            ("value", .doubleAttributeType, false),
            ("typeRawValue", .stringAttributeType, false),
            ("sourceRawValue", .stringAttributeType, false),
            ("date", .dateAttributeType, false),
            ("unit", .stringAttributeType, false),
            ("lastUpdatedAt", .dateAttributeType, false),
            ("syncedWithHealth", .booleanAttributeType, false),
            ("syncedWithBackend", .booleanAttributeType, false),
            ("isDeleted", .booleanAttributeType, false),
            ("backendId", .stringAttributeType, true),
            ("userId", .integer32AttributeType, false)
        ]
        
        metricEntity.properties = attributes.map { (name, type, isOptional) in
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = isOptional
            
            // Set default values
            switch name {
            case "syncedWithHealth", "syncedWithBackend", "isDeleted":
                attribute.defaultValue = false
            case "userId":
                attribute.defaultValue = Int32(0)
            default:
                break
            }
            
            return attribute
        }
        
        // Add unique constraints
        metricEntity.uniquenessConstraints = [["id"]]
        
        model.entities = [metricEntity]
        
        return model
    }
    
    // MARK: - CRUD Operations
    
    func save() {
        if context.hasChanges {
            do {
                try context.save()
                updateSyncStatus()
            } catch {
                print("❌ Error saving context: \(error)")
            }
        }
    }
    
    func createMetric(_ metric: Metric) -> MetricEntity? {
        let entity = MetricEntity(context: context)
        updateEntity(entity, with: metric)
        save()
        return entity
    }
    
    func getAllMetrics(includeDeleted: Bool = false) -> [Metric] {
        let request: NSFetchRequest<MetricEntity> = NSFetchRequest(entityName: "MetricEntity")
        
        if !includeDeleted {
            request.predicate = NSPredicate(format: "isDeleted == FALSE")
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MetricEntity.date, ascending: false)]
        
        do {
            let entities = try context.fetch(request)
            return entities.compactMap { convertToMetric($0) }
        } catch {
            print("❌ Error fetching metrics: \(error)")
            return []
        }
    }
    
    func getMetrics(type: MetricType, includeDeleted: Bool = false) -> [Metric] {
        let request: NSFetchRequest<MetricEntity> = NSFetchRequest(entityName: "MetricEntity")
        
        var predicates = [NSPredicate(format: "typeRawValue == %@", type.rawValue)]
        if !includeDeleted {
            predicates.append(NSPredicate(format: "isDeleted == FALSE"))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MetricEntity.date, ascending: false)]
        
        do {
            let entities = try context.fetch(request)
            return entities.compactMap { convertToMetric($0) }
        } catch {
            print("❌ Error fetching metrics for type \(type): \(error)")
            return []
        }
    }
    
    func getMetric(by id: UUID) -> Metric? {
        let request: NSFetchRequest<MetricEntity> = NSFetchRequest(entityName: "MetricEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        do {
            let entities = try context.fetch(request)
            return entities.first.flatMap { convertToMetric($0) }
        } catch {
            print("❌ Error fetching metric by id: \(error)")
            return nil
        }
    }
    
    func getMetric(by healthKitUUID: String) -> Metric? {
        let request: NSFetchRequest<MetricEntity> = NSFetchRequest(entityName: "MetricEntity")
        request.predicate = NSPredicate(format: "healthKitUUID == %@", healthKitUUID)
        request.fetchLimit = 1
        
        do {
            let entities = try context.fetch(request)
            return entities.first.flatMap { convertToMetric($0) }
        } catch {
            print("❌ Error fetching metric by HealthKit UUID: \(error)")
            return nil
        }
    }
    
    func getMetric(by backendId: String) -> Metric? {
        let request: NSFetchRequest<MetricEntity> = NSFetchRequest(entityName: "MetricEntity")
        request.predicate = NSPredicate(format: "backendId == %@", backendId)
        request.fetchLimit = 1
        
        do {
            let entities = try context.fetch(request)
            return entities.first.flatMap { convertToMetric($0) }
        } catch {
            print("❌ Error fetching metric by backend ID: \(error)")
            return nil
        }
    }
    
    func updateMetric(_ metric: Metric) -> Bool {
        let request: NSFetchRequest<MetricEntity> = NSFetchRequest(entityName: "MetricEntity")
        request.predicate = NSPredicate(format: "id == %@", metric.id as CVarArg)
        request.fetchLimit = 1
        
        do {
            let entities = try context.fetch(request)
            guard let entity = entities.first else { return false }
            
            updateEntity(entity, with: metric)
            save()
            return true
        } catch {
            print("❌ Error updating metric: \(error)")
            return false
        }
    }
    
    func deleteMetric(_ metric: Metric, soft: Bool = true) -> Bool {
        if soft {
            var updatedMetric = metric
            updatedMetric.isDeleted = true
            updatedMetric.lastUpdatedAt = Date()
            updatedMetric.syncedWithBackend = false
            return updateMetric(updatedMetric)
        } else {
            // Hard delete
            let request: NSFetchRequest<MetricEntity> = NSFetchRequest(entityName: "MetricEntity")
            request.predicate = NSPredicate(format: "id == %@", metric.id as CVarArg)
            
            do {
                let entities = try context.fetch(request)
                for entity in entities {
                    context.delete(entity)
                }
                save()
                return true
            } catch {
                print("❌ Error deleting metric: \(error)")
                return false
            }
        }
    }
    
    // MARK: - Sync-specific Operations
    
    func getUnsyncedHealthKitMetrics() -> [Metric] {
        let request: NSFetchRequest<MetricEntity> = NSFetchRequest(entityName: "MetricEntity")
        request.predicate = NSPredicate(format: "syncedWithHealth == FALSE AND sourceRawValue == %@", MetricSource.manual.rawValue)
        
        do {
            let entities = try context.fetch(request)
            return entities.compactMap { convertToMetric($0) }
        } catch {
            print("❌ Error fetching unsynced HealthKit metrics: \(error)")
            return []
        }
    }
    
    func getUnsyncedBackendMetrics() -> [Metric] {
        let request: NSFetchRequest<MetricEntity> = NSFetchRequest(entityName: "MetricEntity")
        request.predicate = NSPredicate(format: "syncedWithBackend == FALSE")
        
        do {
            let entities = try context.fetch(request)
            return entities.compactMap { convertToMetric($0) }
        } catch {
            print("❌ Error fetching unsynced backend metrics: \(error)")
            return []
        }
    }
    
    func getMetricsUpdatedSince(_ date: Date) -> [Metric] {
        let request: NSFetchRequest<MetricEntity> = NSFetchRequest(entityName: "MetricEntity")
        request.predicate = NSPredicate(format: "lastUpdatedAt > %@", date as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MetricEntity.lastUpdatedAt, ascending: true)]
        
        do {
            let entities = try context.fetch(request)
            return entities.compactMap { convertToMetric($0) }
        } catch {
            print("❌ Error fetching metrics updated since date: \(error)")
            return []
        }
    }
    
    // MARK: - Deduplication
    
    func findDuplicateMetric(type: MetricType, date: Date, source: MetricSource, excludeId: UUID? = nil) -> Metric? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let request: NSFetchRequest<MetricEntity> = NSFetchRequest(entityName: "MetricEntity")
        
        var predicates = [
            NSPredicate(format: "typeRawValue == %@", type.rawValue),
            NSPredicate(format: "sourceRawValue == %@", source.rawValue),
            NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate),
            NSPredicate(format: "isDeleted == FALSE")
        ]
        
        if let excludeId = excludeId {
            predicates.append(NSPredicate(format: "id != %@", excludeId as CVarArg))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 1
        
        do {
            let entities = try context.fetch(request)
            return entities.first.flatMap { convertToMetric($0) }
        } catch {
            print("❌ Error finding duplicate metric: \(error)")
            return nil
        }
    }
    
    // MARK: - Conflict Resolution
    
    func resolveConflict(localMetric: Metric, remoteMetric: Metric) -> Metric {
        // Always prefer the metric with the latest timestamp
        if remoteMetric.lastUpdatedAt > localMetric.lastUpdatedAt {
            print("🔄 Conflict resolved: Using remote metric (newer)")
            return remoteMetric
        } else {
            print("🔄 Conflict resolved: Using local metric (newer)")
            return localMetric
        }
    }
    
    // MARK: - Sync Status Management
    
    private func loadSyncStatus() {
        if let data = UserDefaults.standard.data(forKey: "SyncStatus"),
           let status = try? JSONDecoder().decode(SyncStatus.self, from: data) {
            self.syncStatus = status
        }
    }
    
    private func saveSyncStatus() {
        if let data = try? JSONEncoder().encode(syncStatus) {
            UserDefaults.standard.set(data, forKey: "SyncStatus")
        }
    }
    
    func updateSyncStatus() {
        syncStatus.pendingHealthKitCount = getUnsyncedHealthKitMetrics().count
        syncStatus.pendingBackendCount = getUnsyncedBackendMetrics().count
        saveSyncStatus()
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func setSyncTimestamp(healthKit: Date? = nil, backend: Date? = nil) {
        if let healthKit = healthKit {
            syncStatus.lastHealthKitSync = healthKit
        }
        if let backend = backend {
            syncStatus.lastBackendSync = backend
        }
        saveSyncStatus()
    }
    
    func setHealthKitAnchor(_ anchor: HKQueryAnchor) {
        // Convert to data for storage (HKQueryAnchor isn't directly Codable)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "HealthKitAnchor")
        }
    }
    
    func getHealthKitAnchor() -> HKQueryAnchor? {
        if let data = UserDefaults.standard.data(forKey: "HealthKitAnchor"),
           let anchor = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? HKQueryAnchor {
            return anchor
        }
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func updateEntity(_ entity: MetricEntity, with metric: Metric) {
        entity.id = metric.id
        entity.healthKitUUID = metric.healthKitUUID
        entity.value = metric.value
        entity.typeRawValue = metric.type.rawValue
        entity.sourceRawValue = metric.source.rawValue
        entity.date = metric.date
        entity.unit = metric.unit
        entity.lastUpdatedAt = metric.lastUpdatedAt
        entity.syncedWithHealth = metric.syncedWithHealth
        entity.syncedWithBackend = metric.syncedWithBackend
        entity.isDeleted = metric.isDeleted
        entity.backendId = metric.backendId
        entity.userId = Int32(metric.userId ?? 0)
    }
    
    private func convertToMetric(_ entity: MetricEntity) -> Metric? {
        guard let type = MetricType(rawValue: entity.typeRawValue),
              let source = MetricSource(rawValue: entity.sourceRawValue) else {
            return nil
        }
        
        return Metric(
            id: entity.id,
            healthKitUUID: entity.healthKitUUID,
            value: entity.value,
            type: type,
            source: source,
            date: entity.date,
            unit: entity.unit,
            lastUpdatedAt: entity.lastUpdatedAt,
            syncedWithHealth: entity.syncedWithHealth,
            syncedWithBackend: entity.syncedWithBackend,
            isDeleted: entity.isDeleted,
            backendId: entity.backendId,
            userId: entity.userId != 0 ? Int(entity.userId) : nil
        )
    }
    
    // MARK: - Batch Operations
    
    func saveMetrics(_ metrics: [Metric]) -> Bool {
        for metric in metrics {
            let entity = MetricEntity(context: context)
            updateEntity(entity, with: metric)
        }
        
        save()
        return true
    }
    
    func clearAllData() {
        let request: NSFetchRequest<MetricEntity> = NSFetchRequest(entityName: "MetricEntity")
        
        do {
            let entities = try context.fetch(request)
            for entity in entities {
                context.delete(entity)
            }
            save()
            
            // Reset sync status
            syncStatus = SyncStatus()
            saveSyncStatus()
            
        } catch {
            print("❌ Error clearing all data: \(error)")
        }
    }
    
    // MARK: - Compatibility Bridge Methods
    
    // Convert all metrics to StatEntries for compatibility with existing UI
    func getAllStatEntries() -> [StatEntry] {
        return getAllMetrics().map { $0.toStatEntry() }
    }
    
    // Get latest value for a specific stat type
    func getLatestValue(for statType: StatType) -> Double? {
        let metricType = MetricType.fromStatType(statType)
        return getMetrics(type: metricType).first?.value
    }
    
    // Get entries for a specific stat type and source
    func getEntries(for statType: StatType, source: StatEntry.Source = .all) -> [StatEntry] {
        let metricType = MetricType.fromStatType(statType)
        let metrics = getMetrics(type: metricType)
        
        let filteredMetrics: [Metric]
        switch source {
        case .manual:
            filteredMetrics = metrics.filter { $0.source == .manual }
        case .appleHealth:
            filteredMetrics = metrics.filter { $0.source == .health }
        case .all:
            filteredMetrics = metrics
        }
        
        return filteredMetrics.map { $0.toStatEntry() }
    }
    
    // Add entry from existing StatEntry
    func addEntry(_ entry: StatEntry) {
        let metric = Metric.fromStatEntry(entry)
        _ = createMetric(metric)
    }
}