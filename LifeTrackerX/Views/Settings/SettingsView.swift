import SwiftUI
import HealthKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var healthManager = HealthManager()
    @State private var showHealthAccessSheet = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Health Data")) {
                    Button(action: {
                        showHealthAccessSheet = true
                    }) {
                        HStack {
                            Label("Apple Health", systemImage: "heart.fill")
                                .foregroundColor(.red)
                            Spacer()
                            if healthManager.isHealthDataAvailable {
                                if healthManager.isAuthorized {
                                    Text("Connected")
                                        .foregroundColor(.green)
                                } else {
                                    Text("Not Authorized")
                                        .foregroundColor(.orange)
                                }
                            } else {
                                Text("Not Available")
                                    .foregroundColor(.gray)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                }
                
                Section(header: Text("Account")) {
                    Button(action: {
                        // Sign out action
                    }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showHealthAccessSheet) {
                HealthAccessView(healthManager: healthManager)
            }
        }
    }
}

struct HealthAccessView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var healthManager: HealthManager
    @StateObject private var historyManager = StatsHistoryManager()
    @State private var showDebugInfo = false
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "heart.text.square.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.red)
                    .padding(.top, 40)
                
                Text("Connect to Apple Health")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("This app needs access to your health data to provide accurate tracking and insights.")
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
                
                Button(action: {
                    healthManager.requestHealthAuthorization()
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
                
                if healthManager.isAuthorized {
                    HStack {
                        Button(action: {
                            isLoading = true
                            historyManager.clearAllEntries() // Clear existing data for clean test
                            healthManager.importAllHealthData(historyManager: historyManager) { success in
                                isLoading = false
                                showDebugInfo = true
                            }
                        }) {
                            Text("Import Health Data")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                        
                        Button(action: {
                            historyManager.clearAllEntries()
                        }) {
                            Text("Clear Data")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                            .padding()
                    }
                    
                    if showDebugInfo {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Status: \(healthManager.fetchingStatus)")
                                    .bold()
                                
                                Text("Weight entries: \(historyManager.getEntries(for: .weight).count)")
                                ForEach(historyManager.getEntries(for: .weight).prefix(5), id: \.id) { entry in
                                    Text("- \(entry.date.formatted()): \(String(format: "%.1f", entry.value)) kg")
                                        .font(.caption)
                                }
                                
                                Text("Height entries: \(historyManager.getEntries(for: .height).count)")
                                ForEach(historyManager.getEntries(for: .height).prefix(5), id: \.id) { entry in
                                    Text("- \(entry.date.formatted()): \(String(format: "%.1f", entry.value)) cm")
                                        .font(.caption)
                                }
                                
                                Text("Body Fat entries: \(historyManager.getEntries(for: .bodyFat).count)")
                                ForEach(historyManager.getEntries(for: .bodyFat).prefix(5), id: \.id) { entry in
                                    Text("- \(entry.date.formatted()): \(String(format: "%.1f", entry.value))%")
                                        .font(.caption)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                        .frame(maxHeight: 300)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Health Access")
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
