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
                
                Text("This app needs access to your health data to provide accurate tracking and insights. We request permission to read and write the following data:")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 10) {
                    HealthDataTypeRow(icon: "scalemass.fill", title: "Weight", description: "Track your weight changes over time")
                    HealthDataTypeRow(icon: "ruler.fill", title: "Height", description: "Used for BMI calculations")
                    HealthDataTypeRow(icon: "person.fill", title: "Body Fat Percentage", description: "Monitor body composition")
                    HealthDataTypeRow(icon: "heart.fill", title: "Steps", description: "Track your daily activity")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Text("Your health data is kept private and secure. We only access the data you explicitly authorize.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
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
