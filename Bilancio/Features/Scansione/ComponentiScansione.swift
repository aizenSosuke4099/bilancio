import SwiftUI
import SwiftData
import VisionKit

// MARK: - Righe dello scontrino (revisione e modifica)

/// Sezione di un Form con le righe modificabili, aggiunta/eliminazione e "Applica categoria a tutte".
struct SezioneRigheScansione: View {
    @Binding var righe: [RigaInRevisione]
    let categorie: [Categoria]

    var body: some View {
        Section {
            ForEach($righe) { $r in
                NavigationLink { EditorRigaScansioneView(riga: $r, categorie: categorie) } label: { RigaRevisioneScansione(riga: r) }
            }
            .onDelete { righe.remove(atOffsets: $0) }
            Button("Aggiungi riga", systemImage: "plus.circle") {
                righe.append(RigaInRevisione(testo: "", categoria: righe.last?.categoria))
            }
        } header: {
            HStack {
                Text("Righe (\(righe.count))")
                Spacer()
                if !righe.isEmpty {
                    Menu {
                        ForEach(categorie) { c in
                            Button { for i in righe.indices { righe[i].categoria = c } } label: { Label(c.nome, systemImage: c.icona) }
                        }
                    } label: {
                        Label("Applica categoria a tutte", systemImage: "square.stack.3d.down.right").font(.caption).textCase(nil)
                    }
                }
            }
        } footer: {
            Text("Tocca una riga per correggerla. Scorri a sinistra per eliminarla.")
        }
    }
}

struct RigaRevisioneScansione: View {
    let riga: RigaInRevisione

    var body: some View {
        HStack(spacing: 10) {
            IconaCategoria(categoria: riga.categoria)
            VStack(alignment: .leading, spacing: 2) {
                Text(titolo).lineLimit(1)
                Text(dettaglio).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(riga.totale.euro).font(.callout.monospacedDigit())
                Text(riga.imparata ? "imparata" : "proposta")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(riga.imparata ? Color.purple : Color.orange)
            }
        }
    }

    private var titolo: String {
        if !riga.nomeProdotto.isEmpty { return riga.nomeProdotto }
        return riga.testo.isEmpty ? "Nuova riga" : riga.testo
    }

    private var dettaglio: String {
        var parti: [String] = []
        if !riga.testo.isEmpty, riga.testo != riga.nomeProdotto { parti.append(riga.testo) }
        if riga.quantita != 1 { parti.append("\(riga.quantita.quote) \(riga.unita == "pz" ? "×" : riga.unita + " ×") \(riga.prezzoUnitario.euro)") }
        parti.append(riga.categoria?.nome ?? "Senza categoria")
        return parti.joined(separator: " · ")
    }
}

struct EditorRigaScansioneView: View {
    @Binding var riga: RigaInRevisione
    let categorie: [Categoria]

    private let numero = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...3)).locale(localeIT)
    private let importo = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2)).locale(localeIT)

    var body: some View {
        Form {
            Section("Sullo scontrino") {
                TextField("Testo della riga", text: $riga.testo)
            }
            Section("Importi") {
                LabeledContent("Quantità") {
                    TextField("1", value: $riga.quantita, format: numero).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Prezzo unitario") {
                    TextField("0,00", value: $riga.prezzoUnitario, format: importo).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Totale riga") {
                    TextField("0,00", value: $riga.totale, format: importo).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                }
            }
            Section {
                Picker("Categoria", selection: $riga.categoria) {
                    ForEach(categorie) { c in
                        HStack { IconaCategoria(categoria: c, dimensione: 26); Text(c.nome) }.tag(Optional(c))
                    }
                }
                .pickerStyle(.navigationLink)
                TextField("Nome prodotto (es. Latte intero Granarolo 1 l)", text: $riga.nomeProdotto)
                Picker("Unità", selection: $riga.unita) {
                    Text("pezzi").tag("pz")
                    Text("kg").tag("kg")
                    Text("litri").tag("l")
                }
                .pickerStyle(.segmented)
                LabeledContent("Formato (\(riga.unita))") {
                    TextField("es. 0,5", value: $riga.formato, format: numero).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Classificazione")
            } footer: {
                Text(riga.imparata
                     ? "Categoria e prodotto vengono da una tua correzione precedente."
                     : "Proposta automatica: se la correggi, la ricorderò per i prossimi scontrini.")
            }
        }
        .navigationTitle(riga.nomeProdotto.isEmpty ? "Riga" : riga.nomeProdotto)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: riga.quantita) { riga.totale = (riga.quantita * riga.prezzoUnitario).centesimi }
        .onChange(of: riga.prezzoUnitario) { riga.totale = (riga.quantita * riga.prezzoUnitario).centesimi }
    }
}

// MARK: - Immagine

/// Foto dello scontrino a schermo intero, con zoom e trascinamento.
struct FotoSchermoInteroScansione: View {
    let immagine: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZoomImmagineScansione(immagine: immagine)
                .background(Color.black)
                .ignoresSafeArea(edges: .bottom)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}

/// UIScrollView: pinch per ingrandire, doppio tocco per zoom avanti/indietro.
private struct ZoomImmagineScansione: UIViewRepresentable {
    let immagine: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.delegate = context.coordinator
        scroll.showsHorizontalScrollIndicator = false
        let vista = UIImageView(image: immagine)
        vista.contentMode = .scaleAspectFit
        vista.frame = scroll.bounds
        vista.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(vista)
        context.coordinator.vista = vista
        let doppio = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinatore.doppioTocco(_:)))
        doppio.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doppio)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {}

    func makeCoordinator() -> Coordinatore { Coordinatore() }

    final class Coordinatore: NSObject, UIScrollViewDelegate {
        weak var vista: UIView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { vista }
        @objc func doppioTocco(_ g: UITapGestureRecognizer) {
            guard let scroll = g.view as? UIScrollView else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let punto = g.location(in: vista)
                scroll.zoom(to: CGRect(x: punto.x - 60, y: punto.y - 60, width: 120, height: 120), animated: true)
            }
        }
    }
}

/// Miniatura decodificata fuori dal body (le foto sono grandi).
struct MiniaturaScansione: View {
    let dati: Data?
    var larghezza: CGFloat = 44
    var altezza: CGFloat = 58
    @State private var immagine: UIImage?

    var body: some View {
        Group {
            if let immagine {
                Image(uiImage: immagine).resizable().scaledToFill()
            } else {
                Image(systemName: "receipt").font(.title3).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(.tertiarySystemFill))
            }
        }
        .frame(width: larghezza, height: altezza)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task {
            guard let dati, let img = UIImage(data: dati) else { return }
            immagine = await img.byPreparingThumbnail(ofSize: CGSize(width: larghezza * 3, height: altezza * 3 * img.size.height / max(img.size.width, 1)))
        }
    }
}

// MARK: - Fotocamera documenti (VisionKit: ritaglio automatico, più pagine = scontrino lungo)

struct FotocameraScansione: UIViewControllerRepresentable {
    var fatto: ([UIImage]) -> Void
    var annullato: () -> Void
    var errore: (Error) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinatore { Coordinatore(self) }

    final class Coordinatore: NSObject, VNDocumentCameraViewControllerDelegate {
        let padre: FotocameraScansione
        init(_ padre: FotocameraScansione) { self.padre = padre }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            padre.fatto((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { padre.annullato() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { padre.errore(error) }
    }
}
