import SwiftUI
import SwiftData

/// Crea (movimento == nil) o modifica un movimento. Si presenta dentro un NavigationStack (sheet).
struct MovimentoEditorView: View {
    let movimento: Movimento?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Categoria.ordine) private var categorie: [Categoria]
    @Query(filter: #Predicate<Conto> { !$0.archiviato }, sort: \Conto.ordine) private var conti: [Conto]

    @State private var tipo: TipoMovimento
    @State private var importoTesto: String
    /// Spesa: rimborso. Giroconto: entra su questo conto. Investimento: disinvestimento.
    @State private var positivo: Bool
    @State private var data: Date
    @State private var titolo: String
    @State private var categoria: Categoria?
    @State private var conto: Conto?
    @State private var nota: String
    @State private var chiediElimina = false
    @State private var errore: String?

    init(movimento: Movimento? = nil) {
        self.movimento = movimento
        _tipo = State(initialValue: movimento?.tipo ?? .spesa)
        _importoTesto = State(initialValue: movimento.map { abs($0.importo).formatted(.number.precision(.fractionLength(2))) } ?? "")
        _positivo = State(initialValue: (movimento?.importo ?? -1) > 0)
        _data = State(initialValue: movimento?.data ?? Date())
        _titolo = State(initialValue: movimento?.titolo ?? "")
        _categoria = State(initialValue: movimento?.categoria)
        _conto = State(initialValue: movimento?.conto)
        _nota = State(initialValue: movimento?.nota ?? "")
    }

    private var daConfermare: Bool { movimento?.daConfermare ?? false }
    private var conCategoria: Bool { tipo == .spesa || tipo == .entrata }

    /// Importo con il segno deciso dal tipo (si inserisce sempre positivo).
    private var importoFirmato: Double? {
        guard let v = leggiNumero(importoTesto), v != 0, v.isFinite else { return nil }
        let a = abs(v).centesimi
        if tipo == .entrata { return a }
        return positivo ? a : -a
    }

    private var etichettaSegno: String? {
        switch tipo {
        case .spesa: String(localized: "Rimborso (entra denaro)")
        case .giroconto: String(localized: "In entrata su questo conto")
        case .investimento: String(localized: "Disinvestimento (rientro sul conto)")
        case .entrata: nil
        }
    }

    private var categorieTipo: [Categoria] {
        let t: TipoMovimento = tipo == .entrata ? .entrata : .spesa
        return categorie.filter { $0.tipo == t || $0 == categoria }
    }

    /// Conti attivi più quello già assegnato se è archiviato (altrimenti il Picker resta senza selezione).
    private var contiScelta: [Conto] {
        if let c = movimento?.conto, c.archiviato { return conti + [c] }
        return conti
    }

    var body: some View {
        Form {
            if daConfermare {
                Section {
                    Label("Da confermare: controlla importo e categoria, poi conferma.", systemImage: "bell.badge")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }

            Section {
                Picker("Tipo", selection: $tipo) {
                    ForEach(TipoMovimento.allCases) { Text($0.etichetta).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                HStack {
                    Text("€").font(.title2.bold()).foregroundStyle(.secondary)
                    TextField("0,00", text: $importoTesto)
                        .keyboardType(.decimalPad)
                        .font(.title2.bold().monospacedDigit())
                }
                if let etichettaSegno { Toggle(etichettaSegno, isOn: $positivo) }
                DatePicker("Data", selection: $data, displayedComponents: .date)
                TextField("Titolo (negozio o controparte)", text: $titolo)
            }

            if conCategoria {
                Section {
                    Picker("Categoria", selection: $categoria) {
                        Text("Nessuna").tag(Categoria?.none)
                        ForEach(categorieTipo) { c in
                            Label { Text(c.nome) } icon: { IconaCategoria(categoria: c, dimensione: 26) }
                                .tag(Optional(c))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }

            Section {
                Picker("Conto", selection: $conto) {
                    Text("Nessuno").tag(Conto?.none)
                    ForEach(contiScelta) { c in
                        Label(c.nome, systemImage: c.tipo.icona).tag(Optional(c))
                    }
                }
                TextField("Nota", text: $nota, axis: .vertical)
            }

            if let m = movimento {
                Section("Provenienza") {
                    LabeledContent("Origine", value: m.origine.etichetta)
                    if !m.descrizioneOriginale.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Descrizione della banca").font(.caption).foregroundStyle(.secondary)
                            Text(m.descrizioneOriginale).font(.callout).textSelection(.enabled)
                        }
                    }
                    if let s = m.scontrino {
                        NavigationLink {
                            ScontrinoDettaglioView(scontrino: s)
                        } label: {
                            Label(s.righe.isEmpty ? "Scontrino \(s.negozio)" : "Scontrino \(s.negozio) · \(s.righe.count) righe", systemImage: "receipt")
                        }
                    }
                }

                if daConfermare {
                    Section {
                        Button("Salva senza confermare") { salva(confermando: false) }
                            .disabled(importoFirmato == nil)
                    }
                }

                Section {
                    Button("Elimina movimento", role: .destructive) { chiediElimina = true }
                }
            }
        }
        .navigationTitle(movimento == nil ? "Nuovo movimento" : "Movimento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annulla") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(daConfermare ? "Conferma" : "Salva") { salva(confermando: true) }
                    .disabled(importoFirmato == nil)
            }
        }
        .onChange(of: tipo) { _, nuovo in
            positivo = false
            let t: TipoMovimento = nuovo == .entrata ? .entrata : .spesa
            if let c = categoria, c.tipo != t { categoria = nil }
        }
        .onAppear {
            // un movimento inserito a mano di solito è in contanti
            if movimento == nil && conto == nil { conto = conti.first { $0.tipo == .contanti } }
        }
        .confirmationDialog("Eliminare il movimento?", isPresented: $chiediElimina, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { elimina() }
        } message: {
            Text("L'operazione non si può annullare.")
        }
        .alert("Impossibile salvare", isPresented: Binding(get: { errore != nil }, set: { if !$0 { errore = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errore ?? "")
        }
    }

    private func salva(confermando: Bool) {
        guard let nuovoImporto = importoFirmato else { return }
        let cat = conCategoria ? categoria : nil
        let titoloPulito = titolo.trimmingCharacters(in: .whitespacesAndNewlines)

        if let m = movimento {
            // dalla banca/estratto: se l'utente corregge tipo, categoria o titolo, l'app impara
            let corretto = m.tipo != tipo || m.categoria?.persistentModelID != cat?.persistentModelID || m.titolo != titoloPulito
            if corretto && !m.descrizioneOriginale.isEmpty {
                Classificatore.impara(descrizioneBanca: m.descrizioneOriginale, tipo: tipo, categoria: cat, titolo: titoloPulito, in: context)
            }
            // conferma(nuovoImporto:) riproporziona anche le operazioni PAC collegate se l'importo cambia;
            // per "salva senza confermare" si rimette lo stato com'era.
            let eraDaConfermare = m.daConfermare
            m.conferma(nuovoImporto: nuovoImporto)
            if !confermando && eraDaConfermare { m.stato = .daConfermare }
            m.tipo = tipo
            m.data = data
            m.titolo = titoloPulito
            m.categoria = cat
            m.conto = conto
            m.nota = nota
            // segnato a mano come giroconto: anche l'altra metà sull'altro conto smette di contare
            if tipo == .giroconto { Abbinamento.segnaGiroconto(m, in: context) }
        } else {
            let m = Movimento(data: data, importo: nuovoImporto, tipo: tipo, titolo: titoloPulito, origine: .manuale, stato: .confermato)
            m.nota = nota
            context.insert(m)
            // relazioni dopo l'inserimento, così stanno nello stesso contesto
            m.conto = conto
            m.categoria = cat
        }

        do {
            try context.save()
            dismiss()
        } catch {
            errore = error.localizedDescription
        }
    }

    private func elimina() {
        guard let m = movimento else { return }
        context.delete(m)
        do {
            try context.save()
            dismiss()
        } catch {
            errore = error.localizedDescription
        }
    }
}
