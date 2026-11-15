import SwiftUI
import SwiftData

/// Pagamenti ed entrate ricorrenti, piani di accumulo e ricorrenti "scovati" nei movimenti.
/// Pushata dalla scheda Altro.
struct RicorrentiView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Ricorrenza.giorno) private var ricorrenze: [Ricorrenza]
    @Query(filter: #Predicate<PianoPAC> { $0.attivo }) private var piani: [PianoPAC]

    @State private var modifica: RicorrenzaDaModificare?
    @State private var rilevati: [CandidatoRicorrente] = []

    private var attive: [Ricorrenza] { ricorrenze.filter(\.attiva) }
    private func alMese(_ tipo: TipoMovimento) -> Double {
        attive.filter { $0.tipo == tipo }.reduce(0) { $0 + $1.importoAnnuo / 12 }
    }

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    RiquadroKPI(titolo: "Uscite al mese", valore: alMese(.spesa).euro, nota: "\((alMese(.spesa) * 12).euroTondo) all'anno", colore: Tinta.spese)
                    RiquadroKPI(titolo: "Entrate al mese", valore: alMese(.entrata).euro, nota: "\((alMese(.entrata) * 12).euroTondo) all'anno", colore: Tinta.entrate)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                if ricorrenze.isEmpty {
                    Text("Nessun ricorrente. Aggiungi stipendio, affitto, abbonamenti: ogni mese li trovi da confermare.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(ricorrenze) { r in
                    Button { modifica = RicorrenzaDaModificare(ricorrenza: r) } label: { RigaRicorrenza(ricorrenza: r) }
                        .buttonStyle(.plain)
                }
                .onDelete { indici in
                    indici.map { ricorrenze[$0] }.forEach(context.delete)
                    try? context.save()
                }
            } header: { Text("Ricorrenti") }

            if !piani.isEmpty {
                Section {
                    ForEach(piani) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.nome)
                                Text("Ogni mese il \(p.giorno) · \(p.conto?.nome ?? p.piattaforma)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(p.importoMensile.euro).monospacedDigit().foregroundStyle(Tinta.investito)
                        }
                    }
                } header: { Text("Piani di accumulo") } footer: {
                    Text("\((piani.reduce(0) { $0 + $1.importoMensile } * 12).euroTondo) all'anno. Si gestiscono in Investimenti.")
                }
            }

            if !rilevati.isEmpty {
                Section {
                    ForEach(rilevati) { c in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(c.titolo).bold()
                                Spacer()
                                Text(c.importo.euro).monospacedDigit()
                            }
                            Text("In \(c.mesi) mesi diversi · ultimo il \(c.ultimo.data.giornoMese) · \(etichettaFrequenza(c.ogniMesi).lowercased())")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Trasforma in ricorrente") { trasforma(c) }
                                .font(.callout)
                                .buttonStyle(.borderless)
                        }
                    }
                } header: { Text("Ricorrenti rilevati") } footer: {
                    Text("Movimenti con lo stesso nome e importo simile in almeno 3 mesi. Controlla che non siano abbonamenti dimenticati.")
                }
            }
        }
        .navigationTitle("Pagamenti ricorrenti")
        .toolbar {
            Button("Aggiungi", systemImage: "plus") { modifica = RicorrenzaDaModificare(ricorrenza: nil) }
        }
        .sheet(item: $modifica, onDismiss: rileva) { m in
            NavigationStack { EditorRicorrenza(ricorrenza: m.ricorrenza) }
        }
        .onAppear(perform: rileva)
    }

    private func rileva() {
        rilevati = RilevatoreRicorrenti.candidati(in: context, ricorrenze: ricorrenze)
    }

    private func trasforma(_ c: CandidatoRicorrente) {
        let r = Ricorrenza(nome: c.titolo, importo: c.importo, tipo: c.ultimo.tipo, giorno: c.ultimo.data.giorno, ogniMesi: c.ogniMesi)
        r.conto = c.ultimo.conto
        r.categoria = c.ultimo.categoria
        // il mese dell'ultimo movimento è già coperto: il prossimo lo propone il generatore
        r.ultimaGenerazione = c.ultimo.data.inizioMese
        context.insert(r)
        c.movimenti.forEach { $0.ricorrenza = r }
        try? context.save()
        rileva()
    }
}

fileprivate struct RicorrenzaDaModificare: Identifiable {
    let id = UUID()
    let ricorrenza: Ricorrenza?
}

fileprivate func etichettaFrequenza(_ ogniMesi: Int) -> String {
    switch ogniMesi {
    case 1: "Mensile"
    case 2: "Bimestrale"
    case 3: "Trimestrale"
    case 6: "Semestrale"
    case 12: "Annuale"
    default: "Ogni \(ogniMesi) mesi"
    }
}

fileprivate struct RigaRicorrenza: View {
    let ricorrenza: Ricorrenza

    var body: some View {
        HStack(spacing: 10) {
            IconaCategoria(categoria: ricorrenza.categoria)
            VStack(alignment: .leading, spacing: 2) {
                Text(ricorrenza.nome).lineLimit(1)
                Text(dettagli).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ricorrenza.importo.euro).monospacedDigit()
                    .foregroundStyle(ricorrenza.importo > 0 ? Tinta.entrate : .primary)
                if ricorrenza.ogniMesi > 1 {
                    Text("\(ricorrenza.importoAnnuo.euroTondo)/anno").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .opacity(ricorrenza.attiva ? 1 : 0.45)
        .contentShape(Rectangle())
    }

    private var dettagli: String {
        var parti = ["\(etichettaFrequenza(ricorrenza.ogniMesi)), il \(ricorrenza.giorno)"]
        if let c = ricorrenza.categoria { parti.append(c.nome) }
        if let c = ricorrenza.conto { parti.append(c.nome) }
        if !ricorrenza.attiva { parti.append("in pausa") }
        return parti.joined(separator: " · ")
    }
}

// MARK: - Editor

fileprivate struct EditorRicorrenza: View {
    let ricorrenza: Ricorrenza?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Categoria.ordine) private var categorie: [Categoria]
    @Query(sort: \Conto.ordine) private var conti: [Conto]

    @State private var nome = ""
    @State private var importo = ""
    @State private var tipo = TipoMovimento.spesa
    @State private var ogniMesi = 1
    @State private var giorno = 1
    @State private var categoriaID: PersistentIdentifier?
    @State private var contoID: PersistentIdentifier?
    @State private var attiva = true

    var body: some View {
        Form {
            Section {
                TextField("Nome (es. Netflix, Affitto)", text: $nome)
                TextField("Importo", text: $importo).keyboardType(.decimalPad)
                Picker("Tipo", selection: $tipo) {
                    ForEach(TipoMovimento.allCases) { Text($0.etichetta).tag($0) }
                }
            }
            Section {
                Picker("Frequenza", selection: $ogniMesi) {
                    ForEach([1, 2, 3, 6, 12], id: \.self) { Text(etichettaFrequenza($0)).tag($0) }
                }
                Stepper("Il giorno \(giorno) del mese", value: $giorno, in: 1...31)
                Picker("Categoria", selection: $categoriaID) {
                    Text("Nessuna").tag(PersistentIdentifier?.none)
                    ForEach(categorie.filter { tipo == .spesa || tipo == .entrata ? $0.tipo == tipo : true }) { c in
                        Text(c.nome).tag(Optional(c.persistentModelID))
                    }
                }
                Picker("Conto", selection: $contoID) {
                    Text("Nessuno").tag(PersistentIdentifier?.none)
                    ForEach(conti.filter { !$0.archiviato }) { c in Text(c.nome).tag(Optional(c.persistentModelID)) }
                }
                Toggle("Attiva", isOn: $attiva)
            } footer: {
                Text("Ogni volta che arriva il giorno, il movimento compare da confermare. Se poi la banca porta lo stesso pagamento, vengono uniti.")
            }
            if let ricorrenza {
                Section {
                    Button("Elimina ricorrente", role: .destructive) {
                        context.delete(ricorrenza)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(ricorrenza == nil ? "Nuovo ricorrente" : "Ricorrente")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva", action: salva).disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty || leggiNumero(importo) == nil)
            }
        }
        .onAppear(perform: carica)
    }

    private func carica() {
        guard let r = ricorrenza else { return }
        nome = r.nome
        importo = abs(r.importo).formatted(.number.precision(.fractionLength(2)).locale(localeIT))
        tipo = r.tipo
        ogniMesi = r.ogniMesi
        giorno = r.giorno
        categoriaID = r.categoria?.persistentModelID
        contoID = r.conto?.persistentModelID
        attiva = r.attiva
    }

    private func salva() {
        let valore = abs(leggiNumero(importo) ?? 0)
        let r = ricorrenza ?? {
            let nuova = Ricorrenza(nome: "", importo: 0, tipo: tipo, giorno: giorno)
            context.insert(nuova)
            return nuova
        }()
        r.nome = nome.trimmingCharacters(in: .whitespaces)
        r.importo = tipo == .entrata ? valore : -valore
        r.tipo = tipo
        r.ogniMesi = ogniMesi
        r.giorno = giorno
        r.categoria = categorie.first { $0.persistentModelID == categoriaID }
        r.conto = conti.first { $0.persistentModelID == contoID }
        r.attiva = attiva
        try? context.save()
        dismiss()
    }
}

// MARK: - Rilevamento

fileprivate struct CandidatoRicorrente: Identifiable {
    let titolo: String
    /// Importo tipico (mediana), con segno.
    let importo: Double
    let mesi: Int
    let ogniMesi: Int
    let ultimo: Movimento
    let movimenti: [Movimento]
    var id: String { titolo + "|" + String(importo) }
}

fileprivate enum RilevatoreRicorrenti {
    /// Stesso titolo e importo entro ±10% in almeno 3 mesi diversi dell'ultimo anno, non già legati a una ricorrenza.
    static func candidati(in context: ModelContext, ricorrenze: [Ricorrenza]) -> [CandidatoRicorrente] {
        let da = Date().inizioMese.aggiungendo(mesi: -12)
        let movimenti = Contabilita.movimenti(da: da, a: Date().inizioMeseSuccessivo, in: context).filter {
            $0.ricorrenza == nil && $0.tipo != .giroconto && !$0.titolo.isEmpty
        }
        let coperti = Set(ricorrenze.map { Classificatore.normalizza($0.nome) })
        var risultato: [CandidatoRicorrente] = []
        for (chiave, gruppo) in Dictionary(grouping: movimenti, by: { Classificatore.normalizza($0.titolo) })
        where gruppo.count >= 3 && !coperti.contains(chiave) {
            // gruppi di importi simili: ognuno entro il 10% del primo
            var simili: [[Movimento]] = []
            for m in gruppo.sorted(by: { $0.importo < $1.importo }) {
                if let base = simili.last?.first, abs(m.importo - base.importo) <= abs(base.importo) * 0.10 {
                    simili[simili.count - 1].append(m)
                } else {
                    simili.append([m])
                }
            }
            for s in simili {
                let mesi = Set(s.map { $0.data.inizioMese }).sorted()
                guard mesi.count >= 3, let ultimo = s.max(by: { $0.data < $1.data }) else { continue }
                let importi = s.map(\.importo).sorted()
                let salti = zip(mesi, mesi.dropFirst()).map { calendario.dateComponents([.month], from: $0, to: $1).month ?? 1 }.sorted()
                let saltoTipico = salti[salti.count / 2]
                let frequenza = [1, 2, 3, 6, 12].min { abs($0 - saltoTipico) < abs($1 - saltoTipico) } ?? 1
                risultato.append(CandidatoRicorrente(titolo: ultimo.titolo, importo: importi[importi.count / 2].centesimi, mesi: mesi.count,
                                                     ogniMesi: frequenza, ultimo: ultimo, movimenti: s))
            }
        }
        return risultato.sorted { $0.ultimo.data > $1.ultimo.data }
    }
}
