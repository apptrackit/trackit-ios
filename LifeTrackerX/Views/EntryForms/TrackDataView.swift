import SwiftUI

struct TrackDataView: View {
    @ObservedObject var historyManager: StatsHistoryManager
    @State private var selectedType: StatType = .weight
    @State private var value: String = ""
    @State private var date = Date()
    @State private var isKeyboardFocused = false
    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isValueFieldFocused: Bool
    
    private var canSave: Bool {
        !value.isEmpty && Double(value.replacingOccurrences(of: ",", with: ".")) != nil
    }
    
    var body: some View {
                NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Metric Type Icon
                        VStack(spacing: 16) {
                            Circle()
                                .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: selectedType.iconName)
                                        .font(.system(size: 32))
                                        .foregroundColor(.purple)
                                )
                            
                            Text(selectedType.title)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 20)
                        
                        // Metric Type Selection
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
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
                        .padding(.bottom, 30)
                        
                        // Form Fields - Unified Box
                        VStack(spacing: 0) {
                            // Date Field
                            HStack {
                                Text("Date")
                                    .foregroundColor(.white)
                                Spacer()
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundColor(showingDatePicker ? .blue : .white)
                            }
                            .padding()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isValueFieldFocused = false
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showingDatePicker.toggle()
                                    if showingDatePicker {
                                        showingTimePicker = false
                                    }
                                }
                            }
                            
                            // Inline Date Picker
                            if showingDatePicker {
                                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                    .colorScheme(.dark)
                                    .padding()
                                    .transition(.opacity)
                            }
                            
                            // Separator Line
                            if !showingDatePicker {
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                            }
                            
                            // Time Field
                            HStack {
                                Text("Time")
                                    .foregroundColor(.white)
                                Spacer()
                                Text(date.formatted(date: .omitted, time: .shortened))
                                    .foregroundColor(showingTimePicker ? .blue : .white)
                            }
                            .padding()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isValueFieldFocused = false
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showingTimePicker.toggle()
                                    if showingTimePicker {
                                        showingDatePicker = false
                                    }
                                }
                            }
                            
                            // Inline Time Picker
                            if showingTimePicker {
                                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.wheel)
                                    .colorScheme(.dark)
                                    .padding()
                                    .transition(.opacity)
                            }
                            
                            // Separator Line
                            if !showingTimePicker {
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                            }
                            
                            // Value Field
                            HStack {
                                Text(selectedType.unit)
                                    .foregroundColor(.white)
                                Spacer()
                                TextField("", text: $value)
                                    .keyboardType(.decimalPad)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.trailing)
                                    .focused($isValueFieldFocused)
                            }
                            .padding()
                        }
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal)
                        
                        Spacer()
                            .frame(height: 50)
                        }
                    }
                }
            .navigationBarTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        saveEntry()
                    }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(canSave ? .white : .gray)
                            .frame(width: 32, height: 32)
                            .background(canSave ? .blue : .gray.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                // Auto-focus the value field when the view appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isValueFieldFocused = true
                }
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
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
