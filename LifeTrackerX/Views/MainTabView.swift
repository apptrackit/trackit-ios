import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Dashboard Tab (existing ContentView)
            NavigationStack {
                ContentView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar.fill")
            }
            .tag(0)
            
            // Nutrition Tab
            NavigationStack {
                PlaceholderView(title: "Nutrition")
            }
            .tabItem {
                Label("Nutrition", systemImage: "fork.knife")
            }
            .tag(1)
            
            // Workout Tab
            NavigationStack {
                PlaceholderView(title: "Workout")
            }
            .tabItem {
                Label("Workout", systemImage: "dumbbell.fill")
            }
            .tag(2)
            
            // Progress Tab
            NavigationStack {
                ProgressView()
            }
            .tabItem {
                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(3)
            
            // Profile Tab
            NavigationStack {
                PlaceholderView(title: "Profile")
            }
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
            .tag(4)
        }
        .accentColor(.green)
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
} 