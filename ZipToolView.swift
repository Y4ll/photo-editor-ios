import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ZipEntry: Identifiable {
    let id = UUID()
    var name: String
    var data: Data
}

/// Comprimir en ZIP: junta archivos de Archivos y fotos de la galería.
struct ZipToolView: View {
    @State private var entries: [ZipEntry] = []
    @State private var zipName = "archivos"
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var message: String?
    @State private var share: ShareItem?

    var body: some View {
        List {
            Section {
                Button { showFiles = true } label: { Label("Añadir archivos", systemImage: "folder.badge.plus") }
                Button { showPhotos = true } label: { Label("Añadir fotos", systemImage: "photo.badge.plus") }
            }

            if !entries.isEmpty {
                Section("\(entries.count) archivos · \(sizeText)") {
                    ForEach(entries) { e in
                        HStack {
                            Text(e.name).lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(e.data.count), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { entries.remove(atOffsets: $0) }
                }

                Section("Nombre del ZIP") {
                    TextField("Nombre", text: $zipName)
                }

                Section {
                    Button { createZip() } label: { Label("Crear y compartir ZIP", systemImage: "doc.zipper") }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Comprimir en ZIP")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for u in urls {
                if let d = readFile(u) { entries.append(ZipEntry(name: u.lastPathComponent, data: d)) }
            }
        }
        .sheet(isPresented: $showPhotos) {
            PhotoPicker(filter: .images, limit: 0) { results in
                showPhotos = false
                Task {
                    for r in results {
                        guard let typeID = r.itemProvider.registeredTypeIdentifiers.first,
                              let type = UTType(typeID),
                              let d = await r.loadData(type: type) else { continue }
                        let ext = type.preferredFilenameExtension ?? "jpg"
                        let n = entries.count + 1
                        entries.append(ZipEntry(name: "foto_\(String(format: "%03d", n)).\(ext)", data: d))
                    }
                }
            }
        }
        .messageAlert($message)
        .shareSheet($share)
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(entries.reduce(0) { $0 + $1.data.count }), countStyle: .file)
    }

    private func createZip() {
        // Evita nombres repetidos dentro del ZIP.
        var seen: [String: Int] = [:]
        let files = entries.map { e -> (name: String, data: Data) in
            let c = seen[e.name, default: 0]
            seen[e.name] = c + 1
            if c == 0 { return (e.name, e.data) }
            let url = URL(fileURLWithPath: e.name)
            return ("\(url.deletingPathExtension().lastPathComponent)_\(c).\(url.pathExtension)", e.data)
        }
        let name = zipName.trimmingCharacters(in: .whitespaces).isEmpty ? "archivos" : zipName
        if let url = ZipWriter.zipFile(files, name: name) {
            share = ShareItem(urls: [url])
        } else {
            message = "No se pudo crear el ZIP."
        }
    }
}
