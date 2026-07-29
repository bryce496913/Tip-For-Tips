import SwiftUI

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
    func image(for record: ReceiptRecord, thumbnail: Bool = false) async -> UIImage { (try? await (thumbnail ? repository.loadThumbnail(filename: record.thumbnailFilename ?? record.imageFilename ?? "") : repository.loadImage(filename: record.imageFilename ?? ""))) ?? UIImage() }
    func rename(_ record: ReceiptRecord, to name: String) { Task { do { _ = try await repository.rename(receiptID: record.id, newName: name); records = try await repository.fetchReceipts() } catch { errorMessage = error.localizedDescription } } }
    func delete(_ record: ReceiptRecord) { Task { do { try await repository.deleteReceipt(id: record.id); records = try await repository.fetchReceipts() } catch { errorMessage = error.localizedDescription } } }
}

struct Receipts: View {
    @StateObject private var viewModel = ReceiptsViewModel()
    @State private var isShowingSavedReceipts = false

    var body: some View {
        AppScreen { ScrollView { VStack(spacing: AppSpacing.section) { ScreenTitle(text: "Receipts", subtitle: "Scan, import, enter, and manage receipts stored locally on this device."); ThemedCard { Text("Add Receipt").appFont(.title2); Text("Take a photo, choose one from your library, or enter the receipt manually.").appFont(.body).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true); NavigationLink(value: AppRoute.receiptScanner(.newReceipt)) { Label("Add Receipt", systemImage: "plus.circle").appFont(.headline).frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(AppButtonStylePublic.primary); SecondaryButton(title: "Saved Receipts", systemImage: "tray.full") { isShowingSavedReceipts = true } }; if viewModel.records.isEmpty { EmptyStateView(systemImage: "receipt", title: "No saved receipts", message: "Scan, import, or manually enter a receipt to get started.") } else { Text("\(viewModel.records.count) saved receipt\(viewModel.records.count == 1 ? "" : "s")").appFont(.body).foregroundStyle(AppTheme.secondaryText) } }.padding(AppSpacing.screen) } }
        .navigationTitle("Receipts").navigationBarTitleDisplayMode(.inline).onAppear { viewModel.load() }
        .sheet(isPresented: $isShowingSavedReceipts) {
            NavigationStack { SavedReceiptsView(viewModel: viewModel).toolbar { Button("Close") { isShowingSavedReceipts = false } } }
        }
        .alert("Receipts", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(viewModel.errorMessage ?? "") }
    }
}

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
        AppScreen { ScrollView { if viewModel.records.isEmpty { EmptyStateView(systemImage: "receipt", title: "No saved receipts", message: "Scan, import, or manually enter a receipt to get started.") } else { LazyVGrid(columns: columns, spacing: AppSpacing.section) { ForEach(viewModel.records) { receipt in NavigationLink(destination: FullImageView(viewModel: viewModel, record: receipt)) { ThemedCard { ReceiptImageView(viewModel: viewModel, record: receipt, thumbnail: true).frame(maxHeight: 140).clipShape(RoundedRectangle(cornerRadius: 12)); Text(receipt.displayName).appFont(.body).foregroundStyle(AppTheme.text).lineLimit(2); HStack { Button("Rename") { renameText = receipt.displayName; renameRecord = receipt }.accessibilityLabel("Rename receipt \(receipt.displayName)"); Button("Delete", role: .destructive) { deleteRecord = receipt }.accessibilityLabel("Delete receipt \(receipt.displayName)") } } }.accessibilityLabel("Open receipt named \(receipt.displayName)") } }.padding(AppSpacing.screen) } } }
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
#Preview { NavigationStack { Receipts() } }
