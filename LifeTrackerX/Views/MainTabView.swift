import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var syncManager = MetricSyncManager.shared
    @StateObject private var historyManager = StatsHistoryManager.shared
    @State private var selectedTab = 0
    @State private var hasInitializedSync = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Dashboard Tab
            NavigationStack {
                DashboardView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            CompactSyncStatusView()
                        }
                    }
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar.fill")
            }
            .tag(0)
            
            // Progress Tab (measurements)
            NavigationStack {
                ProgressView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            CompactSyncStatusView()
                        }
                    }
            }
            .tabItem {
                Label("Metrics", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(1)
            
            // Progress Photos Tab (new)
            NavigationStack {
                ProgressPhotosView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            CompactSyncStatusView()
                        }
                    }
            }
            .tabItem {
                Label("Photos", systemImage: "photo.fill")
            }
            .tag(2)
        }
        .accentColor(.green)
        .onAppear {
            // Initialize sync on first appear
            if !hasInitializedSync {
                hasInitializedSync = true
                initializeSync()
            }
        }
        .overlay(alignment: .top) {
            // Show sync status at the top when syncing
            if syncManager.syncStatus.isSyncing {
                SyncStatusView()
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(), value: syncManager.syncStatus.isSyncing)
            }
        }
    }
    
    private func initializeSync() {
        print("🚀 Initializing sync on app launch")
        
        // Perform initial sync
        Task {
            // Wait a moment for the UI to settle
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Start full sync
            await syncManager.performFullSync()
        }
    }
}

// Placeholder view for tabs that aren't implemented yet
struct PlaceholderView: View {
    let title: String
    
    var body: some View {
        VStack {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Coming Soon")
                .font(.title2)
                .foregroundColor(.secondary)
                .padding(.top, 5)
            
            Spacer()
        }
        .padding()
        .navigationTitle(title)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
} 