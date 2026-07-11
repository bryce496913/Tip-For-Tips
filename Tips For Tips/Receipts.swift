//
//  Receipts.swift
//  Tips For Tips
//
//  Created by Aditi Abrol on 7/4/24.
//

// !TO DO: Add delete + zoom

import SwiftUI

struct Receipts: View {
    @State private var showPhotoCapture = false
    @State private var showSavedReceipts = false
    @State private var savedReceipts: [Receipt] = []
    @State private var capturedImage: UIImage?
    @State private var isRetake = false
    @State private var photoName: String = ""
    @State private var showingNamePhotoView = false // Flag to control showing NamePhotoView
    
    var body: some View {
        ZStack {
            Color.appBlack.edgesIgnoringSafeArea(.all)
            
            VStack {
                Image("Receipts")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 250, height: 250)
                
                HStack(spacing: 0) {
                    Text("Receipts").foregroundColor(Color.appBlue)
                }
                .font(.largeTitle)
                
                Spacer()
                
                Button(action: {
                    self.showPhotoCapture = true
                }) {
                    Label("Take Photo", systemImage: "camera")
                        .foregroundColor(Color.appBlue)
                        .padding()
                        .background(Color.appDarkBlue)
                        .cornerRadius(15)
                        .font(.title)
                }
                .padding()
                .sheet(isPresented: $showPhotoCapture) {
                    PhotoCaptureView(onPhotoCapture: { image in
                        capturedImage = image
                        // Show NamePhotoView when photo is captured
                        showingNamePhotoView = true
                    })
                }
                
                Button(action: {
                    self.showSavedReceipts = true
                }) {
                    Label("Load Receipts", systemImage: "photo.on.rectangle")
                        .foregroundColor(Color.appBlue)
                        .padding()
                        .background(Color.appDarkBlue)
                        .cornerRadius(15)
                        .font(.title)
                }
                .padding()
                .sheet(isPresented: $showSavedReceipts) {
                    NavigationView {
                        SavedReceiptsView(savedReceipts: $savedReceipts)
                            .navigationBarItems(trailing: Button("Close") {
                                showSavedReceipts = false
                            })
                            .navigationBarTitle("Saved Receipts", displayMode: .inline)
                    }
                }
                
                Spacer()
            }
        }
        .sheet(isPresented: $showingNamePhotoView) {
            NamePhotoView(photoName: $photoName) {
                // Dismiss the sheet and save the photo
                let newReceipt = Receipt(imageData: capturedImage!.pngData()!, name: photoName)
                savedReceipts.append(newReceipt)
                saveReceiptsToStorage()
                self.showingNamePhotoView = false
                self.capturedImage = nil
                self.photoName = ""
            }
        }
        .onAppear {
            loadReceiptsFromStorage()
        }
    }
    
    private func saveReceiptsToStorage() {
        do {
            let data = try JSONEncoder().encode(savedReceipts)
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = documentsURL.appendingPathComponent("receipts.json")
            try data.write(to: fileURL)
        } catch {
            print("Error saving receipts: \(error)")
        }
    }
    
    private func loadReceiptsFromStorage() {
        do {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = documentsURL.appendingPathComponent("receipts.json")
            let data = try Data(contentsOf: fileURL)
            savedReceipts = try JSONDecoder().decode([Receipt].self, from: data)
        } catch {
            print("Error loading receipts: \(error)")
        }
    }
}

struct PhotoCaptureView: View {
    @Environment(\.presentationMode) var presentationMode
    var onPhotoCapture: (UIImage) -> Void

    @State private var orientation: UIImage.Orientation = .up

    var body: some View {
        CameraViewControllerRepresentable(onPhotoCapture: { image in
            // Determine the orientation of the captured image
            if image.size.width > image.size.height {
                // Landscape orientation
                orientation = .right
            } else {
                // Portrait orientation
                orientation = .up
            }

            // Rotate the image if necessary
            let rotatedImage = image.rotate(radians: orientation.radians)

            // Pass the rotated image to the completion handler
            onPhotoCapture(rotatedImage)
        })
    }
}

extension UIImage.Orientation {
    var radians: CGFloat {
        switch self {
        case .up, .upMirrored:
            return 0
        case .right, .rightMirrored:
            return .pi / 2
        case .down, .downMirrored:
            return .pi
        case .left, .leftMirrored:
            return -.pi / 2
        @unknown default:
            return 0
        }
    }
}

extension UIImage {
    func rotate(radians: CGFloat) -> UIImage {
        var newSize = CGRect(origin: CGPoint.zero, size: self.size).applying(CGAffineTransform(rotationAngle: radians)).size
        // Trim off the extremely small float value to prevent core graphics from rounding it up
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)

        UIGraphicsBeginImageContextWithOptions(newSize, true, self.scale)
        let context = UIGraphicsGetCurrentContext()!

        // Move origin to middle
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        // Rotate around middle
        context.rotate(by: radians)
        // Draw the rotated image
        self.draw(in: CGRect(x: -self.size.width / 2, y: -self.size.height / 2, width: self.size.width, height: self.size.height))

        let newImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        return newImage
    }
}

struct SavedReceiptsView: View {
    @Binding var savedReceipts: [Receipt]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                    ForEach(savedReceipts.indices, id: \.self) { index in
                        let receipt = savedReceipts[index]
                        NavigationLink(destination: FullImageView(image: receipt.image)) {
                            VStack {
                                Image(uiImage: receipt.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 100)
                                    .cornerRadius(10)
                                Text(receipt.name)
                                    .foregroundColor(.white)
                                    .padding(.top, 5)
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func saveReceiptsToStorage() {
        do {
            let data = try JSONEncoder().encode(savedReceipts)
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = documentsURL.appendingPathComponent("receipts.json")
            try data.write(to: fileURL)
        } catch {
            print("Error saving receipts: \(error)")
        }
    }
}

struct FullImageView: View {
    let image: UIImage

    @State private var scale: CGFloat = 1.2
    @State private var lastScale: CGFloat = 1.2

    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { value in
                                lastScale = scale
                            }
                    )
                    .scaleEffect(scale)
                    .padding()
                    .background(Color.black)
                    .edgesIgnoringSafeArea(.all)
                Spacer()
            }
        }
    }
}

struct NamePhotoView: View {
    @Binding var photoName: String
    var onSave: () -> Void
    
    var body: some View {
        VStack {
            Text("Enter photo name")
                .foregroundColor(Color.appWhite)
                .font(.headline)
            
            TextField("", text: $photoName)
                .padding()
                .background(Color.white)
                .foregroundColor(Color.appBlack)
                .cornerRadius(10)
                .padding()
            
            HStack {
                Button("Cancel") {
                    photoName = ""
                    onSave()
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
                
                Button("Save") {
                    onSave()
                }
                .padding()
                .background(Color.appGreen)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
        }
        .padding()
        .background(Color.appBlack)
        .cornerRadius(20)
        .padding()
    }
}

struct Receipts_Previews: PreviewProvider {
    static var previews: some View {
        Receipts()
    }
}

struct CameraViewControllerRepresentable: UIViewControllerRepresentable {
    let onPhotoCapture: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .camera
        imagePicker.delegate = context.coordinator
        return imagePicker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Not needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPhotoCapture: onPhotoCapture)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onPhotoCapture: (UIImage) -> Void
        
        init(onPhotoCapture: @escaping (UIImage) -> Void) {
            self.onPhotoCapture = onPhotoCapture
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                onPhotoCapture(image)
            }
            picker.dismiss(animated: true, completion: nil)
        }
    }
}

struct Receipt: Codable, Identifiable {
    var id = UUID()
    var imageData: Data
    var name: String
    
    var image: UIImage {
        UIImage(data: imageData)!
    }
}
