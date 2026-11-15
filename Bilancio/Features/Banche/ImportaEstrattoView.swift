import SwiftUI
import SwiftData
import PDFKit
import FoundationModels
import UniformTypeIdentifiers

/// Importa un estratto conto CSV, testo o PDF. Pushata da Altro o presentata in sheet ("Apri con Bilancio").
struct ImportaEstrattoView: View {
    var fileURL: URL? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Conto.ordine) private var conti: [Conto]
    @Query private var profili: [ProfiloImport]

    private enum Fase: Equatable {
        case scelta, lettura(String), mappatura, anteprima, fatto(Int)
    }

    @State private var fase = Fase.scelta
    @State private var scegliFile = false
    @State private var nomeFile = ""
    @State private var errore: String?
    // CSV
    @State private var righe: [[String]] = []
    @State private var mappatura = ParserEstratto.Mappatura()
    @State private var profilo: ProfiloImport?
    // anteprima
    @State private var lette: [ParserEstratto.Riga] = []
    @State private var voci: [VoceImport] = []
    @State private var contoID: PersistentIdentifier?

    private var conto: Conto? { conti.first { $0.persistentModelID == contoID } }
    private var contiAttivi: [Conto] { conti.filter { !$0.archiviato && $0.tipo != .contanti } }

    var body: some View {
        Group {
            switch fase {
            case .scelta: scelta
            case .lettura(let testo): ProgressView(testo).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .mappatura: vistaMappatura
            case .anteprima: anteprima
            case .fatto(let n): fatto(n)
            }
        }
        .navigationTitle("Importa estratto conto")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $scegliFile, allowedContentTypes: [.commaSeparatedText, .plainText, .pdf, .text]) { esito in
            if case .success(let url) = esito { Task { await apri(url) } }
        }
        .alert("Importazione", isPresented: Binding(get: { errore != nil }, set: { if !$0 { errore = nil } })) {
            Button("OK") {}
        } message: { Text(errore ?? "") }
        .task {
            if let fileURL, fase == .scelta { await apri(fileURL) }
        }
    }

    // MARK: Scelta del file

    private var scelta: some View {
        ScrollView {
            VStack(spacing: 12) {
                Scheda(titolo: "Da dove arriva") {
                    Text("Scarica l'estratto conto dall'app o dal sito della banca (CSV, Excel salvato come CSV, oppure PDF) e sceglilo qui. Puoi anche usare «Apri con Bilancio» da File o Mail.")
                        .font(.subheadline)
                    Text("I CSV si riconoscono da soli dopo la prima volta. I PDF si leggono con Apple Intelligence, se disponibile, altrimenti con regole semplici.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    scegliFile = true
                } label: {
                    Label("Scegli il file", systemImage: "doc.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func apri(_ url: URL) async {
        let accesso = url.startAccessingSecurityScopedResource()
        defer { if accesso { url.stopAccessingSecurityScopedResource() } }
        nomeFile = url.deletingPathExtension().lastPathComponent
        righe = []
        profilo = nil
        fase = .lettura(String(localized: "Leggo \(url.lastPathComponent)…"))
        let tipo = UTType(filenameExtension: url.pathExtension.lowercased())
        if tipo?.conforms(to: .pdf) == true {
            guard let pdf = PDFDocument(url: url) else { return fallito(String(localized: "Non riesco ad aprire il PDF.")) }
            let pagine = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }
            let movimenti = await LettorePDFEstratto.leggi(pagine: pagine) { fase = .lettura($0) }
            guard !movimenti.isEmpty else { return fallito(String(localized: "Nel PDF non ho trovato movimenti. Se è una scansione, prova con il CSV della banca.")) }
            mostraAnteprima(movimenti)
            return
        }
        guard let dati = try? Data(contentsOf: url) else { return fallito(String(localized: "Non riesco a leggere il file.")) }
        let testo = ParserEstratto.decodifica(dati)
        let separatore = ParserEstratto.separatore(di: testo)
        let tabella = ParserEstratto.righeCSV(testo, separatore: separatore)
        guard (tabella.map(\.count).max() ?? 0) >= 3 else {
            // testo senza colonne: stesse regole del PDF
            let movimenti = ParserEstratto.righeDaTesto(testo)
            guard !movimenti.isEmpty else { return fallito(String(localized: "Non ho riconosciuto il formato del file.")) }
            return mostraAnteprima(movimenti)
        }
        righe = tabella
        let proposta = ParserEstratto.proponiMappatura(righe: tabella, separatore: separatore)
        let firma = ParserEstratto.firma(intestazione: tabella[proposta.righeDaSaltare])
        if let p = profili.first(where: { $0.firmaIntestazione == firma }) {
            profilo = p
            mappatura = mappaturaDa(p, separatore: separatore)
            contoID = p.conto?.persistentModelID
            let movimenti = ParserEstratto.applica(mappatura, righe: righe)
            if !movimenti.isEmpty { return mostraAnteprima(movimenti) }
        }
        mappatura = proposta
        fase = .mappatura
    }

    private func fallito(_ messaggio: String) {
        errore = messaggio
        fase = .scelta
    }

    private func mappaturaDa(_ p: ProfiloImport, separatore: Character) -> ParserEstratto.Mappatura {
        ParserEstratto.Mappatura(separatore: p.separatore.first ?? separatore, righeDaSaltare: p.righeDaSaltare, colData: p.colData,
                                 colDescrizione: p.colDescrizione, colImporto: p.colImporto, colAddebito: p.colAddebito,
                                 colAccredito: p.colAccredito, formatoData: p.formatoData, virgolaDecimale: p.virgolaDecimale,
                                 invertiSegno: p.invertiSegno)
    }

    // MARK: Mappatura delle colonne (CSV nuovo)

    private var intestazione: [String] { righe.indices.contains(mappatura.righeDaSaltare) ? righe[mappatura.righeDaSaltare] : [] }

    private var vistaMappatura: some View {
        let prova = ParserEstratto.applica(mappatura, righe: righe)
        return Form {
            Section {
                Stepper("Intestazione alla riga \(mappatura.righeDaSaltare + 1)", value: $mappatura.righeDaSaltare, in: 0...max(0, min(30, righe.count - 1)))
                Text(intestazione.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            } header: { Text("File \(nomeFile)") } footer: {
                Text("Prima volta con questo formato: dimmi cosa c'è in ogni colonna. La prossima volta lo riconosco da solo.")
            }
            Section("Colonne") {
                pickerColonna("Data", selezione: $mappatura.colData)
                pickerColonna("Descrizione", selezione: $mappatura.colDescrizione)
                Picker("Importo", selection: Binding(
                    get: { mappatura.colImporto != nil },
                    set: { unico in
                        if unico { mappatura.colImporto = mappatura.colAddebito ?? 0; mappatura.colAddebito = nil; mappatura.colAccredito = nil }
                        else { mappatura.colAddebito = mappatura.colImporto ?? 0; mappatura.colAccredito = mappatura.colImporto ?? 0; mappatura.colImporto = nil }
                    })) {
                    Text("Colonna unica").tag(true)
                    Text("Dare e Avere").tag(false)
                }
                .pickerStyle(.segmented)
                if mappatura.colImporto != nil {
                    pickerColonna("Importo con segno", selezione: Binding(get: { mappatura.colImporto ?? 0 }, set: { mappatura.colImporto = $0 }))
                } else {
                    pickerColonna("Addebiti (Dare)", selezione: Binding(get: { mappatura.colAddebito ?? 0 }, set: { mappatura.colAddebito = $0 }))
                    pickerColonna("Accrediti (Avere)", selezione: Binding(get: { mappatura.colAccredito ?? 0 }, set: { mappatura.colAccredito = $0 }))
                }
            }
            Section("Formato") {
                Picker("Data", selection: $mappatura.formatoData) {
                    ForEach(ParserEstratto.formatiData, id: \.self) { Text($0.replacingOccurrences(of: "yyyy", with: String(localized: "aaaa", comment: "anno a 4 cifre nel formato data")).replacingOccurrences(of: "yy", with: String(localized: "aa", comment: "anno a 2 cifre nel formato data")).replacingOccurrences(of: "dd", with: String(localized: "gg", comment: "giorno nel formato data"))).tag($0) }
                }
                Toggle("Virgola per i decimali (1.234,56)", isOn: $mappatura.virgolaDecimale)
                Toggle("Inverti il segno (carte: positivo = spesa)", isOn: $mappatura.invertiSegno)
            }
            Section {
                ForEach(Array(prova.prefix(5).enumerated()), id: \.offset) { _, r in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(r.descrizione).lineLimit(1)
                            Text(r.data.breve).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(r.importo.euro).monospacedDigit().foregroundStyle(r.importo > 0 ? Tinta.entrate : .primary)
                    }
                }
            } header: { Text("Prova: \(prova.count) movimenti letti") }
            Section {
                Button("Continua") { salvaProfilo(); mostraAnteprima(prova) }
                    .bold()
                    .disabled(prova.isEmpty)
            }
        }
    }

    private func pickerColonna(_ titolo: LocalizedStringKey, selezione: Binding<Int>) -> some View {
        Picker(titolo, selection: selezione) {
            ForEach(intestazione.indices, id: \.self) { i in
                Text(intestazione[i].isEmpty ? String(localized: "Colonna \(i + 1)") : intestazione[i]).tag(i)
            }
        }
    }

    private func salvaProfilo() {
        let p = profilo ?? {
            let nuovo = ProfiloImport(nome: nomeFile)
            context.insert(nuovo)
            return nuovo
        }()
        p.firmaIntestazione = ParserEstratto.firma(intestazione: intestazione)
        p.separatore = String(mappatura.separatore)
        p.righeDaSaltare = mappatura.righeDaSaltare
        p.colData = mappatura.colData
        p.colDescrizione = mappatura.colDescrizione
        p.colImporto = mappatura.colImporto
        p.colAddebito = mappatura.colAddebito
        p.colAccredito = mappatura.colAccredito
        p.formatoData = mappatura.formatoData
        p.virgolaDecimale = mappatura.virgolaDecimale
        p.invertiSegno = mappatura.invertiSegno
        profilo = p
    }

    // MARK: Anteprima

    private func mostraAnteprima(_ movimenti: [ParserEstratto.Riga]) {
        lette = movimenti
        ricalcola()
        fase = .anteprima
    }

    /// Classifica le righe e segna i duplicati (stesso idEsterno, movimento già esistente o già arrivato dalla banca).
    private func ricalcola() {
        let ids = ParserEstratto.idEsterni(lette)
        voci = zip(lette, ids).map { r, id in
            let idOpzionale: String? = id
            let giaImportato = ((try? context.fetchCount(FetchDescriptor<Movimento>(predicate: #Predicate { $0.idEsterno == idOpzionale }))) ?? 0) > 0
            let esistente = Abbinamento.movimentoEsistentePer(importo: r.importo, data: r.data, conto: conto, in: context)
            let daBanca = conto.map { c in
                Contabilita.movimenti(da: r.data.aggiungendo(giorni: -1), a: r.data.aggiungendo(giorni: 2), in: context).contains {
                    $0.idEsterno != nil && $0.conto?.persistentModelID == c.persistentModelID && abs($0.importo - r.importo) < 0.011
                }
            } ?? false
            let s = Classificatore.suggerisciBanca(descrizione: r.descrizione, importo: r.importo, in: context)
            let duplicato = giaImportato || esistente != nil || daBanca
            return VoceImport(riga: r, idEsterno: id, suggerimento: s, duplicato: duplicato, esistente: esistente, selezionata: !duplicato)
        }
    }

    private var anteprima: some View {
        let selezionate = voci.filter(\.selezionata).count
        return List {
            Section {
                Picker("Conto", selection: $contoID) {
                    Text("Scegli…").tag(PersistentIdentifier?.none)
                    ForEach(contiAttivi) { c in Text(c.nome).tag(Optional(c.persistentModelID)) }
                }
                .onChange(of: contoID) { ricalcola() }
            } footer: {
                Text("\(voci.count) movimenti letti, \(voci.filter(\.duplicato).count) già presenti (deselezionati). Scorri su una riga per invertirne il segno.")
            }
            Section {
                ForEach($voci) { $v in
                    Button { v.selezionata.toggle() } label: { RigaVoceImport(voce: v) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Inverti segno") { inverti(v.id) }.tint(.orange)
                        }
                }
            }
        }
        .toolbar {
            if !righe.isEmpty { Button("Colonne") { fase = .mappatura } }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                importa()
            } label: {
                Text(selezionate == 1 ? "Importa 1 movimento" : "Importa \(selezionate) movimenti").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(conto == nil || selezionate == 0)
            .padding()
            .background(.bar)
        }
    }

    /// Inverte il segno di una riga (PDF senza Dare/Avere): voci e lette hanno gli stessi indici.
    private func inverti(_ id: UUID) {
        guard let i = voci.firstIndex(where: { $0.id == id }) else { return }
        lette[i].importo = -lette[i].importo
        voci[i].riga = lette[i]
        voci[i].idEsterno = ParserEstratto.idEsterni(lette)[i]
        voci[i].suggerimento = Classificatore.suggerisciBanca(descrizione: lette[i].descrizione, importo: lette[i].importo, in: context)
    }

    private func importa() {
        guard let conto else { return }
        var n = 0
        for v in voci {
            if v.selezionata {
                Sincronizzazione.creaMovimento(data: v.riga.data, importo: v.riga.importo, descrizione: v.riga.descrizione, idEsterno: v.idEsterno,
                                               conto: conto, origine: .estratto, suggerimento: v.suggerimento, in: context)
                n += 1
            } else if let e = v.esistente, e.idEsterno == nil {
                // stesso pagamento già registrato (scontrino, ricorrenza…): lo collego all'estratto
                e.idEsterno = v.idEsterno
                e.descrizioneOriginale = v.riga.descrizione
                if e.conto == nil { e.conto = conto }
            }
        }
        profilo?.conto = conto
        Contabilita.aggiornaSnapshot(in: context)
        try? context.save()
        fase = .fatto(n)
    }

    private func fatto(_ n: Int) -> some View {
        ContentUnavailableView {
            Label(n == 1 ? "1 movimento importato" : "\(n) movimenti importati", systemImage: "checkmark.circle")
        } description: {
            Text("Li trovi da confermare nel mese, con tipo e categoria già proposti.")
        } actions: {
            Button("Fine") { dismiss() }.buttonStyle(.borderedProminent)
            Button("Importa un altro file") { fase = .scelta; scegliFile = true }
        }
    }
}

fileprivate struct VoceImport: Identifiable {
    let id = UUID()
    var riga: ParserEstratto.Riga
    var idEsterno: String
    var suggerimento: Suggerimento
    let duplicato: Bool
    let esistente: Movimento?
    var selezionata: Bool
}

fileprivate struct RigaVoceImport: View {
    let voce: VoceImport

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: voce.selezionata ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(voce.selezionata ? Color.accentColor : .secondary)
            IconaCategoria(categoria: voce.suggerimento.categoria, dimensione: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(voce.suggerimento.titolo).lineLimit(1)
                Text(dettagli).font(.caption).foregroundStyle(voce.duplicato ? .orange : .secondary).lineLimit(1)
            }
            Spacer()
            Text(voce.riga.importo.euro).font(.callout.monospacedDigit())
                .foregroundStyle(voce.riga.importo > 0 ? Tinta.entrate : .primary)
        }
        .contentShape(Rectangle())
    }

    private var dettagli: String {
        var parti = [voce.riga.data.giornoMese, voce.suggerimento.categoria?.nome ?? voce.suggerimento.tipo.etichetta]
        if voce.suggerimento.prelievoContanti { parti.append("→ \(DatiIniziali.localizzato("Contanti"))") }
        if voce.duplicato { parti.append(String(localized: "già presente")) }
        return parti.joined(separator: " · ")
    }
}

// MARK: - PDF

/// Movimenti da un PDF: Apple Intelligence su pezzi brevi (il contesto del modello è ~4k token),
/// con le regole di `ParserEstratto.righeDaTesto` dove il modello non c'è o sbaglia.
fileprivate enum LettorePDFEstratto {

    static func leggi(pagine: [String], avanzamento: (String) -> Void) async -> [ParserEstratto.Riga] {
        guard case .available = SystemLanguageModel.default.availability else {
            return pagine.flatMap(ParserEstratto.righeDaTesto)
        }
        var risultato: [ParserEstratto.Riga] = []
        for (i, pagina) in pagine.enumerated() {
            avanzamento(String(localized: "Leggo la pagina \(i + 1) di \(pagine.count)…"))
            for pezzo in pezzi(pagina) {
                if let letti = try? await chiediAlModello(pezzo), !letti.isEmpty {
                    risultato += letti
                } else {
                    risultato += ParserEstratto.righeDaTesto(pezzo)
                }
            }
        }
        return risultato
    }

    /// Mezza pagina circa per volta, tagliando sugli a capo.
    private static func pezzi(_ testo: String, massimo: Int = 2000) -> [String] {
        var pezzi: [String] = []
        var corrente = ""
        for riga in testo.components(separatedBy: .newlines) {
            if corrente.count + riga.count > massimo, !corrente.isEmpty {
                pezzi.append(corrente)
                corrente = ""
            }
            corrente += riga + "\n"
        }
        if !corrente.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pezzi.append(corrente) }
        return pezzi
    }

    private static func chiediAlModello(_ testo: String) async throws -> [ParserEstratto.Riga] {
        let sessione = LanguageModelSession(instructions: """
            Estrai i movimenti da un pezzo di estratto conto bancario italiano. \
            Ignora intestazioni, saldi iniziali e finali, totali e righe senza importo. \
            Le uscite (addebiti, Dare, pagamenti, prelievi) hanno importo negativo, le entrate (accrediti, Avere) positivo.
            """)
        let risposta = try await sessione.respond(to: testo, generating: MovimentiLettiIA.self)
        return risposta.content.movimenti.compactMap { m in
            guard let data = ["dd/MM/yyyy", "dd/MM/yy", "yyyy-MM-dd", "dd.MM.yyyy"].lazy.compactMap({ ParserEstratto.leggiData(m.data, formato: $0) }).first,
                  m.importo != 0, !m.descrizione.isEmpty else { return nil }
            return ParserEstratto.Riga(data: data, descrizione: m.descrizione, importo: m.importo.centesimi)
        }
    }
}

@Generable(description: "Un movimento dell'estratto conto")
fileprivate struct MovimentoLettoIA {
    @Guide(description: "Data dell'operazione, formato gg/mm/aaaa")
    var data: String
    @Guide(description: "Descrizione dell'operazione come è scritta")
    var descrizione: String
    @Guide(description: "Importo in euro con segno: negativo per le uscite, positivo per le entrate")
    var importo: Double
}

@Generable(description: "I movimenti trovati nel testo")
fileprivate struct MovimentiLettiIA {
    @Guide(description: "Tutti i movimenti, nell'ordine; lista vuota se non ce ne sono")
    var movimenti: [MovimentoLettoIA]
}
