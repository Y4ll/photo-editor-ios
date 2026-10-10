import SwiftUI

/// Guarda copias de las imágenes editadas para la pantalla "Imágenes Recientes".
final class RecentStore: ObservableObject {
    static let shared = RecentStore()
    @Published private(set) var items: [URL] = []
    private let dir: URL
    private let maxItems = 40

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("Recents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        items = files
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a > b
            }
    }

    func add(_ image: UIImage) {
        guard let data = image.flattenedOnWhite().jpegData(compressionQuality: 0.9) else { return }
        let name = "img_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        try? data.write(to: dir.appendingPathComponent(name))
        reload()
        if items.count > maxItems {
            for u in items.dropFirst(maxItems) { try? FileManager.default.removeItem(at: u) }
            reload()
        }
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        reload()
    }
}
