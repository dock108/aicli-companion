import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

/// Comprehensive attachment picker for photos, documents, camera, and files
@available(iOS 16.0, macOS 13.0, *)
struct AttachmentPicker: View {
    @Binding var isPresented: Bool
    let onAttachmentSelected: (AttachmentData) -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    @State private var showingImagePicker = false
    @State private var showingDocumentPicker = false
    @State private var showingCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .font(Typography.font(.body))
                .foregroundColor(Colors.textSecondary(for: colorScheme))
                
                Spacer()
                
                Text("Add Attachment")
                    .font(Typography.font(.heading3))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                
                Spacer()
                
                // Invisible button for layout balance
                Button("Cancel") {
                    isPresented = false
                }
                .opacity(0)
                .disabled(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Colors.bgCard(for: colorScheme))
            
            Divider()
            
            // Options Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 20) {
                // Photo Library
                AttachmentOptionView(
                    icon: "photo.on.rectangle",
                    title: "Photo Library",
                    description: "Choose from photos"
                ) {
                    showingImagePicker = true
                }
                
                // Camera
                #if os(iOS)
                AttachmentOptionView(
                    icon: "camera.fill",
                    title: "Camera",
                    description: "Take a photo"
                ) {
                    showingCamera = true
                }
                #endif
                
                // Documents
                AttachmentOptionView(
                    icon: "doc.text.fill",
                    title: "Documents",
                    description: "Browse files"
                ) {
                    showingDocumentPicker = true
                }
                
                // Code Files
                AttachmentOptionView(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "Code Files",
                    description: "Source code"
                ) {
                    showDocumentPickerForCodeFiles()
                }
            }
            .padding(20)
            
            Spacer()
        }
        .background(Colors.bgBase(for: colorScheme))
        .photosPicker(
            isPresented: $showingImagePicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            handlePhotoSelection(newItem)
        }
        .sheet(isPresented: $showingDocumentPicker) {
            #if os(iOS)
            DocumentPicker(
                allowedTypes: [.item], // All document types
                onDocumentPicked: handleDocumentSelection
            )
            #else
            Text("Document picker not available on this platform")
                .padding()
            #endif
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(onImageCaptured: handleCameraCapture)
        }
        #endif
    }
    
    private func showDocumentPickerForCodeFiles() {
        let codeTypes: [UTType] = [
            .sourceCode,
            .swiftSource,
            .cPlusPlusSource,
            .cSource,
            .javaScript,
            .json,
            .xml,
            .yaml,
            .plainText
        ]
        
        // For now, use the same document picker
        showingDocumentPicker = true
    }
    
    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let attachment = AttachmentData(
                        id: UUID(),
                        type: .image,
                        name: "Image",
                        data: data,
                        mimeType: "image/jpeg",
                        size: data.count
                    )
                    
                    await MainActor.run {
                        onAttachmentSelected(attachment)
                        isPresented = false
                    }
                }
            } catch {
                print("❌ Failed to load photo: \(error)")
            }
        }
        
        selectedPhotoItem = nil
    }
    
    private func handleDocumentSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                do {
                    let data = try Data(contentsOf: url)
                    let attachment = AttachmentData(
                        id: UUID(),
                        type: .document,
                        name: url.lastPathComponent,
                        data: data,
                        mimeType: mimeType(for: url),
                        size: data.count
                    )
                    
                    await MainActor.run {
                        onAttachmentSelected(attachment)
                        isPresented = false
                    }
                } catch {
                    print("❌ Failed to read document: \(error)")
                }
            }
            
        case .failure(let error):
            print("❌ Document selection failed: \(error)")
        }
    }
    
    #if os(iOS)
    private func handleCameraCapture(_ result: Result<UIImage, Error>) {
        switch result {
        case .success(let image):
            if let data = image.jpegData(compressionQuality: 0.8) {
                let attachment = AttachmentData(
                    id: UUID(),
                    type: .image,
                    name: "Camera Photo",
                    data: data,
                    mimeType: "image/jpeg",
                    size: data.count
                )
                onAttachmentSelected(attachment)
                isPresented = false
            }
            
        case .failure(let error):
            print("❌ Camera capture failed: \(error)")
        }
    }
    #endif
    
    private func mimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        
        switch pathExtension {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "pdf":
            return "application/pdf"
        case "txt":
            return "text/plain"
        case "md":
            return "text/markdown"
        case "json":
            return "application/json"
        case "xml":
            return "application/xml"
        case "html":
            return "text/html"
        case "css":
            return "text/css"
        case "js":
            return "text/javascript"
        case "py":
            return "text/x-python"
        case "swift":
            return "text/x-swift"
        case "java":
            return "text/x-java-source"
        case "cpp", "c++":
            return "text/x-c++src"
        case "c":
            return "text/x-csrc"
        case "h":
            return "text/x-chdr"
        default:
            return "application/octet-stream"
        }
    }
}

/// Individual attachment option view
@available(iOS 16.0, macOS 13.0, *)
struct AttachmentOptionView: View {
    let icon: String
    let title: String
    let description: String
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Colors.accentPrimary(for: colorScheme).first?.opacity(0.1) ?? Color.blue.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Colors.accentPrimaryEnd)
                }
                
                // Text
                VStack(spacing: 4) {
                    Text(title)
                        .font(Typography.font(.body))
                        .fontWeight(.medium)
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    Text(description)
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Colors.bgCard(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Colors.strokeLight, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Supporting Types

@available(iOS 16.0, macOS 13.0, *)
struct AttachmentData: Identifiable, Codable {
    let id: UUID
    let type: AttachmentType
    let name: String
    let data: Data
    let mimeType: String
    let size: Int
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    var isImage: Bool {
        type == .image
    }
    
    var isDocument: Bool {
        type == .document
    }
}

@available(iOS 16.0, macOS 13.0, *)
enum AttachmentType: String, Codable {
    case image
    case document
    case code
}

// MARK: - Supporting Views

#if os(iOS)
@available(iOS 16.0, *)
struct CameraPicker: UIViewControllerRepresentable {
    let onImageCaptured: (Result<UIImage, Error>) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (Result<UIImage, Error>) -> Void
        
        init(onImageCaptured: @escaping (Result<UIImage, Error>) -> Void) {
            self.onImageCaptured = onImageCaptured
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(.success(image))
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
#endif

#if os(iOS)
@available(iOS 16.0, *)
struct DocumentPicker: UIViewControllerRepresentable {
    let allowedTypes: [UTType]
    let onDocumentPicked: (Result<URL, Error>) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentPicked: onDocumentPicked)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentPicked: (Result<URL, Error>) -> Void
        
        init(onDocumentPicked: @escaping (Result<URL, Error>) -> Void) {
            self.onDocumentPicked = onDocumentPicked
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            if url.startAccessingSecurityScopedResource() {
                onDocumentPicked(.success(url))
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // User cancelled, no action needed
        }
    }
}
#endif

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
#Preview("Attachment Picker") {
    AttachmentPicker(
        isPresented: .constant(true),
        onAttachmentSelected: { attachment in
            print("Selected attachment: \(attachment.name)")
        }
    )
    .preferredColorScheme(.dark)
}
