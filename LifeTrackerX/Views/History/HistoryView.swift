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
    @State private var selectedTimeFrame: TimeFrame = .weekly
    @State private var isEditMode = false
    
    var entries: [StatEntry] {
        historyManager.getEntries(for: statType)
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 20) {
                    HistoryGraphView(historyManager: historyManager,
                                     statType: statType,
                                     selectedTimeFrame: $selectedTimeFrame)
                        .frame(height: 300)
                        .padding(.horizontal)
                    
                    HStack {
                        Text("History")
                            .font(.headline)
                            .foregroundColor(.white)
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
                                .foregroundColor(.white)
                            
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
                        LazyVStack {
                            ForEach(entries) { entry in
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
                            }
                        }
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
                            .foregroundColor(.white)
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
