import SwiftUI

struct Receipts: View {
    @State private var activeSheet: ReceiptSheet?
    @State private var savedReceipts: [Receipt] = []
    @State private var capturedImage: UIImage?
    @State private var photoName = ""

    var body: some View {
        AppScreen {
            ScrollView {
                VStack(spacing: AppSpacing.section) {
                    ScreenTitle(text: "Receipts", subtitle: "Save receipt photos locally and reopen them later.")
                    ThemedCard {
                        PrimaryButton(title: "Add Receipt", systemImage: "camera") { activeSheet = .camera }
                        SecondaryButton(title: "Saved Receipts", systemImage: "photo.on.rectangle") { activeSheet = .saved }
                    }
                    if savedReceipts.isEmpty {
                        EmptyStateView(systemImage: "receipt", title: "No saved receipts", message: "Add a receipt photo to keep a local copy in this app.")
                    } else {
                        Text("\(savedReceipts.count) saved receipt\(savedReceipts.count == 1 ? "" : "s")").appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.8))
                    }
                }
                .padding(AppSpacing.screen)
            }
        }
        .navigationTitle("Receipts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadReceiptsFromStorage)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .camera:
                PhotoCaptureView { image in capturedImage = image; activeSheet = .name }
            case .name:
                NamePhotoView(photoName: $photoName, image: capturedImage, onCancel: { resetCapture() }, onSave: saveCapturedReceipt)
            case .saved:
                NavigationStack { SavedReceiptsView(savedReceipts: $savedReceipts).toolbar { Button("Close") { activeSheet = nil } } }
            }
        }
    }

    private func saveCapturedReceipt() {
        guard let imageData = capturedImage?.pngData(), !photoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { resetCapture(); return }
        savedReceipts.append(Receipt(imageData: imageData, name: photoName.trimmingCharacters(in: .whitespacesAndNewlines)))
        saveReceiptsToStorage(); resetCapture()
    }

    private func resetCapture() { capturedImage = nil; photoName = ""; activeSheet = nil }

    private func saveReceiptsToStorage() {
        do {
            let data = try JSONEncoder().encode(savedReceipts)
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            try data.write(to: documentsURL.appendingPathComponent("receipts.json"))
        } catch { }
    }

    private func loadReceiptsFromStorage() {
        do {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let data = try Data(contentsOf: documentsURL.appendingPathComponent("receipts.json"))
            savedReceipts = try JSONDecoder().decode([Receipt].self, from: data)
        } catch { savedReceipts = [] }
    }
}

private enum ReceiptSheet: String, Identifiable { case camera, name, saved; var id: String { rawValue } }

struct PhotoCaptureView: View {
    var onPhotoCapture: (UIImage) -> Void
    var body: some View { CameraViewControllerRepresentable(onPhotoCapture: { image in onPhotoCapture(image.normalizedForReceipt()) }) }
}

extension UIImage {
    func normalizedForReceipt() -> UIImage {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized ?? self
    }
}

struct SavedReceiptsView: View {
    @Binding var savedReceipts: [Receipt]
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: AppSpacing.section)]

    var body: some View {
        AppScreen {
            ScrollView {
                if savedReceipts.isEmpty {
                    EmptyStateView(systemImage: "receipt", title: "No saved receipts", message: "Saved receipt photos will appear here.")
                } else {
                    LazyVGrid(columns: columns, spacing: AppSpacing.section) {
                        ForEach(savedReceipts) { receipt in
                            NavigationLink(destination: FullImageView(image: receipt.image, title: receipt.name)) {
                                ThemedCard {
                                    Image(uiImage: receipt.image).resizable().scaledToFit().frame(maxHeight: 140).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                                    Text(receipt.name).appFont(.paragraph).foregroundStyle(AppTheme.text).lineLimit(2)
                                }
                            }
                            .accessibilityLabel("Open receipt named \(receipt.name)")
                        }
                    }
                    .padding(AppSpacing.screen)
                }
            }
        }
        .navigationTitle("Saved Receipts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FullImageView: View {
    let image: UIImage
    let title: String
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        AppScreen {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .padding(AppSpacing.screen)
                    .gesture(MagnificationGesture().onChanged { scale = max(1, min(lastScale * $0, 5)) }.onEnded { _ in lastScale = scale })
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NamePhotoView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var photoName: String
    let image: UIImage?
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        NavigationStack {
            AppScreen {
                VStack(spacing: AppSpacing.section) {
                    ScreenTitle(text: "Name Receipt")
                    if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityLabel("Receipt preview") }
                    ThemedCard {
                        Text("Receipt Name").appFont(.h2)
                        TextField("Dinner receipt", text: $photoName).textFieldStyle(AppTextFieldStyle())
                    }
                    PrimaryButton(title: "Save", systemImage: "checkmark", isDisabled: photoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { onSave(); dismiss() }
                    SecondaryButton(title: "Cancel") { onCancel(); dismiss() }
                    Spacer()
                }
                .padding(AppSpacing.screen)
            }
            .navigationTitle("Add Receipt")
        }
    }
}

struct CameraViewControllerRepresentable: UIViewControllerRepresentable {
    let onPhotoCapture: (UIImage) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary; picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(onPhotoCapture: onPhotoCapture) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onPhotoCapture: (UIImage) -> Void
        init(onPhotoCapture: @escaping (UIImage) -> Void) { self.onPhotoCapture = onPhotoCapture }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { if let image = info[.originalImage] as? UIImage { onPhotoCapture(image) }; picker.dismiss(animated: true) }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    }
}

struct Receipt: Codable, Identifiable {
    var id = UUID()
    var imageData: Data
    var name: String
    var image: UIImage { UIImage(data: imageData) ?? UIImage() }
}

#Preview { NavigationStack { Receipts() } }
