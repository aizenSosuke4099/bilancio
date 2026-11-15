import SwiftUI
import SwiftData

/// Conti, carte e contanti con i saldi. Pushata dalla scheda Altro.
struct ContiView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Conto.ordine) private var conti: [Conto]

    @State private var modifica: ContoDaModificare?
    @State private var aggiungiContanti = false
    @State private var contaContanti = false

    private var attivi: [Conto] { conti.filter { !$0.archiviato } }
    private var contanti: Conto? { attivi.first { $0.tipo == .contanti } }
    private var liquidita: Double { attivi.reduce(0) { $0 + Contabilita.saldo($1) } }

    var body: some View {
        List {
            Section {
                RiquadroKPI(titolo: "Liquidità totale", valore: liquidita.euro, nota: "Conti e contanti, meno il debito delle carte", colore: Tinta.patrimonio)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if let contanti {
                Section {
                    sezioneContanti(contanti)
                } header: { Text("Contanti") }
            }
            Section("Conti e carte") {
                ForEach(attivi.filter { $0.tipo != .contanti }) { c in
                    NavigationLink { ContoDettaglioView(conto: c) } label: { RigaConto(conto: c) }
                }
            }
            let archiviati = conti.filter(\.archiviato)
            if !archiviati.isEmpty {
                Section("Archiviati") {
                    ForEach(archiviati) { c in
                        NavigationLink { ContoDettaglioView(conto: c) } label: { RigaConto(conto: c).opacity(0.5) }
                    }
                }
            }
        }
        .navigationTitle("Conti e contanti")
        .toolbar {
            Button("Nuovo conto", systemImage: "plus") { modifica = ContoDaModificare(conto: nil) }
        }
        .sheet(item: $modifica) { m in NavigationStack { EditorConto(conto: m.conto) } }
        .sheet(isPresented: $aggiungiContanti) { NavigationStack { AggiungiContantiView() } }
        .sheet(isPresented: $contaContanti) { if let contanti { NavigationStack { ContaContantiView(contanti: contanti) } } }
    }

    private func sezioneContanti(_ c: Conto) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink { ContoDettaglioView(conto: c) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "banknote").font(.title2).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Color(hex: c.coloreHex), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nel portafoglio").font(.caption).foregroundStyle(.secondary)
                        Text(Contabilita.saldo(c).euro).font(.title2.bold()).monospacedDigit()
                    }
                }
            }
            HStack {
                Button { aggiungiContanti = true } label: { Label("Aggiungi contanti", systemImage: "plus.circle") }
                Spacer()
                Button { contaContanti = true } label: { Label("Conta i contanti", systemImage: "hand.raised") }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(.vertical, 4)
    }
}

fileprivate struct ContoDaModificare: Identifiable {
    let id = UUID()
    let conto: Conto?
}

fileprivate struct RigaConto: View {
    let conto: Conto

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: conto.tipo.icona).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Color(hex: conto.coloreHex), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(conto.nome)
                    if conto.ebAccountUid != nil {
                        Image(systemName: "link").font(.caption2).foregroundStyle(.blue)
                    }
                }
                Text(sottotitolo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Contabilita.saldo(conto).euro).monospacedDigit()
                .foregroundStyle(Contabilita.saldo(conto) < 0 ? Tinta.spese : .primary)
        }
    }

    private var sottotitolo: String {
        var parti = [conto.istituto.isEmpty ? conto.tipo.etichetta : conto.istituto]
        if conto.ebAccountUid != nil, let d = conto.saldoBancaData { parti.append(String(localized: "collegato, saldo al \(d.giornoMese)")) }
        if let t = conto.tassoAnnuo, t > 0 { parti.append(String(localized: "\(t.formatted(.number.precision(.fractionLength(0...2))))% lordo")) }
        return parti.joined(separator: " · ")
    }
}

// MARK: - Dettaglio conto

fileprivate struct ContoDettaglioView: View {
    let conto: Conto
    @State private var modificaConto = false
    @State private var movimentoAperto: Movimento?

    private var movimenti: [Movimento] { conto.movimenti.sorted { $0.data > $1.data } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Contabilita.saldo(conto).euro).font(.largeTitle.bold()).monospacedDigit()
                    if let d = conto.saldoBancaData, conto.saldoBanca != nil {
                        Text("Saldo letto dalla banca il \(d.breve)").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Saldo iniziale \(conto.saldoIniziale.euro) + movimenti").font(.caption).foregroundStyle(.secondary)
                    }
                    if let t = conto.tassoAnnuo, t > 0 {
                        Text("Interessi stimati: \((Contabilita.saldo(conto) * t / 100 / 12).euro) al mese (lordi)").font(.caption).foregroundStyle(Tinta.entrate)
                    }
                    if let iban = conto.iban { Text(iban).font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
            }
            Section("Movimenti") {
                if movimenti.isEmpty { Text("Nessun movimento").foregroundStyle(.secondary) }
                ForEach(movimenti) { m in
                    Button { movimentoAperto = m } label: { RigaMovimento(movimento: m) }
                        .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(conto.nome)
        .toolbar { Button("Modifica") { modificaConto = true } }
        .sheet(isPresented: $modificaConto) { NavigationStack { EditorConto(conto: conto) } }
        .sheet(item: $movimentoAperto) { m in NavigationStack { MovimentoEditorView(movimento: m) } }
    }
}

// MARK: - Editor conto

fileprivate struct EditorConto: View {
    let conto: Conto?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var tutti: [Conto]

    @State private var nome = ""
    @State private var tipo = TipoConto.corrente
    @State private var istituto = ""
    @State private var saldoIniziale = ""
    @State private var tasso = ""
    @State private var colore = "#2563EB"
    @State private var archiviato = false

    private static let colori = ["#2563EB", "#1E3A8A", "#0EA5E9", "#16A34A", "#10B981", "#F59E0B", "#B45309", "#EF4444", "#A855F7", "#EC4899", "#374151", "#111827"]

    var body: some View {
        Form {
            Section {
                TextField("Nome", text: $nome)
                Picker("Tipo", selection: $tipo) {
                    ForEach(TipoConto.allCases) { Label($0.etichetta, systemImage: $0.icona).tag($0) }
                }
                TextField("Banca o istituto", text: $istituto)
            }
            Section {
                TextField("Saldo iniziale", text: $saldoIniziale).keyboardType(.numbersAndPunctuation)
            } footer: {
                Text(conto?.saldoBanca != nil
                     ? "Questo conto è collegato: il saldo arriva dalla banca e il saldo iniziale non conta."
                     : "Il saldo è il saldo iniziale più i movimenti registrati. Per le carte di credito usa un valore negativo (debito).")
            }
            if tipo == .remunerato {
                Section {
                    TextField("Tasso annuo lordo %", text: $tasso).keyboardType(.decimalPad)
                    if let t = leggiNumero(tasso), let c = conto {
                        LabeledContent("Interessi al mese", value: (Contabilita.saldo(c) * t / 100 / 12).euro)
                    }
                } footer: { Text("Stima sul saldo attuale, prima delle tasse (26%).") }
            }
            Section("Colore") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                    ForEach(Self.colori, id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 32, height: 32)
                            .overlay { if hex == colore { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                            .onTapGesture { colore = hex }
                    }
                }
                .padding(.vertical, 4)
            }
            if conto != nil, tipo != .contanti {
                Section {
                    Toggle("Archiviato", isOn: $archiviato)
                } footer: { Text("Un conto archiviato non conta nella liquidità; i suoi movimenti restano.") }
            }
        }
        .navigationTitle(conto == nil ? "Nuovo conto" : "Modifica conto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva", action: salva).disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear(perform: carica)
    }

    private func carica() {
        guard let c = conto else { return }
        nome = c.nome
        tipo = c.tipo
        istituto = c.istituto
        saldoIniziale = c.saldoIniziale == 0 ? "" : c.saldoIniziale.formatted(.number.precision(.fractionLength(2)))
        tasso = c.tassoAnnuo.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? ""
        colore = c.coloreHex
        archiviato = c.archiviato
    }

    private func salva() {
        let c = conto ?? {
            let nuovo = Conto(nome: "", tipo: tipo, ordine: (tutti.map(\.ordine).max() ?? 0) + 1)
            context.insert(nuovo)
            return nuovo
        }()
        c.nome = nome.trimmingCharacters(in: .whitespaces)
        c.tipo = tipo
        c.istituto = istituto.trimmingCharacters(in: .whitespaces)
        c.saldoIniziale = leggiNumero(saldoIniziale) ?? 0
        c.tassoAnnuo = tipo == .remunerato ? leggiNumero(tasso) : nil
        c.coloreHex = colore
        c.archiviato = archiviato
        try? context.save()
        dismiss()
    }
}

// MARK: - Contanti

/// Prelievo da un conto non collegato (giroconto −X / +X) oppure contanti ricevuti (entrata).
fileprivate struct AggiungiContantiView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Conto.ordine) private var conti: [Conto]

    @State private var prelievo = true
    @State private var importo = ""
    @State private var data = Date()
    @State private var contoID: PersistentIdentifier?
    @State private var nota = ""

    private var origini: [Conto] { conti.filter { !$0.archiviato && $0.tipo != .contanti && $0.ebAccountUid == nil } }

    var body: some View {
        Form {
            Picker("Da dove arrivano", selection: $prelievo) {
                Text("Prelievo").tag(true)
                Text("Ricevuti").tag(false)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            Section {
                TextField("Importo", text: $importo).keyboardType(.decimalPad)
                DatePicker("Data", selection: $data, displayedComponents: .date)
                if prelievo {
                    Picker("Dal conto", selection: $contoID) {
                        Text("Scegli…").tag(PersistentIdentifier?.none)
                        ForEach(origini) { c in Text(c.nome).tag(Optional(c.persistentModelID)) }
                    }
                } else {
                    TextField("Da chi (facoltativo)", text: $nota)
                }
            } footer: {
                Text(prelievo
                     ? "I prelievi dai conti collegati arrivano da soli con la sincronizzazione: qui solo quelli dei conti non collegati."
                     : "Regali, rimborsi in contanti, vendite: conta come entrata.")
            }
        }
        .navigationTitle("Aggiungi contanti")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva", action: salva).disabled((leggiNumero(importo) ?? 0) <= 0 || (prelievo && contoID == nil))
            }
        }
    }

    private func salva() {
        let valore = abs(leggiNumero(importo) ?? 0)
        let contanti = DatiIniziali.contoContanti(in: context)
        if prelievo, let origine = conti.first(where: { $0.persistentModelID == contoID }) {
            context.insert(Movimento(data: data, importo: -valore, tipo: .giroconto, titolo: String(localized: "Prelievo contanti"), origine: .manuale, stato: .confermato, conto: origine))
            context.insert(Movimento(data: data, importo: valore, tipo: .giroconto, titolo: String(localized: "Prelievo"), origine: .manuale, stato: .confermato, conto: contanti))
        } else {
            let m = Movimento(data: data, importo: valore, tipo: .entrata, titolo: nota.isEmpty ? String(localized: "Contanti ricevuti") : nota, origine: .manuale,
                              stato: .confermato, conto: contanti, categoria: Classificatore.categoria(nome: "Altre entrate", in: context))
            context.insert(m)
        }
        try? context.save()
        dismiss()
    }
}

/// "Conta i contanti": la differenza col saldo registrato diventa una rettifica confermata.
fileprivate struct ContaContantiView: View {
    let contanti: Conto
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var contati = ""

    private var differenza: Double? { leggiNumero(contati).map { ($0 - Contabilita.saldo(contanti)).centesimi } }

    var body: some View {
        Form {
            Section {
                LabeledContent("Secondo Bilancio", value: Contabilita.saldo(contanti).euro)
                TextField("Quanti ne hai davvero", text: $contati).keyboardType(.decimalPad)
            }
            if let d = differenza, d != 0 {
                Section {
                    LabeledContent("Differenza", value: d.euro)
                } footer: {
                    Text(d < 0
                         ? "Diventa una spesa «Contanti non tracciati» (categoria Altro): soldi spesi senza scontrino."
                         : "Hai più contanti del previsto: la rettifica riduce le spese «Contanti non tracciati».")
                }
            }
        }
        .navigationTitle("Conta i contanti")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva", action: salva).disabled(differenza == nil)
            }
        }
    }

    private func salva() {
        if let d = differenza, d != 0 {
            context.insert(Movimento(data: Date(), importo: d, tipo: .spesa, titolo: String(localized: "Contanti non tracciati"), origine: .manuale,
                                     stato: .confermato, conto: contanti, categoria: Classificatore.categoria(nome: "Altro", in: context)))
            try? context.save()
        }
        dismiss()
    }
}
