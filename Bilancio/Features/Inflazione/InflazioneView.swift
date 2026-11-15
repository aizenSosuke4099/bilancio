import SwiftUI
import SwiftData
import Charts

// MARK: - Dati

/// Un acquisto di un prodotto, letto da una riga di scontrino.
private struct AcquistoInflazione: Identifiable {
    let id: PersistentIdentifier
    let data: Date
    let negozio: String
    let testo: String
    let prezzoConfezione: Double
    /// Nell'unità del prodotto (€/kg, €/l, €/pz).
    let prezzo: Double
    let quantita: Double
    let totale: Double
}

private struct VoceInflazione: Identifiable {
    let prodotto: Prodotto
    let acquisti: [AcquistoInflazione]

    var id: PersistentIdentifier { prodotto.persistentModelID }
    var primo: Double { acquisti.first?.prezzo ?? 0 }
    var ultimo: Double { acquisti.last?.prezzo ?? 0 }
    var variazione: Double { primo > 0 ? ultimo / primo - 1 : 0 }
    var serie: [CalcoloInflazione.Acquisto] { acquisti.map { .init(data: $0.data, prezzo: $0.prezzo, spesa: $0.totale) } }
    var spesaAnno: Double {
        let inizio = Date().aggiungendo(mesi: -12)
        return acquisti.filter { $0.data >= inizio }.reduce(0) { $0 + $1.totale }
    }
    var dateDiverse: Int { Set(acquisti.map { calendario.startOfDay(for: $0.data) }).count }

    init(_ prodotto: Prodotto) {
        self.prodotto = prodotto
        acquisti = prodotto.righe.compactMap { r in
            guard let s = r.scontrino else { return nil }
            let confezione = r.prezzoUnitario > 0 ? r.prezzoUnitario : (r.quantita > 0 ? r.totale / r.quantita : r.totale)
            return AcquistoInflazione(
                id: r.persistentModelID, data: s.data, negozio: s.negozio, testo: r.testo, prezzoConfezione: confezione,
                prezzo: CalcoloInflazione.prezzoConfrontabile(prezzoConfezione: confezione, testo: r.testo, unita: prodotto.unita, formato: prodotto.formato),
                quantita: r.quantita, totale: r.totale)
        }
        .sorted { $0.data < $1.data }
    }
}

private func etichettaUnita(_ p: Prodotto) -> String {
    p.unita == "pz" ? (p.formato == nil ? "a confezione" : "€/pz") : "€/\(p.unita)"
}

private func coloreVariazione(_ v: Double) -> Color {
    v > 0.005 ? Tinta.spese : (v < -0.005 ? Tinta.entrate : .secondary)
}

// MARK: - Pagina

struct InflazioneView: View {
    @Query(sort: \Prodotto.nome) private var prodotti: [Prodotto]
    @Query(sort: \Categoria.ordine) private var categorie: [Categoria]
    @AppStorage("istat.inflazione") private var istat: Double = 0
    @State private var ricerca = ""
    @State private var categoriaScelta: PersistentIdentifier?
    @State private var negozioScelto: String?
    @State private var perSpesa = false

    private enum Ordine: String, CaseIterable { case variazione = "Variazione", spesa = "Spesa" }

    var body: some View {
        let tutte = prodotti.map { VoceInflazione($0) }.filter { $0.dateDiverse >= 2 }
        let voci = filtra(tutte)
        let inflazione = CalcoloInflazione.inflazionePersonale(voci.map(\.serie), oggi: Date())

        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    RiquadroKPI(titolo: "Inflazione personale",
                                valore: inflazione.map { $0.valore.percentoConSegno } ?? "—",
                                nota: inflazione.map { "su \($0.prodotti) prodotti, ultimi 12 mesi" } ?? "servono più acquisti ripetuti",
                                colore: inflazione.map { coloreVariazione($0.valore) } ?? .secondary)
                    RiquadroKPI(titolo: "ISTAT",
                                valore: istat > 0 ? (istat / 100).percento : "—",
                                nota: notaISTAT(inflazione?.valore),
                                coloreNota: inflazione.map { istat > 0 && $0.valore > istat / 100 ? Tinta.spese : .secondary } ?? .secondary)
                }

                let indice = indiceMensile(voci)
                if indice.count > 1 {
                    Scheda(titolo: "Indice dei tuoi prezzi", etichetta: "base 100") {
                        Chart {
                            RuleMark(y: .value("Base", 100)).foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(dash: [4, 4]))
                            ForEach(indice, id: \.mese) { p in
                                LineMark(x: .value("Mese", p.mese, unit: .month), y: .value("Indice", p.indice))
                                    .interpolationMethod(.monotone)
                                PointMark(x: .value("Mese", p.mese, unit: .month), y: .value("Indice", p.indice)).symbolSize(18)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 170)
                    }
                }

                filtri(tutte)

                Scheda(titolo: "Prodotti", etichetta: "\(voci.count)") {
                    if voci.isEmpty {
                        Text(tutte.isEmpty ? "Scansiona qualche scontrino: i prodotti comprati almeno due volte compaiono qui." : "Nessun prodotto con questi filtri.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(voci) { v in
                        NavigationLink { DettaglioProdottoInflazione(prodotto: v.prodotto) } label: { RigaProdottoInflazione(voce: v) }
                            .buttonStyle(.plain)
                        if v.id != voci.last?.id { Divider() }
                    }
                }

                Text("""
                Come si calcola: per ogni prodotto comprato in almeno due giorni diversi si confronta il prezzo medio degli ultimi 3 mesi \
                con quello di un anno prima (acquisti tra 9 e 15 mesi prima). Se lo storico è più breve si confronta il primo acquisto con l'ultimo \
                e la variazione viene riportata su base annua (servono almeno 3 mesi di distanza). Il prezzo è al kg o al litro quando il formato \
                è noto, così anche le confezioni più piccole allo stesso prezzo contano. L'inflazione personale è la media delle variazioni pesata \
                su quanto hai speso per ciascun prodotto negli ultimi 12 mesi. L'indice concatena mese per mese le variazioni medie dei prezzi.
                """)
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Inflazione")
        .searchable(text: $ricerca, prompt: "Cerca un prodotto")
        .toolbar {
            NavigationLink { GestioneProdottiInflazione() } label: { Label("Gestisci prodotti", systemImage: "slider.horizontal.3") }
        }
        .task {
            #if DEBUG
            CalcoloInflazione.autoverifica()
            #endif
        }
    }

    private func filtri(_ tutte: [VoceInflazione]) -> some View {
        let negozi = Set(tutte.flatMap { $0.acquisti.map(\.negozio) }).sorted()
        let categorieUsate = categorie.filter { c in tutte.contains { $0.prodotto.categoria?.persistentModelID == c.persistentModelID } }
        return HStack {
            Picker("Categoria", selection: $categoriaScelta) {
                Text("Tutte le categorie").tag(PersistentIdentifier?.none)
                ForEach(categorieUsate) { c in Text(c.nome).tag(Optional(c.persistentModelID)) }
            }
            Picker("Negozio", selection: $negozioScelto) {
                Text("Tutti i negozi").tag(String?.none)
                ForEach(negozi, id: \.self) { n in Text(n).tag(Optional(n)) }
            }
            Spacer()
            Picker("Ordina", selection: $perSpesa) {
                Text("Per variazione").tag(false)
                Text("Per spesa").tag(true)
            }
        }
        .pickerStyle(.menu)
        .font(.subheadline)
    }

    private func filtra(_ voci: [VoceInflazione]) -> [VoceInflazione] {
        let filtrate = voci.compactMap { v -> VoceInflazione? in
            if let c = categoriaScelta, v.prodotto.categoria?.persistentModelID != c { return nil }
            if !ricerca.isEmpty, !v.prodotto.nome.localizedStandardContains(ricerca) { return nil }
            guard let n = negozioScelto else { return v }
            // con un negozio scelto si guardano solo i suoi acquisti
            let solo = VoceFiltrata(v, negozio: n)
            return solo.dateDiverse >= 2 ? solo : nil
        }
        return perSpesa ? filtrate.sorted { $0.spesaAnno > $1.spesaAnno } : filtrate.sorted { $0.variazione > $1.variazione }
    }

    private func indiceMensile(_ voci: [VoceInflazione]) -> [(mese: Date, indice: Double)] {
        guard let primo = voci.compactMap({ $0.acquisti.first?.data }).min() else { return [] }
        let corrente = Date().inizioMese
        var mese = max(primo.inizioMese, corrente.aggiungendo(mesi: -23))
        var mesi: [Date] = []
        while mese <= corrente { mesi.append(mese); mese = mese.aggiungendo(mesi: 1) }
        return CalcoloInflazione.indiceMensile(voci.map(\.serie), mesi: mesi)
    }

    private func notaISTAT(_ personale: Double?) -> String {
        guard istat > 0 else { return "imposta il dato in Impostazioni" }
        guard let personale else { return "inflazione ufficiale annua" }
        let punti = personale * 100 - istat
        return "tu: \(punti >= 0 ? "+" : "")\(punti.formatted(.number.precision(.fractionLength(1)).locale(localeIT))) punti"
    }
}

/// Stessa voce, limitata agli acquisti di un negozio.
private func VoceFiltrata(_ v: VoceInflazione, negozio: String) -> VoceInflazione {
    VoceInflazione(prodotto: v.prodotto, acquisti: v.acquisti.filter { $0.negozio == negozio })
}

private extension VoceInflazione {
    init(prodotto: Prodotto, acquisti: [AcquistoInflazione]) {
        self.prodotto = prodotto
        self.acquisti = acquisti
    }
}

private struct RigaProdottoInflazione: View {
    let voce: VoceInflazione

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(voce.prodotto.nome).font(.subheadline).lineLimit(1)
                Text("\(voce.acquisti.count) acquisti · da \(voce.primo.euro) a \(voce.ultimo.euro)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Chart(voce.acquisti) { a in
                LineMark(x: .value("Data", a.data), y: .value("Prezzo", a.prezzo))
                    .foregroundStyle(coloreVariazione(voce.variazione))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(width: 56, height: 24)
            Text(voce.variazione.percentoConSegno)
                .font(.callout.monospacedDigit().bold())
                .foregroundStyle(coloreVariazione(voce.variazione))
                .frame(width: 64, alignment: .trailing)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

// MARK: - Dettaglio prodotto

private struct DettaglioProdottoInflazione: View {
    let prodotto: Prodotto

    var body: some View {
        let voce = VoceInflazione(prodotto)
        let unita = etichettaUnita(prodotto)
        let sgrammatura = CalcoloInflazione.sgrammatura(voce.acquisti.map { ($0.data, $0.prezzoConfezione, $0.testo) })
        let perNegozio = Dictionary(grouping: voce.acquisti, by: \.negozio)
            .map { (negozio: $0.key, media: $0.value.reduce(0) { $0 + $1.prezzo } / Double($0.value.count)) }
            .sorted { $0.media < $1.media }

        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    RiquadroKPI(titolo: "Ultimo prezzo", valore: (voce.acquisti.last?.prezzoConfezione ?? 0).euro,
                                nota: voce.acquisti.last.map { "\($0.data.breve) · \($0.negozio)" })
                    RiquadroKPI(titolo: "Variazione", valore: voce.variazione.percentoConSegno,
                                nota: "dal primo acquisto", colore: coloreVariazione(voce.variazione))
                    if prodotto.unita != "pz" || prodotto.formato != nil {
                        RiquadroKPI(titolo: "Prezzo \(unita)", valore: voce.ultimo.euro, nota: "ultimo acquisto")
                    }
                }

                if let s = sgrammatura {
                    Label {
                        Text("Sgrammatura: dal \(s.data.breve) la confezione è passata da \(quantita(s.prima, s.unita)) a \(quantita(s.dopo, s.unita)) a un prezzo simile. Al \(s.unita == "kg" ? "kg" : "litro") costa il \(s.aumentoEffettivo.percento) in più.")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Scheda(titolo: "Prezzo nel tempo", etichetta: unita) {
                    Chart(voce.acquisti) { a in
                        LineMark(x: .value("Data", a.data), y: .value("Prezzo", a.prezzo))
                            .foregroundStyle(.gray.opacity(0.6))
                        PointMark(x: .value("Data", a.data), y: .value("Prezzo", a.prezzo))
                            .foregroundStyle(by: .value("Negozio", a.negozio))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartLegend(position: .bottom)
                    .frame(height: 200)
                }

                if perNegozio.count > 1, let migliore = perNegozio.first, let peggiore = perNegozio.last {
                    Scheda(titolo: "Dove conviene", etichetta: "prezzo medio \(unita)") {
                        ForEach(perNegozio, id: \.negozio) { n in
                            HStack {
                                if n.negozio == migliore.negozio { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                                Text(n.negozio)
                                Spacer()
                                Text(n.media.euro).monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                        Text("\(migliore.negozio) costa in media il \((1 - migliore.media / peggiore.media).percento) in meno di \(peggiore.negozio).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Scheda(titolo: "Acquisti", etichetta: "\(voce.acquisti.count)") {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        GridRow {
                            Text("Data"); Text("Negozio"); Text("Prezzo").gridColumnAlignment(.trailing); Text("Q.tà").gridColumnAlignment(.trailing)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        ForEach(voce.acquisti.reversed()) { a in
                            GridRow {
                                Text(a.data.breve)
                                Text(a.negozio).lineLimit(1)
                                Text(a.prezzoConfezione.euro).monospacedDigit()
                                Text(a.quantita.quote).monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(prodotto.nome)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink { ModificaProdottoInflazione(prodotto: prodotto) } label: { Text("Modifica") }
        }
    }

    private func quantita(_ q: Double, _ unita: String) -> String {
        q < 1 ? "\((q * 1000).formatted(.number.precision(.fractionLength(0)).locale(localeIT))) \(unita == "kg" ? "g" : "ml")"
              : "\(q.quote) \(unita)"
    }
}

// MARK: - Gestione prodotti

private struct GestioneProdottiInflazione: View {
    @Query(sort: \Prodotto.nome) private var prodotti: [Prodotto]
    @State private var ricerca = ""

    var body: some View {
        let elenco = ricerca.isEmpty ? prodotti : prodotti.filter { $0.nome.localizedStandardContains(ricerca) }
        List(elenco) { p in
            NavigationLink { ModificaProdottoInflazione(prodotto: p) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.nome)
                    Text("\(p.righe.count) righe · \(p.unita)\(p.formato.map { " · formato \($0.quote)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .overlay { if prodotti.isEmpty { ContentUnavailableView("Nessun prodotto", systemImage: "cart", description: Text("I prodotti nascono dalle righe degli scontrini.")) } }
        .navigationTitle("Prodotti")
        .searchable(text: $ricerca, prompt: "Cerca")
    }
}

private struct ModificaProdottoInflazione: View {
    @Bindable var prodotto: Prodotto
    @Environment(\.modelContext) private var context
    @Query(sort: \Categoria.ordine) private var categorie: [Categoria]
    @State private var nome = ""
    @State private var sceltaUnione = false

    var body: some View {
        Form {
            Section("Nome") {
                TextField("Nome del prodotto", text: $nome)
                    .onSubmit(rinomina)
            }
            Section {
                Picker("Unità", selection: $prodotto.unita) {
                    Text("Pezzi").tag("pz")
                    Text("Chilogrammi").tag("kg")
                    Text("Litri").tag("l")
                }
                TextField("Formato (es. 0,5 per 500 g)", value: $prodotto.formato, format: .number.locale(localeIT))
                    .keyboardType(.decimalPad)
                Picker("Categoria", selection: $prodotto.categoria) {
                    Text("Nessuna").tag(Categoria?.none)
                    ForEach(categorie.filter { $0.tipo == .spesa }) { c in Text(c.nome).tag(Optional(c)) }
                }
            } header: {
                Text("Formato")
            } footer: {
                Text("Quantità di una confezione nell'unità scelta: serve per il prezzo al kg o al litro. Se la riga dello scontrino riporta il formato (es. \"500G\"), vale quello.")
            }
            Section {
                Button { sceltaUnione = true } label: { Label("Unisci un altro prodotto in questo…", systemImage: "arrow.triangle.merge") }
            } footer: {
                Text("Utile quando lo stesso prodotto è stato registrato con nomi diversi: le righe dell'altro passano qui e l'altro viene eliminato.")
            }
        }
        .navigationTitle("Modifica prodotto")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { nome = prodotto.nome }
        .onDisappear(perform: rinomina)
        .sheet(isPresented: $sceltaUnione) {
            NavigationStack { SceltaProdottoDaUnire(destinazione: prodotto) }
        }
    }

    private func rinomina() {
        let nuovo = nome.trimmingCharacters(in: .whitespaces)
        guard !nuovo.isEmpty, nuovo != prodotto.nome else { return }
        aggiornaRegole(da: prodotto.nome, a: nuovo, in: context)
        prodotto.nome = nuovo
        try? context.save()
    }
}

/// Le regole imparate puntano al prodotto per nome: vanno tenute allineate.
private func aggiornaRegole(da vecchio: String, a nuovo: String, in context: ModelContext) {
    for r in (try? context.fetch(FetchDescriptor<RegolaAppresa>())) ?? [] where r.nomeProdotto == vecchio { r.nomeProdotto = nuovo }
}

private struct SceltaProdottoDaUnire: View {
    let destinazione: Prodotto
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Prodotto.nome) private var prodotti: [Prodotto]
    @State private var ricerca = ""
    @State private var daUnire: Prodotto?

    var body: some View {
        let altri = prodotti.filter { $0.persistentModelID != destinazione.persistentModelID && (ricerca.isEmpty || $0.nome.localizedStandardContains(ricerca)) }
        List(altri) { p in
            Button { daUnire = p } label: {
                VStack(alignment: .leading) {
                    Text(p.nome).foregroundStyle(.primary)
                    Text("\(p.righe.count) righe").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Unisci in \(destinazione.nome)")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $ricerca)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
        .confirmationDialog("Unire i prodotti?", isPresented: Binding(get: { daUnire != nil }, set: { if !$0 { daUnire = nil } }), titleVisibility: .visible) {
            Button("Unisci") { unisci() }
        } message: {
            Text("Le righe di «\(daUnire?.nome ?? "")» passano a «\(destinazione.nome)», poi «\(daUnire?.nome ?? "")» viene eliminato.")
        }
    }

    private func unisci() {
        guard let altro = daUnire else { return }
        for r in Array(altro.righe) { r.prodotto = destinazione }
        if destinazione.formato == nil, destinazione.unita == altro.unita { destinazione.formato = altro.formato }
        if destinazione.categoria == nil { destinazione.categoria = altro.categoria }
        aggiornaRegole(da: altro.nome, a: destinazione.nome, in: context)
        context.delete(altro)
        try? context.save()
        dismiss()
    }
}
