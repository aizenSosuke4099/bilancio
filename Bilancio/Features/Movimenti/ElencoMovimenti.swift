import SwiftUI
import SwiftData

/// Movimenti di un periodo con ricerca e filtri (tipo, categoria, conto). Vista "pushata".
/// Il filtro categoria include gli scontrini con almeno una riga di quella categoria.
struct ElencoMovimentiPeriodoView: View {
    let titolo: String

    @Query private var movimenti: [Movimento]
    @Query(sort: \Categoria.ordine) private var categorie: [Categoria]
    @Query(sort: \Conto.ordine) private var conti: [Conto]
    @State private var ricerca = ""
    @State private var tipo: TipoMovimento?
    @State private var categoria: Categoria?
    @State private var conto: Conto?
    @State private var daModificare: Movimento?

    init(titolo: String, da: Date, a: Date, categoria: Categoria? = nil) {
        self.titolo = titolo
        _movimenti = Query(filter: #Predicate { $0.data >= da && $0.data < a }, sort: \.data, order: .reverse)
        _categoria = State(initialValue: categoria)
    }

    private var filtriAttivi: Bool { tipo != nil || categoria != nil || conto != nil }

    private var filtrati: [Movimento] {
        let testo = Classificatore.normalizza(ricerca)
        return movimenti.filter { m in
            (tipo == nil || m.tipo == tipo)
                && (conto == nil || m.conto?.persistentModelID == conto?.persistentModelID)
                && (categoria.map { haCategoria(m, $0) } ?? true)
                && (testo.isEmpty || Classificatore.normalizza("\(m.titolo) \(m.descrizioneOriginale) \(m.nota) \(m.categoria?.nome ?? "") \(abs(m.importo).euro)").contains(testo))
        }
    }

    private func haCategoria(_ m: Movimento, _ c: Categoria) -> Bool {
        let id = c.persistentModelID
        return m.categoria?.persistentModelID == id || (m.scontrino?.righe.contains { $0.categoria?.persistentModelID == id } ?? false)
    }

    var body: some View {
        let lista = filtrati
        List {
            if !lista.isEmpty {
                Section {
                    HStack {
                        Text(lista.count == 1 ? "1 movimento" : "\(lista.count) movimenti")
                        Spacer()
                        Text(lista.reduce(0) { $0 + $1.importo }.euro).monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(lista) { m in
                    Button { daModificare = m } label: {
                        RigaMovimento(movimento: m).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay {
            if lista.isEmpty {
                ContentUnavailableView("Nessun movimento", systemImage: "tray", description: Text(filtriAttivi || !ricerca.isEmpty ? "Prova a cambiare ricerca o filtri." : "Non ci sono movimenti in questo periodo."))
            }
        }
        .searchable(text: $ricerca, prompt: "Cerca titolo, nota, importo")
        .navigationTitle(titolo)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Tipo", selection: $tipo) {
                        Text("Tutti i tipi").tag(TipoMovimento?.none)
                        ForEach(TipoMovimento.allCases) { Label($0.etichetta, systemImage: $0.icona).tag(Optional($0)) }
                    }
                    .pickerStyle(.menu)
                    Picker("Categoria", selection: $categoria) {
                        Text("Tutte le categorie").tag(Categoria?.none)
                        ForEach(categorie) { Text($0.nome).tag(Optional($0)) }
                    }
                    .pickerStyle(.menu)
                    Picker("Conto", selection: $conto) {
                        Text("Tutti i conti").tag(Conto?.none)
                        ForEach(conti) { Label($0.nome, systemImage: $0.tipo.icona).tag(Optional($0)) }
                    }
                    .pickerStyle(.menu)
                    if filtriAttivi {
                        Button("Togli i filtri", systemImage: "xmark.circle") {
                            tipo = nil
                            categoria = nil
                            conto = nil
                        }
                    }
                } label: {
                    Image(systemName: filtriAttivi ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filtri")
            }
        }
        .sheet(item: $daModificare) { m in
            NavigationStack { MovimentoEditorView(movimento: m) }
        }
    }
}

/// Foglio con tutti i movimenti da confermare: conferma singola (pulsante o swipe), "Conferma tutti", tocco per modificare.
/// Ha il proprio NavigationStack.
struct MovimentiDaConfermareView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var movimenti: [Movimento]
    @State private var daModificare: Movimento?

    init() {
        let stato = StatoMovimento.daConfermare.rawValue
        _movimenti = Query(filter: #Predicate { $0.statoRaw == stato }, sort: \.data, order: .reverse)
    }

    private func conferma(_ lista: [Movimento]) {
        for m in lista { m.conferma() }
        try? context.save()
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(movimenti) { m in
                    HStack(spacing: 12) {
                        Button { daModificare = m } label: {
                            RigaMovimento(movimento: m).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { conferma([m]) } label: {
                            Image(systemName: "checkmark.circle").font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .tint(.green)
                        .accessibilityLabel("Conferma")
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button("Conferma", systemImage: "checkmark") { conferma([m]) }.tint(.green)
                    }
                }
            }
            .overlay {
                if movimenti.isEmpty {
                    ContentUnavailableView("Tutto confermato", systemImage: "checkmark.circle", description: Text("Non ci sono movimenti da confermare."))
                }
            }
            .navigationTitle("Da confermare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Conferma tutti") { conferma(movimenti) }
                        .disabled(movimenti.isEmpty)
                }
            }
            .sheet(item: $daModificare) { m in
                NavigationStack { MovimentoEditorView(movimento: m) }
            }
        }
    }
}
