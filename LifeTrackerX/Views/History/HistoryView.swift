import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    let statType: StatType
    @State private var showingAddEntryView = false
    @State private var selectedEntry: StatEntry?
    @State private var selectedTimeFrame: TimeFrame = .weekly
    @State private var isEditMode = false
    @Environment(\.dismiss) private var dismiss
    
    var entries: [StatEntry] {
        historyManager.getEntries(for: statType)
    }
    
    var body: some View {
        NavigationView {
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
                            
                            if !entries.isEmpty && statType != .bmi {
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
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 5)
                        
                        if entries.isEmpty {
                            ContentUnavailableView {
                                Label("No \(statType.title) History", systemImage: "chart.xyaxis.line")
                            } description: {
                                if statType == .bmi {
                                    Text("BMI is automatically calculated from your weight and height")
                                } else {
                                    Text("Tap + to add your first \(statType.title.lowercased()) entry")
                                }
                            }
                            .foregroundColor(.white)
                        } else {
                            LazyVStack {
                                ForEach(entries) { entry in
                                    HStack {
                                        if isEditMode && statType != .bmi {
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
                                        
                                        if statType == .bmi {
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text(statType.title)
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                if statType != .bmi {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingAddEntryView = true }) {
                            Image(systemName: "plus")
                                .foregroundColor(.white)
                        }
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
