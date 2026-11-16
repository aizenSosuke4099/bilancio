import SwiftUI
import SwiftData

// MARK: - Bozza in revisione (niente è salvato finché l'utente non conferma)

struct RigaInRevisione: Identifiable {
    let id = UUID()
    var testo: String
    var quantita: Double = 1
    var prezzoUnitario: Double = 0
    var totale: Double = 0
    var categoria: Categoria?
    var nomeProdotto: String = ""
    var unita: String = "pz"
    var formato: Double?
    /// true se categoria/prodotto vengono da una correzione passata dell'utente.
    var imparata = false
}

struct ScontrinoInRevisione: Identifiable {
    let id = UUID()
    var immagini: [UIImage]
    var testoOCR: String
    /// Nome del negozio come letto dallo scontrino: è la chiave con cui si impara il nome corretto.
    var negozioLetto: String
    var negozio: String
    var negozioImparato: Bool
    var partitaIva: String
    var indirizzo: String
    var data: Date
    var totale: Double
    var righe: [RigaInRevisione]
    var pagatoInContanti: Bool?
    var conAI: Bool
    var nota: String?

    /// Applica le regole imparate alla lettura (nome negozio, categorie e prodotti delle righe).
    static func prepara(_ esito: LettoreScontrino.Esito, immagini: [UIImage], testoOCR: String, in context: ModelContext) -> ScontrinoInRevisione {
        let b = esito.bozza
        let spesa = TipoMovimento.spesa.rawValue
        let categorie = (try? context.fetch(FetchDescriptor<Categoria>(predicate: #Predicate { $0.tipoRaw == spesa }))) ?? []
        // i nomi proposti dalla lettura sono italiani; le categorie salvate possono essere tradotte
        func categoria(_ nome: String) -> Categoria? {
            guard !nome.isEmpty else { return nil }
            let nomi = [nome, DatiIniziali.localizzato(nome)]
            return categorie.first { c in nomi.contains { c.nome.compare($0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame } }
        }
        let prodotti = SalvataggioScansione.indiceProdotti(in: context)
        let totale = b.totale ?? b.righe.reduce(0) { $0 + $1.totale }.centesimi

        // nome del negozio già corretto in passato + categoria tipica del negozio (parole chiave)
        let suggerimento = b.negozio.isEmpty ? nil : Classificatore.suggerisciBanca(descrizione: b.negozio, importo: -totale, in: context)
        let imparato = suggerimento?.appreso == true
        let categoriaNegozio = suggerimento?.tipo == .spesa ? suggerimento?.categoria : nil

        let righe = b.righe.map { r in
            var x = RigaInRevisione(testo: r.testo, quantita: r.quantita, prezzoUnitario: r.prezzoUnitario, totale: r.totale,
                                    categoria: categoria(r.categoria) ?? categoriaNegozio ?? categoria("Altro"),
                                    nomeProdotto: r.nomeProdotto, unita: r.unita, formato: r.formato)
            if let appresa = Classificatore.suggerisciRiga(r.testo, in: context) {
                if let c = appresa.categoria { x.categoria = c }
                if let n = appresa.nomeProdotto, !n.isEmpty { x.nomeProdotto = n }
                x.imparata = true
            }
            if let p = prodotti[SalvataggioScansione.chiaveProdotto(x.nomeProdotto)] {
                x.unita = p.unita
                x.formato = p.formato ?? x.formato
            }
            return x
        }

        // totale non letto: si propone la somma delle righe, ma va detto (se una riga è sfuggita, la somma è sbagliata)
        let note = [b.totale == nil && !b.righe.isEmpty ? String(localized: "Non ho letto il totale: ho messo la somma delle righe. Controllalo sullo scontrino.") : nil,
                    esito.nota].compactMap { $0 }

        return ScontrinoInRevisione(
            immagini: immagini, testoOCR: testoOCR, negozioLetto: b.negozio,
            negozio: imparato ? (suggerimento?.titolo ?? b.negozio) : b.negozio, negozioImparato: imparato,
            partitaIva: b.partitaIva, indirizzo: b.indirizzo, data: b.data ?? Date(), totale: totale,
            righe: righe, pagatoInContanti: b.pagatoInContanti, conAI: esito.conAI, nota: note.isEmpty ? nil : note.joined(separator: "\n")
        )
    }
}

// MARK: - Salvataggio (condiviso da revisione e modifica)

enum SalvataggioScansione {

    /// Lo stesso prodotto si riconosce dal nome senza badare a maiuscole, accenti e punteggiatura.
    static func chiaveProdotto(_ nome: String) -> String { Classificatore.normalizza(nome) }

    /// Prodotti esistenti per `chiaveProdotto`.
    static func indiceProdotti(in context: ModelContext) -> [String: Prodotto] {
        let tutti = (try? context.fetch(FetchDescriptor<Prodotto>())) ?? []
        return Dictionary(tutti.map { (chiaveProdotto($0.nome), $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Sostituisce le righe dello scontrino con quelle confermate e le impara tutte.
    static func scriviRighe(_ righe: [RigaInRevisione], in scontrino: Scontrino, context: ModelContext) {
        for r in scontrino.righe { context.delete(r) }
        scontrino.righe = []
        var prodotti = indiceProdotti(in: context)
        for (i, r) in righe.enumerated() {
            let riga = RigaScontrino(testo: r.testo, quantita: r.quantita, prezzoUnitario: r.prezzoUnitario, totale: r.totale, ordine: i)
            context.insert(riga)
            riga.scontrino = scontrino
            riga.categoria = r.categoria
            let nome = r.nomeProdotto.trimmingCharacters(in: .whitespaces)
            if !nome.isEmpty {
                let chiave = chiaveProdotto(nome)
                let p = prodotti[chiave] ?? {
                    let nuovo = Prodotto(nome: nome, unita: r.unita, formato: r.formato)
                    context.insert(nuovo)
                    prodotti[chiave] = nuovo
                    return nuovo
                }()
                if p.categoria == nil { p.categoria = r.categoria }
                if p.formato == nil, let f = r.formato { p.formato = f }
                riga.prodotto = p
            }
            Classificatore.impara(rigaScontrino: r.testo, categoria: r.categoria, nomeProdotto: nome.isEmpty ? nil : nome, in: context)
        }
    }

    /// Categoria con l'importo maggiore tra le righe.
    static func categoriaPrevalente(_ righe: [RigaInRevisione]) -> Categoria? {
        var somme: [PersistentIdentifier: (Categoria, Double)] = [:]
        for r in righe { if let c = r.categoria { somme[c.persistentModelID, default: (c, 0)].1 += r.totale } }
        return somme.values.max { $0.1 < $1.1 }?.0
    }

    /// Foto unite in verticale, lato max 1600 px per foto, JPEG 0,6.
    static func immagineUnita(_ immagini: [UIImage], latoMax: CGFloat = 1600) -> Data? {
        guard !immagini.isEmpty else { return nil }
        let larghezza = immagini.map { $0.size.width * min(1, latoMax / max($0.size.width, $0.size.height)) }.min() ?? latoMax
        let altezze = immagini.map { $0.size.height * larghezza / $0.size.width }
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: larghezza, height: altezze.reduce(0, +)), format: formato)
        return renderer.jpegData(withCompressionQuality: 0.6) { _ in
            var y: CGFloat = 0
            for (img, h) in zip(immagini, altezze) {
                img.draw(in: CGRect(x: 0, y: y, width: larghezza, height: h))
                y += h
            }
        }
    }

    /// Nomi dei negozi già in archivio, dal più usato.
    static func negoziEsistenti(in context: ModelContext) -> [String] {
        let tutti = (try? context.fetch(FetchDescriptor<Scontrino>())) ?? []
        let conteggi = Dictionary(grouping: tutti.map(\.negozio).filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        return conteggi.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map(\.key)
    }
}

// MARK: - Schermata di revisione

struct RevisioneScontrinoView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Conto> { !$0.archiviato }, sort: \Conto.ordine) private var conti: [Conto]
    @Query(filter: #Predicate<Categoria> { $0.tipoRaw == "spesa" }, sort: \Categoria.ordine) private var categorie: [Categoria]
    /// Ultimo conto usato per pagare uno scontrino (per proporlo la volta dopo).
    @AppStorage("scansione.ultimoConto") private var ultimoConto = ""

    @State private var s: ScontrinoInRevisione
    @State private var contoScelto: Conto?
    @State private var pagamentoBanca: Movimento?
    @State private var usaPagamentoBanca = true
    @State private var duplicato: Scontrino?
    @State private var negozi: [String] = []
    @State private var mostraImmagine = false
    @State private var errore: String?
    @State private var pronta = false

    init(scontrino: ScontrinoInRevisione) {
        _s = State(initialValue: scontrino)
    }

    private var sommaRighe: Double { s.righe.reduce(0) { $0 + $1.totale }.centesimi }
    private var collegato: Bool { pagamentoBanca != nil && usaPagamentoBanca }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    if let img = s.immagini.first {
                        Button { mostraImmagine = true } label: {
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 64, height: 86).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mostra la foto dello scontrino")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Label(s.conAI ? "Letto con Apple Intelligence" : "Letto con le regole",
                              systemImage: s.conAI ? "apple.intelligence" : "text.viewfinder")
                            .font(.subheadline.weight(.semibold))
                        Text("Controlla e correggi: ricorderò le tue scelte per i prossimi scontrini.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let nota = s.nota { Text(nota).font(.caption).foregroundStyle(.orange) }
                    }
                }
            }

            Section("Scontrino") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Negozio", text: $s.negozio).font(.headline)
                        if s.negozioImparato {
                            Text("imparato").font(.caption2.weight(.semibold)).foregroundStyle(.purple)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.purple.opacity(0.12), in: Capsule())
                        }
                        if !negozi.isEmpty {
                            Menu {
                                ForEach(negozi.prefix(40), id: \.self) { n in Button(n) { s.negozio = n } }
                            } label: { Image(systemName: "list.bullet.circle") }
                            .accessibilityLabel("Scegli un negozio già usato")
                        }
                    }
                    if !negoziSimili.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(negoziSimili, id: \.self) { n in
                                    Button(n) { s.negozio = n }.buttonStyle(.bordered).controlSize(.mini)
                                }
                            }
                        }
                    }
                }
                DatePicker("Data", selection: $s.data, displayedComponents: [.date, .hourAndMinute])
                    
                LabeledContent("Totale") {
                    TextField("0,00", value: $s.totale, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(.body.bold().monospacedDigit())
                }
                if abs(sommaRighe - s.totale) >= 0.01, !s.righe.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("La somma delle righe (\(sommaRighe.euro)) non corrisponde al totale (\(s.totale.euro)).",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                        Button("Usa la somma delle righe come totale") { s.totale = sommaRighe }.font(.footnote)
                    }
                }
                if let d = duplicato {
                    Label("Hai già salvato uno scontrino di \(d.negozio) del \(d.data.breve) da \(d.totale.euro): forse è un doppione.",
                          systemImage: "doc.on.doc.fill")
                        .font(.footnote).foregroundStyle(.red)
                }
                if !s.partitaIva.isEmpty { LabeledContent("P.IVA", value: s.partitaIva) }
            }

            Section {
                if let m = pagamentoBanca {
                    Toggle(isOn: $usaPagamentoBanca) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Collegato al pagamento \(m.conto?.nome ?? String(localized: "bancario", comment: "nella frase «Collegato al pagamento bancario del …»")) del \(m.data.breve) \(abs(m.importo).euro)")
                                    .font(.subheadline)
                                Text(m.titolo).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "link").foregroundStyle(.blue) }
                    }
                }
                if !collegato {
                    Picker("Pagato con", selection: $contoScelto) {
                        ForEach(conti) { c in Label(c.nome, systemImage: c.tipo.icona).tag(Optional(c)) }
                    }
                }
            } header: {
                Text("Pagamento")
            } footer: {
                if collegato {
                    Text("La spesa non verrà contata due volte: lo scontrino si collega al movimento già arrivato dalla banca.")
                }
            }

            SezioneRigheScansione(righe: $s.righe, categorie: categorie)

            Section {
                Button(action: salva) {
                    Label("Conferma e salva", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity).font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(s.negozio.trimmingCharacters(in: .whitespaces).isEmpty || s.totale <= 0 || (!collegato && contoScelto == nil))
            }
        }
        .navigationTitle("Controlla lo scontrino")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva", action: salva).disabled(s.totale <= 0 || (!collegato && contoScelto == nil))
            }
        }
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $mostraImmagine) {
            if let img = s.immagini.first { FotoSchermoInteroScansione(immagine: unite ?? img) }
        }
        .alert("Salvataggio non riuscito", isPresented: Binding(get: { errore != nil }, set: { if !$0 { errore = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errore ?? "") }
        .task {
            guard !pronta else { return }
            pronta = true
            negozi = SalvataggioScansione.negoziEsistenti(in: context)
            aggiornaControlli()
            contoScelto = contoProposto()
        }
        .onChange(of: s.totale) { aggiornaControlli() }
        .onChange(of: s.data) { aggiornaControlli() }
        .onChange(of: s.negozio) { aggiornaDuplicato() }
    }

    /// Anteprima a schermo intero di tutte le foto unite (scontrino lungo).
    private var unite: UIImage? {
        s.immagini.count > 1 ? SalvataggioScansione.immagineUnita(s.immagini).flatMap(UIImage.init(data:)) : nil
    }

    /// Negozi già usati con una parola in comune col nome letto (per tenere unito l'archivio).
    private var negoziSimili: [String] {
        let parole = Set(Classificatore.normalizza(s.negozio).split(separator: " ").filter { $0.count >= 3 })
        guard !parole.isEmpty else { return [] }
        return negozi.filter { n in
            n.compare(s.negozio, options: .caseInsensitive) != .orderedSame
                && !parole.isDisjoint(with: Classificatore.normalizza(n).split(separator: " "))
        }.prefix(5).map { $0 }
    }

    private func aggiornaControlli() {
        let trovato = s.totale > 0 ? Abbinamento.movimentoBancaPer(totale: s.totale, data: s.data, in: context) : nil
        if trovato?.persistentModelID != pagamentoBanca?.persistentModelID { usaPagamentoBanca = true }
        pagamentoBanca = trovato
        aggiornaDuplicato()
    }

    private func aggiornaDuplicato() {
        let da = calendario.startOfDay(for: s.data)
        let a = da.aggiungendo(giorni: 1)
        let stessoGiorno = (try? context.fetch(FetchDescriptor<Scontrino>(predicate: #Predicate { $0.data >= da && $0.data < a }))) ?? []
        duplicato = stessoGiorno.first {
            $0.negozio.compare(s.negozio, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame && abs($0.totale - s.totale) < 0.01
        }
    }

    /// Contanti se lo scontrino lo dice, altrimenti l'ultimo conto usato.
    private func contoProposto() -> Conto? {
        let contanti = conti.first { $0.tipo == .contanti }
        let ultimo = conti.first { $0.nome == ultimoConto }
        switch s.pagatoInContanti {
        case true?: return contanti ?? ultimo
        case false?: return (ultimo?.tipo == .contanti ? nil : ultimo) ?? conti.first { $0.tipo != .contanti }
        case nil: return ultimo ?? contanti
        }
    }

    private func salva() {
        let negozio = s.negozio.trimmingCharacters(in: .whitespaces)
        let scontrino = Scontrino(negozio: negozio, data: s.data, totale: s.totale.centesimi)
        scontrino.indirizzo = s.indirizzo
        scontrino.partitaIva = s.partitaIva
        scontrino.testoOCR = s.testoOCR
        scontrino.immagine = SalvataggioScansione.immagineUnita(s.immagini)
        context.insert(scontrino)
        SalvataggioScansione.scriviRighe(s.righe, in: scontrino, context: context)

        let prevalente = SalvataggioScansione.categoriaPrevalente(s.righe)
        if let m = pagamentoBanca, usaPagamentoBanca {
            scontrino.movimento = m
            m.tipo = .spesa
            if let prevalente { m.categoria = prevalente }
            m.conferma()
        } else {
            let m = Movimento(data: s.data, importo: -s.totale.centesimi, tipo: .spesa, titolo: negozio, origine: .scontrino,
                              // in contanti è confermato; con carta o conto lo conferma l'addebito della banca (o tu, a fine mese)
                              stato: contoScelto?.tipo == .contanti ? .confermato : .daConfermare, conto: contoScelto, categoria: prevalente)
            // su un conto in valuta lo scontrino è in quella valuta
            Contabilita.imposta(m, importoInValuta: -s.totale.centesimi, valuta: contoScelto?.valuta ?? "EUR")
            m.descrizioneOriginale = s.negozioLetto
            context.insert(m)
            scontrino.movimento = m
            if let c = contoScelto { ultimoConto = c.nome }
        }
        if !s.negozioLetto.isEmpty, let prevalente {   // senza categoria non si impara nulla (cancellerebbe quella già imparata)
            Classificatore.impara(descrizioneBanca: s.negozioLetto, tipo: .spesa, categoria: prevalente, titolo: negozio, in: context)
        }

        do {
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            context.rollback()
            errore = String(localized: "Non sono riuscito a salvare lo scontrino: \(error.localizedDescription)")
        }
    }
}
