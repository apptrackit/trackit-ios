# TrackIt iOS - Three-Way Sync Migration Guide

This guide explains how to migrate from your existing `HealthManager.swift` implementation to the new robust three-way sync system.

## 🎯 What's New

### Before: Simple HealthKit Integration
- Direct HealthKit → StatsHistoryManager sync
- No offline support
- No conflict resolution
- Manual sync only
- Buggy and unreliable

### After: Three-Way Sync Architecture
- **Apple Health** ↔ **Local Storage** ↔ **Backend API**
- Offline-first with UUID deduplication
- Automatic conflict resolution using timestamps
- Background sync with anchored queries
- Real-time sync status and error handling

## 📁 New File Structure

```
LifeTrackerX/
├── Models/
│   └── MetricModels.swift              # Core data models with sync flags
├── Storage/
│   └── LocalStorageManager.swift       # Core Data persistence layer
├── Managers/
│   ├── HealthKitSyncManager.swift      # HealthKit integration
│   ├── BackendSyncManager.swift        # Backend API communication
│   └── SyncCoordinator.swift           # Main sync orchestrator
├── Examples/
│   └── SyncExamples.swift              # Usage examples and migration guide
└── Views/
    └── Components/
        └── SyncStatusView.swift        # Built-in sync status UI
```

## 🔄 Migration Steps

### 1. Replace HealthManager References

**Old Code:**
```swift
import HealthKit

class ViewController {
    let healthManager = HealthManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Request authorization
        healthManager.requestHealthAuthorization()
        
        // Import data
        healthManager.importAllHealthData(historyManager: StatsHistoryManager.shared) { success in
            DispatchQueue.main.async {
                // Handle result
            }
        }
    }
}
```

**New Code:**
```swift
import SwiftUI

class ViewController {
    let syncCoordinator = SyncCoordinator.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        Task {
            // Request HealthKit authorization
            let healthKitSuccess = await syncCoordinator.requestHealthKitAuthorization()
            
            // Login to backend
            let backendSuccess = await syncCoordinator.login(username: "user", password: "pass")
            
            if healthKitSuccess && backendSuccess {
                // Perform full sync across all three sources
                await syncCoordinator.performFullSync()
            }
        }
    }
}
```

### 2. Update Manual Entry Logic

**Old Code:**
```swift
func addWeight(_ weight: Double) {
    let entry = StatEntry(date: Date(), value: weight, type: .weight, source: .manual)
    
    // Save to StatsHistoryManager
    StatsHistoryManager.shared.addEntry(entry)
    
    // Try to save to HealthKit
    healthManager.saveToHealthKit(entry) { success, error in
        // Handle result
    }
    
    // Manual backend sync
    NetworkManager.shared.uploadEntry(entry)
}
```

**New Code:**
```swift
func addWeight(_ weight: Double) async {
    let metric = Metric(
        value: weight,
        type: .weight,
        source: .manual,
        date: Date(),
        unit: "kg"
    )
    
    // Automatically saves to local storage, syncs to HealthKit, and queues for backend
    let success = await syncCoordinator.addManualEntry(metric)
    
    if success {
        print("✅ Weight added and synced across all sources")
    }
}
```

### 3. Update Data Retrieval

**Old Code:**
```swift
func getWeightHistory() -> [StatEntry] {
    return StatsHistoryManager.shared.getEntries(for: .weight, source: .all)
}

func getLatestWeight() -> StatEntry? {
    let entries = StatsHistoryManager.shared.getEntries(for: .weight, source: .all)
    return entries.sorted(by: { $0.date > $1.date }).first
}
```

**New Code:**
```swift
func getWeightHistory() -> [Metric] {
    return syncCoordinator.getMetrics(for: .weight)
}

func getLatestWeight() -> Metric? {
    return syncCoordinator.getLatestMetric(for: .weight)
}
```

### 4. SwiftUI Integration

**Old Approach:**
```swift
struct ContentView: View {
    @ObservedObject var healthManager = HealthManager()
    @ObservedObject var statsManager = StatsHistoryManager.shared
    
    var body: some View {
        VStack {
            if healthManager.fetchingStatus.isEmpty {
                Text("Ready")
            } else {
                Text(healthManager.fetchingStatus)
            }
            
            // Manual sync button
            Button("Sync HealthKit") {
                healthManager.importAllHealthData(historyManager: statsManager) { _ in }
            }
        }
    }
}
```

**New Approach:**
```swift
struct ContentView: View {
    @ObservedObject var syncCoordinator = SyncCoordinator.shared
    
    var body: some View {
        VStack {
            // Built-in sync status component
            SyncStatusView()
            
            // Automatic sync with pull-to-refresh
            List(syncCoordinator.getAllMetrics(), id: \.id) { metric in
                MetricRow(metric: metric)
            }
            .refreshable {
                await syncCoordinator.performIncrementalSync()
            }
        }
        .task {
            // Auto-sync on app launch
            await syncCoordinator.performFullSync()
        }
    }
}
```

## 🔧 Configuration Setup

### 1. Environment Configuration

Add to your app's environment (e.g., in Info.plist or environment variables):

```swift
// Set your backend URL
ProcessInfo.processInfo.environment["BACKEND_URL"] = "https://your-trackit-backend.com"
```

### 2. Permissions (Info.plist)

The new system requires the same HealthKit permissions:

```xml
<key>NSHealthShareUsageDescription</key>
<string>TrackIt needs access to read your health data to sync with your metrics.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>TrackIt needs access to write health data to keep your metrics in sync.</string>
```

### 3. Background App Refresh

For automatic sync, enable background app refresh:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>background-processing</string>
    <string>background-fetch</string>
</array>
```

## 🎛️ Key Features Comparison

| Feature | Old System | New System |
|---------|------------|------------|
| **Data Storage** | StatsHistoryManager only | Core Data + Cloud sync |
| **HealthKit Sync** | Manual import/export | Live anchored queries |
| **Backend Sync** | Manual API calls | Automatic with conflict resolution |
| **Offline Support** | None | Full offline-first |
| **Conflict Resolution** | None | Timestamp-based |
| **Deduplication** | Basic date checking | UUID-based across sources |
| **Error Handling** | Basic | Comprehensive with retry logic |
| **Sync Status** | Basic strings | Rich status with indicators |
| **Background Sync** | None | Automatic with timers |

## 📱 Usage Examples

### Authentication Flow
```swift
// Check if already authenticated
if !syncCoordinator.isConnected {
    // Request HealthKit access
    let healthKitSuccess = await syncCoordinator.requestHealthKitAuthorization()
    
    // Login to backend
    let backendSuccess = await syncCoordinator.login(username: username, password: password)
    
    if healthKitSuccess && backendSuccess {
        // Perform initial sync
        await syncCoordinator.performFullSync()
    }
}
```

### Manual Data Entry
```swift
// Add weight measurement
let weightMetric = Metric(
    value: 75.5,
    type: .weight,
    source: .manual,
    date: Date(),
    unit: "kg"
)

let success = await syncCoordinator.addManualEntry(weightMetric)
// Automatically syncs to HealthKit and backend
```

### Data Retrieval with Sync Status
```swift
// Get weight history
let weightMetrics = syncCoordinator.getMetrics(for: .weight)

// Check sync status for each metric
for metric in weightMetrics {
    print("Weight: \(metric.value)")
    print("Synced with HealthKit: \(metric.syncedWithHealth)")
    print("Synced with Backend: \(metric.syncedWithBackend)")
    print("Source: \(metric.source.displayName)")
}
```

### Real-time Sync Status
```swift
struct SyncStatusIndicator: View {
    @ObservedObject var syncCoordinator = SyncCoordinator.shared
    
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
            
            Text(syncCoordinator.statusDescription)
            
            if syncCoordinator.overallStatus == .syncing {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }
    
    private var statusIcon: String {
        switch syncCoordinator.overallStatus {
        case .synced: return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .offline: return "wifi.slash"
        default: return "exclamationmark.triangle"
        }
    }
    
    private var statusColor: Color {
        switch syncCoordinator.overallStatus {
        case .synced: return .green
        case .syncing: return .blue
        case .offline: return .gray
        default: return .orange
        }
    }
}
```

## 🐛 Migration Checklist

- [ ] **Remove old HealthManager references**
  - Delete or comment out HealthManager usage
  - Remove StatsHistoryManager direct calls
  - Update NetworkManager usage

- [ ] **Add new sync system files**
  - Copy MetricModels.swift
  - Copy LocalStorageManager.swift
  - Copy HealthKitSyncManager.swift
  - Copy BackendSyncManager.swift
  - Copy SyncCoordinator.swift

- [ ] **Update UI code**
  - Replace manual sync buttons with SyncCoordinator calls
  - Add SyncStatusView component
  - Update data retrieval logic
  - Add pull-to-refresh support

- [ ] **Test sync scenarios**
  - Manual entry sync to HealthKit and backend
  - HealthKit import and backend sync
  - Offline mode and sync when online
  - Conflict resolution with timestamp comparison
  - App background and foreground sync

- [ ] **Configure auto-sync**
  - Set sync intervals in settings
  - Enable background app refresh
  - Test periodic sync functionality

## 🚨 Common Issues & Solutions

### Issue: Core Data crashes on first launch
**Solution:** The system creates the Core Data model programmatically, but ensure you don't have conflicting .xcdatamodeld files.

### Issue: HealthKit authorization not working
**Solution:** Ensure Info.plist permissions are correct and you're not calling authorization too frequently.

### Issue: Backend authentication failing
**Solution:** Check BACKEND_URL environment variable and verify credentials with your backend.

### Issue: Duplicate entries appearing
**Solution:** The new system prevents duplicates via UUID tracking. If migrating existing data, run a one-time cleanup.

### Issue: Sync status not updating in UI
**Solution:** Ensure you're using @ObservedObject for SyncCoordinator in your SwiftUI views.

## 🔄 Data Migration

If you have existing data in the old system, create a one-time migration:

```swift
func migrateExistingData() async {
    let existingEntries = StatsHistoryManager.shared.getAllEntries()
    
    for entry in existingEntries {
        let metric = Metric(
            value: entry.value,
            type: entry.type,
            source: entry.source == .appleHealth ? .health : .manual,
            date: entry.date,
            unit: entry.type.defaultUnit,
            syncedWithBackend: false, // Will sync on next backend sync
            syncedWithHealth: entry.source == .appleHealth
        )
        
        _ = storage.createMetric(metric)
    }
    
    // Trigger full sync to upload migrated data
    await syncCoordinator.performFullSync()
    
    print("✅ Migrated \(existingEntries.count) existing entries")
}
```

## 📊 Benefits Summary

✅ **Reliability**: UUID-based deduplication eliminates duplicate entries  
✅ **Offline Support**: Works without internet, syncs when available  
✅ **Conflict Resolution**: Automatic timestamp-based conflict handling  
✅ **Real-time Updates**: Live HealthKit monitoring with anchored queries  
✅ **Better UX**: Rich sync status indicators and error messages  
✅ **Scalability**: Designed for future feature additions  
✅ **Maintainability**: Clean separation of concerns with distinct managers  

The new system transforms your app from a basic HealthKit integration into a robust, enterprise-ready sync solution that works seamlessly across Apple Health, local storage, and your backend API.