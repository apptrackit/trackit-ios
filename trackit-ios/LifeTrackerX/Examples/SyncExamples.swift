import Foundation
import SwiftUI
import HealthKit

// MARK: - Integration Examples

/**
 This file demonstrates how to replace the existing HealthManager.swift usage
 with the new three-way sync system (Apple Health ↔ Local Storage ↔ Backend)
 */

struct SyncExamplesView: View {
    @ObservedObject private var syncCoordinator = SyncCoordinator.shared
    @State private var showingLogin = false
    @State private var isAddingMetric = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Sync Status
                SyncStatusCard()
                
                // Authentication
                AuthenticationSection()
                
                // Manual Entry Examples  
                ManualEntrySection()
                
                // Data Display Examples
                DataDisplaySection()
                
                Spacer()
            }
            .padding()
            .navigationTitle("Sync Examples")
        }
        .sheet(isPresented: $isAddingMetric) {
            AddMetricSheet()
        }
    }
}

// MARK: - Sync Status Card

struct SyncStatusCard: View {
    @ObservedObject private var syncCoordinator = SyncCoordinator.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync Status")
                .font(.headline)
            
            SyncStatusView()
            
            HStack {
                Button("Sync Now") {
                    Task {
                        await syncCoordinator.performFullSync()
                    }
                }
                .disabled(syncCoordinator.overallStatus == .syncing)
                
                Spacer()
                
                Button("Settings") {
                    // Navigate to sync settings
                }
                .buttonStyle(.bordered)
            }
            
            // Data Summary
            let summary = syncCoordinator.getDataSummary()
            VStack(alignment: .leading, spacing: 4) {
                Text("Data Summary")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                HStack {
                    Text("Total: \(summary.totalMetrics)")
                    Spacer()
                    Text("HealthKit: \(summary.healthKitMetrics)")
                    Spacer()
                    Text("Manual: \(summary.manualMetrics)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                HStack {
                    Text("Pending HealthKit: \(summary.pendingHealthKitSync)")
                    Spacer()
                    Text("Pending Backend: \(summary.pendingBackendSync)")
                }
                .font(.caption)
                .foregroundColor(summary.pendingHealthKitSync > 0 || summary.pendingBackendSync > 0 ? .orange : .secondary)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Authentication Section

struct AuthenticationSection: View {
    @ObservedObject private var syncCoordinator = SyncCoordinator.shared
    @State private var showingLogin = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Authentication")
                .font(.headline)
            
            // HealthKit Authorization
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                
                Text("Apple Health")
                
                Spacer()
                
                Button(syncCoordinator.healthKitSync.isAuthorized ? "Authorized" : "Authorize") {
                    Task {
                        await requestHealthKitAccess()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(syncCoordinator.healthKitSync.isAuthorized)
            }
            
            // Backend Authentication  
            HStack {
                Image(systemName: "cloud.fill")
                    .foregroundColor(.blue)
                
                Text("Backend")
                
                Spacer()
                
                if syncCoordinator.backendSync.isAuthenticated {
                    Button("Logout") {
                        Task {
                            await syncCoordinator.logout()
                        }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Login") {
                        showingLogin = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showingLogin) {
            LoginSheet()
        }
    }
    
    private func requestHealthKitAccess() async {
        let success = await syncCoordinator.requestHealthKitAuthorization()
        
        if success {
            print("✅ HealthKit authorization granted")
            // Trigger initial sync
            await syncCoordinator.performFullSync()
        } else {
            print("❌ HealthKit authorization denied")
        }
    }
}

// MARK: - Manual Entry Section

struct ManualEntrySection: View {
    @State private var showingAddMetric = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Manual Entry Examples")
                    .font(.headline)
                
                Spacer()
                
                Button("Add Metric") {
                    showingAddMetric = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Quick Entry Buttons
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach([MetricType.weight, .height, .bodyFat, .waist], id: \.self) { type in
                    QuickEntryButton(metricType: type)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showingAddMetric) {
            AddMetricSheet()
        }
    }
}

struct QuickEntryButton: View {
    let metricType: MetricType
    @State private var showingEntry = false
    
    var body: some View {
        Button(action: {
            showingEntry = true
        }) {
            VStack {
                Text(metricType.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(metricType.defaultUnit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
        .sheet(isPresented: $showingEntry) {
            QuickEntrySheet(metricType: metricType)
        }
    }
}

// MARK: - Data Display Section

struct DataDisplaySection: View {
    @ObservedObject private var syncCoordinator = SyncCoordinator.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Metrics")
                .font(.headline)
            
            let recentMetrics = syncCoordinator.getAllMetrics().prefix(5)
            
            if recentMetrics.isEmpty {
                Text("No metrics available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(Array(recentMetrics), id: \.id) { metric in
                    MetricRow(metric: metric)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

struct MetricRow: View {
    let metric: Metric
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(metric.value, specifier: "%.1f") \(metric.unit)")
                    .font(.caption)
                    .foregroundColor(.primary)
                
                Text(metric.date, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                // Source indicator
                HStack(spacing: 4) {
                    Image(systemName: metric.source == .health ? "heart.fill" : "hand.tap.fill")
                        .font(.caption2)
                        .foregroundColor(metric.source == .health ? .red : .blue)
                    
                    Text(metric.source.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Sync status indicators
                HStack(spacing: 4) {
                    if metric.syncedWithHealth {
                        Image(systemName: "heart.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    
                    if metric.syncedWithBackend {
                        Image(systemName: "cloud.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    
                    if !metric.syncedWithHealth || !metric.syncedWithBackend {
                        Image(systemName: "clock.circle")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sheets and Modals

struct LoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            Form {
                Section("Account") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    SecureField("Password", text: $password)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button("Login") {
                        Task {
                            await performLogin()
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isLoggingIn)
                }
            }
            .navigationTitle("Backend Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func performLogin() async {
        isLoggingIn = true
        errorMessage = nil
        
        let success = await SyncCoordinator.shared.login(username: username, password: password)
        
        await MainActor.run {
            isLoggingIn = false
            
            if success {
                dismiss()
            } else {
                errorMessage = "Login failed. Please check your credentials."
            }
        }
    }
}

struct AddMetricSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType = MetricType.weight
    @State private var value = ""
    @State private var date = Date()
    @State private var isSaving = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Metric Details") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(MetricType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    HStack {
                        TextField("Value", text: $value)
                            .keyboardType(.decimalPad)
                        
                        Text(selectedType.defaultUnit)
                            .foregroundColor(.secondary)
                    }
                    
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section {
                    Button("Save Metric") {
                        Task {
                            await saveMetric()
                        }
                    }
                    .disabled(value.isEmpty || isSaving)
                }
            }
            .navigationTitle("Add Metric")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveMetric() async {
        guard let numValue = Double(value) else { return }
        
        isSaving = true
        
        let metric = Metric(
            value: numValue,
            type: selectedType,
            source: .manual,
            date: date,
            unit: selectedType.defaultUnit
        )
        
        let success = await SyncCoordinator.shared.addManualEntry(metric)
        
        await MainActor.run {
            isSaving = false
            
            if success {
                dismiss()
            }
        }
    }
}

struct QuickEntrySheet: View {
    let metricType: MetricType
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var isSaving = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Quick Entry") {
                    Text(metricType.displayName)
                        .font(.headline)
                    
                    HStack {
                        TextField("Value", text: $value)
                            .keyboardType(.decimalPad)
                        
                        Text(metricType.defaultUnit)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button("Save") {
                        Task {
                            await saveQuickEntry()
                        }
                    }
                    .disabled(value.isEmpty || isSaving)
                }
            }
            .navigationTitle("Add \(metricType.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveQuickEntry() async {
        guard let numValue = Double(value) else { return }
        
        isSaving = true
        
        let metric = Metric(
            value: numValue,
            type: metricType,
            source: .manual,
            date: Date(),
            unit: metricType.defaultUnit
        )
        
        let success = await SyncCoordinator.shared.addManualEntry(metric)
        
        await MainActor.run {
            isSaving = false
            
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - Code Examples

/**
 MIGRATION GUIDE: Replacing existing HealthManager usage
 
 OLD CODE (HealthManager.swift):
 ```swift
 let healthManager = HealthManager()
 healthManager.requestHealthAuthorization()
 healthManager.importAllHealthData(historyManager: StatsHistoryManager.shared) { success in
     // Handle result
 }
 ```
 
 NEW CODE (SyncCoordinator):
 ```swift
 let syncCoordinator = SyncCoordinator.shared
 
 // Request authorization
 Task {
     let success = await syncCoordinator.requestHealthKitAuthorization()
     if success {
         await syncCoordinator.performFullSync()
     }
 }
 
 // Add manual entry
 let metric = Metric(
     value: 70.5,
     type: .weight,
     source: .manual,
     date: Date(),
     unit: "kg"
 )
 
 Task {
     let success = await syncCoordinator.addManualEntry(metric)
     // Automatically syncs to HealthKit and Backend
 }
 
 // Get data
 let weightMetrics = syncCoordinator.getMetrics(for: .weight)
 let latestWeight = syncCoordinator.getLatestMetric(for: .weight)
 ```
 */

// MARK: - SwiftUI Views Integration

struct ContentViewExample: View {
    @ObservedObject private var syncCoordinator = SyncCoordinator.shared
    
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "house")
                }
            
            MetricsListView()
                .tabItem {
                    Label("Metrics", systemImage: "list.bullet")
                }
            
            SyncSettingsView()
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .environmentObject(syncCoordinator)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var syncCoordinator: SyncCoordinator
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Sync status at the top
                    SyncStatusView()
                        .padding()
                        .background(Color(.systemGroupedBackground))
                        .cornerRadius(12)
                    
                    // Quick stats
                    ForEach([MetricType.weight, .height, .bodyFat], id: \.self) { type in
                        if let latestMetric = syncCoordinator.getLatestMetric(for: type) {
                            MetricCardView(metric: latestMetric)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable {
                await syncCoordinator.performIncrementalSync()
            }
        }
    }
}

struct MetricCardView: View {
    let metric: Metric
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(metric.type.displayName)
                    .font(.headline)
                
                Text("\(metric.value, specifier: "%.1f") \(metric.unit)")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(metric.date, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Source and sync indicators
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: metric.source == .health ? "heart.fill" : "hand.tap.fill")
                    .foregroundColor(metric.source == .health ? .red : .blue)
                
                HStack(spacing: 2) {
                    if metric.syncedWithHealth {
                        Image(systemName: "heart.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    if metric.syncedWithBackend {
                        Image(systemName: "cloud.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

struct MetricsListView: View {
    @EnvironmentObject private var syncCoordinator: SyncCoordinator
    @State private var selectedType = MetricType.weight
    
    var body: some View {
        NavigationView {
            VStack {
                // Type picker
                Picker("Metric Type", selection: $selectedType) {
                    ForEach(MetricType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Metrics list
                List {
                    ForEach(syncCoordinator.getMetrics(for: selectedType), id: \.id) { metric in
                        MetricRow(metric: metric)
                    }
                }
            }
            .navigationTitle("Metrics")
            .refreshable {
                await syncCoordinator.performIncrementalSync()
            }
        }
    }
}

struct SyncSettingsView: View {
    @EnvironmentObject private var syncCoordinator: SyncCoordinator
    
    var body: some View {
        NavigationView {
            Form {
                Section("Status") {
                    SyncStatusView()
                    
                    Button("Sync Now") {
                        Task {
                            await syncCoordinator.performFullSync()
                        }
                    }
                    .disabled(syncCoordinator.overallStatus == .syncing)
                }
                
                Section("Auto-Sync") {
                    Toggle("Auto-Sync Enabled", isOn: $syncCoordinator.autoSyncEnabled)
                    
                    if syncCoordinator.autoSyncEnabled {
                        Stepper("Interval: \(Int(syncCoordinator.syncInterval / 60)) minutes", 
                               value: .init(get: {
                                   syncCoordinator.syncInterval / 60
                               }, set: { newValue in
                                   syncCoordinator.updateAutoSyncSettings(
                                       enabled: syncCoordinator.autoSyncEnabled,
                                       interval: newValue * 60
                                   )
                               }), 
                               in: 1...60)
                    }
                }
                
                Section("Data Summary") {
                    let summary = syncCoordinator.getDataSummary()
                    
                    LabeledContent("Total Metrics", value: "\(summary.totalMetrics)")
                    LabeledContent("HealthKit Metrics", value: "\(summary.healthKitMetrics)")
                    LabeledContent("Manual Metrics", value: "\(summary.manualMetrics)")
                    LabeledContent("Pending HealthKit Sync", value: "\(summary.pendingHealthKitSync)")
                    LabeledContent("Pending Backend Sync", value: "\(summary.pendingBackendSync)")
                }
                
                Section("Actions") {
                    Button("Clear All Data", role: .destructive) {
                        syncCoordinator.clearAllData()
                    }
                }
            }
            .navigationTitle("Sync Settings")
        }
    }
}

// MARK: - Preview Providers

#if DEBUG
struct SyncExamplesView_Previews: PreviewProvider {
    static var previews: some View {
        SyncExamplesView()
    }
}
#endif