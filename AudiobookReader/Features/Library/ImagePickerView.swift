import SwiftUI

struct ImagePickerView: View {
    let audiobook: AudiobookModel
    let onImageSelected: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchResults: [ImageSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingPhotoPicker = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Text(NSLocalizedString("Choose Cover Image", comment: "Choose cover image title"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(String(format: NSLocalizedString("for %@", comment: "Cover image for audiobook title"), audiobook.title ?? AudiobookModel.unknownTitle))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                
                // Action Buttons
                HStack(spacing: 16) {
                    Button(NSLocalizedString("Search Google Images", comment: "Search Google Images button")) {
                        searchGoogleImages()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isLoading)
                    
                    Button(NSLocalizedString("Choose from Photos", comment: "Choose from Photos button")) {
                        showingPhotoPicker = true
                    }
                    .buttonStyle(.glass)
                }
                .padding(.horizontal)
                
                if isLoading {
                    VStack {
                        ProgressView()
                        Text(NSLocalizedString("Searching for images...", comment: "Searching for images loading text"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty {
                    VStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("No images found", comment: "No images found message"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("Try searching for images or choose from your photos", comment: "No images found instructions"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
                            ForEach(searchResults, id: \.id) { result in
                                AsyncImage(url: URL(string: result.thumbnailUrl)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 100)
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
            .navigationTitle(NSLocalizedString("Cover Image", comment: "Cover image view title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoPickerView { image in
                onImageSelected(image)
                dismiss()
            }
        }
    }
    
    private func searchGoogleImages() {
        guard let title = audiobook.title, !title.isEmpty else {
            errorMessage = NSLocalizedString("No title available for search", comment: "No title error message")
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
                        errorMessage = NSLocalizedString("No images found for this audiobook", comment: "No images found for audiobook message")
                    }
                case .failure(let error):
                    errorMessage = String(format: NSLocalizedString("Search failed: %@", comment: "Search failed error message"), error.localizedDescription)
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
                        errorMessage = NSLocalizedString("Invalid image URL", comment: "Invalid image URL error message")
                    }
                    return
                }
                
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run { onImageSelected(image); dismiss() }
                }
            } catch {
                await MainActor.run {
                    errorMessage = String(format: NSLocalizedString("Failed to download image: %@", comment: "Image download error message"), error.localizedDescription)
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
    ImagePickerView(audiobook: PreviewContent.audiobook()) { _ in }
}
