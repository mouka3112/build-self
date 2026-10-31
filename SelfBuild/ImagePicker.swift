import SwiftUI
import UIKit

struct ImagePicker: UIViewControllerRepresentable {
    var source: UIImagePickerController.SourceType
    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(source) ? source : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ p: ImagePicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onPick(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

enum PhotoSource: Identifiable { case camera, library; var id: Int { self == .camera ? 0 : 1 } }

struct PhotoPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    var onPick: (UIImage) -> Void
    @State private var chosen: PhotoSource?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Source de la photo", isPresented: $isPresented, titleVisibility: .visible) {
                Button("Appareil photo") { chosen = .camera }
                Button("Galerie") { chosen = .library }
                Button("Annuler", role: .cancel) {}
            }
            .fullScreenCover(item: $chosen) { s in
                ImagePicker(source: s == .camera ? .camera : .photoLibrary, onPick: onPick).ignoresSafeArea()
            }
    }
}

extension View {
    func photoPicker(isPresented: Binding<Bool>, onPick: @escaping (UIImage) -> Void) -> some View {
        modifier(PhotoPickerModifier(isPresented: isPresented, onPick: onPick))
    }
}
