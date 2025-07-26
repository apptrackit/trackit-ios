import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject private var historyManager = StatsHistoryManager.shared
    @StateObject private var healthManager = HealthManager()
    @State private var showingAddEntrySheet = false
    @State private var showingAccountSheet = false
    @State private var selectedTimeFrame: TimeFrame = .sixMonths
    @State private var showingAddPhotoSheet = false
    @State private var hasPerformedInitialSync = false
    @State private var isRefreshing = false
    @EnvironmentObject var authViewModel: AuthViewModel
    
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
                                title: "Add Metric",
                                icon: "ruler.fill",
                                color: .blue
                            ) {
                                showingAddEntrySheet = true
                            }
                            
                            QuickActionButton(
                                title: "Add Photo",
                                icon: "camera.fill",
                                color: .green
                            ) {
                                showingAddPhotoSheet = true
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
        .sheet(isPresented: $showingAddPhotoSheet) {
            AddPhotoView(
                photoManager: ProgressPhotoManager.shared,
                historyManager: StatsHistoryManager.shared
            )
        }
        .onAppear {
            // Only perform initial sync once
            if !hasPerformedInitialSync && healthManager.isAuthorized {
                hasPerformedInitialSync = true
                Task {
                    await refreshData()
                }
            }
        }
    }
    
    private func refreshData() async {
        // Prevent multiple simultaneous refreshes
        guard !isRefreshing else { return }
        isRefreshing = true
        
        if healthManager.isAuthorized {
            do {
                // Create a continuation that can only be resumed once
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    var hasResumed = false
                    
                    healthManager.importAllHealthData(historyManager: historyManager) { success in
                        // Ensure we only resume once
                        guard !hasResumed else { return }
                        hasResumed = true
                        
                        if success {
                            print("Data refresh completed successfully")
                            continuation.resume()
                        } else {
                            print("Data refresh failed")
                            continuation.resume(throwing: NSError(domain: "DashboardView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Data refresh failed"]))
                        }
                    }
                }
            } catch {
                print("Error during data refresh: \(error.localizedDescription)")
            }
        }
        
        isRefreshing = false
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
    
    private var chartData: [StatEntry] {
        let calendar = Calendar.current
        let now = Date()
        
        // Get all entries and sort by date
        let allEntries = historyManager.getEntries(for: statType)
            .sorted { $0.date < $1.date }
        
        // If no entries, return empty array
        guard !allEntries.isEmpty else { return [] }
        
        // Calculate the date range based on timeFrame
        let startDate: Date
        switch timeFrame {
        case .weekly:
            startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .monthly:
            startDate = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .sixMonths:
            startDate = calendar.date(byAdding: .month, value: -6, to: now) ?? now
        case .yearly:
            startDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .allTime:
            return allEntries // Return all data for all time
        }
        
        // Filter entries for the selected timeFrame
        let filteredEntries = allEntries.filter { $0.date >= startDate }
        
        // If no entries in the selected timeFrame, return the last 5 entries
        if filteredEntries.isEmpty {
            return Array(allEntries.suffix(min(5, allEntries.count)))
        }
        
        return filteredEntries
    }
    
    private var yAxisRange: ClosedRange<Double> {
        guard !chartData.isEmpty else { return 0...100 }
        
        let values = chartData.map { $0.value }
        let min = values.min() ?? 0
        let max = values.max() ?? 100
        
        // If all values are the same, create a range around that value
        if min == max {
            let padding = max * 0.1 // 10% padding
            return (max - padding)...(max + padding)
        }
        
        let padding = (max - min) * 0.15 // 15% padding for better visualization
        return (min - padding)...(max + padding)
    }
    
    private var xAxisDates: [Date] {
        guard !chartData.isEmpty else { return [] }
        
        let calendar = Calendar.current
        let startDate = chartData.first!.date
        let endDate = chartData.last!.date
        
        switch timeFrame {
        case .weekly:
            // Show every day of the week
            return (0..<7).compactMap { dayOffset in
                calendar.date(byAdding: .day, value: -6 + dayOffset, to: endDate)
            }
        case .monthly:
            // Show 4 evenly spaced dates
            return (0..<4).compactMap { index in
                let daysOffset = Int(Double(index) * 30.0 / 3.0)
                return calendar.date(byAdding: .day, value: -30 + daysOffset, to: endDate)
            }
        case .sixMonths:
            // Show 6 months
            return (0..<6).compactMap { monthOffset in
                calendar.date(byAdding: .month, value: -5 + monthOffset, to: endDate)
            }
        case .yearly:
            // Show 12 months
            return (0..<12).compactMap { monthOffset in
                calendar.date(byAdding: .month, value: -11 + monthOffset, to: endDate)
            }
        case .allTime:
            // For all time, show years if data spans multiple years
            let yearRange = calendar.component(.year, from: endDate) - calendar.component(.year, from: startDate)
            if yearRange > 1 {
                return (0...yearRange).compactMap { yearOffset in
                    calendar.date(from: DateComponents(year: calendar.component(.year, from: startDate) + yearOffset))
                }
            } else {
                // If less than 2 years, show months
                return (0..<12).compactMap { monthOffset in
                    calendar.date(byAdding: .month, value: monthOffset, to: startDate)
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        
        switch timeFrame {
        case .weekly:
            formatter.dateFormat = "E"
            return formatter.string(from: date)
        case .monthly:
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        case .sixMonths:
            formatter.dateFormat = "MMM"
            return formatter.string(from: date)
        case .yearly:
            formatter.dateFormat = "MMM"
            return formatter.string(from: date)
        case .allTime:
            let yearRange = calendar.component(.year, from: chartData.last?.date ?? date) - calendar.component(.year, from: chartData.first?.date ?? date)
            if yearRange > 1 {
                formatter.dateFormat = "yyyy"
                return formatter.string(from: date)
            } else {
                formatter.dateFormat = "MMM"
                return formatter.string(from: date)
            }
        }
    }
    
    private var chartColor: Color {
        switch statType {
        case .weight:
            return .blue
        case .bodyFat:
            return .green
        case .height:
            return .purple
        case .bmi:
            return .orange
        default:
            return .blue
        }
    }
    
    private var shouldShowDots: Bool {
        // Show dots for sparse data (less than 10 points)
        if chartData.count < 10 {
            return true
        }
        
        // Show dots for weekly view (usually sparse)
        if timeFrame == .weekly {
            return true
        }
        
        // Show dots for monthly view if data is sparse
        if timeFrame == .monthly && chartData.count < 15 {
            return true
        }
        
        // Don't show dots for dense data in longer timeframes
        return false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                Text("\(String(format: "%.1f", value))\(unit)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            if chartData.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                    Text("No data available")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: 150)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            } else {
                Chart {
                    ForEach(chartData) { entry in
                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Value", entry.value)
                        )
                        .foregroundStyle(chartColor.gradient)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        
                        // Only show dots for sparse data (less than 10 points) or for specific timeframes
                        if shouldShowDots {
                            PointMark(
                                x: .value("Date", entry.date),
                                y: .value("Value", entry.value)
                            )
                            .foregroundStyle(chartColor)
                            .symbolSize(20)
                        }
                    }
                }
                .frame(height: 150)
                .chartYScale(domain: yAxisRange)
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color.clear)
                }
                .chartXAxis {
                    AxisMarks(values: xAxisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(0.2))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(formatDate(date))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(0.2))
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(String(format: "%.1f", doubleValue))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.gray)
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
                    .font(.system(size: 24))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .padding()
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .cornerRadius(15)
        }
    }
}

// Example of how to make an authenticated API call
extension DashboardView {
    func fetchUserData() async {
        do {
            // Example of using NetworkManager for authenticated requests
            let _: User = try await NetworkManager.shared.makeAuthenticatedRequest("/user/profile")
            // Handle the response
        } catch {
            // Handle error
            print("Error fetching user data: \(error)")
        }
    }
}
