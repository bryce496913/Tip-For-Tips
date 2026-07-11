import SwiftUI

struct NotePad: View {
    @State private var showNewNote = false
    @State private var savedNotes: [NoteFile] = []
    @State private var selectedNote: NoteFile?

    var body: some View {
        AppScreen {
            VStack(spacing: 24) {
                Image("NotePad").resizable().aspectRatio(contentMode: .fit).frame(width: 190, height: 190).accessibilityHidden(true)
                ScreenTitle(text: "Note Pad")
                ThemedCard {
                    PrimaryButton(title: "New Note", systemImage: "square.and.pencil") { showNewNote = true }
                    NavigationLink { SavedNotesView(savedNotes: $savedNotes, onNoteSelected: { selectedNote = $0 }) } label: {
                        Label("Saved Notes", systemImage: "folder").appFont(.h3).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppSpacing.section)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.accent, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Spacer()
            }.padding(20)
        }
        .navigationTitle("Note Pad")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadNotes)
        .sheet(isPresented: $showNewNote, onDismiss: loadNotes) { NewNoteView(text: "", onSave: saveNoteText) }
        .sheet(item: $selectedNote, onDismiss: loadNotes) { note in NewNoteView(text: loadNoteContent(note.name) ?? "", onSave: saveNoteText) }
    }

    private func loadNotes() {
        do {
            let documentsURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            savedNotes = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "txt" }
                .map { NoteFile(name: $0.lastPathComponent) }
                .sorted { $0.name > $1.name }
        } catch { savedNotes = [] }
    }

    private func loadNoteContent(_ noteName: String) -> String? {
        guard let documentsURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return nil }
        return try? String(contentsOf: documentsURL.appendingPathComponent(noteName), encoding: .utf8)
    }

    private func saveNoteText(_ text: String) {
        let dateFormatter = DateFormatter(); dateFormatter.dateFormat = "dd MM yyyy HH:mm"
        guard let fileURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("\(dateFormatter.string(from: Date())).txt") else { return }
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

struct NoteFile: Identifiable, Hashable { let id: String; let name: String; init(name: String) { self.id = name; self.name = name } }

struct NewNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @State var text: String
    let onSave: (String) -> Void
    @State private var showUnsavedAlert = false

    var body: some View {
        NavigationStack {
            AppScreen {
                VStack(spacing: 16) {
                    TextEditor(text: $text)
                        .appFont(.paragraph)
                        .foregroundStyle(AppTheme.text)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Note text")
                    PrimaryButton(title: "Save", isDisabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { onSave(text); dismiss() }
                }.padding(20)
            }
            .navigationTitle("Note")
            .toolbar { Button("Cancel") { text.isEmpty ? dismiss() : (showUnsavedAlert = true) } }
            .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
                Button("Dismiss", role: .destructive) { dismiss() }
                Button("Save") { onSave(text); dismiss() }
            } message: { Text("Would you like to save your changes?") }
        }
    }
}

struct SavedNotesView: View {
    @Binding var savedNotes: [NoteFile]
    let onNoteSelected: (NoteFile) -> Void

    var body: some View {
        AppScreen {
            List {
                if savedNotes.isEmpty {
                    EmptyStateView(systemImage: "note.text", title: "No saved notes", message: "Create a note and it will appear here.").listRowBackground(AppTheme.background)
                }
                ForEach(savedNotes) { note in
                    Button(note.name) { onNoteSelected(note) }
                        .appFont(.paragraph)
                        .foregroundStyle(AppTheme.text)
                        .listRowBackground(AppTheme.surface)
                        .swipeActions { Button(role: .destructive) { delete(note: note) } label: { Label("Delete", systemImage: "trash") } }
                }
            }
        }
        .navigationTitle("Saved Notes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func delete(note: NoteFile) {
        guard let documentsURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        try? FileManager.default.removeItem(at: documentsURL.appendingPathComponent(note.name))
        savedNotes.removeAll { $0.id == note.id }
    }
}

#Preview { NotePad() }
