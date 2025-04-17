import SwiftUI
import PhotosUI
import ImageIO
import Photos

struct AddPhotoView: View {
    @ObservedObject var photoManager: ProgressPhotoManager
    @ObservedObject var historyManager: StatsHistoryManager
    var category: PhotoCategory?
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedCategories: Set<PhotoCategory> = []
    @State private var selectedDate = Date()
    @State private var notes = ""
    @State private var loadingImage = false
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Image picker
                        VStack {
                            if let selectedImage {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 300)
                                    .cornerRadius(12)
                            } else if loadingImage {
                                ProgressView()
                                    .frame(height: 300)
                            } else {
                                ZStack {
                                    Rectangle()
                                        .fill(Color(red: 0.15, green: 0.15, blue: 0.15))
                                        .frame(height: 300)
                                        .cornerRadius(12)
                                    
                                    VStack(spacing: 12) {
                                        Image(systemName: "photo.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray)
                                        
                                        Text("Tap to add photo")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .onTapGesture {
                                    // Fallback if PhotosPicker doesn't work
                                }
                            }
                            
                            PhotosPicker(
                                selection: $selectedItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Text("Select Photo")
                                    .foregroundColor(.blue)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 20)
                                    .background(Color(red: 0.15, green: 0.15, blue: 0.15))
                                    .cornerRadius(8)
                            }
                            .onChange(of: selectedItem) { newValue in
                                loadImage()
                            }
                        }
                        .padding(.horizontal)
                        
                        // Category selector
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Categories")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                if !selectedCategories.isEmpty {
                                    Text("\(selectedCategories.count) selected")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            MultiCategorySelector(
                                selectedCategories: $selectedCategories
                            )
                        }
                        .padding(.horizontal)
                        
                        // Date picker
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Date")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            DatePicker("", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 20)
                                .background(Color(red: 0.15, green: 0.15, blue: 0.15))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        
                        // Measurements on this date
                        MeasurementSummaryView(
                            date: selectedDate,
                            historyManager: historyManager
                        )
                        .padding()
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .cornerRadius(16)
                        .padding(.horizontal)
                        
                        // Notes
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Notes")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            TextEditor(text: $notes)
                                .frame(height: 120)
                                .padding(10)
                                .background(Color(red: 0.15, green: 0.15, blue: 0.15))
                                .cornerRadius(12)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 50)
                    }
                }
            }
            .navigationTitle("Add Progress Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .foregroundColor(.blue)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        savePhoto()
                    }) {
                        Text("Save")
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    .disabled(selectedImage == nil || selectedCategories.isEmpty)
                    .opacity((selectedImage == nil || selectedCategories.isEmpty) ? 0.5 : 1.0)
                }
            }
            .onAppear {
                if let category = category {
                    selectedCategories.insert(category)
                }
            }
        }
    }
    
    private func loadImage() {
        loadingImage = true
        
        Task {
            if let data = try? await selectedItem?.loadTransferable(type: Data.self) {
                if let uiImage = UIImage(data: data) {
                    selectedImage = uiImage
                    
                    // Store original date to check if it's changed
                    let originalDate = selectedDate
                    
                    // Try to get creation date directly from PHAsset
                    if let assetIdentifier = selectedItem?.itemIdentifier,
                       let assetResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).firstObject {
                        print("Found PHAsset with creation date: \(String(describing: assetResult.creationDate))")
                        
                        if let creationDate = assetResult.creationDate {
                            selectedDate = creationDate
                            print("Set date from PHAsset: \(creationDate)")
                        }
                    }
                    
                    // If PHAsset didn't work, try metadata extraction
                    if selectedDate == originalDate { // Only proceed if date hasn't been updated by PHAsset
                        // Extract creation date from image metadata
                        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil) {
                            if let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] {
                                print("Image properties found: \(imageProperties.keys)")
                                
                                // Try EXIF dictionary first
                                if let exifDictionary = imageProperties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                                    print("EXIF data found: \(exifDictionary.keys)")
                                    
                                    // Try various EXIF date properties
                                    if let dateTimeOriginal = exifDictionary[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                                        print("Found EXIF DateTimeOriginal: \(dateTimeOriginal)")
                                        let dateFormatter = DateFormatter()
                                        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                                        
                                        if let date = dateFormatter.date(from: dateTimeOriginal) {
                                            print("Successfully parsed date: \(date)")
                                            selectedDate = date
                                        }
                                    } else if let dateTimeDigitized = exifDictionary[kCGImagePropertyExifDateTimeDigitized as String] as? String {
                                        print("Found EXIF DateTimeDigitized: \(dateTimeDigitized)")
                                        let dateFormatter = DateFormatter()
                                        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                                        
                                        if let date = dateFormatter.date(from: dateTimeDigitized) {
                                            print("Successfully parsed date: \(date)")
                                            selectedDate = date
                                        }
                                    }
                                }
                                
                                // Try TIFF dictionary if EXIF didn't work
                                if let tiffDictionary = imageProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                                    print("TIFF data found: \(tiffDictionary.keys)")
                                    
                                    if let dateTime = tiffDictionary[kCGImagePropertyTIFFDateTime as String] as? String {
                                        print("Found TIFF DateTime: \(dateTime)")
                                        let dateFormatter = DateFormatter()
                                        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                                        
                                        if let date = dateFormatter.date(from: dateTime) {
                                            print("Successfully parsed date: \(date)")
                                            selectedDate = date
                                        }
                                    }
                                }
                                
                                // Try GPS dictionary if others didn't work
                                if let gpsDictionary = imageProperties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
                                    print("GPS data found: \(gpsDictionary.keys)")
                                    
                                    if let dateStamp = gpsDictionary[kCGImagePropertyGPSDateStamp as String] as? String {
                                        print("Found GPS DateStamp: \(dateStamp)")
                                        
                                        // GPS date format is typically different
                                        let dateFormatter = DateFormatter()
                                        dateFormatter.dateFormat = "yyyy:MM:dd"
                                        
                                        if let date = dateFormatter.date(from: dateStamp) {
                                            // If we have time data, try to combine
                                            if let timeStamp = gpsDictionary[kCGImagePropertyGPSTimeStamp as String] as? String {
                                                print("Found GPS TimeStamp: \(timeStamp)")
                                                let timeFormatter = DateFormatter()
                                                timeFormatter.dateFormat = "HH:mm:ss"
                                                
                                                if let time = timeFormatter.date(from: timeStamp) {
                                                    let calendar = Calendar.current
                                                    let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
                                                    
                                                    var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
                                                    dateComponents.hour = timeComponents.hour
                                                    dateComponents.minute = timeComponents.minute
                                                    dateComponents.second = timeComponents.second
                                                    
                                                    if let combinedDate = calendar.date(from: dateComponents) {
                                                        print("Successfully parsed GPS date/time: \(combinedDate)")
                                                        selectedDate = combinedDate
                                                    }
                                                } else {
                                                    print("Successfully parsed GPS date: \(date)")
                                                    selectedDate = date
                                                }
                                            } else {
                                                print("Successfully parsed GPS date: \(date)")
                                                selectedDate = date
                                            }
                                        }
                                    }
                                }
                                
                                // Print final selected date
                                print("Final selected date: \(selectedDate)")
                            } else {
                                print("No image properties found")
                            }
                        } else {
                            print("Failed to create image source")
                        }
                    }
                    
                    // Final fallback: Try to check if the image has creation date as UIImage property
                    if selectedDate == originalDate {
                        // This is a last resort option - fall back to current date if no metadata was found
                        print("No metadata found, using current date")
                    }
                }
            }
            
            loadingImage = false
        }
    }
    
    private func savePhoto() {
        guard let selectedImage = selectedImage, let imageData = selectedImage.jpegData(compressionQuality: 0.7) else {
            return
        }
        
        guard !selectedCategories.isEmpty else {
            return
        }
        
        // Get measurements close to this date to associate with photo
        let measurements = photoManager.getMeasurementsAtTime(date: selectedDate, statsManager: historyManager)
        
        let photo = ProgressPhoto(
            date: selectedDate,
            categories: Array(selectedCategories),
            imageData: imageData,
            associatedMeasurements: measurements,
            notes: notes.isEmpty ? nil : notes
        )
        
        photoManager.addPhoto(photo: photo)
        dismiss()
    }
}

struct EditPhotoView: View {
    let photo: ProgressPhoto
    @ObservedObject var photoManager: ProgressPhotoManager
    @ObservedObject var historyManager: StatsHistoryManager
    var onSave: () -> Void
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedCategories: Set<PhotoCategory>
    @State private var selectedDate: Date
    @State private var notes: String
    @State private var loadingImage = false
    
    @Environment(\.dismiss) private var dismiss
    
    init(photo: ProgressPhoto, photoManager: ProgressPhotoManager, historyManager: StatsHistoryManager, onSave: @escaping () -> Void) {
        self.photo = photo
        self.photoManager = photoManager
        self.historyManager = historyManager
        self.onSave = onSave
        
        _selectedCategories = State(initialValue: Set(photo.categories))
        _selectedDate = State(initialValue: photo.date)
        _notes = State(initialValue: photo.notes ?? "")
        _selectedImage = State(initialValue: photo.image)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Image picker
                        VStack {
                            if let selectedImage {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 300)
                                    .cornerRadius(12)
                            } else if loadingImage {
                                ProgressView()
                                    .frame(height: 300)
                            } else {
                                ZStack {
                                    Rectangle()
                                        .fill(Color(red: 0.15, green: 0.15, blue: 0.15))
                                        .frame(height: 300)
                                        .cornerRadius(12)
                                    
                                    VStack(spacing: 12) {
                                        Image(systemName: "photo.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray)
                                        
                                        Text("Tap to add photo")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .onTapGesture {
                                    // Fallback if PhotosPicker doesn't work
                                }
                            }
                            
                            PhotosPicker(
                                selection: $selectedItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Text("Replace Photo")
                                    .foregroundColor(.blue)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 20)
                                    .background(Color(red: 0.15, green: 0.15, blue: 0.15))
                                    .cornerRadius(8)
                            }
                            .onChange(of: selectedItem) { newValue in
                                loadImage()
                            }
                        }
                        .padding(.horizontal)
                        
                        // Category selector
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Categories")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                if !selectedCategories.isEmpty {
                                    Text("\(selectedCategories.count) selected")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            MultiCategorySelector(
                                selectedCategories: $selectedCategories
                            )
                        }
                        .padding(.horizontal)
                        
                        // Date picker
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Date")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            DatePicker("", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 20)
                                .background(Color(red: 0.15, green: 0.15, blue: 0.15))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        
                        // Measurements on this date
                        MeasurementSummaryView(
                            date: selectedDate,
                            historyManager: historyManager
                        )
                        .padding()
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .cornerRadius(16)
                        .padding(.horizontal)
                        
                        // Notes
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Notes")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            TextEditor(text: $notes)
                                .frame(height: 120)
                                .padding(10)
                                .background(Color(red: 0.15, green: 0.15, blue: 0.15))
                                .cornerRadius(12)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 50)
                    }
                }
            }
            .navigationTitle("Edit Progress Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .foregroundColor(.blue)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        updatePhoto()
                    }) {
                        Text("Save")
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    .disabled(selectedImage == nil || selectedCategories.isEmpty)
                    .opacity((selectedImage == nil || selectedCategories.isEmpty) ? 0.5 : 1.0)
                }
            }
        }
    }
    
    private func loadImage() {
        loadingImage = true
        
        Task {
            if let data = try? await selectedItem?.loadTransferable(type: Data.self) {
                if let uiImage = UIImage(data: data) {
                    selectedImage = uiImage
                    
                    // Store original date to check if it's changed
                    let originalDate = selectedDate
                    
                    // Try to get creation date directly from PHAsset
                    if let assetIdentifier = selectedItem?.itemIdentifier,
                       let assetResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).firstObject {
                        print("Edit mode - Found PHAsset with creation date: \(String(describing: assetResult.creationDate))")
                        
                        if let creationDate = assetResult.creationDate {
                            selectedDate = creationDate
                            print("Edit mode - Set date from PHAsset: \(creationDate)")
                        }
                    }
                    
                    // If PHAsset didn't work, try metadata extraction
                    if selectedDate == originalDate { // Only proceed if date hasn't been updated by PHAsset
                        // Extract creation date from image metadata
                        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil) {
                            if let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] {
                                print("Edit mode - Image properties found: \(imageProperties.keys)")
                                
                                // Try EXIF dictionary first
                                if let exifDictionary = imageProperties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                                    print("Edit mode - EXIF data found: \(exifDictionary.keys)")
                                    
                                    // Try various EXIF date properties
                                    if let dateTimeOriginal = exifDictionary[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                                        print("Edit mode - Found EXIF DateTimeOriginal: \(dateTimeOriginal)")
                                        let dateFormatter = DateFormatter()
                                        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                                        
                                        if let date = dateFormatter.date(from: dateTimeOriginal) {
                                            print("Edit mode - Successfully parsed date: \(date)")
                                            selectedDate = date
                                        }
                                    } else if let dateTimeDigitized = exifDictionary[kCGImagePropertyExifDateTimeDigitized as String] as? String {
                                        print("Edit mode - Found EXIF DateTimeDigitized: \(dateTimeDigitized)")
                                        let dateFormatter = DateFormatter()
                                        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                                        
                                        if let date = dateFormatter.date(from: dateTimeDigitized) {
                                            print("Edit mode - Successfully parsed date: \(date)")
                                            selectedDate = date
                                        }
                                    }
                                }
                                
                                // Try TIFF dictionary if EXIF didn't work
                                if let tiffDictionary = imageProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                                    print("Edit mode - TIFF data found: \(tiffDictionary.keys)")
                                    
                                    if let dateTime = tiffDictionary[kCGImagePropertyTIFFDateTime as String] as? String {
                                        print("Edit mode - Found TIFF DateTime: \(dateTime)")
                                        let dateFormatter = DateFormatter()
                                        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                                        
                                        if let date = dateFormatter.date(from: dateTime) {
                                            print("Edit mode - Successfully parsed date: \(date)")
                                            selectedDate = date
                                        }
                                    }
                                }
                                
                                // Try GPS dictionary if others didn't work
                                if let gpsDictionary = imageProperties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
                                    print("Edit mode - GPS data found: \(gpsDictionary.keys)")
                                    
                                    if let dateStamp = gpsDictionary[kCGImagePropertyGPSDateStamp as String] as? String {
                                        print("Edit mode - Found GPS DateStamp: \(dateStamp)")
                                        
                                        // GPS date format is typically different
                                        let dateFormatter = DateFormatter()
                                        dateFormatter.dateFormat = "yyyy:MM:dd"
                                        
                                        if let date = dateFormatter.date(from: dateStamp) {
                                            // If we have time data, try to combine
                                            if let timeStamp = gpsDictionary[kCGImagePropertyGPSTimeStamp as String] as? String {
                                                print("Edit mode - Found GPS TimeStamp: \(timeStamp)")
                                                let timeFormatter = DateFormatter()
                                                timeFormatter.dateFormat = "HH:mm:ss"
                                                
                                                if let time = timeFormatter.date(from: timeStamp) {
                                                    let calendar = Calendar.current
                                                    let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
                                                    
                                                    var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
                                                    dateComponents.hour = timeComponents.hour
                                                    dateComponents.minute = timeComponents.minute
                                                    dateComponents.second = timeComponents.second
                                                    
                                                    if let combinedDate = calendar.date(from: dateComponents) {
                                                        print("Edit mode - Successfully parsed GPS date/time: \(combinedDate)")
                                                        selectedDate = combinedDate
                                                    }
                                                } else {
                                                    print("Edit mode - Successfully parsed GPS date: \(date)")
                                                    selectedDate = date
                                                }
                                            } else {
                                                print("Edit mode - Successfully parsed GPS date: \(date)")
                                                selectedDate = date
                                            }
                                        }
                                    }
                                }
                                
                                // Print final selected date
                                print("Edit mode - Final selected date: \(selectedDate)")
                            } else {
                                print("Edit mode - No image properties found")
                            }
                        } else {
                            print("Edit mode - Failed to create image source")
                        }
                    }
                    
                    // Final fallback: Try to check if the image has creation date as UIImage property
                    if selectedDate == originalDate {
                        // This is a last resort option - fall back to current date
                        print("Edit mode - No metadata found, using original date")
                    }
                }
            }
            
            loadingImage = false
        }
    }
    
    private func updatePhoto() {
        guard let selectedImage = selectedImage else { return }
        guard !selectedCategories.isEmpty else { return }
        
        var imageData = photo.imageData
        
        // Only update the image data if a new image was selected
        if selectedItem != nil {
            if let newImageData = selectedImage.jpegData(compressionQuality: 0.7) {
                imageData = newImageData
            }
        }
        
        // Get measurements close to this date to associate with photo
        let measurements = photoManager.getMeasurementsAtTime(date: selectedDate, statsManager: historyManager)
        
        let updatedPhoto = ProgressPhoto(
            id: photo.id,
            date: selectedDate,
            categories: Array(selectedCategories),
            imageData: imageData,
            associatedMeasurements: measurements,
            notes: notes.isEmpty ? nil : notes
        )
        
        photoManager.updatePhoto(photo: updatedPhoto)
        onSave()
        dismiss()
    }
}

struct MultiCategorySelector: View {
    @Binding var selectedCategories: Set<PhotoCategory>
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(PhotoCategory.allCases.filter { $0 != .all }) { category in
                    MultipleCategorySelectorButton(
                        category: category,
                        isSelected: selectedCategories.contains(category),
                        action: {
                            if selectedCategories.contains(category) {
                                selectedCategories.remove(category)
                            } else {
                                selectedCategories.insert(category)
                            }
                        }
                    )
                }
            }
        }
    }
}

struct MultipleCategorySelectorButton: View {
    let category: PhotoCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color(red: 0.2, green: 0.2, blue: 0.2))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: category.iconName)
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                    
                    if isSelected {
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 60, height: 60)
                    }
                }
                
                Text(category.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 70)
    }
}

struct CategorySelectorButton: View {
    let category: PhotoCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color(red: 0.2, green: 0.2, blue: 0.2))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: category.iconName)
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                
                Text(category.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 70)
    }
}

struct MeasurementSummaryView: View {
    let date: Date
    @ObservedObject var historyManager: StatsHistoryManager
    
    private var measurements: [StatType: Double] {
        var result: [StatType: Double] = [:]
        
        let relevantTypes: [StatType] = [.weight, .bodyFat, .bicep, .chest, .waist, .thigh, .shoulder, .glutes]
        
        for type in relevantTypes {
            if let entry = historyManager.getEntries(for: type)
                .filter({ $0.date <= date })
                .sorted(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
                .first {
                result[type] = entry.value
            }
        }
        
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Measurements at this time")
                .font(.headline)
                .foregroundColor(.white)
            
            if measurements.isEmpty {
                Text("No measurements were found near this date")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            } else {
                VStack(spacing: 10) {
                    ForEach(measurements.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { type in
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
                            
                            if type != measurements.keys.sorted(by: { $0.rawValue < $1.rawValue }).last {
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                            }
                        }
                    }
                }
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

#Preview {
    AddPhotoView(photoManager: ProgressPhotoManager.shared, historyManager: StatsHistoryManager.shared)
} 