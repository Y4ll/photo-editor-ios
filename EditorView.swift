import SwiftUI

enum EditTab: String, CaseIterable, Identifiable {
    case ajustes = "Ajustes", filtros = "Filtros", recortar = "Recortar", girar = "Girar", texto = "Texto"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .ajustes: return "slider.horizontal.3"
        case .filtros: return "camera.filters"
        case .recortar: return "crop"
        case .girar: return "rotate.right"
        case .texto: return "textformat"
        }
    }
}

struct EditorView: View {
    @StateObject private var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    @State private var tab: EditTab = .ajustes
    @State private var showOriginal = false
    @State private var message: String?
    @State private var share: ShareItem?
    @State private var busy = false
    @State private var selectedText: Int?

    init(image: UIImage) {
        _model = StateObject(wrappedValue: EditorModel(image: image))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    Image(uiImage: showOriginal ? model.small : model.preview)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .onLongPressGesture(minimumDuration: 0.01, maximumDistance: 60,
                                            pressing: { showOriginal = $0 }, perform: {})
                    if busy { ProgressView().controlSize(.large) }
                    VStack {
                        Spacer()
                        Text("Mantén pulsada la imagen para ver el original")
                            .font(.caption2).foregroundStyle(.secondary).padding(.bottom, 4)
                    }
                }
                .frame(maxHeight: .infinity)

                panel
                    .frame(height: 200)
                    .background(Color(white: 0.1))

                HStack(spacing: 0) {
                    ForEach(EditTab.allCases) { t in
                        Button { tab = t } label: {
                            VStack(spacing: 3) {
                                Image(systemName: t.icon)
                                Text(t.rawValue).font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(tab == t ? Color.accentColor : .secondary)
                        }
                    }
                }
                .background(Color(white: 0.07))
            }
            .navigationTitle("Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!model.canUndo)
                    Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!model.canRedo)
                    Menu {
                        Button { save() } label: { Label("Guardar en Fotos", systemImage: "square.and.arrow.down") }
                        Button { exportShare() } label: { Label("Compartir", systemImage: "square.and.arrow.up") }
                        Button(role: .destructive) { model.reset() } label: { Label("Restablecer", systemImage: "arrow.counterclockwise") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .messageAlert($message)
        .shareSheet($share)
    }

    // MARK: Acciones

    private func save() {
        Task {
            busy = true
            let img = await model.renderFull()
            RecentStore.shared.add(img)
            let ok = await PhotoSaver.save(img)
            busy = false
            message = ok ? "Imagen guardada en Fotos." : "No se pudo guardar. Revisa el permiso de Fotos."
        }
    }

    private func exportShare() {
        Task {
            busy = true
            let img = await model.renderFull()
            busy = false
            if let data = img.flattenedOnWhite().jpegData(compressionQuality: 0.95) {
                let url = tempURL("jpg", name: "foto_editada")
                try? data.write(to: url)
                share = ShareItem(urls: [url])
            }
        }
    }

    // MARK: Paneles

    @ViewBuilder private var panel: some View {
        switch tab {
        case .ajustes: adjustPanel
        case .filtros: filterPanel
        case .recortar: cropPanel
        case .girar: rotatePanel
        case .texto: textPanel
        }
    }

    private func slider(_ title: String, _ kp: WritableKeyPath<EditState, Double>,
                        _ range: ClosedRange<Double>, _ def: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: "%.2f", model.state[keyPath: kp]))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { model.state[keyPath: kp] },
                                  set: { model.state[keyPath: kp] = $0 }),
                   in: range,
                   onEditingChanged: { if $0 { model.beginEdit() } })
        }
        .onTapGesture(count: 2) { model.beginEdit(); model.state[keyPath: kp] = def }
    }

    private var adjustPanel: some View {
        ScrollView {
            VStack(spacing: 8) {
                slider("Brillo", \.brightness, -0.5...0.5, 0)
                slider("Contraste", \.contrast, 0.5...1.5, 1)
                slider("Saturación", \.saturation, 0...2, 1)
                slider("Exposición", \.exposure, -2...2, 0)
                slider("Nitidez", \.sharpness, 0...2, 0)
                slider("Temperatura", \.warmth, -1...1, 0)
                Text("Doble toque en un control para restablecerlo")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private var filterPanel: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PhotoFilter.allCases) { f in
                        Button {
                            model.beginEdit()
                            model.state.filter = f
                        } label: {
                            VStack(spacing: 4) {
                                Group {
                                    if let t = model.thumbs[f] {
                                        Image(uiImage: t).resizable().scaledToFill()
                                    } else {
                                        Color.gray.opacity(0.3)
                                    }
                                }
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(model.state.filter == f ? Color.accentColor : .clear, lineWidth: 2))
                                Text(f.title).font(.caption2)
                                    .foregroundStyle(model.state.filter == f ? Color.accentColor : .secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
            }
            slider("Intensidad", \.filterIntensity, 0...1, 1)
                .padding(.horizontal)
            Spacer(minLength: 0)
        }
    }

    private var cropPanel: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CropAspect.allCases) { a in
                        Button(a.rawValue) { model.beginEdit(); model.state.aspect = a }
                            .buttonStyle(.bordered)
                            .tint(model.state.aspect == a ? .accentColor : .gray)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
            }
            VStack(spacing: 6) {
                slider("Zoom", \.zoom, 1...3, 1)
                slider("Mover horizontal", \.panX, -1...1, 0)
                slider("Mover vertical", \.panY, -1...1, 0)
            }
            .padding(.horizontal)
            Spacer(minLength: 0)
        }
    }

    private var rotatePanel: some View {
        HStack(spacing: 24) {
            Spacer()
            bigButton("Izquierda", "rotate.left") { model.beginEdit(); model.state.rotation -= 1 }
            bigButton("Derecha", "rotate.right") { model.beginEdit(); model.state.rotation += 1 }
            bigButton("Voltear", "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                model.beginEdit(); model.state.flipH.toggle()
            }
            Spacer()
        }
    }

    private func bigButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.caption)
            }
            .frame(width: 80, height: 80)
            .background(Color(white: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Texto

    private func textBinding<T>(_ i: Int, _ kp: WritableKeyPath<TextOverlay, T>, default d: T) -> Binding<T> {
        Binding(
            get: { model.state.texts.indices.contains(i) ? model.state.texts[i][keyPath: kp] : d },
            set: { if model.state.texts.indices.contains(i) { model.state.texts[i][keyPath: kp] = $0 } }
        )
    }

    private var textPanel: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack {
                    Button {
                        model.beginEdit()
                        model.state.texts.append(TextOverlay(text: "Texto"))
                        selectedText = model.state.texts.count - 1
                    } label: { Label("Añadir texto", systemImage: "plus") }
                    .buttonStyle(.bordered)

                    ForEach(Array(model.state.texts.enumerated()), id: \.element.id) { i, t in
                        Button(t.text.isEmpty ? "…" : String(t.text.prefix(8))) { selectedText = i }
                            .buttonStyle(.bordered)
                            .tint(selectedText == i ? .accentColor : .gray)
                    }
                    Spacer()
                    if let i = selectedText, model.state.texts.indices.contains(i) {
                        Button(role: .destructive) {
                            model.beginEdit()
                            model.state.texts.remove(at: i)
                            selectedText = nil
                        } label: { Image(systemName: "trash") }
                    }
                }

                if let i = selectedText, model.state.texts.indices.contains(i) {
                    TextField("Escribe aquí", text: textBinding(i, \.text, default: ""))
                        .textFieldStyle(.roundedBorder)
                    labeledSlider("Posición X", textBinding(i, \.x, default: 0.5), 0...1)
                    labeledSlider("Posición Y", textBinding(i, \.y, default: 0.5), 0...1)
                    labeledSlider("Tamaño", textBinding(i, \.size, default: 0.08), 0.02...0.3)
                    HStack {
                        ForEach(TextColor.allCases) { c in
                            Circle().fill(c.color).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.white, lineWidth: model.state.texts[i].color == c ? 3 : 0.5))
                                .onTapGesture { model.beginEdit(); model.state.texts[i].color = c }
                        }
                    }
                } else if model.state.texts.isEmpty {
                    Text("Añade un texto y muévelo con los controles.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private func labeledSlider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 80, alignment: .leading)
            Slider(value: value, in: range)
        }
    }
}
