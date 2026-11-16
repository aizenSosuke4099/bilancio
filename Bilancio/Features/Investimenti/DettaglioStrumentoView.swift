import SwiftUI
import SwiftData
import Charts

/// Limite annuo di deducibilità dei fondi pensione italiani.
private let limiteDeducibile = 5164.57

/// Dettaglio di uno strumento: numeri, grafico, operazioni, valutazioni e azioni rapide.
struct DettaglioStrumentoView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let strumento: Strumento

    @State private var storico: [Prezzi.Chiusura] = []
    @State private var modifica = false
    @State private var nuovaOperazione = false
    @State private var operazioneInModifica: Operazione?
    @State private var foglio: Foglio?
    @State private var aggiornando = false

    private enum Foglio: String, Identifiable {
        case valore, riallinea, prezzo
        var id: String { rawValue }
    }

    var body: some View {
        if strumento.isDeleted || strumento.modelContext == nil {
            ContentUnavailableView("Strumento eliminato", systemImage: "trash")
        } else {
            contenuto
        }
    }

    private var contenuto: some View {
        let s = strumento
        return ScrollView {
            VStack(spacing: 12) {
                riquadri
                if s.fondoPensioneItaliano { deducibilita }
                grafico
                azioni
                info
                operazioni
                if !s.valutazioni.isEmpty { valutazioni }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(s.nome)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Modifica") { modifica = true } }
        }
        .refreshable { await aggiornaPrezzo() }
        .task(id: s.ticker) { await caricaStorico() }
        .sheet(isPresented: $modifica) {
            StrumentoEditorView(strumento: s) {
                dismiss()
                context.delete(s)
                try? context.save()
            }
        }
        .sheet(isPresented: $nuovaOperazione) { OperazioneEditorView(strumento: s, operazione: nil) }
        .sheet(item: $operazioneInModifica) { op in OperazioneEditorView(strumento: s, operazione: op) }
        .sheet(item: $foglio) { f in
            switch f {
            case .valore:
                FoglioValoreInvestimenti(titolo: "Aggiorna valore", etichetta: "Valore attuale", unita: s.valuta, conData: true,
                                         nota: "Il valore totale della posizione come lo vedi nell'app della piattaforma.",
                                         iniziale: Portafoglio.valore(s).centesimi) { v, data in
                    let val = Valutazione(data: data, valore: v)
                    context.insert(val)
                    val.strumento = s
                    try? context.save()
                }
            case .riallinea:
                FoglioValoreInvestimenti(titolo: "Riallinea quote", etichetta: s.tipo == .obbligazione ? "Nominale reale" : "Quote reali", unita: nil, conData: false,
                                         nota: "Inserisci le quote che vedi sulla piattaforma: la differenza diventa un'operazione con importo 0, il versato non cambia.",
                                         iniziale: Portafoglio.quote(s)) { q, _ in riallinea(a: q) }
            case .prezzo:
                FoglioValoreInvestimenti(titolo: "Prezzo a mano", etichetta: s.tipo == .obbligazione ? "Prezzo (% nominale)" : "Prezzo", unita: s.tipo == .obbligazione ? "%" : s.valuta, conData: false,
                                         nota: s.ticker == nil ? "Yahoo non ha questo strumento: aggiorna il prezzo quando vuoi." : "Il prezzo verrà sovrascritto al prossimo aggiornamento automatico.",
                                         iniziale: s.ultimoPrezzo ?? 0) { p, _ in
                    s.ultimoPrezzo = p
                    s.ultimoPrezzoData = Date()
                    try? context.save()
                }
            }
        }
    }

    // MARK: - Sezioni

    private var riquadri: some View {
        let s = strumento
        let valore = Portafoglio.valoreEUR(s)
        let versato = Portafoglio.versatoEUR(s)
        let guadagno = Portafoglio.guadagnoEUR(s)   // con dividendi e cedole
        let investito = Portafoglio.investitoEUR(s)
        let colore = guadagno >= 0 ? Tinta.entrate : Tinta.spese
        let quote = Portafoglio.quote(s)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            RiquadroKPI(titolo: "Valore", valore: valore.euro, nota: s.valuta != "EUR" ? "\(Portafoglio.valore(s).valuta(s.valuta))" : nil, colore: Tinta.investito)
            RiquadroKPI(titolo: "Versato", valore: versato.euro)
            RiquadroKPI(titolo: "Guadagno", valore: (guadagno >= 0 ? "+" : "") + guadagno.euro,
                        nota: investito > 0 ? "\((guadagno / investito).percentoConSegno)" : nil, colore: colore, coloreNota: colore)
            if !s.valoreManuale || quote > 0 {
                RiquadroKPI(titolo: s.tipo == .obbligazione ? "Nominale" : "Quote", valore: quote.quote,
                            nota: Portafoglio.prezzoMedio(s).map { "carico medio \(prezzoTesto($0))" })
            }
        }
    }

    private var deducibilita: some View {
        let anno = Date().anno
        let versato = strumento.operazioni.filter { $0.data.anno == anno && $0.tipo.entraCapitale && !Portafoglio.èSituazioneIniziale($0) }
            .reduce(0) { $0 + ($1.importo + $1.commissioni) * $1.cambioEUR }
        return Scheda(titolo: "Deducibilità \(String(anno))") {
            Text("Versato quest'anno **\(versato.euro)** di \(limiteDeducibile.euro) deducibili")
                .font(.subheadline)
            ProgressView(value: min(versato, limiteDeducibile), total: limiteDeducibile)
                .tint(versato > limiteDeducibile ? .orange : Tinta.entrate)
            Text(versato < limiteDeducibile ? "Puoi ancora dedurre \((limiteDeducibile - versato).euro)." : "Hai raggiunto il limite: l'eccedenza non è deducibile.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var grafico: some View {
        let s = strumento
        if !storico.isEmpty && !s.valoreManuale {
            Scheda(titolo: "Prezzo", etichetta: "5 anni · \(s.ticker ?? "")") {
                Chart(storico, id: \.data) { c in
                    LineMark(x: .value("Mese", c.data, unit: .month), y: .value("Prezzo", c.prezzo))
                        .foregroundStyle(Tinta.investito)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 170)
            }
        } else if s.valutazioni.count >= 2 {
            let punti = s.valutazioni.sorted { $0.data < $1.data }
            Scheda(titolo: "Valore", etichetta: "\(s.valuta)") {
                Chart(punti) { v in
                    LineMark(x: .value("Data", v.data), y: .value("Valore", v.valore))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(Tinta.investito)
                    PointMark(x: .value("Data", v.data), y: .value("Valore", v.valore))
                        .foregroundStyle(Tinta.investito)
                        .symbolSize(20)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 170)
            }
        }
    }

    private var azioni: some View {
        let s = strumento
        return Scheda {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Button { nuovaOperazione = true } label: { Label("Operazione", systemImage: "plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                    if s.valoreManuale {
                        Button { foglio = .valore } label: { Label("Aggiorna valore", systemImage: "pencil").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                    } else {
                        Button { foglio = .riallinea } label: { Label("Riallinea quote", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                    }
                }
                if !s.valoreManuale {
                    HStack(spacing: 8) {
                        if s.ticker != nil {
                            Button { Task { await aggiornaPrezzo() } } label: {
                                Label(aggiornando ? String(localized: "Aggiorno…") : String(localized: "Aggiorna prezzo"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(aggiornando)
                        }
                        Button { foglio = .prezzo } label: { Label("Prezzo a mano", systemImage: "hand.point.up.left").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .font(.subheadline)
        }
    }

    private var info: some View {
        let s = strumento
        return Scheda(titolo: "Informazioni") {
            VStack(spacing: 6) {
                riga("Tipo", s.tipo.etichetta)
                riga("Piattaforma", s.piattaforma)
                if !s.isin.isEmpty { riga("ISIN", s.isin) }
                if let t = s.ticker { riga("Listino Yahoo", t) }
                riga("Valuta", s.valuta)
                if s.valuta != "EUR" { riga("Cambio", "1 \(s.valuta) = " + Portafoglio.cambio(s.valuta).formatted(.number.precision(.fractionLength(4))) + " €") }
                if let p = s.ultimoPrezzo, !s.valoreManuale {
                    riga("Ultimo prezzo", prezzoTesto(s.tipo == .obbligazione ? p / 100 : p) + (s.ultimoPrezzoData.map { " · " + $0.breve } ?? ""))
                }
                if let c = s.cedola { riga("Cedola", String(localized: "\((c / 100).percento) annua")) }
                if let d = s.scadenza { riga("Scadenza", d.breve) }
                if s.valoreManuale { riga("Valore", String(localized: "aggiornato a mano")) }
            }
            .font(.subheadline)
        }
    }

    private var operazioni: some View {
        let ops = strumento.operazioni.sorted { $0.data > $1.data }
        return Scheda(titolo: "Operazioni", etichetta: "\(ops.count)") {
            if ops.isEmpty {
                Text("Nessuna operazione. Aggiungi acquisti, versamenti, dividendi…").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(ops) { op in
                if op.id != ops.first?.id { Divider() }
                Button { operazioneInModifica = op } label: { RigaOperazioneInvestimenti(operazione: op, valuta: strumento.valuta) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Elimina", systemImage: "trash", role: .destructive) {
                            context.delete(op)
                            try? context.save()
                        }
                    }
            }
        }
    }

    private var valutazioni: some View {
        let vals = strumento.valutazioni.sorted { $0.data > $1.data }
        return Scheda(titolo: "Valutazioni", etichetta: "tieni premuto per eliminare") {
            ForEach(vals) { v in
                HStack {
                    Text(v.data.breve).foregroundStyle(.secondary)
                    Spacer()
                    Text(v.valore.valuta(strumento.valuta)).monospacedDigit()
                }
                .font(.subheadline)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Elimina", systemImage: "trash", role: .destructive) {
                        context.delete(v)
                        try? context.save()
                    }
                }
            }
        }
    }

    // MARK: - Supporto

    private func riga(_ titolo: LocalizedStringKey, _ valore: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titolo).foregroundStyle(.secondary)
            Spacer()
            Text(valore).multilineTextAlignment(.trailing)
        }
    }

    /// Prezzo unitario; per le obbligazioni in % del nominale.
    private func prezzoTesto(_ unitario: Double) -> String {
        strumento.tipo == .obbligazione
            ? (unitario * 100).formatted(.number.precision(.fractionLength(2))) + " %"
            : unitario.valuta(strumento.valuta)
    }

    private func caricaStorico() async {
        guard let t = strumento.ticker, !strumento.valoreManuale else { storico = []; return }
        storico = await Prezzi.storicoMensile(t)
    }

    private func aggiornaPrezzo() async {
        guard let t = strumento.ticker else { return }
        aggiornando = true
        defer { aggiornando = false }
        if let q = await Prezzi.quotazione(t), q.valuta == strumento.valuta {   // un prezzo in un'altra valuta non è il suo
            strumento.ultimoPrezzo = q.prezzo
            strumento.ultimoPrezzoData = q.data ?? Date()
        }
        if strumento.valuta != "EUR", let c = await Prezzi.cambio(strumento.valuta) {
            Portafoglio.salvaCambio(strumento.valuta, c)
        }
        try? context.save()
    }

    /// Porta le quote al valore reale con un acquisto/vendita a importo 0 (il versato non cambia).
    private func riallinea(a quoteReali: Double) {
        let differenza = quoteReali - Portafoglio.quote(strumento)
        guard abs(differenza) > 1e-9 else { return }
        let op = Operazione(data: Date(), tipo: differenza > 0 ? .acquisto : .vendita, quote: abs(differenza), prezzo: 0, importo: 0,
                            cambioEUR: Portafoglio.cambio(strumento.valuta))
        op.nota = String(localized: "Riallineamento")
        context.insert(op)
        op.strumento = strumento
        try? context.save()
    }
}

private struct RigaOperazioneInvestimenti: View {
    let operazione: Operazione
    let valuta: String

    var body: some View {
        let op = operazione
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(op.tipo.etichetta).font(.subheadline.weight(.medium))
                    if op.movimento?.daConfermare == true {
                        Text("da confermare").font(.caption2).foregroundStyle(.blue)
                    }
                }
                Text(([op.data.breve] + (op.nota.isEmpty ? [] : [op.nota])).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(op.importo.valuta(valuta)).font(.subheadline.monospacedDigit())
                    .foregroundStyle(op.tipo.esceCapitale ? Tinta.spese : (op.tipo == .dividendo || op.tipo == .cedola ? Tinta.entrate : .primary))
                if op.quote > 0 {
                    Text((op.tipo == .vendita ? "−" : "+") + String(localized: "\(op.quote.quote) q.")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// Foglio con un solo numero (e una data facoltativa): valore, quote reali, prezzo a mano.
private struct FoglioValoreInvestimenti: View {
    @Environment(\.dismiss) private var dismiss
    let titolo: LocalizedStringKey
    let etichetta: LocalizedStringKey
    let unita: String?
    let conData: Bool
    let nota: LocalizedStringKey
    let iniziale: Double
    let onSalva: (Double, Date) -> Void

    @State private var testo = ""
    @State private var data = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CampoNumeroInvestimenti(titolo: etichetta, testo: $testo, unita: unita)
                    if conData { DatePicker("Data", selection: $data, in: ...Date(), displayedComponents: .date) }
                } footer: {
                    Text(nota)
                }
            }
            .navigationTitle(titolo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        if let v = leggiNumero(testo), v >= 0 { onSalva(v, data) }
                        dismiss()
                    }
                    .disabled(leggiNumero(testo) == nil)
                }
            }
            .onAppear { if testo.isEmpty && iniziale > 0 { testo = CalcoliInvestimenti.testoNumero(iniziale) } }
        }
        .presentationDetents([.medium])
    }
}

/// Aggiunta o modifica di un'operazione su uno strumento.
struct OperazioneEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let strumento: Strumento
    let operazione: Operazione?

    @State private var tipo: TipoOperazione = .acquisto
    @State private var data = Date()
    @State private var importo = ""
    @State private var quote = ""
    @State private var prezzo = ""
    @State private var commissioni = ""
    @State private var cambio = ""
    @State private var nota = ""
    @State private var caricato = false
    @State private var cercaPrezzo = false

    private var conQuote: Bool { tipo == .acquisto || tipo == .vendita }
    private var obbligazione: Bool { strumento.tipo == .obbligazione }
    private var fattore: Double { obbligazione ? 100 : 1 }

    private var valori: (importo: Double, quote: Double, prezzo: Double) {
        let q = conQuote ? (leggiNumero(quote) ?? 0) : 0
        var p = conQuote ? (leggiNumero(prezzo) ?? 0) : 0
        var i = leggiNumero(importo) ?? 0
        if i == 0 && q > 0 && p > 0 { i = q * p / fattore }
        if p == 0 && q > 0 && i > 0 { p = i / q * fattore }
        return (i, q, p)
    }

    private var valido: Bool {
        let v = valori
        return conQuote ? v.quote > 0 : v.importo > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $tipo) {
                        ForEach(TipoOperazione.allCases) { Text($0.etichetta).tag($0) }
                    }
                    DatePicker("Data", selection: $data, displayedComponents: .date)
                }
                Section {
                    if conQuote {
                        CampoNumeroInvestimenti(titolo: obbligazione ? "Nominale" : "Quote", testo: $quote)
                        HStack {
                            CampoNumeroInvestimenti(titolo: "Prezzo", testo: $prezzo, unita: obbligazione ? "%" : strumento.valuta)
                            if let t = strumento.ticker {
                                Button {
                                    Task {
                                        cercaPrezzo = true
                                        if let p = await Prezzi.prezzo(t, al: data) { prezzo = CalcoliInvestimenti.testoNumero(p) }
                                        cercaPrezzo = false
                                    }
                                } label: {
                                    if cercaPrezzo { ProgressView() } else { Image(systemName: "arrow.down.circle") }
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Prezzo di chiusura del giorno")
                            }
                        }
                    }
                    CampoNumeroInvestimenti(titolo: "Importo", testo: $importo, unita: strumento.valuta)
                    if conQuote {
                        CampoNumeroInvestimenti(titolo: "Commissioni", testo: $commissioni, unita: strumento.valuta)
                    }
                    if strumento.valuta != "EUR" {
                        CampoNumeroInvestimenti(titolo: "1 \(strumento.valuta) =", testo: $cambio, unita: "€")
                    }
                } footer: {
                    if conQuote {
                        let v = valori
                        Text("Lascia vuoto l'importo o il prezzo: lo calcolo dagli altri due. Totale \(v.importo.valuta(strumento.valuta)).")
                    }
                }
                Section("Nota") {
                    TextField("Facoltativa", text: $nota)
                }
                if let op = operazione {
                    Section {
                        Button("Elimina operazione", role: .destructive) {
                            context.delete(op)
                            try? context.save()
                            dismiss()
                        }
                    } footer: {
                        if op.movimento != nil { Text("Fa parte di un addebito del piano di accumulo.") }
                    }
                }
            }
            .navigationTitle(operazione == nil ? "Nuova operazione" : "Modifica operazione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { salva() }.disabled(!valido) }
            }
            .onAppear(perform: carica)
        }
    }

    private func carica() {
        guard !caricato else { return }
        caricato = true
        cambio = CalcoliInvestimenti.testoNumero(Portafoglio.cambio(strumento.valuta))
        if strumento.valoreManuale { tipo = .versamento }
        guard let op = operazione else { return }
        tipo = op.tipo
        data = op.data
        importo = CalcoliInvestimenti.testoNumero(op.importo)
        quote = op.quote > 0 ? CalcoliInvestimenti.testoNumero(op.quote) : ""
        prezzo = op.prezzo > 0 ? CalcoliInvestimenti.testoNumero(op.prezzo) : ""
        commissioni = op.commissioni > 0 ? CalcoliInvestimenti.testoNumero(op.commissioni) : ""
        cambio = CalcoliInvestimenti.testoNumero(op.cambioEUR)
        nota = op.nota
    }

    private func salva() {
        let v = valori
        let cambioEUR = strumento.valuta == "EUR" ? 1 : (leggiNumero(cambio).flatMap { $0 > 0 ? $0 : nil } ?? Portafoglio.cambio(strumento.valuta))
        let op = operazione ?? Operazione(data: data, tipo: tipo, quote: 0, prezzo: 0, importo: 0)
        if operazione == nil { context.insert(op) }
        op.data = data
        op.tipo = tipo
        op.quote = v.quote
        op.prezzo = v.prezzo
        op.importo = v.importo
        op.commissioni = conQuote ? (leggiNumero(commissioni) ?? 0) : 0
        op.cambioEUR = cambioEUR
        op.nota = nota.trimmingCharacters(in: .whitespaces)
        op.strumento = strumento
        try? context.save()
        dismiss()
    }
}
