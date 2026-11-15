import SwiftUI
import SwiftData
import Charts

/// Radice della tab Investimenti: totali, andamento, ripartizione e posizioni per piattaforma.
struct InvestimentiView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Strumento.nome) private var tutti: [Strumento]
    @AppStorage(Prezzi.chiaveUltimoAggiornamento) private var aggiornatoIl: Double = 0
    /// ticker → (primo giorno del mese → chiusura del mese)
    @State private var storici: [String: [Date: Double]] = [:]
    @State private var nuovoStrumento = false

    private var strumenti: [Strumento] { tutti.filter { !$0.archiviato } }
    private var archiviati: [Strumento] { tutti.filter(\.archiviato) }
    private var tickers: [String] { strumenti.filter { !$0.valoreManuale }.compactMap(\.ticker).sorted() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if strumenti.isEmpty {
                        statoVuoto
                    } else {
                        riquadri
                        andamento
                        ripartizione
                        ForEach(gruppi, id: \.piattaforma) { g in
                            Scheda(titolo: g.piattaforma, etichetta: g.valore.euro) {
                                ForEach(g.strumenti) { s in
                                    if s.id != g.strumenti.first?.id { Divider() }
                                    NavigationLink { DettaglioStrumentoView(strumento: s) } label: { RigaStrumentoInvestimenti(strumento: s) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    if !archiviati.isEmpty {
                        Scheda(titolo: "Archiviati") {
                            ForEach(archiviati) { s in
                                NavigationLink { DettaglioStrumentoView(strumento: s) } label: {
                                    HStack {
                                        Text(s.nome).foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Investimenti")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { PianiPACView() } label: { Label("Piani di accumulo", systemImage: "calendar.badge.clock") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { nuovoStrumento = true } label: { Label("Aggiungi strumento", systemImage: "plus") }
                }
            }
            .refreshable {
                await Prezzi.aggiornaTutto(in: context)
                await caricaStorici()
            }
            .task(id: tickers) { await caricaStorici() }
            .sheet(isPresented: $nuovoStrumento) { StrumentoEditorView(strumento: nil) }
        }
    }

    // MARK: - Sezioni

    private var statoVuoto: some View {
        Scheda {
            VStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 40)).foregroundStyle(Tinta.investito)
                Text("Nessun investimento").font(.headline)
                Text("Aggiungi il primo strumento (ETF, obbligazione, fondo pensione, gestione) con la situazione attuale. Poi crea un piano di accumulo: ogni mese l'app registra da sola l'addebito e le quote comprate.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { nuovoStrumento = true } label: { Label("Aggiungi strumento", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                NavigationLink { PianiPACView() } label: { Label("Piani di accumulo", systemImage: "calendar.badge.clock") }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var riquadri: some View {
        let valore = strumenti.reduce(0) { $0 + Portafoglio.valoreEUR($1) }
        let versato = strumenti.reduce(0) { $0 + Portafoglio.versatoEUR($1) }
        let guadagno = valore - versato
        let colore = guadagno >= 0 ? Tinta.entrate : Tinta.spese
        let aggiornato = aggiornatoIl > 0 ? Date(timeIntervalSince1970: aggiornatoIl) : nil
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            RiquadroKPI(titolo: "Valore", valore: valore.euroTondo, nota: strumenti.count == 1 ? "1 strumento" : "\(strumenti.count) strumenti", colore: Tinta.investito)
            RiquadroKPI(titolo: "Versato", valore: versato.euroTondo, nota: "capitale netto")
            RiquadroKPI(titolo: "Guadagno", valore: (guadagno >= 0 ? "+" : "") + guadagno.euroTondo,
                        nota: versato > 0 ? (guadagno / versato).percentoConSegno : nil, colore: colore, coloreNota: colore)
            RiquadroKPI(titolo: "Prezzi", valore: aggiornato.map { $0.giornoMese + " " + $0.formatted(.dateTime.hour().minute().locale(localeIT)) } ?? "mai",
                        nota: "tira giù per aggiornare")
        }
    }

    @ViewBuilder private var andamento: some View {
        let serie = AndamentoInvestimenti.serie(strumenti, storici: storici)
        if serie.count >= 2 {
            Scheda(titolo: "Valore vs versato", etichetta: "per mese") {
                Chart {
                    ForEach(serie) { p in
                        AreaMark(x: .value("Mese", p.mese, unit: .month), y: .value("Valore", p.valore))
                            .foregroundStyle(Tinta.investito.opacity(0.12))
                        LineMark(x: .value("Mese", p.mese, unit: .month), y: .value("Euro", p.valore), series: .value("Serie", "Valore"))
                            .foregroundStyle(Tinta.investito)
                        LineMark(x: .value("Mese", p.mese, unit: .month), y: .value("Euro", p.versato), series: .value("Serie", "Versato"))
                            .foregroundStyle(Color.gray)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine()
                        AxisValueLabel { if let d = v.as(Double.self) { Text(d.euroTondo).font(.caption2) } }
                    }
                }
                .frame(height: 180)
                HStack(spacing: 12) {
                    Label { Text("Valore") } icon: { Circle().fill(Tinta.investito).frame(width: 8, height: 8) }
                    Label { Text("Versato") } icon: { Circle().fill(Color.gray).frame(width: 8, height: 8) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var ripartizione: some View {
        let perPiattaforma = Dictionary(grouping: strumenti, by: \.piattaforma).mapValues { $0.reduce(0) { $0 + Portafoglio.valoreEUR($1) } }
        let perTipo = Dictionary(grouping: strumenti, by: { $0.tipo.etichetta }).mapValues { $0.reduce(0) { $0 + Portafoglio.valoreEUR($1) } }
        CiambellaInvestimenti(titolo: "Per piattaforma", voci: perPiattaforma)
        if perTipo.count > 1 { CiambellaInvestimenti(titolo: "Per tipo", voci: perTipo) }
    }

    private var gruppi: [(piattaforma: String, valore: Double, strumenti: [Strumento])] {
        Dictionary(grouping: strumenti, by: \.piattaforma)
            .map { (piattaforma: $0.key.isEmpty ? "Altro" : $0.key, valore: $0.value.reduce(0) { $0 + Portafoglio.valoreEUR($1) }, strumenti: $0.value) }
            .sorted { $0.valore > $1.valore }
    }

    private func caricaStorici() async {
        var nuovi: [String: [Date: Double]] = [:]
        for t in Set(tickers) {
            let c = await Prezzi.storicoMensile(t)
            nuovi[t] = Dictionary(c.map { ($0.data, $0.prezzo) }, uniquingKeysWith: { _, b in b })
        }
        storici = nuovi
    }
}

// MARK: - Componenti

/// Riga di uno strumento: nome, ISIN, quote; a destra valore EUR (e in valuta) e rendimento.
private struct RigaStrumentoInvestimenti: View {
    let strumento: Strumento

    var body: some View {
        let s = strumento
        let rendimento = Portafoglio.rendimento(s)
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.nome).font(.subheadline.weight(.medium)).lineLimit(2)
                Text(sottotitolo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Portafoglio.valoreEUR(s).euro).font(.subheadline.monospacedDigit())
                if s.valuta != "EUR" {
                    Text(Portafoglio.valore(s).valuta(s.valuta)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(rendimento.percentoConSegno).font(.caption.monospacedDigit())
                    .foregroundStyle(rendimento >= 0 ? Tinta.entrate : Tinta.spese)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).padding(.top, 3)
        }
        .contentShape(Rectangle())
    }

    private var sottotitolo: String {
        var parti: [String] = []
        if !strumento.isin.isEmpty { parti.append(strumento.isin) }
        let q = Portafoglio.quote(strumento)
        if q > 0 { parti.append(q.quote + (strumento.tipo == .obbligazione ? " nominale" : " quote")) }
        if parti.isEmpty { parti.append(strumento.tipo.etichetta) }
        return parti.joined(separator: " · ")
    }
}

/// Colori delle ciambelle (stesso ordine = stessa voce).
private let coloriInvestimenti: [Color] = [.blue, .purple, .green, .orange, .pink, .teal, .indigo, .brown, .cyan, .mint]

private struct CiambellaInvestimenti: View {
    let titolo: String
    let voci: [String: Double]

    var body: some View {
        let ordinate = voci.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let totale = ordinate.reduce(0) { $0 + $1.value }
        if totale > 0 {
            Scheda(titolo: titolo) {
                HStack(spacing: 16) {
                    Chart(Array(ordinate.enumerated()), id: \.element.key) { i, voce in
                        SectorMark(angle: .value("Valore", voce.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(coloriInvestimenti[i % coloriInvestimenti.count])
                            .cornerRadius(3)
                    }
                    .frame(width: 110, height: 110)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(ordinate.enumerated()), id: \.element.key) { i, voce in
                            HStack(spacing: 6) {
                                Circle().fill(coloriInvestimenti[i % coloriInvestimenti.count]).frame(width: 8, height: 8)
                                Text(voce.key).font(.caption).lineLimit(1)
                                Spacer(minLength: 4)
                                Text((voce.value / totale).percento).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Andamento nel tempo

/// Valore e versato di fine mese, ricostruiti dalle operazioni e dallo storico dei prezzi.
private enum AndamentoInvestimenti {
    struct Punto: Identifiable {
        let mese: Date
        let valore: Double
        let versato: Double
        var id: Date { mese }
    }

    // ponytail: cambio attuale anche per i mesi passati; il cambio storico serve solo se le posizioni in CHF diventano grandi
    static func serie(_ strumenti: [Strumento], storici: [String: [Date: Double]]) -> [Punto] {
        let date = strumenti.flatMap { s in s.operazioni.map(\.data) + s.valutazioni.map(\.data) }
        guard let primo = date.min() else { return [] }
        let corrente = Date().inizioMese
        var mese = max(primo.inizioMese, corrente.aggiungendo(mesi: -59))
        var punti: [Punto] = []
        while mese <= corrente {
            let fine = mese.inizioMeseSuccessivo
            var valore = 0.0, versato = 0.0
            for s in strumenti {
                let ops = s.operazioni.filter { $0.data < fine }
                let v = versatoEUR(ops)
                versato += v
                if mese == corrente {
                    valore += Portafoglio.valoreEUR(s)
                } else if !s.valoreManuale, let t = s.ticker, let prezzo = storici[t]?[mese] {
                    let q = ops.reduce(0.0) { $0 + ($1.tipo == .acquisto ? $1.quote : $1.tipo == .vendita ? -$1.quote : 0) }
                    valore += q * (s.tipo == .obbligazione ? prezzo / 100 : prezzo) * Portafoglio.cambio(s.valuta)
                } else if let val = s.valutazioni.filter({ $0.data < fine }).max(by: { $0.data < $1.data }) {
                    // valutazione "a gradini" + versamenti successivi
                    let delta = ops.filter { $0.data > val.data }.reduce(0.0) { acc, op in
                        op.tipo.entraCapitale ? acc + op.importo : (op.tipo.esceCapitale ? acc - op.importo : acc)
                    }
                    valore += (val.valore + delta) * Portafoglio.cambio(s.valuta)
                } else {
                    valore += v
                }
            }
            punti.append(Punto(mese: mese, valore: valore, versato: versato))
            mese = fine
        }
        return punti
    }

    /// Stessa regola di `Portafoglio.versatoEUR`, ma su un sottoinsieme di operazioni.
    private static func versatoEUR(_ ops: [Operazione]) -> Double {
        ops.reduce(0) { acc, op in
            if op.tipo.entraCapitale { return acc + (op.importo + op.commissioni) * op.cambioEUR }
            if op.tipo.esceCapitale { return acc - op.importo * op.cambioEUR }
            if op.tipo == .commissione { return acc + op.importo * op.cambioEUR }
            return acc
        }
    }
}
