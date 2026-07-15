import SwiftUI
import PhotosUI
import AVFoundation

enum ReceiptStorageError: LocalizedError {
    case conversion, directory, imageWrite, metadataWrite, metadataRead, imageLoad, delete, rename, invalidImageFilename
    var errorDescription: String? {
        switch self {
        case .conversion: return "Unable to prepare this receipt image. Please try another image."
        case .directory: return "Unable to prepare receipt storage. Please try again."
        case .imageWrite: return "Unable to save this receipt image. Please try again."
        case .metadataWrite: return "Unable to save receipt details. Please try again."
        case .metadataRead: return "Some saved receipts could not be loaded."
        case .imageLoad: return "Unable to open this receipt image."
        case .delete: return "Unable to delete this receipt. Please try again."
        case .rename: return "Unable to rename this receipt. Please try again."
        case .invalidImageFilename: return "Your saved receipt information needs recovery before files can be changed."
        }
    }
}

@MainActor final class ReceiptsViewModel: ObservableObject {
    @Published var records: [ReceiptRecord] = []
    @Published var errorMessage: String?
    private let repository: FileReceiptRepository = FileReceiptRepository()
    func load() { Task { do { records = try await repository.fetchReceipts() } catch { errorMessage = error.localizedDescription } } }
    func save(image: UIImage?, name: String) { guard let image, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; Task { do { records = try await saveReceiptImage(image, name: name.trimmingCharacters(in: .whitespacesAndNewlines)) } catch { errorMessage = error.localizedDescription } } }
    func image(for record: ReceiptRecord, thumbnail: Bool = false) async -> UIImage { (try? await (thumbnail ? repository.loadThumbnail(filename: record.thumbnailFilename ?? record.imageFilename ?? "") : repository.loadImage(filename: record.imageFilename ?? ""))) ?? UIImage() }
    func rename(_ record: ReceiptRecord, to name: String) { Task { do { _ = try await repository.rename(receiptID: record.id, newName: name); records = try await repository.fetchReceipts() } catch { errorMessage = error.localizedDescription } } }
    func delete(_ record: ReceiptRecord) { Task { do { try await repository.deleteReceipt(id: record.id); records = try await repository.fetchReceipts() } catch { errorMessage = error.localizedDescription } } }
    private func saveReceiptImage(_ image: UIImage, name: String) async throws -> [ReceiptRecord] {
        let id = UUID()
        let now = Date()
        let full = image.normalizedForReceipt().resizedForReceipt(maxDimension: 1800)
        let thumb = image.normalizedForReceipt().resizedForReceipt(maxDimension: 420)
        let record = ReceiptRecord(id: id, merchantName: name, receiptDate: nil, subtotal: nil, tax: nil, total: nil, detectedCharges: [], imageFilename: "\(id.uuidString).jpg", thumbnailFilename: "\(id.uuidString)-thumb.jpg", notes: "", createdAt: now, updatedAt: now)
        _ = try await repository.create(draft: record, fullImage: full, thumbnail: thumb)
        return try await repository.fetchReceipts()
    }
}

struct Receipts: View {
    @StateObject private var viewModel = ReceiptsViewModel()
    @State private var activeSheet: ReceiptSheet?
    @State private var capturedImage: UIImage?
    @State private var photoName = ""
    @State private var presentNameAfterDismiss = false

    var body: some View {
        AppScreen { ScrollView { VStack(spacing: AppSpacing.section) { ScreenTitle(text: "Receipts", subtitle: "Save receipt photos locally and reopen them later."); ThemedCard { NavigationLink(value: AppRoute.receiptScanner(.newReceipt)) { Label("Add Receipt", systemImage: "camera").appFont(.headline).frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(AppButtonStylePublic.primary); SecondaryButton(title: "Saved Receipts", systemImage: "photo.on.rectangle") { activeSheet = .saved } }; if viewModel.records.isEmpty { EmptyStateView(systemImage: "receipt", title: "No saved receipts", message: "Add a receipt photo to keep a local copy in this app.") } else { Text("\(viewModel.records.count) saved receipt\(viewModel.records.count == 1 ? "" : "s")").appFont(.body).foregroundStyle(AppTheme.secondaryText) } }.padding(AppSpacing.screen) } }
        .navigationTitle("Receipts").navigationBarTitleDisplayMode(.inline).onAppear { viewModel.load() }
        .sheet(item: $activeSheet, onDismiss: { if presentNameAfterDismiss { presentNameAfterDismiss = false; activeSheet = .name } }) { sheet in
            switch sheet {
            case .camera: PhotoCaptureView(onCancel: resetCapture) { image in capturedImage = image; presentNameAfterDismiss = true; activeSheet = nil }
            case .name: NamePhotoView(photoName: $photoName, image: capturedImage, onCancel: resetCapture, onSave: { viewModel.save(image: capturedImage, name: photoName); resetCapture() })
            case .saved: NavigationStack { SavedReceiptsView(viewModel: viewModel).toolbar { Button("Close") { activeSheet = nil } } }
            }
        }
        .alert("Receipts", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(viewModel.errorMessage ?? "") }
    }
    private func resetCapture() { capturedImage = nil; photoName = ""; presentNameAfterDismiss = false; activeSheet = nil }
}

private enum ReceiptSheet: String, Identifiable { case camera, name, saved; var id: String { rawValue } }
struct PhotoCaptureView: View { var onCancel: () -> Void; var onPhotoCapture: (UIImage) -> Void; var body: some View { CameraViewControllerRepresentable(onPhotoCapture: { onPhotoCapture($0.normalizedForReceipt()) }, onCancel: onCancel) } }

extension UIImage {
    func normalizedForReceipt() -> UIImage { if imageOrientation == .up { return self }; UIGraphicsBeginImageContextWithOptions(size, false, scale); draw(in: CGRect(origin: .zero, size: size)); let normalized = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return normalized ?? self }
    func resizedForReceipt(maxDimension: CGFloat) -> UIImage { let longest = max(size.width, size.height); guard longest > maxDimension else { return self }; let scale = maxDimension / longest; let newSize = CGSize(width: size.width * scale, height: size.height * scale); UIGraphicsBeginImageContextWithOptions(newSize, false, 1); draw(in: CGRect(origin: .zero, size: newSize)); let resized = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return resized ?? self }
}

struct SavedReceiptsView: View {
    @ObservedObject var viewModel: ReceiptsViewModel
    @State private var renameRecord: ReceiptRecord?
    @State private var deleteRecord: ReceiptRecord?
    @State private var renameText = ""
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: AppSpacing.section)]
    var body: some View {
        AppScreen { ScrollView { if viewModel.records.isEmpty { EmptyStateView(systemImage: "receipt", title: "No saved receipts", message: "Saved receipt photos will appear here.") } else { LazyVGrid(columns: columns, spacing: AppSpacing.section) { ForEach(viewModel.records) { receipt in NavigationLink(destination: FullImageView(viewModel: viewModel, record: receipt)) { ThemedCard { ReceiptImageView(viewModel: viewModel, record: receipt, thumbnail: true).frame(maxHeight: 140).clipShape(RoundedRectangle(cornerRadius: 12)); Text(receipt.displayName).appFont(.body).foregroundStyle(AppTheme.text).lineLimit(2); HStack { Button("Rename") { renameText = receipt.displayName; renameRecord = receipt }.accessibilityLabel("Rename receipt \(receipt.displayName)"); Button("Delete", role: .destructive) { deleteRecord = receipt }.accessibilityLabel("Delete receipt \(receipt.displayName)") } } }.accessibilityLabel("Open receipt named \(receipt.displayName)") } }.padding(AppSpacing.screen) } } }
        .navigationTitle("Saved Receipts").navigationBarTitleDisplayMode(.inline)
        .alert("Rename Receipt", isPresented: Binding(get: { renameRecord != nil }, set: { if !$0 { renameRecord = nil } })) { TextField("Receipt name", text: $renameText); Button("Save") { if let r = renameRecord { viewModel.rename(r, to: renameText) }; renameRecord = nil }; Button("Cancel", role: .cancel) { renameRecord = nil } }
        .alert("Delete Receipt?", isPresented: Binding(get: { deleteRecord != nil }, set: { if !$0 { deleteRecord = nil } })) { Button("Delete", role: .destructive) { if let r = deleteRecord { viewModel.delete(r) }; deleteRecord = nil }; Button("Cancel", role: .cancel) { deleteRecord = nil } } message: { Text("This deletes the receipt image and thumbnail from local storage.") }
    }
}

struct ReceiptImageView: View {
    @ObservedObject var viewModel: ReceiptsViewModel
    let record: ReceiptRecord
    let thumbnail: Bool
    @State private var image: UIImage?
    var body: some View { Group { if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityHidden(true) } else { ProgressView().task { image = await viewModel.image(for: record, thumbnail: thumbnail) } } } }
}

struct FullImageView: View { @ObservedObject var viewModel: ReceiptsViewModel; let record: ReceiptRecord; @State private var image: UIImage?; @State private var scale: CGFloat = 1; @State private var lastScale: CGFloat = 1; var body: some View { AppScreen { ScrollView([.horizontal, .vertical]) { if let image { Image(uiImage: image).resizable().scaledToFit().scaleEffect(scale).padding(AppSpacing.screen).gesture(MagnificationGesture().onChanged { scale = max(1, min(lastScale * $0, 5)) }.onEnded { _ in lastScale = scale }) } else { ProgressView().task { image = await viewModel.image(for: record) } } } }.navigationTitle(record.displayName).navigationBarTitleDisplayMode(.inline) } }
struct NamePhotoView: View { @Environment(\.dismiss) private var dismiss; @Binding var photoName: String; let image: UIImage?; var onCancel: () -> Void; var onSave: () -> Void; var body: some View { NavigationStack { AppScreen { VStack(spacing: AppSpacing.section) { ScreenTitle(text: "Name Receipt"); if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityLabel("Receipt preview") }; ThemedCard { Text("Receipt Name").appFont(.title2); TextField("Dinner receipt", text: $photoName).textFieldStyle(AppTextFieldStyle()) }; PrimaryButton(title: "Save", systemImage: "checkmark", isDisabled: photoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { onSave(); dismiss() }; SecondaryButton(title: "Cancel") { onCancel(); dismiss() }; Spacer() }.padding(AppSpacing.screen) }.navigationTitle("Add Receipt") } } }

struct CameraViewControllerRepresentable: UIViewControllerRepresentable { let onPhotoCapture: (UIImage) -> Void; let onCancel: () -> Void; func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary; picker.delegate = context.coordinator; return picker }; func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }; func makeCoordinator() -> Coordinator { Coordinator(onPhotoCapture: onPhotoCapture, onCancel: onCancel) }
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate { let onPhotoCapture: (UIImage) -> Void; let onCancel: () -> Void; init(onPhotoCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) { self.onPhotoCapture = onPhotoCapture; self.onCancel = onCancel }; func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { if let image = info[.originalImage] as? UIImage { onPhotoCapture(image) }; picker.dismiss(animated: true) }; func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) { self.onCancel() } } }
}
#Preview { NavigationStack { Receipts() } }
