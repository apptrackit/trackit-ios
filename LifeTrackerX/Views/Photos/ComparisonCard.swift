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
            // Initialize with oldest photo on left, newest on right
            if categoryPhotos.count >= 2 {
                // Sort photos by date (oldest to newest)
                let sortedIndices = categoryPhotos.indices.sorted { categoryPhotos[$0].date < categoryPhotos[$1].date }
                // Set leftPhotoIndex to oldest photo, rightPhotoIndex to newest photo
                leftPhotoIndex = sortedIndices.first ?? 0
                rightPhotoIndex = sortedIndices.last ?? (categoryPhotos.count - 1)
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
    @State private var sortOption: PhotoSortOption = .date
    
    enum PhotoSortOption: String, CaseIterable {
        case date = "Date"
        case weight = "Weight"
        case bodyFat = "Body Fat"
        case bicep = "Bicep"
        case chest = "Chest"
        case shoulder = "Shoulder"
        case waist = "Waist"
        case thigh = "Thigh"
        
        var iconName: String {
            switch self {
            case .date: return "calendar"
            case .weight: return "scalemass"
            case .bodyFat: return "percent"
            case .bicep: return "figure.arms.open"
            case .chest: return "heart.fill"
            case .shoulder: return "figure.american.football"
            case .waist: return "circle.dashed"
            case .thigh: return "figure.walk"
            }
        }
        
        var statType: StatType {
            switch self {
            case .date: return .weight // Default, not used
            case .weight: return .weight
            case .bodyFat: return .bodyFat
            case .bicep: return .bicep
            case .chest: return .chest
            case .shoulder: return .shoulder
            case .waist: return .waist
            case .thigh: return .thigh
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 12) {
                    // Sort options
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(PhotoSortOption.allCases, id: \.self) { option in
                                Button(action: {
                                    sortOption = option
                                }) {
                                    HStack {
                                        Image(systemName: option.iconName)
                                            .font(.system(size: 12))
                                        Text(option.rawValue)
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(sortOption == option ? Color.blue : Color(red: 0.2, green: 0.2, blue: 0.2))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    
                    // Photo grid organized by selected sort option
                    ScrollView {
                        // Use different grouping methods based on the sort option
                        Group {
                            if sortOption == .date {
                                // Date sorting (existing implementation)
                                DateSortedPhotosView(
                                    photos: photos,
                                    currentlySelectedIndex: currentlySelectedIndex,
                                    onSelect: onSelect
                                )
                            } else {
                                // All measurement-based sorting uses the same view with different stat types
                                MeasurementSortedPhotosView(
                                    photos: photos,
                                    statType: sortOption.statType,
                                    currentlySelectedIndex: currentlySelectedIndex,
                                    onSelect: onSelect
                                )
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

// View for photos sorted by date
struct DateSortedPhotosView: View {
    let photos: [ProgressPhoto]
    let currentlySelectedIndex: Int
    let onSelect: (Int) -> Void
    
    var body: some View {
        // Group photos by month
        let groupedByMonth = Dictionary(grouping: photos.sorted(by: { $0.date > $1.date })) { photo in
            formatMonth(photo.date)
        }
        
        // Get unique months as Date objects for proper chronological sorting
        let monthDates = groupedByMonth.keys.compactMap { key -> Date? in
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMMM yyyy"
            return dateFormatter.date(from: key)
        }
        
        // Sort months in reverse chronological order (newest first)
        let sortedMonths = monthDates.sorted(by: >).compactMap { date -> String? in
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMMM yyyy"
            return dateFormatter.string(from: date)
        }
        
        ForEach(sortedMonths, id: \.self) { month in
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
                
                PhotoGrid(
                    photos: monthPhotos,
                    allPhotos: photos,
                    currentlySelectedIndex: currentlySelectedIndex,
                    onSelect: onSelect
                )
            }
        }
    }
    
    private func formatMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}

// View for photos sorted by measurement values
struct MeasurementSortedPhotosView: View {
    let photos: [ProgressPhoto]
    let statType: StatType
    let currentlySelectedIndex: Int
    let onSelect: (Int) -> Void
    
    // Get the associated measurement for each photo
    private var photosWithMeasurements: [(photo: ProgressPhoto, value: Double?)] {
        return photos.map { photo in
            // Find the measurement of the specified type
            let value = photo.associatedMeasurements?
                .first(where: { $0.type == statType })?.value
            return (photo, value)
        }
    }
    
    // Group photos by measurement range
    private var groupedPhotos: [(range: String, photos: [ProgressPhoto])] {
        // Filter out photos without the measurement
        let validPhotos = photosWithMeasurements.filter { $0.value != nil }
        
        // If no valid photos, return empty array
        if validPhotos.isEmpty {
            return []
        }
        
        // Sort by measurement value
        let sortedPhotos = validPhotos.sorted { a, b in
            guard let aValue = a.value, let bValue = b.value else {
                return false
            }
            return aValue > bValue // Higher values first
        }
        
        // Find ranges for grouping
        let allValues = sortedPhotos.compactMap { $0.value }
        if allValues.isEmpty {
            return []
        }
        
        // Get min and max values for range calculation
        let maxValue = allValues.max() ?? 0
        let minValue = allValues.min() ?? 0
        let range = maxValue - minValue
        
        // If all values are the same, use a single group
        if range < 0.1 {
            return [("All \(statType.title)", sortedPhotos.map { $0.photo })]
        }
        
        // Determine range increments based on the data spread
        let increment: Double
        if statType == .weight {
            increment = 5.0 // 5kg/10lb increments for weight
        } else if statType == .bodyFat {
            increment = 2.0 // 2% increments for body fat
        } else {
            increment = max(1.0, range / 4) // Divide into ~4 groups for other measurements
        }
        
        // Create range groups
        var groups: [String: [ProgressPhoto]] = [:]
        
        for (photo, value) in sortedPhotos {
            guard let value = value else { continue }
            
            // Calculate the range this value belongs to
            let rangeStart = floor(value / increment) * increment
            let rangeEnd = rangeStart + increment
            
            // Format the range label
            let rangeLabel = "\(formatValue(rangeStart))-\(formatValue(rangeEnd)) \(statType.unit)"
            
            // Add photo to the appropriate range group
            if groups[rangeLabel] == nil {
                groups[rangeLabel] = []
            }
            groups[rangeLabel]?.append(photo)
        }
        
        // Convert to array and sort by range value (descending)
        return groups.map { (range, photos) in
            (range, photos)
        }
        .sorted { a, b in
            // Extract the starting range value for sorting
            let aValue = Double(a.range.split(separator: "-").first?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
            let bValue = Double(b.range.split(separator: "-").first?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
            return aValue > bValue
        }
    }
    
    var body: some View {
        if groupedPhotos.isEmpty {
            VStack {
                Text("No photos with \(statType.title) data")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .padding()
                
                // Show all photos without grouping
                Text("All Photos")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading)
                    .padding(.top, 8)
                
                PhotoGrid(
                    photos: photos,
                    allPhotos: photos,
                    currentlySelectedIndex: currentlySelectedIndex,
                    onSelect: onSelect
                )
            }
        } else {
            ForEach(groupedPhotos, id: \.range) { group in
                // Range header
                HStack {
                    Text(group.range)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading)
                        .padding(.top, 8)
                    
                    Spacer()
                }
                
                PhotoGrid(
                    photos: group.photos,
                    allPhotos: photos,
                    currentlySelectedIndex: currentlySelectedIndex,
                    onSelect: onSelect
                )
            }
        }
    }
    
    private func formatValue(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// Reusable photo grid component
struct PhotoGrid: View {
    let photos: [ProgressPhoto]
    let allPhotos: [ProgressPhoto] // The complete photo array for finding index
    let currentlySelectedIndex: Int
    let onSelect: (Int) -> Void
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
            ForEach(photos, id: \.id) { photo in
                let index = allPhotos.firstIndex(where: { $0.id == photo.id }) ?? 0
                
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
                            
                            // Measurement badge if available
                            if let measurements = photo.associatedMeasurements, !measurements.isEmpty {
                                HStack {
                                    Spacer()
                                    ForEach(getSummaryMeasurements(for: photo), id: \.type) { measurement in
                                        Text("\(measurement.type.title): \(formatValue(measurement.value, type: measurement.type))")
                                            .font(.system(size: 9, weight: .medium))
                                            .padding(4)
                                            .background(Color.gray.opacity(0.7))
                                            .cornerRadius(4)
                                            .foregroundColor(.white)
                                    }
                                }
                            }
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
    
    // Helper to get key measurements for display
    private func getSummaryMeasurements(for photo: ProgressPhoto) -> [StatEntry] {
        guard let measurements = photo.associatedMeasurements else { return [] }
        
        // Priority order for measurements to show
        let priorityTypes: [StatType] = [.weight, .bodyFat, .chest, .waist, .glutes]
        
        // Return up to 2 measurements based on priority
        return priorityTypes.compactMap { type in
            measurements.first { $0.type == type }
        }.prefix(2).map { $0 }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
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
    
    private func formatValue(_ value: Double, type: StatType) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        
        if let formattedValue = formatter.string(from: NSNumber(value: value)) {
            return formattedValue
        }
        return "\(value)"
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
        return [.weight, .bodyFat, .bicep, .chest, .waist, .thigh, .shoulder, .glutes]
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
        return [.weight, .bodyFat, .bicep, .chest, .waist, .thigh, .shoulder, .glutes]
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