import SwiftUI

struct ContentView: View {
    @StateObject private var historyManager = StatsHistoryManager.shared
    @StateObject private var healthManager = HealthManager()
    @State private var showingAddEntrySheet = false
    @State private var showingSettingsSheet = false
    @State private var isRefreshing = false
    
    // Computed properties to get latest values or nil
    private var weight: Double? {
        historyManager.getLatestValue(for: .weight)
    }
    
    private var height: Double? {
        historyManager.getLatestValue(for: .height)
    }
    
    private var bodyFat: Double? {
        historyManager.getLatestValue(for: .bodyFat)
    }
    
    private var bmi: Double? {
        if let weight = weight, let height = height, height > 0 {
            let heightInMeters = height / 100
            return weight / (heightInMeters * heightInMeters)
        }
        return nil
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    RefreshControl(isRefreshing: $isRefreshing) {
                        refreshData()
                    }
                    
                    VStack(spacing: 20) {
                        GridView(weight: weight, height: height, bmi: bmi, bodyFat: bodyFat, historyManager: historyManager)
                            .padding(.top,-40)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddEntrySheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingSettingsSheet = true
                    }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingAddEntrySheet) {
                TrackDataView(historyManager: historyManager)
            }
            .sheet(isPresented: $showingSettingsSheet) {
                SettingsView(historyManager: historyManager)
            }
            .onAppear {
                // Sync with Apple Health when the app launches
                if healthManager.isAuthorized {
                    healthManager.importAllHealthData(historyManager: historyManager) { _ in
                        print("Initial sync completed on app launch")
                    }
                }
            }
        }
    }
    
    private func refreshData() {
        isRefreshing = true
        if healthManager.isAuthorized {
            healthManager.importAllHealthData(historyManager: historyManager) { _ in
                isRefreshing = false
            }
        } else {
            isRefreshing = false
        }
    }
}
