import SwiftUI
import StoreKit

struct Tile: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 32))
                .frame(height: 40)
            Text(title)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 4)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct HomeView: View {
    @State private var editor: ImageBox?
    @State private var showGallery = false
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var showNew = false
    @Environment(\.requestReview) private var requestReview

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 12) {
                    tileButton("Galería", "photo.on.rectangle") { showGallery = true }
                    tileButton("Archivos", "folder") { showFiles = true }
                    tileButton("Cámara", "camera") { showCamera = true }
                    tileButton("Nueva Imagen", "doc.badge.plus") { showNew = true }
                    NavigationLink { RecentsView() } label: {
                        Tile(title: "Imágenes Recientes", symbol: "clock.arrow.circlepath")
                    }
                    NavigationLink { BatchView() } label: {
                        Tile(title: "Tareas por Lotes", symbol: "square.on.square")
                    }
                    NavigationLink { ToolsView() } label: {
                        Tile(title: "Herramientas", symbol: "wrench.fill")
                    }
                    tileButton("Calificar Photo Editor", "star.fill") { requestReview() }
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Photo Editor")
        }
        .sheet(isPresented: $showGallery) {
            PhotoPicker { results in
                showGallery = false
                guard let r = results.first else { return }
                Task { if let img = await r.loadUIImage() { open(img) } }
            }
        }
        .sheet(isPresented: $showNew) {
            NewImageView { open($0) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in if let img { open(img) } }
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $editor) { box in
            EditorView(image: box.image)
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result, let d = readFile(url), let img = UIImage(data: d) {
                open(img.normalized())
            }
        }
    }

    private func tileButton(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Tile(title: title, symbol: symbol) }
    }

    /// Abre el editor tras dejar que termine de cerrarse el selector anterior.
    private func open(_ image: UIImage) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            editor = ImageBox(image: image)
        }
    }
}

// MARK: - Nueva imagen

struct NewImageView: View {
    var onCreate: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var width = "1080"
    @State private var height = "1080"
    @State private var color = Color.white

    var body: some View {
        NavigationStack {
            Form {
                Section("Tamaño (píxeles)") {
                    HStack {
                        TextField("Ancho", text: $width).keyboardType(.numberPad)
                        Text("×")
                        TextField("Alto", text: $height).keyboardType(.numberPad)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            preset("Cuadrado", 1080, 1080)
                            preset("Historia", 1080, 1920)
                            preset("Retrato", 1080, 1350)
                            preset("Horizontal", 1920, 1080)
                            preset("4K", 3840, 2160)
                        }
                    }
                }
                Section("Fondo") {
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                }
            }
            .navigationTitle("Nueva imagen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Crear") { create() } }
            }
        }
    }

    private func preset(_ name: String, _ w: Int, _ h: Int) -> some View {
        Button(name) { width = "\(w)"; height = "\(h)" }.buttonStyle(.bordered)
    }

    private func create() {
        let w = min(max(Int(width) ?? 1080, 16), 8000)
        let h = min(max(Int(height) ?? 1080, 16), 8000)
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f).image { ctx in
            UIColor(color).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        dismiss()
        onCreate(img)
    }
}

// MARK: - Recientes

struct RecentsView: View {
    @ObservedObject private var store = RecentStore.shared
    @State private var editor: ImageBox?

    var body: some View {
        ScrollView {
            if store.items.isEmpty {
                Text("Todavía no hay imágenes recientes.\nLas que guardes desde el editor aparecerán aquí.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                    ForEach(store.items, id: \.self) { url in
                        RecentThumb(url: url)
                            .onTapGesture {
                                if let img = UIImage(contentsOfFile: url.path) { editor = ImageBox(image: img) }
                            }
                            .contextMenu {
                                Button(role: .destructive) { store.remove(url) } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(8)
            }
        }
        .navigationTitle("Imágenes Recientes")
        .onAppear { store.reload() }
        .fullScreenCover(item: $editor) { EditorView(image: $0.image) }
    }
}

struct RecentThumb: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .frame(height: 100)
            .overlay(Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() } else { Color.gray.opacity(0.2) }
            })
            .clipped()
            .task { image = downsample(url: url, maxPixel: 300) }
    }
}
