import SwiftUI
import SwiftData
import Charts

/// Tab "Mese": selettore ‹ › e contenuto del mese.
struct MeseView: View {
    @State private var mese = Date().inizioMese

    var body: some View {
        NavigationStack {
            MeseContenuto(mese: mese)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { mese = mese.aggiungendo(mesi: -1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Mese precedente")
                        Button { mese = mese.aggiungendo(mesi: 1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("Mese successivo")
                            .disabled(mese >= Date().inizioMese)
                    }
                }
        }
    }
}

/// Pagina di un mese. La usa la tab Mese e il dettaglio della tabella annuale (vista "pushata", senza NavigationStack).
struct MeseContenuto: View {
    let mese: Date

    @Environment(\.modelContext) private var context
    /// Mese scelto + mese precedente (per i confronti).
    @Query private var movimentiDueMesi: [Movimento]
    @Query private var daConfermare: [Movimento]
    @Query(filter: #Predicate<Conto> { !$0.archiviato }, sort: \Conto.ordine) private var conti: [Conto]
    @Query(sort: \Categoria.ordine) private var categorie: [Categoria]
    @State private var foglio: FoglioMeseB?

    init(mese: Date) {
        let inizio = mese.inizioMese
        self.mese = inizio
        let da = inizio.aggiungendo(mesi: -1), a = inizio.inizioMeseSuccessivo
        _movimentiDueMesi = Query(filter: #Predicate { $0.data >= da && $0.data < a }, sort: \.data, order: .reverse)
        let stato = StatoMovimento.daConfermare.rawValue
        _daConfermare = Query(filter: #Predicate { $0.statoRaw == stato })
    }

    var body: some View {
        let precedente = mese.aggiungendo(mesi: -1)
        let movimenti = movimentiDueMesi.filter { $0.data >= mese }
        let movPrec = movimentiDueMesi.filter { $0.data < mese }
        let totali = Contabilita.totali(movimenti)
        let corrente = mese == Date().inizioMese
        let giorniMese = CalcoliDashboard.giorniNelMese(mese)
        let giorno = corrente ? min(Date().giorno, giorniMese) : giorniMese
        let giorniPrec = CalcoliDashboard.giorniNelMese(precedente)
        let cumulata = CalcoliDashboard.spesaCumulata(movimenti, mese: mese, giorni: giorno)
        let cumulataPrec = CalcoliDashboard.spesaCumulata(movPrec, mese: precedente, giorni: giorniPrec)
        let confronto = CalcoliConsigli.variazione(da: cumulataPrec[min(giorno, giorniPrec) - 1], a: cumulata.last ?? 0)

        ScrollView {
            VStack(spacing: 12) {
                BannerScadenza()

                if !daConfermare.isEmpty {
                    Button { foglio = .daConfermare } label: {
                        HStack {
                            Label(daConfermare.count == 1 ? "1 movimento da confermare" : "\(daConfermare.count) movimenti da confermare", systemImage: "bell.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    RiquadroKPI(titolo: "Entrate", valore: totali.entrate.euroTondo, nota: notaEntrate(movimenti), colore: Tinta.entrate)
                    RiquadroKPI(titolo: "Spese", valore: totali.spese.euroTondo,
                                nota: confronto.map { "\(CalcoliDashboard.percentoTondoConSegno($0)) vs \(precedente.meseBreve).\(corrente ? " allo stesso giorno" : "")" },
                                colore: Tinta.spese,
                                coloreNota: (confronto ?? 0) > 0 ? Tinta.spese : Tinta.entrate)
                    RiquadroKPI(titolo: "Risparmio", valore: totali.risparmio.euroTondo,
                                nota: totali.tassoSignificativo ? "\(CalcoliDashboard.percentoTondo(totali.tassoRisparmio)) delle entrate" : nil,
                                colore: Tinta.risparmio,
                                coloreNota: totali.risparmio >= 0 ? Tinta.entrate : Tinta.spese)
                    RiquadroKPI(titolo: "Investito", valore: totali.investito.euroTondo,
                                nota: notaInvestito(movimenti), colore: Tinta.investito)
                }

                Scheda(titolo: "Spesa accumulata nel mese") {
                    GraficoSpesaAccumulataMese(corrente: cumulata, precedente: cumulataPrec,
                                               nomeCorrente: mese.nomeMese, nomePrecedente: precedente.nomeMese,
                                               giorniMese: giorniMese)
                }

                SchedaCategorieBudgetMese(voci: Contabilita.spesePerCategoria(movimenti), categorie: categorie, mese: mese)

                SchedaSaldiMese(conti: conti)

                Scheda(titolo: "Ultimi movimenti") {
                    if movimenti.isEmpty {
                        Text("Nessun movimento in questo mese.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(movimenti.prefix(10)) { m in
                        Button { foglio = .modifica(m) } label: {
                            RigaMovimento(movimento: m).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                    NavigationLink {
                        ElencoMovimentiPeriodoView(titolo: mese.nomeMese + " " + String(mese.anno), da: mese, a: mese.inizioMeseSuccessivo)
                    } label: {
                        HStack {
                            Text("Vedi tutti")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }

                SchedaConsigli(titolo: "Questo mese", consigli: Consigli.delMese(mese, in: context))

                NavigationLink {
                    ControlloFineMeseView(mese: mese)
                } label: {
                    Label("Controllo di fine mese", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(mese.nomeMese)
        .navigationSubtitle(String(mese.anno))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { foglio = .nuovo } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nuovo movimento")
            }
        }
        .sheet(item: $foglio) { f in
            switch f {
            case .nuovo: NavigationStack { MovimentoEditorView() }
            case .modifica(let m): NavigationStack { MovimentoEditorView(movimento: m) }
            case .daConfermare: MovimentiDaConfermareView()
            }
        }
    }

    /// Categorie delle entrate, dalla più alta ("stipendio, rimborsi").
    private func notaEntrate(_ movimenti: [Movimento]) -> String? {
        let somme = Dictionary(grouping: movimenti.filter { $0.tipo == .entrata }) { $0.categoria?.nome ?? "altro" }
            .mapValues { $0.reduce(0) { $0 + $1.importo } }
        guard !somme.isEmpty else { return nil }
        return somme.sorted { $0.value > $1.value }.prefix(2).map { $0.key.lowercased() }.joined(separator: ", ")
    }

    /// "Broker 300 · Fondo 100"
    private func notaInvestito(_ movimenti: [Movimento]) -> String? {
        let piattaforme = CalcoliDashboard.investitoPerPiattaforma(movimenti)
        guard !piattaforme.isEmpty else { return nil }
        return piattaforme.prefix(2).map { "\($0.nome) \(CalcoliDashboard.numeroTondo($0.importo))" }.joined(separator: " · ")
    }
}

// MARK: - Componenti del mese

fileprivate enum FoglioMeseB: Identifiable {
    case nuovo, daConfermare, modifica(Movimento)
    var id: AnyHashable {
        switch self {
        case .nuovo: "nuovo"
        case .daConfermare: "daConfermare"
        case .modifica(let m): m.persistentModelID
        }
    }
}

fileprivate struct PuntoSpesaAccumulata: Identifiable {
    let serie: String
    let giorno: Int
    let valore: Double
    var id: String { "\(serie)-\(giorno)" }
}

/// Linea giorno per giorno del mese vs linea tratteggiata del mese precedente.
fileprivate struct GraficoSpesaAccumulataMese: View {
    let corrente: [Double]
    let precedente: [Double]
    let nomeCorrente: String
    let nomePrecedente: String
    let giorniMese: Int

    var body: some View {
        let punti = precedente.enumerated().map { PuntoSpesaAccumulata(serie: nomePrecedente, giorno: $0.offset + 1, valore: $0.element) }
            + corrente.enumerated().map { PuntoSpesaAccumulata(serie: nomeCorrente, giorno: $0.offset + 1, valore: $0.element) }
        Chart {
            ForEach(punti) { p in
                LineMark(x: .value("Giorno", p.giorno), y: .value("Spesa", p.valore))
                    .foregroundStyle(by: .value("Mese", p.serie))
                    .lineStyle(p.serie == nomePrecedente ? StrokeStyle(lineWidth: 2, dash: [4, 3]) : StrokeStyle(lineWidth: 2.5))
            }
            if let ultimo = corrente.last {
                PointMark(x: .value("Giorno", corrente.count), y: .value("Spesa", ultimo))
                    .foregroundStyle(Tinta.spese)
            }
        }
        .chartForegroundStyleScale([nomeCorrente: Tinta.spese, nomePrecedente: Color.gray.opacity(0.5)])
        .chartXScale(domain: 1...max(giorniMese, precedente.count, 2))
        .frame(height: 150)
    }
}

fileprivate struct RigaBudgetMese: Identifiable {
    let id: String
    let nome: String
    let coloreHex: String
    let speso: Double
    let budget: Double?
    let categoria: Categoria?
}

/// Barre speso/budget. Senza budget la barra è relativa alla categoria più alta; oltre budget in rosso.
fileprivate struct SchedaCategorieBudgetMese: View {
    let voci: [Contabilita.VoceCategoria]
    let categorie: [Categoria]
    let mese: Date

    var body: some View {
        var righe = voci.filter { $0.importo > 0 }.map {
            RigaBudgetMese(id: $0.id, nome: $0.nome, coloreHex: $0.coloreHex, speso: $0.importo,
                           budget: $0.categoria?.budgetMensile.flatMap { $0 > 0 ? $0 : nil }, categoria: $0.categoria)
        }
        for c in categorie where c.tipo == .spesa && (c.budgetMensile ?? 0) > 0 && !righe.contains(where: { $0.id == c.nome }) {
            righe.append(RigaBudgetMese(id: c.nome, nome: c.nome, coloreHex: c.coloreHex, speso: 0, budget: c.budgetMensile, categoria: c))
        }
        let massimo = max(righe.map(\.speso).max() ?? 1, 1)
        let senzaBudget = !righe.contains { $0.budget != nil }

        return Scheda(titolo: "Categorie", etichetta: senzaBudget && !righe.isEmpty ? "nessun budget impostato" : nil) {
            if righe.isEmpty {
                Text("Nessuna spesa in questo mese.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(righe) { r in
                let oltre = r.budget.map { r.speso > $0 } ?? false
                NavigationLink {
                    ElencoMovimentiPeriodoView(titolo: r.nome, da: mese, a: mese.inizioMeseSuccessivo, categoria: r.categoria)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(r.nome)
                            Spacer()
                            Text(r.budget.map { "\(CalcoliDashboard.numeroTondo(r.speso)) / \($0.euroTondo)" } ?? r.speso.euroTondo)
                                .monospacedDigit()
                                .foregroundStyle(oltre ? Tinta.spese : Color.primary)
                        }
                        .font(.subheadline)
                        ProgressView(value: min(r.speso / (r.budget ?? massimo), 1))
                            .tint(oltre ? Tinta.spese : Color(hex: r.coloreHex))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(r.categoria == nil)
            }
        }
    }
}

/// Saldi attuali dei conti attivi; le carte di credito sono il debito "da addebitare".
fileprivate struct SchedaSaldiMese: View {
    let conti: [Conto]

    private func nome(_ c: Conto) -> String {
        if c.tipo == .carta { return "\(c.nome) · da addebitare" }
        if let t = c.tassoAnnuo, t > 0 {
            return "\(c.nome) (\((t / 100).formatted(.percent.precision(.fractionLength(0...2)).locale(localeIT))))"
        }
        return c.nome
    }

    var body: some View {
        Scheda(titolo: "Saldi") {
            ForEach(conti) { c in
                HStack {
                    Text(nome(c))
                    Spacer()
                    Text(Contabilita.saldo(c).euro).monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(c.tipo == .carta ? Color.secondary : Color.primary)
            }
            Divider()
            NavigationLink {
                ContiView()
            } label: {
                HStack {
                    Text("Conti e contanti")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }
}
