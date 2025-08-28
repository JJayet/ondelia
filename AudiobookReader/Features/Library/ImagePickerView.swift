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
        
        Task {
            // Create search query
            let author = audiobook.author ?? ""
            let searchQuery = "\(title) \(author) audiobook cover"
            
            let result = await GoogleImageSearchService.shared.searchImages(query: searchQuery)
            
            await MainActor.run {
                switch result {
                case .success(let results):
                    searchResults = results
                    if searchResults.isEmpty {
                        errorMessage = "No images found for this audiobook"
                    }
                case .failure(let error):
                    errorMessage = "Search failed: \(error.localizedDescription)"
                    searchResults = []
                }
                isLoading = false
            }
        }
    }
    
    
    private func downloadAndSelectImage(_ result: ImageSearchResult) {
        Task {
            do {
                guard let url = URL(string: result.fullUrl) else {
                    await MainActor.run {
                        errorMessage = "Invalid image URL"
                    }
                    return
                }
                
                let (data, _) = try await URLSession.shared.data(from: url)
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


struct PhotoPickerView: UIViewControllerRepresentable {
    let onImageSelected: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true // Allow basic editing like cropping
        picker.delegate = context.coordinator
        
        // Ensure camera is not available as a source
        picker.mediaTypes = ["public.image"]
        
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
            // Prefer edited image if available (for cropping), otherwise use original
            let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            
            if let selectedImage = image {
                parent.onImageSelected(selectedImage)
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