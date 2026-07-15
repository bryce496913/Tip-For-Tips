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

actor ReceiptStore {
    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var receiptsDir: URL { rootURL.appendingPathComponent("V2/Receipts", isDirectory: true) }
    private var imagesDir: URL { receiptsDir.appendingPathComponent("Images", isDirectory: true) }
    private var thumbsDir: URL { receiptsDir.appendingPathComponent("Thumbnails", isDirectory: true) }
    private var metadataURL: URL { receiptsDir.appendingPathComponent("receipts.json") }
    private var legacyMetadataURL: URL { rootURL.appendingPathComponent("receipts.json") }

    init(rootURL: URL? = nil, fileManager: FileManager = .default) { self.rootURL = rootURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]; self.fileManager = fileManager; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; decoder.dateDecodingStrategy = .iso8601 }

    func load() throws -> [ReceiptRecord] { try migrateLegacyIfNeeded(); guard fileManager.fileExists(atPath: metadataURL.path) else { return [] }; do { return try decoder.decode(StoredDataEnvelope<ReceiptRecord>.self, from: Data(contentsOf: metadataURL)).records.sorted { $0.updatedAt > $1.updatedAt } } catch { throw ReceiptStorageError.metadataRead } }
    func image(for record: ReceiptRecord, thumbnail: Bool = false) throws -> UIImage { guard let imageFilename = record.imageFilename else { throw ReceiptStorageError.imageLoad }; let name = thumbnail ? (record.thumbnailFilename ?? imageFilename) : imageFilename; let url = (thumbnail ? thumbsDir : imagesDir).appendingPathComponent(name); guard let image = UIImage(contentsOfFile: url.path) else { throw ReceiptStorageError.imageLoad }; return image }

    func save(image: UIImage, name: String) throws -> [ReceiptRecord] {
        try ensureDirectories()
        let id = UUID(); let imageName = "\(id.uuidString).jpg"; let thumbName = "\(id.uuidString)-thumb.jpg"
        guard let fullData = image.normalizedForReceipt().resizedForReceipt(maxDimension: 1800).jpegData(compressionQuality: 0.82), let thumbData = image.normalizedForReceipt().resizedForReceipt(maxDimension: 420).jpegData(compressionQuality: 0.78) else { throw ReceiptStorageError.conversion }
        do { try fullData.write(to: imagesDir.appendingPathComponent(imageName), options: [.atomic]); try thumbData.write(to: thumbsDir.appendingPathComponent(thumbName), options: [.atomic]) } catch { throw ReceiptStorageError.imageWrite }
        var records = try load()
        let now = Date(); records.append(ReceiptRecord(id: id, merchantName: name, receiptDate: nil, subtotal: nil, tax: nil, total: nil, detectedCharges: [], imageFilename: imageName, thumbnailFilename: thumbName, notes: "", createdAt: now, updatedAt: now)); try saveMetadata(records); return records.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(record: ReceiptRecord, fullImage: UIImage, thumbnail: UIImage) throws -> [ReceiptRecord] {
        try ensureDirectories()
        let imageName = record.imageFilename ?? "\(record.id.uuidString).jpg"
        let thumbName = record.thumbnailFilename ?? "\(record.id.uuidString)-thumb.jpg"
        guard let fullData = fullImage.jpegData(compressionQuality: 0.82), let thumbData = thumbnail.jpegData(compressionQuality: 0.78) else { throw ReceiptStorageError.conversion }
        do { try fullData.write(to: imagesDir.appendingPathComponent(imageName), options: [.atomic]); try thumbData.write(to: thumbsDir.appendingPathComponent(thumbName), options: [.atomic]) } catch { throw ReceiptStorageError.imageWrite }
        do { var records = try load(); records.removeAll { $0.id == record.id }; records.insert(record, at: 0); try saveMetadata(records); return records.sorted { $0.updatedAt > $1.updatedAt } }
        catch { try? fileManager.removeItem(at: imagesDir.appendingPathComponent(imageName)); try? fileManager.removeItem(at: thumbsDir.appendingPathComponent(thumbName)); throw ReceiptStorageError.metadataWrite }
    }

    func rename(_ record: ReceiptRecord, to newName: String) throws -> [ReceiptRecord] { var records = try load(); guard let index = records.firstIndex(where: { $0.id == record.id }) else { return records }; records[index].merchantName = newName; records[index].updatedAt = Date(); do { try saveMetadata(records); return records.sorted { $0.updatedAt > $1.updatedAt } } catch { throw ReceiptStorageError.rename } }
    func delete(_ record: ReceiptRecord) throws -> [ReceiptRecord] { var records = try load(); guard records.contains(where: { $0.id == record.id }) else { return records }; do { let staged = try stageFilesForDeletion(record); records.removeAll { $0.id == record.id }; do { try saveMetadata(records); for url in staged { if fileManager.fileExists(atPath: url.path) { try? fileManager.removeItem(at: url) } }; return records } catch { try restore(stagedFiles: staged); throw error } } catch { throw ReceiptStorageError.delete } }

    private var temporaryDir: URL { receiptsDir.appendingPathComponent("Temporary", isDirectory: true) }
    private func ensureDirectories() throws { do { try fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true); try fileManager.createDirectory(at: thumbsDir, withIntermediateDirectories: true); try fileManager.createDirectory(at: temporaryDir, withIntermediateDirectories: true) } catch { throw ReceiptStorageError.directory } }
    private func saveMetadata(_ records: [ReceiptRecord]) throws { do { try ensureDirectories(); let data = try encoder.encode(StoredDataEnvelope(version: 1, records: records)); try data.write(to: metadataURL, options: [.atomic]) } catch { throw ReceiptStorageError.metadataWrite } }

    private func stageFilesForDeletion(_ record: ReceiptRecord) throws -> [URL] {
        var staged: [URL] = []
        for (filename, dir) in [(record.imageFilename, imagesDir), (record.thumbnailFilename, thumbsDir)] {
            guard let filename else { continue }
            let source = try validatedURL(filename: filename, in: dir)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = temporaryDir.appendingPathComponent("delete-\(UUID().uuidString)-\(source.lastPathComponent)")
            try fileManager.moveItem(at: source, to: destination)
            staged.append(destination)
        }
        return staged
    }
    private func restore(stagedFiles: [URL]) throws { for staged in stagedFiles { let name = staged.lastPathComponent.components(separatedBy: "-").dropFirst(2).joined(separator: "-"); let targetDir = name.contains("-thumb") ? thumbsDir : imagesDir; try? fileManager.moveItem(at: staged, to: targetDir.appendingPathComponent(name)) } }
    private func validatedURL(filename: String, in directory: URL) throws -> URL {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == (trimmed as NSString).lastPathComponent, !trimmed.contains(".."), !trimmed.hasPrefix("/") else { throw ReceiptStorageError.invalidImageFilename }
        let dir = directory.standardizedFileURL.resolvingSymlinksInPath()
        let url = dir.appendingPathComponent(trimmed).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(dir.path + "/"), url.deletingLastPathComponent().path == dir.path else { throw ReceiptStorageError.invalidImageFilename }
        return url
    }

    /// Migrates old root receipts.json records with embedded image Data into JPEG files, then writes metadata.
    /// The old JSON is moved to receipts.json.legacy after the new metadata is saved, making migration idempotent.
    private func migrateLegacyIfNeeded() throws {
        guard !fileManager.fileExists(atPath: metadataURL.path), fileManager.fileExists(atPath: legacyMetadataURL.path) else { return }
        struct LegacyReceipt: Codable { var id: UUID?; var imageData: Data; var name: String }
        do {
            let legacy = try decoder.decode([LegacyReceipt].self, from: Data(contentsOf: legacyMetadataURL))
            try ensureDirectories()
            var records: [ReceiptRecord] = []
            for item in legacy { guard let image = UIImage(data: item.imageData), let full = image.normalizedForReceipt().resizedForReceipt(maxDimension: 1800).jpegData(compressionQuality: 0.82), let thumb = image.normalizedForReceipt().resizedForReceipt(maxDimension: 420).jpegData(compressionQuality: 0.78) else { throw ReceiptStorageError.conversion }; let id = item.id ?? UUID(); let imageName = "\(id.uuidString).jpg"; let thumbName = "\(id.uuidString)-thumb.jpg"; try full.write(to: imagesDir.appendingPathComponent(imageName), options: [.atomic]); try thumb.write(to: thumbsDir.appendingPathComponent(thumbName), options: [.atomic]); let now = Date(); records.append(ReceiptRecord(id: id, merchantName: item.name, receiptDate: nil, subtotal: nil, tax: nil, total: nil, detectedCharges: [], imageFilename: imageName, thumbnailFilename: thumbName, notes: "", createdAt: now, updatedAt: now)) }
            try saveMetadata(records)
            try fileManager.moveItem(at: legacyMetadataURL, to: rootURL.appendingPathComponent("receipts.json.legacy"))
        } catch { throw ReceiptStorageError.metadataRead }
    }
}

@MainActor final class ReceiptsViewModel: ObservableObject {
    @Published var records: [ReceiptRecord] = []
    @Published var errorMessage: String?
    private let store = ReceiptStore()
    func load() { Task { do { records = try await store.load() } catch { errorMessage = error.localizedDescription } } }
    func save(image: UIImage?, name: String) { guard let image, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; Task { do { records = try await store.save(image: image, name: name.trimmingCharacters(in: .whitespacesAndNewlines)) } catch { errorMessage = error.localizedDescription } } }
    func image(for record: ReceiptRecord, thumbnail: Bool = false) async -> UIImage { (try? await store.image(for: record, thumbnail: thumbnail)) ?? UIImage() }
    func rename(_ record: ReceiptRecord, to name: String) { Task { do { records = try await store.rename(record, to: name) } catch { errorMessage = error.localizedDescription } } }
    func delete(_ record: ReceiptRecord) { Task { do { records = try await store.delete(record) } catch { errorMessage = error.localizedDescription } } }
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
