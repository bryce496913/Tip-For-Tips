//
//  NotePad.swift
//  Tips For Tips
//
//  Created by Aditi Abrol on 7/4/24.
//

import SwiftUI

struct NotePad: View {
    // Wrapper struct to make String identifiable
    struct IdentifiedNote: Identifiable {
        var id: String { name }
        let name: String
    }
    
    @State private var showNewNote = false
    @State private var showSavedNotes = false
    @State private var savedNotes: [IdentifiedNote] = []
    @State private var selectedNote: String?
    
    var body: some View {
        ZStack {
            Color.appBlack.edgesIgnoringSafeArea(.all)
            
            VStack {
                Image("NotePad")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 250, height: 250)
                
                HStack(spacing: 0) {
                    Text("Note").foregroundColor(Color.appBlue)
                    Text(" Pad ").foregroundColor(Color.appGold)
                }
                .font(.largeTitle)
                
                Spacer()
                
                Button(action: {
                    self.showNewNote = true
                }) {
                    Label("New Note", systemImage: "square.and.pencil")
                        .foregroundColor(Color.appBlue)
                        .padding()
                        .background(Color.appDarkBlue)
                        .cornerRadius(15)
                        .font(.title)
                }
                .padding()
                .sheet(isPresented: $showNewNote, onDismiss: loadNotes) {
                    NewNoteView(text: "", onSave: { newText in
                        saveNoteText(newText)
                    })
                }
                
                NavigationLink(destination: SavedNotesView(savedNotes: Binding(
                    get: { savedNotes.map { $0.name } },
                    set: { newValue in
                        savedNotes = newValue.map { IdentifiedNote(name: $0) }
                    }
                )) { selectedNote in
                    self.selectedNote = selectedNote
                    showSavedNotes = false // Dismiss the saved notes sheet
                }, isActive: $showSavedNotes) {
                    EmptyView()
                }
                .hidden()
                
                Button(action: {
                    self.showSavedNotes = true
                }) {
                    Label("Load Note", systemImage: "folder")
                        .foregroundColor(Color.appBlue)
                        .padding()
                        .background(Color.appDarkBlue)
                        .cornerRadius(15)
                        .font(.title)
                }
                .padding()
                
                Spacer()
            }
        }
        .onAppear(perform: loadNotes)
        .sheet(item: $selectedNote) { noteName in
            if let content = loadNoteContent(noteName) {
                NewNoteView(text: content, onSave: { newText in
                    saveNoteText(newText)
                })
            }
        }
    }
    
    private func loadNotes() {
        do {
            let fileManager = FileManager.default
            let documentsURL = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let files = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            
            savedNotes = files.filter { $0.pathExtension == "txt" }.map { IdentifiedNote(name: $0.lastPathComponent) }
        } catch {
            print("Failed to load notes: \(error)")
        }
    }
    
    private func loadNoteContent(_ noteName: String) -> String? {
        do {
            let documentsURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let fileURL = documentsURL.appendingPathComponent(noteName)
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            print("Failed to load note content: \(error)")
            return nil
        }
    }
    
    private func saveNoteText(_ text: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd MM yyyy HH:mm"
        let fileName = "\(dateFormatter.string(from: Date())).txt"
        
        do {
            let fileURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent(fileName)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save note: \(error)")
        }
    }
}

struct NewNoteView: View {
    @Environment(\.presentationMode) var presentationMode
    @State var text: String
    let onSave: (String) -> Void
    @State private var showUnsavedAlert = false
    
    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $text)
                    .foregroundColor(Color.appBlack)
                    .background(Color.appBlack)
                    .padding()
                
                Button("Save") {
                    onSave(text)
                    presentationMode.wrappedValue.dismiss()
                }
                .padding()
                .foregroundColor(Color.appWhite)
                .background(Color.appDarkBlue)
                .cornerRadius(10)
                
                Spacer()
            }
            .navigationBarTitle("New Note", displayMode: .inline)
            .navigationBarItems(trailing: Button("Cancel") {
                if text.isEmpty {
                    presentationMode.wrappedValue.dismiss()
                } else {
                    showUnsavedAlert = true
                }
            })
            .alert(isPresented: $showUnsavedAlert) {
                Alert(
                    title: Text("Unsaved Changes"),
                    message: Text("Would you like to save your changes?"),
                    primaryButton: .destructive(Text("Dismiss")) {
                        presentationMode.wrappedValue.dismiss()
                    },
                    secondaryButton: .default(Text("Save")) {
                        onSave(text)
                        presentationMode.wrappedValue.dismiss()
                    })
            }
        }
    }
}

struct SavedNotesView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var savedNotes: [String]
    let onNoteSelected: (String) -> Void
    
    var body: some View {
        NavigationView {
            List {
                ForEach(savedNotes, id: \.self) { note in
                    Button(action: {
                        onNoteSelected(note)
                        presentationMode.wrappedValue.dismiss() // Dismiss the saved notes sheet
                    }) {
                        Text(note)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            delete(note: note)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationBarTitle("Saved Notes", displayMode: .inline)
        }
    }
    
    private func delete(note: String) {
        do {
            let fileManager = FileManager.default
            let documentsURL = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let fileURL = documentsURL.appendingPathComponent(note)
            try fileManager.removeItem(at: fileURL)
            
            if let index = savedNotes.firstIndex(of: note) {
                savedNotes.remove(at: index)
            }
        } catch {
            print("Failed to delete note: \(error)")
        }
    }
}

struct NotePad_Previews: PreviewProvider {
    static var previews: some View {
        NotePad()
    }
}

extension String: Identifiable {
    public var id: String { self }
}
