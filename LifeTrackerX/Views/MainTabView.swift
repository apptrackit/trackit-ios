import SwiftUI
import UIKit // Import UIKit for UIViewRepresentable

struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var selectedTab = 0
    @Namespace private var animation
    
    init() {
        // Configure UITabBar appearance for transparency and hide it
        UITabBar.appearance().backgroundImage = UIImage()
        UITabBar.appearance().shadowImage = UIImage()
        UITabBar.appearance().backgroundColor = .clear
        UITabBar.appearance().unselectedItemTintColor = .gray // Optional: set unselected item color if needed
        UITabBar.appearance().isHidden = true // Hide the default tab bar
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            TabView(selection: $selectedTab) {
                NavigationStack {
                    DashboardView()
                }
                .tag(0)
                
                NavigationStack {
                    ProgressView()
                }
                .tag(1)
                
                NavigationStack {
                    ProgressPhotosView()
                }
                .tag(2)
            }
            .ignoresSafeArea(.container, edges: .bottom) // Ensure TabView content goes under the bar
            
            // Full-width background blur behind the custom tab bar using UIKit
            SubtleBlur() // Use the custom subtle blur view with alpha
                .ignoresSafeArea(.all, edges: .bottom) // Ignore all bottom safe area
                .frame(height: 100) // Give it a generous height to cover the area
            
            // Custom floating tab bar
            HStack(spacing: 0) {
                ForEach(0..<3) { index in
                    TabBarButton(
                        icon: getIcon(for: index),
                        title: getTitle(for: index),
                        isSelected: selectedTab == index,
                        animation: animation
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = index
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 33)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
    
    private func getIcon(for index: Int) -> String {
        switch index {
        case 0: return "chart.bar.fill"
        case 1: return "chart.line.uptrend.xyaxis"
        case 2: return "photo.fill"
        default: return ""
        }
    }
    
    private func getTitle(for index: Int) -> String {
        switch index {
        case 0: return "Dashboard"
        case 1: return "Metrics"
        case 2: return "Photos"
        default: return ""
        }
    }
}

// Custom Subtle Blur View using alpha
struct SubtleBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let blurEffect = UIBlurEffect(style: .systemMaterial) // less bright than .light
        let view = UIVisualEffectView(effect: blurEffect)
        view.alpha = 3 // control the intensity here
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let animation: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .green : .gray)
                    .frame(height: 24)
                
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .green : .gray)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .scaleEffect(isSelected ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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