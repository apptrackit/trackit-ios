import SwiftUI
import HealthKit

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var healthManager = HealthManager()
    @ObservedObject var historyManager: StatsHistoryManager
    @State private var showHealthAccessSheet = false
    @State private var showExportSheet = false
    
    // Computed property to check if Apple Health is actively connected
    private var isAppleHealthConnected: Bool {
        let weightEntries = historyManager.getEntries(for: .weight, source: .appleHealth)
        let heightEntries = historyManager.getEntries(for: .height, source: .appleHealth)
        let bodyFatEntries = historyManager.getEntries(for: .bodyFat, source: .appleHealth)
        return !weightEntries.isEmpty || !heightEntries.isEmpty || !bodyFatEntries.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Health & Data")) {
                    Button(action: {
                        showHealthAccessSheet = true
                    }) {
                        HStack {
                            Image("applehealthdark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Apple Health")
                                .foregroundColor(.primary)
                            Spacer()
                            if healthManager.isHealthDataAvailable {
                                if healthManager.isAuthorized {
                                    if isAppleHealthConnected {
                                        Text("Connected")
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Disconnected")
                                            .foregroundColor(.orange)
                                    }
                                } else {
                                    Text("Not Authorized")
                                        .foregroundColor(.orange)
                                }
                            } else {
                                Text("Not Available")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                
                Section(header: Text("Appearance")) {
                    NavigationLink(destination: Text("Theme Settings")) {
                        Label("Theme", systemImage: "paintbrush.fill")
                    }
                    
                    NavigationLink(destination: Text("Units Settings")) {
                        Label("Units", systemImage: "ruler")
                    }
                }
                
                Section(header: Text("Data Management")) {
                    Button(action: {
                        showExportSheet = true
                    }) {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                }
                
                Section(header: Text("About")) {
                    NavigationLink(destination: Text("Privacy Policy")) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                    
                    NavigationLink(destination: Text("Terms of Service")) {
                        Label("Terms of Service", systemImage: "doc.text.fill")
                    }
                    
                    HStack {
                        Label("Version", systemImage: "info.circle.fill")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                }
                
                Section {
                    Button(action: {
                        // Sign out action
                    }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showHealthAccessSheet) {
                HealthAccessView(healthManager: healthManager, historyManager: historyManager)
            }
            .sheet(isPresented: $showExportSheet) {
                ExportDataView(historyManager: historyManager)
            }
        }
    }
}

// Placeholder views for new features
struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Personal Information")) {
                    TextField("Name", text: .constant(""))
                    TextField("Email", text: .constant(""))
                    DatePicker("Birth Date", selection: .constant(Date()), displayedComponents: .date)
                }
                
                Section(header: Text("Goals")) {
                    TextField("Target Weight", text: .constant(""))
                    TextField("Target Body Fat", text: .constant(""))
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct NotificationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Reminders")) {
                    Toggle("Daily Weight Reminder", isOn: .constant(true))
                    Toggle("Weekly Progress Report", isOn: .constant(true))
                    Toggle("Goal Achievement Alerts", isOn: .constant(true))
                }
                
                Section(header: Text("Measurement Reminders")) {
                    Toggle("Weight Tracking", isOn: .constant(true))
                    Toggle("Body Measurements", isOn: .constant(true))
                    Toggle("Progress Photos", isOn: .constant(true))
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct HealthAccessView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var healthManager: HealthManager
    @ObservedObject var historyManager: StatsHistoryManager
    @State private var showDebugInfo = false
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var showingActionSheet = false
    
    // Computed property to check if there are any Apple Health entries
    private var hasAppleHealthData: Bool {
        let weightEntries = historyManager.getEntries(for: .weight, source: .appleHealth)
        let heightEntries = historyManager.getEntries(for: .height, source: .appleHealth)
        let bodyFatEntries = historyManager.getEntries(for: .bodyFat, source: .appleHealth)
        return !weightEntries.isEmpty || !heightEntries.isEmpty || !bodyFatEntries.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                RefreshControl(isRefreshing: $isRefreshing) {
                    refreshData()
                }
                
                VStack(spacing: 20) {
                    Image("applehealthdark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .padding(.top, 40)
                    
                    Text("Connect to Apple Health")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("This app needs access to your health data to provide accurate tracking and insights. Your data will be automatically synced with Apple Health.")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HealthDataTypeRow(icon: "scalemass.fill", title: "Weight", description: "Track your weight changes over time")
                        HealthDataTypeRow(icon: "ruler.fill", title: "Height", description: "Used for BMI calculations")
                        HealthDataTypeRow(icon: "person.fill", title: "Body Fat Percentage", description: "Monitor body composition")
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    if healthManager.isAuthorized {
                        if hasAppleHealthData {
                            Button(action: {
                                showingActionSheet = true
                            }) {
                                Text("Disconnect Apple Health")
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal)
                            .confirmationDialog(
                                "Disconnect Apple Health",
                                isPresented: $showingActionSheet,
                                titleVisibility: .visible
                            ) {
                                Button("Disconnect", role: .destructive) {
                                    clearAppleHealthData()
                                }
                            } message: {
                                Text("This will disconnect Apple Health and remove all imported data. You can reconnect later to import data again.")
                            }
                        } else {
                            Button(action: {
                                importHealthData()
                            }) {
                                Text("Connect Apple Health")
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal)
                        }
                    } else {
                        Button(action: {
                            requestAuthorization()
                        }) {
                            Text("Request Health Access")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                            .padding()
                    }
                    
                    if showDebugInfo {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Status: \(healthManager.fetchingStatus)")
                                .bold()
                            
                            Text("Last sync: \(healthManager.lastUpdateTimestamp.formatted())")
                                .font(.caption)
                            
                            Text("Weight entries: \(historyManager.getEntries(for: .weight, source: .appleHealth).count)")
                            ForEach(historyManager.getEntries(for: .weight, source: .appleHealth).prefix(5), id: \.id) { entry in
                                Text("- \(entry.date.formatted()): \(String(format: "%.1f", entry.value)) kg")
                                    .font(.caption)
                            }
                            
                            Text("Height entries: \(historyManager.getEntries(for: .height, source: .appleHealth).count)")
                            ForEach(historyManager.getEntries(for: .height, source: .appleHealth).prefix(5), id: \.id) { entry in
                                Text("- \(entry.date.formatted()): \(String(format: "%.1f", entry.value)) cm")
                                    .font(.caption)
                            }
                            
                            Text("Body Fat entries: \(historyManager.getEntries(for: .bodyFat, source: .appleHealth).count)")
                            ForEach(historyManager.getEntries(for: .bodyFat, source: .appleHealth).prefix(5), id: \.id) { entry in
                                Text("- \(entry.date.formatted()): \(String(format: "%.1f", entry.value))%")
                                    .font(.caption)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func requestAuthorization() {
        print("🔑 Starting authorization request")
        
        // First check if we're already authorized
        if healthManager.isAuthorized {
            print("🔑 Already authorized, proceeding to import")
            importHealthData()
            return
        }
        
        // Request authorization directly
        healthManager.requestHealthAuthorization()
        
        // After authorization request, check status and proceed accordingly
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if healthManager.isAuthorized {
                print("🔑 Authorization successful")
                
                // First sync existing manual entries to Apple Health
                print("📤 Syncing existing manual entries to Apple Health")
                self.historyManager.syncManualEntriesToHealthKit()
                
                // Then import Apple Health data
                print("📥 Importing data from Apple Health")
                self.importHealthData()
            } else {
                print("❌ Authorization failed or denied")
                // Show an alert or message to the user
            }
        }
    }
    
    private func importHealthData() {
        print("📥 Starting health data import")
        isLoading = true
        healthManager.importAllHealthData(historyManager: historyManager) { success in
            isLoading = false
            showDebugInfo = true
            if success {
                print("✅ Health data import successful")
                // After successful import, sync any remaining manual entries
                if healthManager.isAuthorized {
                    print("📤 Syncing manual entries after import")
                    self.historyManager.syncManualEntriesToHealthKit()
                } else {
                    print("❌ Cannot sync manual entries - not authorized")
                }
            } else {
                print("❌ Health data import failed")
            }
        }
    }
    
    private func refreshData() {
        // Only refresh if we have Apple Health data connected
        if hasAppleHealthData {
            print("🔄 Starting data refresh")
            isRefreshing = true
            healthManager.importAllHealthData(historyManager: historyManager) { success in
                isRefreshing = false
                showDebugInfo = true
                if success {
                    print("✅ Data refresh successful")
                    // After successful refresh, sync manual entries
                    print("📤 Syncing manual entries after refresh")
                    self.historyManager.syncManualEntriesToHealthKit()
                } else {
                    print("❌ Data refresh failed")
                }
            }
        } else {
            print("⚠️ No Apple Health data to refresh")
            isRefreshing = false
        }
    }
    
    private func clearAppleHealthData() {
        isLoading = true
        
        // Clear the HealthKit sample map
        healthManager.clearHealthKitSampleMap()
        
        // Only remove entries that were imported from Apple Health
        historyManager.clearEntries(from: .appleHealth)
        
        // Show the debug info and stop loading
        showDebugInfo = true
        isLoading = false
    }
}

struct RefreshControl: View {
    @Binding var isRefreshing: Bool
    let action: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            let offset = geometry.frame(in: .global).minY
            let threshold: CGFloat = -50
            
            VStack {
                if offset < threshold {
                    Spacer()
                        .onAppear {
                            if !isRefreshing {
                                isRefreshing = true
                                action()
                            }
                        }
                }
                
                HStack {
                    Spacer()
                    if isRefreshing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                    Spacer()
                }
            }
        }
        .frame(height: 50)
    }
}

struct HealthDataTypeRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
}
