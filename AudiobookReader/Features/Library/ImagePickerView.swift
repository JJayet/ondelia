import SwiftUI

struct ImagePickerView: View {
    let audiobook: Audiobook
    let onImageSelected: (UIImage) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @State private var searchResults: [ImageSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingPhotoPicker = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Text("Choose Cover Image")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("for \(audiobook.title ?? "Unknown Title")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                
                // Action Buttons
                HStack(spacing: 16) {
                    Button("Search Google Images") {
                        searchGoogleImages()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                    
                    Button("Choose from Photos") {
                        showingPhotoPicker = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                
                if isLoading {
                    VStack {
                        ProgressView()
                        Text("Searching for images...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty {
                    VStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No images found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Try searching for images or choose from your photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Image Grid
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            ForEach(searchResults, id: \.id) { result in
                                AsyncImage(url: URL(string: result.thumbnailUrl)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 100, height: 100)
                                        .clipped()
                                        .cornerRadius(8)
                                        .onTapGesture {
                                            downloadAndSelectImage(result)
                                        }
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 100, height: 100)
                                        .cornerRadius(8)
                                        .overlay(
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        )
                                }
                            }
                        }
                        .padding()
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Cover Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoPickerView { image in
                onImageSelected(image)
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
    
    private func searchGoogleImages() {
        guard let title = audiobook.title, !title.isEmpty else {
            errorMessage = "No title available for search"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Create search query
        let author = audiobook.author ?? ""
        let _ = "\(title) \(author) audiobook cover".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // For now, create mock results since we can't directly access Google Images API
        // In a real implementation, you'd use a service like Unsplash API, Pixabay API, or similar
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            createMockSearchResults()
            isLoading = false
        }
    }
    
    private func createMockSearchResults() {
        // Mock search results with placeholder images
        // In reality, you'd integrate with an image search API
        searchResults = [
            ImageSearchResult(id: "1", thumbnailUrl: "https://via.placeholder.com/150x200/FF6B6B/FFFFFF?text=Book+1", fullUrl: "https://via.placeholder.com/300x400/FF6B6B/FFFFFF?text=Book+1"),
            ImageSearchResult(id: "2", thumbnailUrl: "https://via.placeholder.com/150x200/4ECDC4/FFFFFF?text=Book+2", fullUrl: "https://via.placeholder.com/300x400/4ECDC4/FFFFFF?text=Book+2"),
            ImageSearchResult(id: "3", thumbnailUrl: "https://via.placeholder.com/150x200/45B7D1/FFFFFF?text=Book+3", fullUrl: "https://via.placeholder.com/300x400/45B7D1/FFFFFF?text=Book+3"),
            ImageSearchResult(id: "4", thumbnailUrl: "https://via.placeholder.com/150x200/96CEB4/FFFFFF?text=Book+4", fullUrl: "https://via.placeholder.com/300x400/96CEB4/FFFFFF?text=Book+4"),
            ImageSearchResult(id: "5", thumbnailUrl: "https://via.placeholder.com/150x200/FFEAA7/333333?text=Book+5", fullUrl: "https://via.placeholder.com/300x400/FFEAA7/333333?text=Book+5"),
            ImageSearchResult(id: "6", thumbnailUrl: "https://via.placeholder.com/150x200/DDA0DD/FFFFFF?text=Book+6", fullUrl: "https://via.placeholder.com/300x400/DDA0DD/FFFFFF?text=Book+6")
        ]
        
        if searchResults.isEmpty {
            errorMessage = "No images found for this audiobook"
        }
    }
    
    private func downloadAndSelectImage(_ result: ImageSearchResult) {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: URL(string: result.fullUrl)!)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        onImageSelected(image)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to download image: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct ImageSearchResult {
    let id: String
    let thumbnailUrl: String
    let fullUrl: String
}

struct PhotoPickerView: UIViewControllerRepresentable {
    let onImageSelected: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotoPickerView
        
        init(_ parent: PhotoPickerView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageSelected(image)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    ImagePickerView(audiobook: Audiobook()) { _ in }
}