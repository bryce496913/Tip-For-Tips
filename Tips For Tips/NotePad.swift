import SwiftUI

struct SavedNote: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    let createdAt: Date
    var updatedAt: Date
}


enum NoteStorageError: LocalizedError {
    case load, save, delete, migration
    var errorDescription: String? {
        switch self {
        case .load: return "Some saved notes could not be loaded."
        case .save: return "Unable to save this note. Please try again."
        case .delete: return "Unable to delete this note. Please try again."
        case .migration: return "Some older notes could not be migrated."
        }
    }
}

actor NoteStore {
    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var notesURL: URL { rootURL.appendingPathComponent("Notes", isDirectory: true).appendingPathComponent("notes.json") }
    private var legacyURL: URL { rootURL.appendingPathComponent("Notes", isDirectory: true).appendingPathComponent("Legacy", isDirectory: true) }

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadNotes() throws -> [SavedNote] {
        try migrateLegacyNotesIfNeeded()
        guard fileManager.fileExists(atPath: notesURL.path) else { return [] }
        do {
            let envelope = try decoder.decode(StoredDataEnvelope<SavedNote>.self, from: Data(contentsOf: notesURL))
            return sort(envelope.records)
        } catch { throw NoteStorageError.load }
    }

    func upsert(_ note: SavedNote) throws -> [SavedNote] {
        var notes = try loadNotes()
        if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index] = note } else { notes.append(note) }
        try save(notes)
        return sort(notes)
    }

    func delete(_ note: SavedNote) throws -> [SavedNote] {
        var notes = try loadNotes()
        notes.removeAll { $0.id == note.id }
        try save(notes)
        return sort(notes)
    }

    private func save(_ notes: [SavedNote]) throws {
        do {
            try fileManager.createDirectory(at: notesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(StoredDataEnvelope(version: 1, records: sort(notes)))
            try data.write(to: notesURL, options: [.atomic])
        } catch { throw NoteStorageError.save }
    }

    private func sort(_ notes: [SavedNote]) -> [SavedNote] { notes.sorted { $0.updatedAt == $1.updatedAt ? $0.createdAt > $1.createdAt : $0.updatedAt > $1.updatedAt } }

    /// Migrates only legacy files named "dd MM yyyy HH:mm.txt". Successfully migrated files are moved
    /// into Documents/Notes/Legacy, so the migration is idempotent and unrelated text files are ignored.
    private func migrateLegacyNotesIfNeeded() throws {
        let formatter = DateFormatter(); formatter.dateFormat = "dd MM yyyy HH:mm"; formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let files = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey]) else { return }
        let legacyFiles = files.filter { $0.pathExtension == "txt" && formatter.date(from: $0.deletingPathExtension().lastPathComponent) != nil }
        guard !legacyFiles.isEmpty else { return }
        do {
            var notes: [SavedNote] = []
            if fileManager.fileExists(atPath: notesURL.path), let existing = try? decoder.decode(StoredDataEnvelope<SavedNote>.self, from: Data(contentsOf: notesURL)).records { notes = existing }
            for file in legacyFiles {
                let text = try String(contentsOf: file, encoding: .utf8)
                let values = try file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let parsed = formatter.date(from: file.deletingPathExtension().lastPathComponent)
                let created = parsed ?? values.creationDate ?? values.contentModificationDate ?? Date()
                notes.append(SavedNote(id: UUID(), text: text, createdAt: created, updatedAt: values.contentModificationDate ?? created))
            }
            try save(notes)
            try fileManager.createDirectory(at: legacyURL, withIntermediateDirectories: true)
            for file in legacyFiles {
                let destination = legacyURL.appendingPathComponent(file.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: file) } else { try fileManager.moveItem(at: file, to: destination) }
            }
        } catch { throw NoteStorageError.migration }
    }
}

@MainActor
final class NotePadViewModel: ObservableObject {
    @Published var notes: [SavedNote] = []
    @Published var errorMessage: String?
    private let store: NoteStore
    init(store: NoteStore = NoteStore()) { self.store = store }
    func load() { Task { do { notes = try await store.loadNotes() } catch { errorMessage = error.localizedDescription } } }
    func save(note: SavedNote?, text: String) { Task { do { let now = Date(); let record = SavedNote(id: note?.id ?? UUID(), text: text, createdAt: note?.createdAt ?? now, updatedAt: now); notes = try await store.upsert(record) } catch { errorMessage = error.localizedDescription } } }
    func delete(_ note: SavedNote) { Task { do { notes = try await store.delete(note) } catch { errorMessage = error.localizedDescription } } }
}

struct NotePad: View {
    @StateObject private var viewModel = NotePadViewModel()
    @State private var editorMode: NoteEditorMode?

    var body: some View {
        AppScreen {
            VStack(spacing: 24) {
                Image("NotePad").resizable().aspectRatio(contentMode: .fit).frame(width: 190, height: 190).accessibilityHidden(true)
                ScreenTitle(text: "Note Pad")
                ThemedCard {
                    PrimaryButton(title: "New Note", systemImage: "square.and.pencil") { editorMode = .create }
                    NavigationLink { SavedNotesView(viewModel: viewModel, onNoteSelected: { editorMode = .edit($0) }) } label: { Label("Saved Notes", systemImage: "folder").appFont(.headline).frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.plain).padding(.horizontal, AppSpacing.section).frame(maxWidth: .infinity, minHeight: 44).background(AppTheme.surface).overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.accent, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Spacer()
            }.padding(20)
        }
        .navigationTitle("Note Pad")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.load() }
        .sheet(item: $editorMode) { mode in NewNoteView(note: mode.note, onSave: { viewModel.save(note: mode.note, text: $0) }) }
        .alert("Notes", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(viewModel.errorMessage ?? "") }
    }
}

enum NoteEditorMode: Identifiable { case create, edit(SavedNote); var id: String { switch self { case .create: return "create"; case .edit(let note): return note.id.uuidString } }; var note: SavedNote? { if case .edit(let note) = self { return note }; return nil } }

struct NewNoteView: View {
    @Environment(\.dismiss) private var dismiss
    let note: SavedNote?
    let onSave: (String) -> Void
    @State private var text: String
    @State private var showUnsavedAlert = false
    private let originalText: String

    init(note: SavedNote?, onSave: @escaping (String) -> Void) { self.note = note; self.onSave = onSave; self.originalText = note?.text ?? ""; _text = State(initialValue: note?.text ?? "") }
    var hasChanges: Bool { text != originalText }

    var body: some View {
        NavigationStack {
            AppScreen { VStack(spacing: 16) { TextEditor(text: $text).appFont(.body).foregroundStyle(AppTheme.text).scrollContentBackground(.hidden).padding(8).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityLabel("Note text"); PrimaryButton(title: "Save", isDisabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { onSave(text); dismiss() } }.padding(20) }
            .navigationTitle(note == nil ? "New Note" : "Edit Note")
            .toolbar { Button("Cancel") { hasChanges ? (showUnsavedAlert = true) : dismiss() } }
            .alert("Unsaved Changes", isPresented: $showUnsavedAlert) { Button("Save") { onSave(text); dismiss() }; Button("Discard Changes", role: .destructive) { dismiss() }; Button("Keep Editing", role: .cancel) {} } message: { Text("Would you like to save your changes before closing?") }
        }
    }
}

struct SavedNotesView: View {
    @ObservedObject var viewModel: NotePadViewModel
    let onNoteSelected: (SavedNote) -> Void
    @State private var notePendingDelete: SavedNote?
    var body: some View {
        AppScreen { List { if viewModel.notes.isEmpty { EmptyStateView(systemImage: "note.text", title: "No saved notes", message: "Create a note and it will appear here.").listRowBackground(AppTheme.background) }
            ForEach(viewModel.notes) { note in Button { onNoteSelected(note) } label: { VStack(alignment: .leading) { Text(note.text.split(separator: "\n").first.map(String.init) ?? "Untitled Note").appFont(.body); Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened)).appFont(.body).foregroundStyle(AppTheme.tertiaryText) } }.foregroundStyle(AppTheme.text).listRowBackground(AppTheme.surface).accessibilityLabel("Open note").swipeActions { Button(role: .destructive) { notePendingDelete = note } label: { Label("Delete note", systemImage: "trash") } } }
        } }
        .navigationTitle("Saved Notes").navigationBarTitleDisplayMode(.inline)
        .alert("Delete Note?", isPresented: Binding(get: { notePendingDelete != nil }, set: { if !$0 { notePendingDelete = nil } })) { Button("Delete", role: .destructive) { if let notePendingDelete { viewModel.delete(notePendingDelete) }; notePendingDelete = nil }; Button("Cancel", role: .cancel) { notePendingDelete = nil } } message: { Text("This note will be removed from your saved notes.") }
    }
}

#Preview { NotePad() }
