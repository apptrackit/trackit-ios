import SwiftUI

struct TrackDataView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    @State private var selectedType: StatType = .weight
    @State private var value: String = ""
    @State private var date = Date()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
                    Text("Track New Data")
                        .font(.title.bold())
                        .foregroundColor(.white)
                        .padding()
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(StatType.allCases.filter { !$0.isCalculated }) { type in
                                MeasurementTypeButton(
                                    type: type,
                                    isSelected: selectedType == type,
                                    action: { selectedType = type }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("\(selectedType.title) (\(selectedType.unit))")
                            .foregroundColor(.white)
                        TextField("Value in \(selectedType.unit)", text: $value)
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                    }
                    .padding()
                    
                    VStack(alignment: .leading) {
                        Text("Date")
                            .foregroundColor(.white)
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .datePickerStyle(WheelDatePickerStyle())
                            .labelsHidden()
                            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                            .cornerRadius(10)
                            .colorScheme(.dark)
                    }
                    .padding()
                    
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .cornerRadius(10)
                        
                        Spacer()
                        
                        Button("Save") {
                            saveEntry()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    .padding()
                    
                    Spacer()
                }
                .padding()
            }
        }
    }
    
    private func saveEntry() {
        guard let valueDouble = Double(value.replacingOccurrences(of: ",", with: ".")) else { return }
        let entry = StatEntry(date: date, value: valueDouble, type: selectedType)
        historyManager.addEntry(entry)
        dismiss()
    }
}

struct MeasurementTypeButton: View {
    let type: StatType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Spacer()
                    .frame(height: 4)  // Add small top spacing
                
                Image(systemName: type.iconName)
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
                    .foregroundColor(isSelected ? .white : .gray)
                
                Text(type.title)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : .gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 32)
                
                Spacer()
                    .frame(height: 4)  // Add small bottom spacing
            }
            .frame(width: 80, height: 80)
            .background(isSelected ? Color.blue : Color(red: 0.11, green: 0.11, blue: 0.12))
            .cornerRadius(10)
        }
    }
}
