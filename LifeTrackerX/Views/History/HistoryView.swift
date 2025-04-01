import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    let statType: StatType
    @State private var showingAddEntryView = false
    @State private var selectedEntry: StatEntry?
    @State private var selectedTimeFrame: TimeFrame = .weekly
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
                        
                        Text("History")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        
                        if entries.isEmpty {
                            ContentUnavailableView {
                                Label("No \(statType.title) History", systemImage: "chart.xyaxis.line")
                            } description: {
                                Text("Tap + to add your first \(statType.title.lowercased()) entry")
                            }
                            .foregroundColor(.white)
                        } else {
                            LazyVStack {
                                ForEach(entries) { entry in
                                    EntryRow(entry: entry, statType: statType) {
                                        selectedEntry = entry
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 80) // Add some bottom padding for the close button
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Button(action: { dismiss() }) {
                            Text("Close")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                                .cornerRadius(10)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                }
            }
            .navigationTitle("\(statType.title) History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

struct EntryRow: View {
    let entry: StatEntry
    let statType: StatType
    let onEdit: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(formatDate(entry.date))
                    .font(.headline)
                    .foregroundColor(.white)
                
                let formattedValue = entry.value.truncatingRemainder(dividingBy: 1) == 0 ?
                    String(format: "%.0f", entry.value) :
                    String(format: "%.1f", entry.value)
                
                Text("\(formattedValue) \(statType.unit)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
