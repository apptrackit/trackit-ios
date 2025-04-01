import SwiftUI

struct ContentView: View {
    @StateObject private var historyManager = StatsHistoryManager()
    @State private var showingAddEntrySheet = false
    
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
        ZStack {
            VStack {
                HStack {
                    Text("Dashboard")
                        .font(.title.bold())
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: signOut) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .foregroundColor(.white)
                    }
                }
                .padding()
                
                if weight == nil && height == nil && bodyFat == nil {
                    ContentUnavailableView {
                        Label("No Data", systemImage: "chart.bar.xaxis")
                    } description: {
                        Text("Tap on a card to add your first measurement")
                    }
                    .foregroundColor(.white)
                } else {
                    GridView(
                        weight: weight,
                        height: height,
                        bmi: bmi,
                        bodyFat: bodyFat,
                        historyManager: historyManager
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                
                Spacer()
            }
            .background(Color.black.ignoresSafeArea())
            
            // Floating action button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        showingAddEntrySheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.title)
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 5)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showingAddEntrySheet) {
            TrackDataView(historyManager: historyManager)
        }
    }
    
    func signOut() {
        print("User signed out")
    }
}
