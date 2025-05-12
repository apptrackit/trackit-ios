import SwiftUI

struct ExportDataView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTypes: Set<StatType> = Set(StatType.allCases)
    @State private var selectedSources: Set<StatSource> = [.manual] // Default to manual only
    @State private var exportFormat: ExportFormat = .json
    @State private var showingShareSheet = false
    @State private var exportData: Data?
    
    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case csv = "CSV"
        
        var iconName: String {
            switch self {
            case .json: return "doc.text"
            case .csv: return "tablecells"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Export Format")) {
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Label(format.rawValue, systemImage: format.iconName)
                                .tag(format)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("Data Sources")) {
                    ForEach(StatSource.allCases, id: \.self) { source in
                        Toggle(isOn: Binding(
                            get: { selectedSources.contains(source) },
                            set: { isSelected in
                                if isSelected {
                                    selectedSources.insert(source)
                                } else {
                                    selectedSources.remove(source)
                                }
                            }
                        )) {
                            switch source {
                            case .manual:
                                Label(source.rawValue.capitalized, systemImage: "figure.walk")
                                    .foregroundColor(.white)
                            case .appleHealth:
                                Label {
                                    Text(source.rawValue.capitalized)
                                } icon: {
                                    Image("applehealthdark")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                }
                                .foregroundColor(.white)
                            case .automated:
                                Label(source.rawValue.capitalized, systemImage: "gearshape.2.fill")
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                
                Section(header: Text("Data Types")) {
                    ForEach(StatType.allCases, id: \.self) { type in
                        Toggle(isOn: Binding(
                            get: { selectedTypes.contains(type) },
                            set: { isSelected in
                                if isSelected {
                                    selectedTypes.insert(type)
                                } else {
                                    selectedTypes.remove(type)
                                }
                            }
                        )) {
                            Label(type.title, systemImage: type.iconName)
                        }
                    }
                }
                
                Section {
                    Button(action: prepareExport) {
                        HStack {
                            Spacer()
                            Label("Export Data", systemImage: "square.and.arrow.up")
                                .bold()
                            Spacer()
                        }
                    }
                    .disabled(selectedTypes.isEmpty || selectedSources.isEmpty)
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let data = exportData {
                    ShareSheet(items: [data])
                }
            }
        }
    }
    
    private func prepareExport() {
        var exportEntries: [String: [StatEntry]] = [:]
        
        // Collect all entries for selected types and sources
        for type in selectedTypes {
            let entries = historyManager.getEntries(for: type)
                .filter { selectedSources.contains($0.source) }
            if !entries.isEmpty {
                exportEntries[type.rawValue] = entries
            }
        }
        
        // Convert to selected format
        switch exportFormat {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            exportData = try? encoder.encode(exportEntries)
            
        case .csv:
            var csvString = "Type,Date,Value,Unit,Source\n"
            for (type, entries) in exportEntries {
                for entry in entries {
                    let dateFormatter = ISO8601DateFormatter()
                    let dateString = dateFormatter.string(from: entry.date)
                    csvString += "\(type),\(dateString),\(entry.value),\(entry.type.unit),\(entry.source.rawValue)\n"
                }
            }
            exportData = csvString.data(using: .utf8)
        }
        
        showingShareSheet = true
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
} 