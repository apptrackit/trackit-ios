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
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    
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
            Color(.systemBackground).edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Welcome Section
                    VStack(alignment: .leading, spacing: 4) {
                        Text(welcomeMessage)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
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
                                .foregroundColor(.primary)
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
                                .foregroundColor(.primary)
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
                                .foregroundColor(.primary)
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
                HStack(spacing: 12) {
                    SyncStatusView()
                    
                Button(action: {
                    showingAddEntrySheet = true
                }) {
                    Image(systemName: "plus")
                    }
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
                        .foregroundColor(.primary)
                    
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
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ProgressChartView: View {
    let title: String
    let value: Double
    let unit: String
    let historyManager: StatsHistoryManager
    let statType: StatType
    let timeFrame: TimeFrame
    
    private var allEntries: [StatEntry] {
        historyManager.getEntries(for: statType).sorted { $0.date < $1.date }
    }
    
    private var chartData: [StatEntry] {
        guard !allEntries.isEmpty else { return [] }
        
        let calendar = Calendar.current
        let mostRecentEntry = allEntries.last!
        let mostRecentDate = mostRecentEntry.date
        
        let filteredEntries: [StatEntry]
        
        switch timeFrame {
        case .weekly:
            // Show 7 days ending with the most recent data's day
            let startDate = calendar.date(byAdding: .day, value: -6, to: mostRecentDate) ?? mostRecentDate
            filteredEntries = allEntries.filter { $0.date >= startDate && $0.date <= mostRecentDate }
            
        case .monthly:
            // Show 30 days ending with the most recent data's day
            let startDate = calendar.date(byAdding: .day, value: -29, to: mostRecentDate) ?? mostRecentDate
            filteredEntries = allEntries.filter { $0.date >= startDate && $0.date <= mostRecentDate }
            
        case .sixMonths:
            // Show 6 months ending with the most recent data's month
            let startDate = calendar.date(byAdding: .month, value: -5, to: mostRecentDate) ?? mostRecentDate
            filteredEntries = allEntries.filter { $0.date >= startDate && $0.date <= mostRecentDate }
            
        case .yearly:
            // Show 12 months ending with the most recent data's month
            let startDate = calendar.date(byAdding: .month, value: -11, to: mostRecentDate) ?? mostRecentDate
            filteredEntries = allEntries.filter { $0.date >= startDate && $0.date <= mostRecentDate }
            
        case .allTime:
            filteredEntries = allEntries
        }
        
        return filteredEntries
    }
    
    private var yAxisRange: ClosedRange<Double> {
        guard !chartData.isEmpty else { return 0...100 }
        
        let values = chartData.map { $0.value }
        let min = values.min() ?? 0
        let max = values.max() ?? 100
        
        if min == max {
            let padding = max * 0.1
            return (max - padding)...(max + padding)
        }
        
        let padding = (max - min) * 0.15
        return (min - padding)...(max + padding)
    }
    
    private var xAxisDates: [Date] {
        guard !chartData.isEmpty else { return [] }
        
        let calendar = Calendar.current
        let mostRecentDate = chartData.last!.date
        let oldestDate = chartData.first!.date
        
        switch timeFrame {
        case .weekly:
            // Show 7 days: Mon, Tue, Wed, Thu, Fri, Sat, Sun
            // Based on the most recent data's day
            return (0..<7).compactMap { dayOffset in
                calendar.date(byAdding: .day, value: -6 + dayOffset, to: mostRecentDate)
            }
            
        case .monthly:
            // Show 4 evenly spaced dates across the month
            return (0..<4).compactMap { index in
                let daysOffset = -29 + (index * 10) // Roughly every 10 days
                return calendar.date(byAdding: .day, value: daysOffset, to: mostRecentDate)
            }
            
        case .sixMonths:
            // Show 6 months
            return (0..<6).compactMap { monthOffset in
                calendar.date(byAdding: .month, value: -5 + monthOffset, to: mostRecentDate)
            }
            
        case .yearly:
            // Show all 12 months
            return (0..<12).compactMap { monthOffset in
                calendar.date(byAdding: .month, value: -11 + monthOffset, to: mostRecentDate)
            }
            
        case .allTime:
            let yearRange = calendar.component(.year, from: mostRecentDate) - calendar.component(.year, from: oldestDate)
            
            if yearRange <= 10 {
                // Show all years if 10 or fewer
                return (0...yearRange).compactMap { yearOffset in
                    calendar.date(from: DateComponents(year: calendar.component(.year, from: oldestDate) + yearOffset))
                }
            } else {
                // Show first, 2 middle, and last year if more than 10 years
                let firstYear = calendar.component(.year, from: oldestDate)
                let lastYear = calendar.component(.year, from: mostRecentDate)
                let middleYear1 = firstYear + (lastYear - firstYear) / 3
                let middleYear2 = firstYear + 2 * (lastYear - firstYear) / 3
                
                return [firstYear, middleYear1, middleYear2, lastYear].compactMap { year in
                    calendar.date(from: DateComponents(year: year))
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
            // Show day names: Mon, Tue, Wed, etc.
            formatter.dateFormat = "E"
            return formatter.string(from: date)
            
        case .monthly:
            // Show month day: Jan 7, Jan 14, etc.
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
            
        case .sixMonths:
            // Show month names: Jan, Feb, Mar, etc.
            formatter.dateFormat = "MMM"
            return formatter.string(from: date)
            
        case .yearly:
            // Show first letter of months: J, F, M, A, M, J, J, A, S, O, N, D
            formatter.dateFormat = "MMM"
            let monthName = formatter.string(from: date)
            return String(monthName.prefix(1))
            
        case .allTime:
            // Show years: 2020, 2021, 2022, etc.
            formatter.dateFormat = "yyyy"
            return formatter.string(from: date)
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
        // Show dots for sparse data or specific timeframes
        return chartData.count < 10 || timeFrame == .weekly || (timeFrame == .monthly && chartData.count < 15)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
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
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                .frame(height: 160)
                .chartYScale(domain: yAxisRange)
                .chartPlotStyle { plotArea in
                    plotArea.background(Color.clear)
                }
                .chartXAxis {
                    AxisMarks(values: xAxisDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(0.2))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(formatDate(date))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                    .foregroundColor(.primary)
                
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text("\(String(format: "%.1f", entry.value)) \(entry.type.unit)")
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
