import SwiftUI

struct PhotoHistoryView: View {
    let category: PhotoCategory
    @ObservedObject var photoManager: ProgressPhotoManager
    @ObservedObject var historyManager: StatsHistoryManager
    @State private var selectedPhoto: ProgressPhoto?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack {
                Text("Photo History")
                    .font(.title3)
                    .foregroundColor(.white)
                
                Spacer()
                
                HStack(spacing: 5) {
                    Image(systemName: "photo.stack.fill")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Text("\(photoManager.getPhotos(for: category).count) photos")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)
            
            let groupedPhotos = photoManager.getPhotosByDate(category: category)
            
            if groupedPhotos.isEmpty {
                EmptyStateView(category: category)
            } else {
                // Group by date
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(groupedPhotos.keys.sorted(by: >), id: \.self) { date in
                            if let photos = groupedPhotos[date] {
                                HistoryDateGroupHeader(date: date)
                                    .padding(.horizontal)
                                
                                // Photos grid
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    ForEach(photos) { photo in
                                        HistoryPhotoThumbnail(photo: photo, historyManager: historyManager) {
                                            selectedPhoto = photo
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(
                photo: photo,
                photoManager: photoManager,
                historyManager: historyManager
            )
        }
    }
}

struct HistoryDateGroupHeader: View {
    let date: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatDate(date))
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Divider()
                .background(Color.gray.opacity(0.5))
        }
        .padding(.top, 16)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
}

struct HistoryPhotoThumbnail: View {
    let photo: ProgressPhoto
    @ObservedObject var historyManager: StatsHistoryManager
    let action: () -> Void
    
    private var weight: Double? {
        historyManager.getEntries(for: .weight)
            .filter { $0.date <= photo.date }
            .sorted { $0.date > $1.date }
            .first?.value
    }
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                if let uiImage = photo.image {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .clipped()
                        .cornerRadius(12)
                }
                
                // Metadata overlay
                VStack(alignment: .leading, spacing: 4) {
                    // Category badges
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(photo.categories, id: \.self) { category in
                                HStack(spacing: 2) {
                                    Image(systemName: category.iconName)
                                        .font(.system(size: 10))
                                        .foregroundColor(.white)
                                    
                                    Text(category.name)
                                        .font(.system(size: 10))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(4)
                            }
                        }
                    }
                    
                    if let weight = weight {
                        Text("\(String(format: "%.1f", weight)) kg")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                    }
                }
                .padding(8)
            }
            .frame(height: 150)
        }
    }
}

struct PhotoDetailView: View {
    let photo: ProgressPhoto
    @ObservedObject var photoManager: ProgressPhotoManager
    @ObservedObject var historyManager: StatsHistoryManager
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Photo
                        if let image = photo.image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 500)
                                .cornerRadius(12)
                                .padding(.horizontal)
                        }
                        
                        // Date and categories
                        VStack(alignment: .leading, spacing: 8) {
                            Text(formatDate(photo.date))
                                .font(.title3)
                                .foregroundColor(.white)
                            
                            // Category badges
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(photo.categories, id: \.self) { category in
                                        HStack(spacing: 4) {
                                            Image(systemName: category.iconName)
                                                .foregroundColor(.blue)
                                            
                                            Text(category.name)
                                                .font(.subheadline)
                                                .foregroundColor(.gray)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(red: 0.15, green: 0.15, blue: 0.15))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Measurements
                        MeasurementDetailView(
                            photo: photo,
                            historyManager: historyManager
                        )
                        .padding()
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showEditSheet = true }) {
                            Label("Edit Photo", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive, action: { showDeleteAlert = true }) {
                            Label("Delete Photo", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditPhotoView(
                    photo: photo,
                    photoManager: photoManager,
                    historyManager: historyManager,
                    onSave: { dismiss() }
                )
            }
            .alert("Delete Photo", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    photoManager.deletePhoto(id: photo.id)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete this photo? This action cannot be undone.")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }
} 