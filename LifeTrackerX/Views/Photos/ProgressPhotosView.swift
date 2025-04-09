import SwiftUI

struct ProgressPhotosView: View {
    @StateObject private var photoManager = ProgressPhotoManager.shared
    @StateObject private var historyManager = StatsHistoryManager.shared
    @State private var showingAddPhotoSheet = false
    @State private var selectedCategory: PhotoCategory?
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Categories scroll view
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach(PhotoCategory.allCases) { category in
                                CategoryButton(
                                    category: category,
                                    isSelected: selectedCategory == category,
                                    action: {
                                        withAnimation {
                                            if selectedCategory == category {
                                                selectedCategory = nil
                                            } else {
                                                selectedCategory = category
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 10)
                    
                    // Before/After comparison cards
                    VStack(spacing: 15) {
                        if let category = selectedCategory {
                            let comparisonData = photoManager.getComparisonPhotos(for: category)
                            
                            if let latest = comparisonData.latest {
                                if let previous = comparisonData.previous {
                                    // We have both photos for comparison
                                    ComparisonCard(
                                        oldPhoto: previous,
                                        newPhoto: latest,
                                        historyManager: historyManager
                                    )
                                } else {
                                    // We only have one photo
                                    SinglePhotoCard(
                                        photo: latest, 
                                        historyManager: historyManager
                                    )
                                }
                            } else {
                                EmptyStateView(category: category)
                            }
                        } else {
                            // Summary grid of latest photos per category
                            LazyVGrid(columns: columns, spacing: 16) {
                                let latestByCategory = photoManager.getLatestPhotosByCategory()
                                
                                ForEach(PhotoCategory.allCases) { category in
                                    if let photo = latestByCategory[category] {
                                        CategoryPhotoCard(
                                            category: category,
                                            photo: photo,
                                            action: {
                                                selectedCategory = category
                                            }
                                        )
                                    } else {
                                        CategoryEmptyCard(
                                            category: category,
                                            action: {
                                                selectedCategory = category
                                                showingAddPhotoSheet = true
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Photo history if category is selected
                    if let category = selectedCategory {
                        PhotoHistoryView(
                            category: category,
                            photoManager: photoManager,
                            historyManager: historyManager
                        )
                    }
                }
            }
        }
        .navigationTitle("Progress Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAddPhotoSheet = true
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showingAddPhotoSheet) {
            AddPhotoView(
                photoManager: photoManager,
                historyManager: historyManager,
                category: selectedCategory
            )
        }
    }
}

struct CategoryButton: View {
    let category: PhotoCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color(red: 0.2, green: 0.2, blue: 0.2))
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: category.iconName)
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
                
                Text(category.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 80)
    }
}

struct EmptyStateView: View {
    let category: PhotoCategory
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No \(category.name) Photos")
                .font(.title3)
                .foregroundColor(.white)
            
            Text("Take your first photo to start tracking your progress.")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(red: 0.15, green: 0.15, blue: 0.15))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

struct CategoryPhotoCard: View {
    let category: PhotoCategory
    let photo: ProgressPhoto
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                if let uiImage = photo.image {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 180)
                        .clipped()
                }
                
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: category.iconName)
                            .foregroundColor(.white)
                        
                        Text(category.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Text(formatDate(photo.date))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0.3)]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            }
            .cornerRadius(16)
            .frame(height: 180)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

struct CategoryEmptyCard: View {
    let category: PhotoCategory
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 15) {
                Image(systemName: category.iconName)
                    .font(.system(size: 30))
                    .foregroundColor(.gray)
                
                Text(category.name)
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                Text("Add Photo")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(Color(red: 0.15, green: 0.15, blue: 0.15))
            .cornerRadius(16)
        }
    }
}

#Preview {
    NavigationStack {
        ProgressPhotosView()
    }
} 