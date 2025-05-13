import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var historyManager = StatsHistoryManager.shared
    @StateObject private var healthManager = HealthManager()
    @State private var showingAddEntrySheet = false
    @State private var showingSettingsSheet = false
    @State private var isRefreshing = false
    @State private var selectedTimeFrame: TimeFrame = .monthly
    
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
    
    private var recentMeasurements: [StatEntry] {
        let types: [StatType] = [.weight, .bodyFat, .bicep, .chest, .waist, .thigh, .shoulder, .glutes]
        return types.flatMap { type in
            historyManager.getEntries(for: type).prefix(1)
        }.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                RefreshControl(isRefreshing: $isRefreshing) {
                    refreshData()
                }
                
                VStack(spacing: 20) {
                    // Summary Section
                    VStack(spacing: 15) {
                        HStack {
                            Text("Summary")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        
                        HStack(spacing: 15) {
                            // Weight Card
                            SummaryCard(
                                title: "Weight",
                                value: weight,
                                unit: "kg",
                                icon: "scalemass.fill",
                                color: .blue
                            )
                            
                            // Body Fat Card
                            SummaryCard(
                                title: "Body Fat",
                                value: bodyFat,
                                unit: "%",
                                icon: "figure.arms.open",
                                color: .green
                            )
                        }
                        
                        HStack(spacing: 15) {
                            // BMI Card
                            SummaryCard(
                                title: "BMI",
                                value: bmi,
                                unit: "",
                                icon: "chart.bar.fill",
                                color: .orange
                            )
                            
                            // Height Card
                            SummaryCard(
                                title: "Height",
                                value: height,
                                unit: "cm",
                                icon: "ruler.fill",
                                color: .purple
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Progress Section
                    VStack(spacing: 15) {
                        HStack {
                            Text("Progress")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Spacer()
                            
                            Picker("Time Frame", selection: $selectedTimeFrame) {
                                ForEach(TimeFrame.allCases, id: \.self) { timeFrame in
                                    Text(timeFrame.rawValue.capitalized)
                                        .tag(timeFrame)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                        
                        // Weight Progress Chart
                        if let weight = weight {
                            ProgressChartView(
                                title: "Weight Trend",
                                value: weight,
                                unit: "kg",
                                historyManager: historyManager,
                                statType: .weight,
                                timeFrame: selectedTimeFrame
                            )
                        }
                        
                        // Body Fat Progress Chart
                        if let bodyFat = bodyFat {
                            ProgressChartView(
                                title: "Body Fat Trend",
                                value: bodyFat,
                                unit: "%",
                                historyManager: historyManager,
                                statType: .bodyFat,
                                timeFrame: selectedTimeFrame
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Recent Measurements
                    VStack(spacing: 15) {
                        HStack {
                            Text("Recent Measurements")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        
                        ForEach(recentMeasurements.prefix(5), id: \.id) { entry in
                            RecentMeasurementRow(entry: entry)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Quick Actions
                    VStack(spacing: 15) {
                        HStack {
                            Text("Quick Actions")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        
                        HStack(spacing: 15) {
                            QuickActionButton(
                                title: "Add Weight",
                                icon: "scalemass.fill",
                                color: .blue
                            ) {
                                showingAddEntrySheet = true
                            }
                            
                            QuickActionButton(
                                title: "Add Photo",
                                icon: "camera.fill",
                                color: .green
                            ) {
                                // TODO: Add photo action
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
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

struct SummaryCard: View {
    let title: String
    let value: Double?
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            if let value = value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", value))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            } else {
                Text("No data")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .cornerRadius(15)
    }
}

struct ProgressChartView: View {
    let title: String
    let value: Double
    let unit: String
    let historyManager: StatsHistoryManager
    let statType: StatType
    let timeFrame: TimeFrame
    
    private var data: [StatEntry] {
        let calendar = Calendar.current
        let now = Date()
        
        switch timeFrame {
        case .weekly:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            return historyManager.getEntries(for: statType)
                .filter { $0.date >= weekAgo }
                .sorted { $0.date < $1.date }
        case .monthly:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
            return historyManager.getEntries(for: statType)
                .filter { $0.date >= monthAgo }
                .sorted { $0.date < $1.date }
        case .yearly:
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
            return historyManager.getEntries(for: statType)
                .filter { $0.date >= yearAgo }
                .sorted { $0.date < $1.date }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("\(String(format: "%.1f", value))\(unit)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            if data.isEmpty {
                Text("No data available")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                Chart {
                    ForEach(data) { entry in
                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Value", entry.value)
                        )
                        .foregroundStyle(Color.blue.gradient)
                        
                        PointMark(
                            x: .value("Date", entry.date),
                            y: .value("Value", entry.value)
                        )
                        .foregroundStyle(Color.blue)
                    }
                }
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
            }
        }
        .padding()
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .cornerRadius(15)
    }
}

struct RecentMeasurementRow: View {
    let entry: StatEntry
    
    var body: some View {
        HStack {
            Image(systemName: entry.type.iconName)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading) {
                Text(entry.type.title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text("\(String(format: "%.1f", entry.value)) \(entry.type.unit)")
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .cornerRadius(15)
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .cornerRadius(15)
        }
    }
}
