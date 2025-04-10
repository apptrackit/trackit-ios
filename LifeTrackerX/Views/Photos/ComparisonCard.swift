import SwiftUI

struct ComparisonCard: View {
    @ObservedObject var photoManager: ProgressPhotoManager
    let category: PhotoCategory
    let historyManager: StatsHistoryManager
    
    @State private var leftPhotoIndex: Int = 0
    @State private var rightPhotoIndex: Int = 1
    @State private var showingPhotoSelector = false
    @State private var isSelectingLeftPhoto = true
    
    private var categoryPhotos: [ProgressPhoto] {
        photoManager.getPhotos(for: category)
    }
    
    private var leftPhoto: ProgressPhoto? {
        categoryPhotos.indices.contains(leftPhotoIndex) ? categoryPhotos[leftPhotoIndex] : nil
    }
    
    private var rightPhoto: ProgressPhoto? {
        categoryPhotos.indices.contains(rightPhotoIndex) ? categoryPhotos[rightPhotoIndex] : nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Comparison")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                if let leftPhoto = leftPhoto, let rightPhoto = rightPhoto {
                    // Time difference
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        
                        Text(formatTimeDifference(from: leftPhoto.date, to: rightPhoto.date))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            
            // Photo comparison
            GeometryReader { geometry in
                let availableWidth = geometry.size.width - 16
                let photoWidth = (availableWidth / 2) - 4
                let photoHeight = photoWidth * 1.4 // Taller photos
                
                HStack(spacing: 8) {
                    // Left photo with date and controls
                    VStack(spacing: 4) {
                        if let photo = leftPhoto, let image = photo.image {
                            ZStack(alignment: .topLeading) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: photoWidth, height: photoHeight)
                                    .clipped()
                                    .cornerRadius(10)
                                
                                Text("BEFORE")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(5)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(5)
                                    .padding(6)
                            }
                            .onTapGesture {
                                isSelectingLeftPhoto = true
                                showingPhotoSelector = true
                            }
                        } else {
                            Rectangle()
                                .fill(Color(red: 0.15, green: 0.15, blue: 0.15))
                                .frame(width: photoWidth, height: photoHeight)
                                .cornerRadius(10)
                                .overlay(
                                    Text("Select photo")
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray)
                                )
                                .onTapGesture {
                                    isSelectingLeftPhoto = true
                                    showingPhotoSelector = true
                                }
                        }
                        
                        if let photo = leftPhoto {
                            Text(formatDate(photo.date))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                    
                    // Right photo with date and controls
                    VStack(spacing: 4) {
                        if let photo = rightPhoto, let image = photo.image {
                            ZStack(alignment: .topLeading) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: photoWidth, height: photoHeight)
                                    .clipped()
                                    .cornerRadius(10)
                                
                                Text("AFTER")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(5)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(5)
                                    .padding(6)
                            }
                            .onTapGesture {
                                isSelectingLeftPhoto = false
                                showingPhotoSelector = true
                            }
                        } else {
                            Rectangle()
                                .fill(Color(red: 0.15, green: 0.15, blue: 0.15))
                                .frame(width: photoWidth, height: photoHeight)
                                .cornerRadius(10)
                                .overlay(
                                    Text("Select photo")
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray)
                                )
                                .onTapGesture {
                                    isSelectingLeftPhoto = false
                                    showingPhotoSelector = true
                                }
                        }
                        
                        if let photo = rightPhoto {
                            Text(formatDate(photo.date))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 300)
            
            // Stats comparison
            if let leftPhoto = leftPhoto, let rightPhoto = rightPhoto {
                MeasurementComparisonView(
                    oldPhoto: leftPhoto, 
                    newPhoto: rightPhoto,
                    historyManager: historyManager
                )
                .padding(.top, 4)
            }
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .cornerRadius(14)
        .padding(.horizontal, 4)
        .onAppear {
            // Initialize with latest photos
            if categoryPhotos.count >= 2 {
                rightPhotoIndex = categoryPhotos.count - 1
                leftPhotoIndex = rightPhotoIndex - 1
            }
        }
        .sheet(isPresented: $showingPhotoSelector) {
            PhotoSelectorView(
                photos: categoryPhotos,
                onSelect: { selectedIndex in
                    if isSelectingLeftPhoto {
                        leftPhotoIndex = selectedIndex
                    } else {
                        rightPhotoIndex = selectedIndex
                    }
                    showingPhotoSelector = false
                },
                currentlySelectedIndex: isSelectingLeftPhoto ? leftPhotoIndex : rightPhotoIndex,
                title: isSelectingLeftPhoto ? "Select Left Photo" : "Select Right Photo"
            )
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter.string(from: date)
    }
    
    private func formatTimeDifference(from startDate: Date, to endDate: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .month], from: startDate, to: endDate)
        
        if let months = components.month, months > 0 {
            return "\(months)m"
        } else if let days = components.day, days > 0 {
            return "\(days)d"
        } else {
            return "Today"
        }
    }
}

struct CategoryBadge: View {
    let category: PhotoCategory
    
    var body: some View {
        Image(systemName: category.iconName)
            .font(.system(size: 12))
            .foregroundColor(.white)
            .padding(6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(4)
    }
}

struct PhotoSelectorView: View {
    let photos: [ProgressPhoto]
    let onSelect: (Int) -> Void
    let currentlySelectedIndex: Int
    let title: String
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 12) {
                    // Photo grid organized by date
                    ScrollView {
                        // Group photos by month
                        let groupedByMonth = Dictionary(grouping: photos.sorted(by: { $0.date > $1.date })) { photo in
                            formatMonth(photo.date)
                        }
                        
                        ForEach(groupedByMonth.keys.sorted(by: <), id: \.self) { month in
                            if let monthPhotos = groupedByMonth[month] {
                                // Month header
                                HStack {
                                    Text(month)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading)
                                        .padding(.top, 8)
                                    
                                    Spacer()
                                }
                                
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                                    ForEach(monthPhotos, id: \.id) { photo in
                                        let index = photos.firstIndex(where: { $0.id == photo.id }) ?? 0
                                        
                                        if let image = photo.image {
                                            ZStack {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 100, height: 130)
                                                    .clipped()
                                                    .cornerRadius(8)
                                                
                                                // Selection indicator
                                                if index == currentlySelectedIndex {
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(Color.blue, lineWidth: 3)
                                                        .frame(width: 100, height: 130)
                                                }
                                                
                                                VStack {
                                                    // Date badge
                                                    HStack {
                                                        Text(formatDate(photo.date))
                                                            .font(.system(size: 10, weight: .medium))
                                                            .padding(4)
                                                            .background(Color.black.opacity(0.7))
                                                            .cornerRadius(4)
                                                            .foregroundColor(.white)
                                                        
                                                        Spacer()
                                                        
                                                        // Age indicator
                                                        if let days = daysSinceDate(photo.date) {
                                                            Text(formatAge(days))
                                                                .font(.system(size: 10, weight: .medium))
                                                                .padding(4)
                                                                .background(Color.blue.opacity(0.7))
                                                                .cornerRadius(4)
                                                                .foregroundColor(.white)
                                                        }
                                                    }
                                                    
                                                    Spacer()
                                                    
                                                    // Removed category icons display
                                                }
                                                .padding(4)
                                            }
                                            .onTapGesture {
                                                onSelect(index)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Bottom padding
                        Color.clear.frame(height: 20)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .accentColor(.white)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter.string(from: date)
    }
    
    private func formatMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func daysSinceDate(_ date: Date) -> Int? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: date, to: Date())
        return components.day
    }
    
    private func formatAge(_ days: Int) -> String {
        if days == 0 {
            return "Today"
        } else if days == 1 {
            return "1 day"
        } else if days < 7 {
            return "\(days) days"
        } else if days < 30 {
            let weeks = days / 7
            return "\(weeks)w"
        } else if days < 365 {
            let months = days / 30
            return "\(months)m"
        } else {
            let years = days / 365
            return "\(years)y"
        }
    }
}

struct SinglePhotoCard: View {
    let photo: ProgressPhoto
    let historyManager: StatsHistoryManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(photo.primaryCategory.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                if photo.categories.count > 1 {
                    Text("+\(photo.categories.count - 1)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Text(formatDate(photo.date))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            
            // Category tags if multiple categories
            if photo.categories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photo.categories, id: \.self) { category in
                            CategoryBadge(category: category)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 5)
                }
            }
            
            // Photo
            if let image = photo.image {
                GeometryReader { geometry in
                    let availableWidth = geometry.size.width - 20
                    
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: availableWidth)
                        .cornerRadius(10)
                        .padding(.horizontal, 10)
                }
                .frame(height: 300) // Increased height
            }
            
            // Associated measurements
            MeasurementDetailView(
                photo: photo,
                historyManager: historyManager
            )
            .padding(10)
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .cornerRadius(14)
        .padding(.horizontal, 4)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Measurements")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            
            if oldMeasurements.isEmpty && newMeasurements.isEmpty {
                Text("No measurements")
                    .font(.body)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            } else {
                VStack(spacing: 4) {
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
                                    .padding(.horizontal, 10)
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
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
    
    private var isGoodChange: Bool {
        // For bodyFat and waist, decrease is good
        if type == .bodyFat || type == .waist {
            return change < 0
        }
        // For all others, increase is good (muscle measurements, weight for muscle gain)
        return change > 0
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Text(type.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 70, alignment: .leading)
            
            Spacer()
            
            if let old = oldValue {
                Text(formatValue(old, type: type))
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
            } else {
                Text("-")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
            }
            
            Image(systemName: "arrow.right")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            
            if let new = newValue {
                Text(formatValue(new, type: type))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
            } else {
                Text("-")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
            }
            
            if hasChange {
                Text(formatChange(change, type: type))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isGoodChange ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isGoodChange ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .cornerRadius(6)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }
    
    private func formatValue(_ value: Double, type: StatType) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        
        if let formattedValue = formatter.string(from: NSNumber(value: value)) {
            return "\(formattedValue)"
        }
        
        return "\(value)"
    }
    
    private func formatChange(_ change: Double, type: StatType) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        
        if let formattedValue = formatter.string(from: NSNumber(value: change)) {
            return "\(formattedValue)"
        }
        
        return "\(change > 0 ? "+" : "")\(change)"
    }
}

struct MeasurementDetailView: View {
    let photo: ProgressPhoto
    let historyManager: StatsHistoryManager
    
    private var measurements: [StatType: StatEntry] {
        var result: [StatType: StatEntry] = [:]
        let entries = photo.associatedMeasurements ?? historyManager.getEntriesAt(date: photo.date)
        for entry in entries {
            result[entry.type] = entry
        }
        return result
    }
    
    private var relevantTypes: [StatType] {
        return [.weight, .bodyFat, .bicep, .chest, .waist, .thigh, .shoulder]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Measurements")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            if measurements.isEmpty {
                Text("No measurements")
                    .font(.body)
                    .foregroundColor(.gray)
                    .padding(.bottom, 5)
            } else {
                VStack(spacing: 5) {
                    ForEach(relevantTypes, id: \.self) { type in
                        if let entry = measurements[type] {
                            HStack {
                                Text(type.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                HStack(spacing: 6) {
                                    Image(systemName: entry.source.iconName)
                                        .font(.system(size: 13))
                                        .foregroundColor(entry.source == .appleHealth ? .green : 
                                                        entry.source == .automated ? .orange : .blue)
                                    
                                    Text(formatValue(entry.value, type: type))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.vertical, 4)
                            
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
                    .padding(.vertical, 6)
                
                Text("Notes")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.bottom, 4)
                
                Text(notes)
                    .font(.body)
                    .foregroundColor(.gray)
                    .lineLimit(3)
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