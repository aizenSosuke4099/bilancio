import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import VisionKit

/// Tab "Scansiona": foto dello scontrino → lettura → revisione → salvataggio.
struct ScansioneView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var recenti: [Scontrino]

    @State private var mostraFotocamera = false
    @State private var selezioneFoto: [PhotosPickerItem] = []
    @State private var mostraSpesaManuale = false
    @State private var avanzamento: String?
    @State private var revisione: ScontrinoInRevisione?
    @State private var errore: String?
    @State private var permessoNegato = false

    init() {
        var d = FetchDescriptor<Scontrino>(sortBy: [SortDescriptor(\.creatoIl, order: .reverse)])
        d.fetchLimit = 10
        _recenti = Query(d)
    }

    private var fotocameraDisponibile: Bool { VNDocumentCameraViewController.isSupported }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    azioni
                    if !recenti.isEmpty { ultimiScontrini }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Scansiona")
            .disabled(avanzamento != nil)
            .overlay { if let avanzamento { schermataLettura(avanzamento) } }
            .fullScreenCover(isPresented: $mostraFotocamera) {
                FotocameraScansione(
                    fatto: { immagini in
                        mostraFotocamera = false
                        Task { await analizza(immagini) }
                    },
                    annullato: { mostraFotocamera = false },
                    errore: { e in
                        mostraFotocamera = false
                        errore = String(localized: "La fotocamera non ha funzionato: \(e.localizedDescription)")
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(item: $revisione) { r in
                NavigationStack { RevisioneScontrinoView(scontrino: r) }
            }
            .sheet(isPresented: $mostraSpesaManuale) {
                NavigationStack { MovimentoEditorView() }
            }
            .onChange(of: selezioneFoto) { Task { await caricaFoto() } }
            .alert("Qualcosa non va", isPresented: Binding(get: { errore != nil }, set: { if !$0 { errore = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errore ?? "") }
            .alert("Accesso alla fotocamera negato", isPresented: $permessoNegato) {
                Button("Apri Impostazioni") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Per scansionare gli scontrini consenti a Bilancio di usare la fotocamera in Impostazioni › Bilancio. Intanto puoi scegliere una foto dalla libreria.")
            }
        }
    }

    // MARK: Sezioni

    private var azioni: some View {
        VStack(spacing: 10) {
            if fotocameraDisponibile {
                Button(action: apriFotocamera) {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.viewfinder").font(.system(size: 44, weight: .regular))
                        Text("Scansiona scontrino").font(.title3.bold())
                        Text("Ritaglio automatico. Scontrino lungo? Scatta più foto di seguito.")
                            .font(.caption).multilineTextAlignment(.center).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                    .padding(.horizontal, 12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            PhotosPicker(selection: $selezioneFoto, maxSelectionCount: 6, selectionBehavior: .ordered, matching: .images) {
                Label(fotocameraDisponibile ? "Scegli dalla libreria foto" : "Scegli la foto dello scontrino",
                      systemImage: "photo.on.rectangle")
                    .font(fotocameraDisponibile ? .body.weight(.medium) : .title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, fotocameraDisponibile ? 14 : 26)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text("Puoi selezionare più foto dello stesso scontrino, in ordine dall'alto in basso.")
                .font(.caption2).foregroundStyle(.secondary)

            Button { mostraSpesaManuale = true } label: {
                Label("Spesa senza scontrino", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(.top, 8)
    }

    private var ultimiScontrini: some View {
        Scheda(titolo: "Ultimi scontrini") {
            VStack(spacing: 0) {
                ForEach(recenti) { s in
                    NavigationLink { ScontrinoDettaglioView(scontrino: s) } label: {
                        HStack(spacing: 10) {
                            MiniaturaScansione(dati: s.immagine)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.negozio.isEmpty ? String(localized: "Scontrino") : s.negozio).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text("\(s.data.giornoMese) \(String(s.data.anno)) · \(s.righe.count) righe").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(s.totale.euro).font(.callout.monospacedDigit())
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if s.id != recenti.last?.id { Divider() }
                }
            }
        }
    }

    private func schermataLettura(_ testo: String) -> some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(testo).font(.headline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: Azioni

    private func apriFotocamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            mostraFotocamera = true
        case .notDetermined:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) { mostraFotocamera = true } else { permessoNegato = true }
            }
        default:
            permessoNegato = true
        }
    }

    private func caricaFoto() async {
        guard !selezioneFoto.isEmpty else { return }
        let elementi = selezioneFoto
        selezioneFoto = []
        avanzamento = String(localized: "Apro le foto…")
        var immagini: [UIImage] = []
        for e in elementi {
            if let dati = try? await e.loadTransferable(type: Data.self), let img = UIImage(data: dati) { immagini.append(img) }
        }
        guard !immagini.isEmpty else {
            avanzamento = nil
            errore = String(localized: "Non riesco ad aprire le foto scelte. Se sono su iCloud, attendi che vengano scaricate e riprova.")
            return
        }
        await analizza(immagini)
    }

    private func analizza(_ immagini: [UIImage]) async {
        avanzamento = String(localized: "Leggo lo scontrino…")
        defer { avanzamento = nil }
        do {
            let testo = try await LettoreScontrino.leggiTesto(da: immagini)
            guard testo.filter(\.isLetter).count >= 5 else {
                errore = String(localized: "Non trovo testo nella foto. Riprova con più luce, lo scontrino disteso e tutto inquadrato.")
                return
            }
            let spesa = TipoMovimento.spesa.rawValue
            let categorie = ((try? context.fetch(FetchDescriptor<Categoria>(predicate: #Predicate { $0.tipoRaw == spesa }, sortBy: [SortDescriptor(\.ordine)]))) ?? []).map(\.nome)
            avanzamento = String(localized: "Capisco le voci…")
            let esito = await LettoreScontrino.estrai(testo: testo, categorie: categorie) { avanzamento = $0 }
            revisione = ScontrinoInRevisione.prepara(esito, immagini: immagini, testoOCR: testo, in: context)
        } catch {
            errore = String(localized: "Non sono riuscito a leggere lo scontrino: \(error.localizedDescription)")
        }
    }
}
