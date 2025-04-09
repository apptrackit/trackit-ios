import SwiftUI

struct ComparisonCard: View {
    let oldPhoto: ProgressPhoto
    let newPhoto: ProgressPhoto
    let historyManager: StatsHistoryManager
    
    @State private var sliderPosition: CGFloat = 0.5
    @State private var cardWidth: CGFloat = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Progress Comparison")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Time difference
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text(formatTimeDifference(from: oldPhoto.date, to: newPhoto.date))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)
            
            // Before/After dates
            HStack {
                Text(formatDate(oldPhoto.date))
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(formatDate(newPhoto.date))
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(.horizontal)
            
            // Image comparison with slider
            ZStack(alignment: .leading) {
                // Container to measure width
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            self.cardWidth = geometry.size.width
                        }
                }
                
                // Old photo (full width)
                if let oldImage = oldPhoto.image {
                    Image(uiImage: oldImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 400)
                        .clipped()
                        .cornerRadius(12)
                }
                
                // New photo (masked by slider position)
                if let newImage = newPhoto.image {
                    Image(uiImage: newImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 400)
                        .clipped()
                        .cornerRadius(12)
                        .mask(
                            Rectangle()
                                .frame(width: cardWidth * sliderPosition)
                        )
                }
                
                // Slider handle
                Rectangle()
                    .frame(width: 3, height: 400)
                    .offset(x: cardWidth * sliderPosition)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newPosition = value.location.x / cardWidth
                                sliderPosition = min(max(newPosition, 0), 1)
                            }
                    )
                
                // Slider handle knob
                Circle()
                    .fill(Color.white)
                    .frame(width: 30, height: 30)
                    .offset(x: cardWidth * sliderPosition - 15)
                    .shadow(radius: 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newPosition = value.location.x / cardWidth
                                sliderPosition = min(max(newPosition, 0), 1)
                            }
                    )
                
                // Before/After labels
                ZStack(alignment: .top) {
                    HStack {
                        Text("BEFORE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .padding(.leading, 8)
                            .padding(.top, 8)
                        
                        Spacer()
                        
                        Text("AFTER")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .padding(.trailing, 8)
                            .padding(.top, 8)
                    }
                }
            }
            .frame(height: 400)
            .cornerRadius(12)
            .padding(.horizontal)
            
            // Stats comparison
            MeasurementComparisonView(
                oldPhoto: oldPhoto, 
                newPhoto: newPhoto,
                historyManager: historyManager
            )
            .padding()
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func formatTimeDifference(from startDate: Date, to endDate: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .month], from: startDate, to: endDate)
        
        if let months = components.month, months > 0 {
            return "\(months) month\(months == 1 ? "" : "s") difference"
        } else if let days = components.day, days > 0 {
            return "\(days) day\(days == 1 ? "" : "s") difference"
        } else {
            return "Same day"
        }
    }
}

struct SinglePhotoCard: View {
    let photo: ProgressPhoto
    let historyManager: StatsHistoryManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(photo.category.name)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(formatDate(photo.date))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)
            
            // Photo
            if let image = photo.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 400)
                    .clipped()
                    .cornerRadius(12)
                    .padding(.horizontal)
            }
            
            // Associated measurements
            MeasurementDetailView(
                photo: photo,
                historyManager: historyManager
            )
            .padding()
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

struct MeasurementComparisonView: View {
    let oldPhoto: ProgressPhoto
    let newPhoto: ProgressPhoto
    let historyManager: StatsHistoryManager
    
    private var oldMeasurements: [StatType: Double] {
        var result: [StatType: Double] = [:]
        let measurements = oldPhoto.associatedMeasurements ?? historyManager.getEntriesAt(date: oldPhoto.date)
        for measurement in measurements {
            result[measurement.type] = measurement.value
        }
        return result
    }
    
    private var newMeasurements: [StatType: Double] {
        var result: [StatType: Double] = [:]
        let measurements = newPhoto.associatedMeasurements ?? historyManager.getEntriesAt(date: newPhoto.date)
        for measurement in measurements {
            result[measurement.type] = measurement.value
        }
        return result
    }
    
    private var relevantTypes: [StatType] {
        return [.weight, .bodyFat, .bicep, .chest, .waist, .thigh, .shoulder]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Measurement Changes")
                .font(.headline)
                .foregroundColor(.white)
            
            if oldMeasurements.isEmpty && newMeasurements.isEmpty {
                Text("No measurements associated with these photos")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            } else {
                VStack(spacing: 10) {
                    ForEach(relevantTypes, id: \.self) { type in
                        if oldMeasurements[type] != nil || newMeasurements[type] != nil {
                            MeasurementComparisonRow(
                                type: type,
                                oldValue: oldMeasurements[type],
                                newValue: newMeasurements[type]
                            )
                            
                            if type != relevantTypes.last {
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                            }
                        }
                    }
                }
            }
        }
    }
}

struct MeasurementComparisonRow: View {
    let type: StatType
    let oldValue: Double?
    let newValue: Double?
    
    private var hasChange: Bool {
        guard let old = oldValue, let new = newValue else { return false }
        return abs(new - old) > 0.01
    }
    
    private var change: Double {
        guard let old = oldValue, let new = newValue else { return 0 }
        return new - old
    }
    
    private var percentChange: Double? {
        guard let old = oldValue, let new = newValue, old != 0 else { return nil }
        return ((new - old) / old) * 100
    }
    
    var body: some View {
        HStack {
            Text(type.title)
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(width: 100, alignment: .leading)
            
            Spacer()
            
            if let old = oldValue {
                Text(formatValue(old, type: type))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            } else {
                Text("-")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundColor(.gray)
            
            if let new = newValue {
                Text(formatValue(new, type: type))
                    .font(.subheadline)
                    .foregroundColor(.white)
            } else {
                Text("-")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            if hasChange {
                HStack(spacing: 2) {
                    Text(formatChange(change, type: type))
                        .font(.caption)
                        .foregroundColor(change < 0 ? .green : (type == .bodyFat || type == .waist) ? .green : .red)
                    
                    if let percent = percentChange {
                        Text("(\(String(format: "%.1f", percent))%)")
                            .font(.caption)
                            .foregroundColor(change < 0 ? .green : (type == .bodyFat || type == .waist) ? .green : .red)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((change < 0 ? Color.green : (type == .bodyFat || type == .waist) ? Color.green : Color.red).opacity(0.2))
                .cornerRadius(4)
            }
        }
    }
    
    private func formatValue(_ value: Double, type: StatType) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        
        if let formattedValue = formatter.string(from: NSNumber(value: value)) {
            return "\(formattedValue) \(type.unit)"
        }
        
        return "\(value) \(type.unit)"
    }
    
    private func formatChange(_ change: Double, type: StatType) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        
        if let formattedValue = formatter.string(from: NSNumber(value: change)) {
            return "\(formattedValue) \(type.unit)"
        }
        
        return "\(change > 0 ? "+" : "")\(change) \(type.unit)"
    }
}

struct MeasurementDetailView: View {
    let photo: ProgressPhoto
    let historyManager: StatsHistoryManager
    
    private var measurements: [StatType: Double] {
        var result: [StatType: Double] = [:]
        let entries = photo.associatedMeasurements ?? historyManager.getEntriesAt(date: photo.date)
        for entry in entries {
            result[entry.type] = entry.value
        }
        return result
    }
    
    private var relevantTypes: [StatType] {
        return [.weight, .bodyFat, .bicep, .chest, .waist, .thigh, .shoulder]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Measurements")
                .font(.headline)
                .foregroundColor(.white)
            
            if measurements.isEmpty {
                Text("No measurements associated with this photo")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            } else {
                VStack(spacing: 10) {
                    ForEach(relevantTypes, id: \.self) { type in
                        if let value = measurements[type] {
                            HStack {
                                Text(type.title)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Text(formatValue(value, type: type))
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            
                            if type != relevantTypes.last {
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                            }
                        }
                    }
                }
            }
            
            if let notes = photo.notes, !notes.isEmpty {
                Divider()
                    .background(Color.gray.opacity(0.3))
                    .padding(.vertical, 4)
                
                Text("Notes")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func formatValue(_ value: Double, type: StatType) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        
        if let formattedValue = formatter.string(from: NSNumber(value: value)) {
            return "\(formattedValue) \(type.unit)"
        }
        
        return "\(value) \(type.unit)"
    }
} 