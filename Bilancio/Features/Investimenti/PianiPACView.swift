import SwiftUI
import SwiftData

/// Elenco dei piani di accumulo (pushata dalla tab Investimenti).
struct PianiPACView: View {
    @Query(sort: \PianoPAC.nome) private var piani: [PianoPAC]
    @State private var nuovo = false
    @State private var inModifica: PianoPAC?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if piani.isEmpty {
                    Scheda {
                        VStack(spacing: 10) {
                            Image(systemName: "calendar.badge.clock").font(.system(size: 36)).foregroundStyle(Tinta.investito)
                            Text("Nessun piano di accumulo").font(.headline)
                            Text("Indica quanto versi ogni mese e come si divide tra gli strumenti: l'app crea da sola l'addebito da confermare e le quote comprate al prezzo del giorno. Vale anche per i versamenti periodici ai fondi pensione (un solo strumento al 100%).")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button { nuovo = true } label: { Label("Crea piano", systemImage: "plus") }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
                ForEach(piani) { p in
                    Button { inModifica = p } label: { SchedaPianoPAC(piano: p) }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Piani di accumulo")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { nuovo = true } label: { Label("Nuovo piano", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $nuovo) { PianoPACEditorView(piano: nil) }
        .sheet(item: $inModifica) { PianoPACEditorView(piano: $0) }
    }
}

/// Le allocazioni raggruppate per data di validità, dalla più recente.
private func setAllocazioniPAC(_ piano: PianoPAC) -> [(dal: Date, voci: [AllocazionePAC])] {
    Dictionary(grouping: piano.allocazioni.filter { $0.strumento != nil }) { calendario.startOfDay(for: $0.validaDal) }
        .map { (dal: $0.key, voci: $0.value.sorted { $0.percentuale > $1.percentuale }) }
        .sorted { $0.dal > $1.dal }
}

private struct SchedaPianoPAC: View {
    let piano: PianoPAC

    var body: some View {
        let correnti = setAllocazioniPAC(piano).first?.voci ?? []
        Scheda(titolo: "\(piano.nome)", etichetta: piano.attivo ? "attivo" : "in pausa") {
            HStack(alignment: .firstTextBaseline) {
                Text("\(piano.importoMensile.euro) al mese").font(.title3.bold()).foregroundStyle(piano.attivo ? Tinta.investito : .secondary)
                Spacer()
                Text("il \(piano.giorno)").foregroundStyle(.secondary)
            }
            Text([piano.piattaforma, piano.conto.map { String(localized: "da \($0.nome)") }].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if correnti.isEmpty {
                Text("Nessuno strumento: tocca per scegliere la ripartizione.").font(.caption).foregroundStyle(.orange)
            }
            ForEach(correnti) { a in
                HStack {
                    Text(a.strumento?.nome ?? "").font(.subheadline).lineLimit(1)
                    Spacer()
                    Text((a.percentuale / 100).percento).font(.subheadline.monospacedDigit())
                    Text((piano.importoMensile * a.percentuale / 100).euro).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(minWidth: 70, alignment: .trailing)
                }
            }
            if let u = piano.ultimaGenerazione {
                Text("Generato fino a \(u.meseAnno)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Riga modificabile della ripartizione.
private struct RigaAllocazionePAC: Identifiable {
    let id = UUID()
    var strumento: Strumento?
    var percentuale: String
}

/// Creazione/modifica di un piano. Cambiare la ripartizione crea un nuovo set "valido dal": lo storico resta.
struct PianoPACEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let piano: PianoPAC?

    @Query(sort: \Strumento.nome) private var strumenti: [Strumento]
    @Query(sort: \Conto.ordine) private var conti: [Conto]

    private static let altra = "__altra"

    @State private var nome = ""
    @State private var piattaforma = Portafoglio.piattaformeNote[0]
    @State private var piattaformaAltra = ""
    @State private var importo = ""
    @State private var giorno = 1
    @State private var conto: Conto?
    @State private var attivo = true
    @State private var primoMese = Date()
    @State private var righe: [RigaAllocazionePAC] = []
    @State private var righeIniziali: [(Strumento?, Double)] = []
    @State private var validaDal = Date()
    @State private var caricato = false
    @State private var chiediElimina = false

    private var nomePiattaforma: String { piattaforma == Self.altra ? piattaformaAltra.trimmingCharacters(in: .whitespaces) : piattaforma }
    private var percentuali: [Double] { righe.map { leggiNumero($0.percentuale) ?? 0 } }
    private var totale: Double { percentuali.reduce(0, +) }
    private var ripartizioneCambiata: Bool {
        let attuali = righe.map { ($0.strumento?.persistentModelID, leggiNumero($0.percentuale) ?? 0) }
        let prima = righeIniziali.map { ($0.0?.persistentModelID, $0.1) }
        return attuali.count != prima.count || zip(attuali, prima).contains { $0.0 != $1.0 || abs($0.1 - $1.1) > 1e-9 }
    }
    private var ripartizioneOK: Bool {
        let scelti = righe.compactMap(\.strumento).map(\.persistentModelID)
        return !righe.isEmpty && scelti.count == righe.count && Set(scelti).count == scelti.count
            && percentuali.allSatisfy { $0 > 0 } && CalcoliInvestimenti.sommaCento(percentuali)
    }
    private var valido: Bool {
        !nome.trimmingCharacters(in: .whitespaces).isEmpty && !nomePiattaforma.isEmpty && (leggiNumero(importo) ?? 0) > 0 && ripartizioneOK
    }
    /// Strumenti della piattaforma del piano per primi.
    private var strumentiOrdinati: [Strumento] {
        let attivi = strumenti.filter { !$0.archiviato }
        return attivi.filter { $0.piattaforma == nomePiattaforma } + attivi.filter { $0.piattaforma != nomePiattaforma }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome (es. ETF mensile)", text: $nome)
                    Picker("Piattaforma", selection: $piattaforma) {
                        ForEach(Portafoglio.piattaformeNote, id: \.self) { Text($0).tag($0) }
                        Text("Altra…").tag(Self.altra)
                    }
                    if piattaforma == Self.altra { TextField("Nome piattaforma", text: $piattaformaAltra) }
                    CampoNumeroInvestimenti(titolo: "Importo mensile", testo: $importo, unita: "€")
                    Stepper("Giorno di esecuzione: \(giorno)", value: $giorno, in: 1...31)
                    Picker("Addebito su", selection: $conto) {
                        Text("Nessun conto").tag(Conto?.none)
                        ForEach(conti.filter { !$0.archiviato }) { c in Text(c.nome).tag(Optional(c)) }
                    }
                    Toggle("Attivo", isOn: $attivo)
                    if piano == nil {
                        DatePicker("Registra dal mese di", selection: $primoMese, in: ...Date().aggiungendo(mesi: 12), displayedComponents: .date)
                    }
                } header: {
                    Text("Piano")
                } footer: {
                    if piano == nil {
                        Text("Ogni mese, passato il giorno di esecuzione, arriva un addebito da confermare con le quote già calcolate. Se l'addebito di questo mese è già compreso nella situazione iniziale degli strumenti, parti dal mese prossimo; scegliendo un mese passato vengono registrati anche gli addebiti arretrati, ai prezzi di allora.")
                    }
                }

                Section {
                    if strumenti.isEmpty {
                        Text("Aggiungi prima gli strumenti dalla tab Investimenti (tasto +).").foregroundStyle(.secondary)
                    }
                    ForEach($righe) { $riga in
                        HStack {
                            Picker("Strumento", selection: $riga.strumento) {
                                Text("Scegli…").tag(Strumento?.none)
                                ForEach(strumentiOrdinati) { s in Text(s.nome).tag(Optional(s)) }
                            }
                            .labelsHidden()
                            Spacer()
                            TextField("0", text: $riga.percentuale)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("%").foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { righe.remove(atOffsets: $0) }
                    if !strumenti.isEmpty {
                        Button { righe.append(RigaAllocazionePAC(strumento: nil, percentuale: righe.isEmpty ? "100" : "")) } label: {
                            Label("Aggiungi strumento", systemImage: "plus.circle")
                        }
                    }
                    if piano != nil && ripartizioneCambiata {
                        DatePicker("Nuova ripartizione valida dal", selection: $validaDal, displayedComponents: .date)
                    }
                } header: {
                    Text("Ripartizione")
                } footer: {
                    let colore: Color = CalcoliInvestimenti.sommaCento(percentuali) ? .secondary : .red
                    Text(CalcoliInvestimenti.sommaCento(percentuali) ? String(localized: "Totale \((totale / 100).percento)") : String(localized: "Totale \((totale / 100).percento) — deve fare 100%"))
                        .foregroundStyle(colore)
                }

                if let p = piano {
                    let storico = setAllocazioniPAC(p)
                    if storico.count > 1 || (storico.count == 1 && ripartizioneCambiata) {
                        Section("Ripartizioni precedenti") {
                            ForEach(storico, id: \.dal) { set in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("dal \(set.dal.breve)").font(.caption).foregroundStyle(.secondary)
                                    Text(set.voci.map { ($0.percentuale / 100).percento + " " + ($0.strumento?.nome ?? "") }.joined(separator: " · "))
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                    Section {
                        Button("Elimina piano", role: .destructive) { chiediElimina = true }
                    } footer: {
                        Text("Gli addebiti e le operazioni già registrati restano.")
                    }
                }
            }
            .navigationTitle(piano == nil ? "Nuovo piano" : "Modifica piano")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { salva() }.disabled(!valido) }
            }
            .confirmationDialog("Eliminare il piano?", isPresented: $chiediElimina, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    if let p = piano { context.delete(p); try? context.save() }
                    dismiss()
                }
            }
            .onAppear(perform: carica)
        }
    }

    private func carica() {
        guard !caricato else { return }
        caricato = true
        guard let p = piano else { return }
        nome = p.nome
        if Portafoglio.piattaformeNote.contains(p.piattaforma) { piattaforma = p.piattaforma } else { piattaforma = Self.altra; piattaformaAltra = p.piattaforma }
        importo = CalcoliInvestimenti.testoNumero(p.importoMensile)
        giorno = p.giorno
        conto = p.conto
        attivo = p.attivo
        let correnti = setAllocazioniPAC(p).first?.voci ?? []
        righe = correnti.map { RigaAllocazionePAC(strumento: $0.strumento, percentuale: CalcoliInvestimenti.testoNumero($0.percentuale)) }
        righeIniziali = correnti.map { ($0.strumento, $0.percentuale) }
    }

    private func salva() {
        let p = piano ?? PianoPAC(nome: nome, piattaforma: nomePiattaforma, importoMensile: 0, giorno: giorno)
        if piano == nil {
            context.insert(p)
            // il primo mese da generare è quello scelto: si segna come generato il mese prima
            p.ultimaGenerazione = primoMese.inizioMese.aggiungendo(mesi: -1)
        }
        p.nome = nome.trimmingCharacters(in: .whitespaces)
        p.piattaforma = nomePiattaforma
        p.importoMensile = leggiNumero(importo) ?? 0
        p.giorno = giorno
        p.conto = conto
        // riattivato dopo una pausa: i mesi saltati non si generano tutti insieme, si riparte da questo mese
        if piano != nil, !p.attivo, attivo, var u = p.ultimaGenerazione {
            while u.aggiungendo(mesi: 1) < Date().inizioMese { u = u.aggiungendo(mesi: 1) }
            p.ultimaGenerazione = u
        }
        p.attivo = attivo

        if piano == nil || ripartizioneCambiata {
            // nuovo piano: la ripartizione vale dal primo mese; modifica: dalla data scelta
            let dal = calendario.startOfDay(for: piano == nil ? primoMese.inizioMese : validaDal)
            p.allocazioni.filter { calendario.startOfDay(for: $0.validaDal) == dal }.forEach(context.delete)
            for (riga, perc) in zip(righe, percentuali) {
                let a = AllocazionePAC(percentuale: perc, validaDal: dal)
                context.insert(a)
                a.piano = p
                a.strumento = riga.strumento
            }
        }
        try? context.save()
        dismiss()
        Task { await PAC.generaSeServe(in: context) }
    }
}
