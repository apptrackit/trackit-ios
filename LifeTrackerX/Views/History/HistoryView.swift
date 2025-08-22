import SwiftUI

struct HistoryViewModal: View {
    @ObservedObject var historyManager: StatsHistoryManager
    let statType: StatType
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            HistoryView(historyManager: historyManager, statType: statType)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { dismiss() }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
        }
    }
}

struct HistoryView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    let statType: StatType
    @State private var showingAddEntryView = false
    @State private var selectedEntry: StatEntry?
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @State private var selectedTimeFrame: TimeFrame = .weekly
    @State private var isEditMode = false
    @AppStorage("preferredWeightUnit") private var preferredWeightUnit: String = "kg"
    
    var entries: [StatEntry] {
        historyManager.getEntries(for: statType)
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground).edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 20) {
                    HistoryGraphView(historyManager: historyManager,
                                     statType: statType,
                                     selectedTimeFrame: $selectedTimeFrame)
                        .frame(height: 300)
                        .padding(.horizontal)
                    
                    HStack {
                        Text("All Recorded Data")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if !entries.isEmpty && !statType.isCalculated {
                            Button(action: {
                                withAnimation {
                                    isEditMode.toggle()
                                }
                            }) {
                                Text(isEditMode ? "Done" : "Edit")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Legend for data sources
                    HStack(spacing: 20) {
                        HStack(spacing: 5) {
                            Image("applehealthdark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Apple Health")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        HStack(spacing: 5) {
                            Image(systemName: "figure.walk")
                                .foregroundColor(.blue)
                            Text("Manual Entry")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        HStack(spacing: 5) {
                            Image(systemName: "gearshape.2.fill")
                                .foregroundColor(.orange)
                            Text("Automated")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 5)
                    
                    if entries.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            
                            Text("No \(statType.title) History")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(statType == .bmi ? 
                                "BMI is automatically calculated from your weight and height" :
                                "Tap + to add your first \(statType.title.lowercased()) entry")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            // Metric type label on top left
                            Text(statType == .weight ? (preferredWeightUnit == "lb" ? "lb" : "kg") : statType.unit)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                            
                            VStack(spacing: 0) {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                    VStack(spacing: 0) {
                                        HStack {
                                            if isEditMode && !statType.isCalculated && entry.source != .automated {
                                                Button(action: {
                                                    withAnimation(.easeInOut) {
                                                        historyManager.removeEntry(entry)
                                                    }
                                                }) {
                                                    Image(systemName: "minus.circle.fill")
                                                        .foregroundColor(.red)
                                                        .padding(.leading)
                                                }
                                                .transition(.move(edge: .leading))
                                            }
                                            
                                            if statType.isCalculated {
                                                BMIRow(entry: entry, historyManager: historyManager)
                                            } else {
                                                EntryRow(entry: entry, statType: statType) {
                                                    if !isEditMode {
                                                        selectedEntry = entry
                                                    }
                                                }
                                            }
                                        }
                                        .animation(.easeInOut, value: isEditMode)
                                        
                                        // Add separator line if not the last item
                                        if index < entries.count - 1 {
                                            Divider()
                                                .background(Color.gray.opacity(0.3))
                                                .padding(.horizontal)
                                        }
                                    }
                                }
                            }
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .navigationTitle("\(statType.title) History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !statType.isCalculated {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddEntryView = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddEntryView) {
            AddEntryView(historyManager: historyManager, statType: statType)
        }
        .sheet(item: $selectedEntry) { entry in
            EditEntryView(historyManager: historyManager, entry: entry)
        }
    }
}
