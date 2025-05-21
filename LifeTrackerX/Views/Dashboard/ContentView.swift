import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var historyManager = StatsHistoryManager.shared
    @StateObject private var healthManager = HealthManager()
    @State private var showingAddEntrySheet = false
    @State private var showingAccountSheet = false
    @State private var selectedTimeFrame: TimeFrame = .sixMonths
    
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
    
    private var welcomeMessage: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Welcome Section
                    VStack(alignment: .leading, spacing: 4) {
                        Text(welcomeMessage)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(Date().formatted(date: .complete, time: .omitted))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    
                    // Summary Section
                    VStack(spacing: 15) {
                        
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
            .refreshable {
                await refreshData()
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
                    showingAccountSheet = true
                }) {
                    Image(systemName: "person.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddEntrySheet) {
            TrackDataView(historyManager: historyManager)
        }
        .sheet(isPresented: $showingAccountSheet) {
            AccountView(historyManager: historyManager)
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
    
    private func refreshData() async {
        if healthManager.isAuthorized {
            // Start refresh in background without waiting
            Task(priority: .background) {
                healthManager.importAllHealthData(historyManager: historyManager) { _ in
                    print("Data refresh completed")
                }
            }
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
        
        // Get all entries first
        let allEntries = historyManager.getEntries(for: statType)
            .sorted { $0.date < $1.date }
        
        // If no entries, return empty array
        if allEntries.isEmpty {
            return []
        }
        
        // Calculate the date range based on timeFrame
        let startDate: Date
        switch timeFrame {
        case .weekly:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)!
        case .monthly:
            startDate = calendar.date(byAdding: .day, value: -30, to: now)!
        case .sixMonths:
            startDate = calendar.date(byAdding: .month, value: -6, to: now)!
        case .yearly:
            startDate = calendar.date(byAdding: .year, value: -1, to: now)!
        case .allTime:
            startDate = .distantPast
        }
        
        // Filter entries for the selected timeFrame
        let filteredEntries = allEntries.filter { $0.date >= startDate }
        
        // If no entries in the selected timeFrame, return the last 5 entries
        if filteredEntries.isEmpty {
            return Array(allEntries.suffix(5))
        }
        
        return filteredEntries
    }
    
    private var yAxisRange: ClosedRange<Double> {
        guard !data.isEmpty else { return 0...100 }
        
        let values = data.map { $0.value }
        let min = values.min() ?? 0
        let max = values.max() ?? 100
        let padding = (max - min) * 0.1 // 10% padding
        
        return (min - padding)...(max + padding)
    }
    
    private func getDateStride() -> Calendar.Component {
        switch timeFrame {
        case .weekly:
            return .day
        case .monthly:
            return .day
        case .sixMonths:
            return .month
        case .yearly:
            return .month
        case .allTime:
            return .year
        }
    }
    
    private func monthlyAxisDates() -> [Date] {
        // 4 evenly spaced real dates: start, 1/3, 2/3, end of last 30 days
        let calendar = Calendar.current
        let now = Date()
        guard let start = calendar.date(byAdding: .day, value: -29, to: now) else { return [] }
        let interval = 29.0 / 3.0
        return (0...3).map { i in
            calendar.date(byAdding: .day, value: Int(round(Double(i) * interval)), to: start)!
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        switch timeFrame {
        case .weekly:
            let weekday = calendar.component(.weekday, from: date)
            let weekdaySymbol = calendar.veryShortWeekdaySymbols[weekday - 1]
            return weekdaySymbol
        case .monthly:
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
            return formatter.string(from: date)
        case .sixMonths:
            let month = calendar.component(.month, from: date)
            return calendar.shortMonthSymbols[month - 1]
        case .yearly:
            let month = calendar.component(.month, from: date)
            return String(calendar.shortMonthSymbols[month - 1].prefix(1))
        case .allTime:
            formatter.setLocalizedDateFormatFromTemplate("yyyy")
            return formatter.string(from: date)
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
                        .interpolationMethod(.linear)
                    }
                }
                .frame(height: 150)
                .chartYScale(domain: yAxisRange)
                .chartXAxis {
                    if timeFrame == .monthly {
                        AxisMarks(values: monthlyAxisDates()) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(formatDate(date)).font(.caption)
                                }
                            }
                        }
                    } else if timeFrame == .allTime {
                        // For all time view, show first year, last year, and evenly spaced years in between
                        let calendar = Calendar.current
                        let allEntries = historyManager.getEntries(for: statType)
                            .sorted { $0.date < $1.date }
                        
                        if let firstDate = allEntries.first?.date,
                           let lastDate = allEntries.last?.date {
                            let firstYear = calendar.component(.year, from: firstDate)
                            let lastYear = calendar.component(.year, from: lastDate)
                            let yearRange = lastYear - firstYear
                            
                            // If less than 3 years, show all years
                            if yearRange <= 2 {
                                AxisMarks(values: .stride(by: .year)) { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let date = value.as(Date.self) {
                                            Text(formatDate(date)).font(.caption)
                                        }
                                    }
                                }
                            } else {
                                // Show first year, last year, and one in the middle
                                let middleYear = firstYear + (yearRange / 2)
                                let dates = [
                                    calendar.date(from: DateComponents(year: firstYear))!,
                                    calendar.date(from: DateComponents(year: middleYear))!,
                                    calendar.date(from: DateComponents(year: lastYear))!
                                ]
                                
                                AxisMarks(values: dates) { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let date = value.as(Date.self) {
                                            Text(formatDate(date)).font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        AxisMarks(values: .stride(by: getDateStride(), count: timeFrame == .monthly ? 7 : 1)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(formatDate(date)).font(.caption)
                                }
                            }
                        }
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
