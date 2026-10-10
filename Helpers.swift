import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
import UIKit

// MARK: - UIImage

extension UIImage {
    /// Devuelve la imagen con orientación .up (píxeles reales).
    func normalized() -> UIImage {
        if imageOrientation == .up { return self }
        let f = UIGraphicsImageRendererFormat()
        f.scale = scale
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Reduce para que el lado más largo sea `maxSide` píxeles (0 = sin cambio).
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard maxSide > 0, longest > maxSide else { return self }
        let r = maxSide / longest
        let newSize = CGSize(width: (size.width * r).rounded(), height: (size.height * r).rounded())
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: f).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Pinta la imagen sobre fondo blanco (para exportar a JPG).
    func flattenedOnWhite() -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Copia con scale = 1 (1 punto = 1 píxel).
    func atScale1() -> UIImage {
        let px = CGSize(width: size.width * scale, height: size.height * scale)
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: px, format: f).image { _ in
            draw(in: CGRect(origin: .zero, size: px))
        }
    }

    /// Rellena un lienzo de `target` píxeles recortando lo que sobre (aspect-fill).
    func filled(to target: CGSize) -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: target, format: f).image { _ in
            let r = max(target.width / size.width, target.height / size.height)
            let w = size.width * r, h = size.height * r
            draw(in: CGRect(x: (target.width - w) / 2, y: (target.height - h) / 2, width: w, height: h))
        }
    }
}

func downsample(url: URL, maxPixel: CGFloat) -> UIImage? {
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceShouldCacheImmediately: true
    ]
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    return UIImage(cgImage: cg)
}

// MARK: - Archivos temporales

func tempURL(_ ext: String, name: String? = nil) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent((name ?? UUID().uuidString) + "." + ext)
}

func readFile(_ url: URL) -> Data? {
    let ok = url.startAccessingSecurityScopedResource()
    defer { if ok { url.stopAccessingSecurityScopedResource() } }
    return try? Data(contentsOf: url)
}

// MARK: - Guardar en Fotos

enum PhotoSaver {
    private static func authorized() async -> Bool {
        await withCheckedContinuation { c in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { st in
                c.resume(returning: st == .authorized || st == .limited)
            }
        }
    }

    static func save(_ image: UIImage) async -> Bool {
        guard await authorized() else { return false }
        return await withCheckedContinuation { c in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { ok, _ in c.resume(returning: ok) }
        }
    }

    static func save(_ images: [UIImage]) async -> Bool {
        guard await authorized() else { return false }
        return await withCheckedContinuation { c in
            PHPhotoLibrary.shared().performChanges({
                for i in images { PHAssetChangeRequest.creationRequestForAsset(from: i) }
            }) { ok, _ in c.resume(returning: ok) }
        }
    }

    /// Guarda un archivo (GIF, JPG, PNG…) tal cual, conservando animación.
    static func saveFiles(_ urls: [URL]) async -> Bool {
        guard await authorized() else { return false }
        return await withCheckedContinuation { c in
            PHPhotoLibrary.shared().performChanges({
                for u in urls {
                    let req = PHAssetCreationRequest.forAsset()
                    req.addResource(with: .photo, fileURL: u, options: nil)
                }
            }) { ok, _ in c.resume(returning: ok) }
        }
    }
}

// MARK: - Selectores

struct PhotoPicker: UIViewControllerRepresentable {
    var filter: PHPickerFilter = .images
    var limit: Int = 1
    var onPick: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var c = PHPickerConfiguration()
        c.filter = filter
        c.selectionLimit = limit
        c.preferredAssetRepresentationMode = .current
        let p = PHPickerViewController(configuration: c)
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([PHPickerResult]) -> Void
        init(_ f: @escaping ([PHPickerResult]) -> Void) { onPick = f }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onPick(results)
        }
    }
}

extension PHPickerResult {
    func loadUIImage() async -> UIImage? {
        guard itemProvider.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { c in
            itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                c.resume(returning: (obj as? UIImage)?.normalized())
            }
        }
    }

    func loadData(type: UTType) async -> Data? {
        await withCheckedContinuation { c in
            itemProvider.loadDataRepresentation(forTypeIdentifier: type.identifier) { d, _ in
                c.resume(returning: d)
            }
        }
    }

    func loadFileCopy(type: UTType) async -> URL? {
        await withCheckedContinuation { c in
            itemProvider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { c.resume(returning: nil); return }
                let dest = tempURL(url.pathExtension)
                try? FileManager.default.copyItem(at: url, to: dest)
                c.resume(returning: dest)
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onImage((info[.originalImage] as? UIImage)?.normalized())
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onImage(nil)
            parent.dismiss()
        }
    }
}

// MARK: - Compartir y mensajes

struct ShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension View {
    func messageAlert(_ msg: Binding<String?>) -> some View {
        alert("Photo Editor", isPresented: Binding(
            get: { msg.wrappedValue != nil },
            set: { if !$0 { msg.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(msg.wrappedValue ?? "")
        }
    }

    func shareSheet(_ item: Binding<ShareItem?>) -> some View {
        sheet(item: item) { ShareSheet(urls: $0.urls) }
    }
}

struct ImageBox: Identifiable {
    let id = UUID()
    let image: UIImage
}
