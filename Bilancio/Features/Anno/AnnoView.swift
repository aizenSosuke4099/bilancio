import SwiftUI
import SwiftData
import Charts

/// Tab "Anno": riepilogo annuale con KPI, grafici, tabella mese per mese e consigli.
struct AnnoView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Movimento.data, order: .reverse) private var tutti: [Movimento]
    @State private var anno = Date().anno

    /// Anni da proporre: dal primo movimento all'ultimo, sempre compreso l'anno corrente.
    private var anni: [Int] {
        let oggi = Date().anno
        let primo = min(tutti.last?.data.anno ?? oggi, oggi)
        let ultimo = max(tutti.first?.data.anno ?? oggi, oggi)
        return Array((primo...ultimo).reversed())
    }

    var body: some View {
        let oggi = Date()
        let da = inizioAnno(anno), a = inizioAnno(anno + 1)
        let movimenti = tutti.filter { $0.data >= da && $0.data < a }
        let totali = Contabilita.totali(movimenti)
        let gruppi = Dictionary(grouping: movimenti) { $0.data.inizioMese }
        let ultimoMese = anno == oggi.anno ? oggi.mese : 12
        let mesi = (1...ultimoMese).map { m in
            let inizio = inizioMese(anno: anno, mese: m)
            return DatiMeseAnno(mese: inizio, totali: Contabilita.totali(gruppi[inizio] ?? []), haDati: gruppi[inizio] != nil)
        }
        let mesiDati = mesi.filter(\.haDati)
        let nMesi = Double(max(mesiDati.count, 1))
        let piattaforme = CalcoliDashboard.investitoPerPiattaforma(movimenti)
        let patrimonio = CalcoliDashboard.patrimonio(mesi: [da.aggiungendo(mesi: -1)] + mesi.map(\.mese), in: context)
        let patrimonioFine = patrimonio.last?.totale ?? 0
        let variazionePatrimonio = patrimonioFine - (patrimonio.first?.totale ?? 0)

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    BannerScadenza()

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        RiquadroKPI(titolo: "Entrate", valore: totali.entrate.euroTondo,
                                    nota: "media \((totali.entrate / nMesi).euroTondo)/mese", colore: Tinta.entrate)
                        RiquadroKPI(titolo: "Spese", valore: totali.spese.euroTondo,
                                    nota: "media \((totali.spese / nMesi).euroTondo)/mese", colore: Tinta.spese)
                        RiquadroKPI(titolo: "Risparmio", valore: totali.risparmio.euroTondo,
                                    nota: totali.tassoSignificativo ? "\(CalcoliDashboard.percentoTondo(totali.tassoRisparmio)) delle entrate" : nil,
                                    colore: Tinta.risparmio,
                                    coloreNota: totali.risparmio >= 0 ? Tinta.entrate : Tinta.spese)
                        RiquadroKPI(titolo: "Investito", valore: totali.investito.euroTondo,
                                    nota: piattaforme.isEmpty ? nil : "\(piattaforme.prefix(3).map(\.nome).joined(separator: ", "))\(piattaforme.count > 3 ? "…" : "")",
                                    colore: Tinta.investito)
                    }
                    RiquadroKPI(titolo: "Patrimonio netto", valore: patrimonioFine.euroTondo,
                                nota: "\(variazionePatrimonio >= 0 ? "+" : "−")\(abs(variazionePatrimonio).euroTondo) da gennaio · conti + contanti + investimenti",
                                colore: Tinta.patrimonio,
                                coloreNota: variazionePatrimonio >= 0 ? Tinta.entrate : Tinta.spese)

                    Scheda(titolo: "Entrate e spese per mese") {
                        GraficoEntrateSpeseAnno(mesi: mesi)
                    }

                    SchedaCiambellaAnno(voci: Contabilita.spesePerCategoria(movimenti).filter { $0.importo > 0 }, anno: anno)

                    Scheda(titolo: "Patrimonio nel tempo") {
                        GraficoPatrimonioAnno(punti: patrimonio)
                    }

                    SchedaTabellaMesiAnno(mesi: mesiDati, totali: totali)

                    SchedaConsigli(titolo: "Consigli dell'anno", consigli: Consigli.dellAnno(anno, in: context))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(anno))
            .navigationSubtitle(sottotitolo(mesiDati))
            .toolbarTitleMenu {
                Picker("Anno", selection: $anno) {
                    ForEach(anni, id: \.self) { Text(String($0)).tag($0) }
                }
            }
        }
    }

    /// "Riepilogo annuale · gen–nov"
    private func sottotitolo(_ mesi: [DatiMeseAnno]) -> String {
        guard let primo = mesi.first, let ultimo = mesi.last else { return String(localized: "Riepilogo annuale") }
        if primo.mese == ultimo.mese { return String(localized: "Riepilogo annuale · \(primo.mese.meseBreve)") }
        return String(localized: "Riepilogo annuale · \(primo.mese.meseBreve)–\(ultimo.mese.meseBreve)")
    }
}

// MARK: - Componenti dell'anno

fileprivate struct DatiMeseAnno: Identifiable {
    let mese: Date
    let totali: Contabilita.Totali
    let haDati: Bool
    var id: Date { mese }
}

/// Barre entrate/spese per mese + linea del risparmio.
fileprivate struct GraficoEntrateSpeseAnno: View {
    let mesi: [DatiMeseAnno]

    var body: some View {
        let entrate = String(localized: "Entrate"), spese = String(localized: "Spese"), risparmio = String(localized: "Risparmio")
        Chart {
            ForEach(mesi) { d in
                BarMark(x: .value("Mese", d.mese, unit: .month), y: .value("Importo", d.totali.entrate))
                    .foregroundStyle(by: .value("Serie", entrate))
                    .position(by: .value("Serie", entrate))
                BarMark(x: .value("Mese", d.mese, unit: .month), y: .value("Importo", d.totali.spese))
                    .foregroundStyle(by: .value("Serie", spese))
                    .position(by: .value("Serie", spese))
                LineMark(x: .value("Mese", d.mese, unit: .month), y: .value("Importo", d.totali.risparmio))
                    .foregroundStyle(by: .value("Serie", risparmio))
                    .symbol(.circle)
                    .symbolSize(20)
            }
        }
        .chartForegroundStyleScale([entrate: Tinta.entrate, spese: Tinta.spese, risparmio: Color.primary])
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
            }
        }
        
        .frame(height: 190)
    }
}

fileprivate struct FettaAnno: Identifiable {
    let id: String
    let nome: String
    let colore: Color
    let importo: Double
    let categoria: Categoria?
}

/// Ciambella delle spese per categoria: le prime 5 + "Altro"; tocco su una categoria → i suoi movimenti dell'anno.
fileprivate struct SchedaCiambellaAnno: View {
    let voci: [Contabilita.VoceCategoria]
    let anno: Int

    var body: some View {
        let totale = voci.reduce(0) { $0 + $1.importo }
        var fette = voci.prefix(5).map { FettaAnno(id: $0.id, nome: $0.nome, colore: Color(hex: $0.coloreHex), importo: $0.importo, categoria: $0.categoria) }
        let resto = voci.dropFirst(5).reduce(0) { $0 + $1.importo }
        if resto > 0 { fette.append(FettaAnno(id: "_altre", nome: String(localized: "Altre categorie"), colore: Color(.systemGray4), importo: resto, categoria: nil)) }

        return Scheda(titolo: "Dove sono andati i soldi") {
            if fette.isEmpty {
                Text("Nessuna spesa nell'anno.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 14) {
                    Chart(fette) { f in
                        SectorMark(angle: .value("Importo", f.importo), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(f.colore)
                            .cornerRadius(3)
                    }
                    .frame(width: 120, height: 120)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(fette) { f in
                            let riga = HStack(spacing: 6) {
                                Circle().fill(f.colore).frame(width: 8, height: 8)
                                Text(f.nome).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(CalcoliDashboard.percentoTondo(f.importo / totale)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .font(.caption)
                            .contentShape(Rectangle())
                            if let c = f.categoria {
                                NavigationLink {
                                    ElencoMovimentiPeriodoView(titolo: f.nome + " " + String(anno), da: inizioAnno(anno), a: inizioAnno(anno + 1), categoria: c)
                                } label: { riga }
                                .buttonStyle(.plain)
                            } else {
                                riga
                            }
                        }
                    }
                }
                if voci.count > 5 {
                    NavigationLink {
                        CategorieAnnoView(voci: voci, anno: anno)
                    } label: {
                        HStack {
                            Text("Tutte le categorie")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
    }
}

/// Elenco completo delle categorie dell'anno.
fileprivate struct CategorieAnnoView: View {
    let voci: [Contabilita.VoceCategoria]
    let anno: Int

    var body: some View {
        let totale = voci.reduce(0) { $0 + $1.importo }
        List(voci) { v in
            NavigationLink {
                ElencoMovimentiPeriodoView(titolo: v.nome + " " + String(anno), da: inizioAnno(anno), a: inizioAnno(anno + 1), categoria: v.categoria)
            } label: {
                HStack(spacing: 10) {
                    IconaCategoria(categoria: v.categoria)
                    Text(v.nome)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(v.importo.euroTondo).monospacedDigit()
                        Text(CalcoliDashboard.percentoTondo(v.importo / totale)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(v.categoria == nil)
        }
        .navigationTitle(String(localized: "Spese \(String(anno))"))
    }
}

/// Area impilata: investimenti sotto, conti + contanti sopra, a fine mese.
fileprivate struct GraficoPatrimonioAnno: View {
    let punti: [CalcoliDashboard.PuntoPatrimonio]

    var body: some View {
        let investimenti = String(localized: "Investimenti"), liquidita = String(localized: "Conti + contanti")
        Chart {
            ForEach(punti) { p in
                AreaMark(x: .value("Data", p.mese.inizioMeseSuccessivo), y: .value("Valore", p.investimenti))
                    .foregroundStyle(by: .value("Tipo", investimenti))
                AreaMark(x: .value("Data", p.mese.inizioMeseSuccessivo), y: .value("Valore", p.liquidita))
                    .foregroundStyle(by: .value("Tipo", liquidita))
            }
        }
        .chartForegroundStyleScale([investimenti: Color(hex: "#6366F1"), liquidita: Color(hex: "#C7D2FE")])
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow))
            }
        }
        
        .frame(height: 150)
    }
}

/// Tabella Entrate / Spese / Risparmio / % con riga totale. Mesi con tasso di risparmio basso in rosso; tocco → dettaglio del mese.
fileprivate struct SchedaTabellaMesiAnno: View {
    let mesi: [DatiMeseAnno]
    let totali: Contabilita.Totali

    /// Sotto questo tasso di risparmio il mese è segnato in rosso.
    private let sogliaBassa = 0.2

    var body: some View {
        Scheda(titolo: "Mese per mese", etichetta: mesi.isEmpty ? nil : "tocca un mese") {
            RigaTabellaAnno(etichetta: "", entrate: String(localized: "Entrate"), spese: String(localized: "Spese"),
                            risparmio: String(localized: "Risp.", comment: "Intestazione abbreviata della colonna Risparmio"), tasso: "%", colore: .secondary)
            Divider()
            ForEach(mesi) { d in
                let basso = d.totali.entrate > 0 ? d.totali.tassoRisparmio < sogliaBassa : d.totali.spese > 0
                NavigationLink {
                    MeseContenuto(mese: d.mese)
                } label: {
                    riga(d.mese.meseBreve.capitalized(with: .current), d.totali, basso: basso)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
            riga(String(localized: "Tot", comment: "Riga del totale annuo, abbreviato"), totali, basso: false).bold()
        }
    }

    private func riga(_ etichetta: String, _ t: Contabilita.Totali, basso: Bool) -> RigaTabellaAnno {
        RigaTabellaAnno(etichetta: etichetta,
                        entrate: CalcoliDashboard.numeroTondo(t.entrate),
                        spese: CalcoliDashboard.numeroTondo(t.spese),
                        risparmio: CalcoliDashboard.numeroTondo(t.risparmio),
                        tasso: t.entrate > 0 ? CalcoliDashboard.percentoTondo(t.tassoRisparmio) : "–",
                        rosso: basso)
    }
}

fileprivate struct RigaTabellaAnno: View {
    let etichetta: String
    let entrate: String
    let spese: String
    let risparmio: String
    let tasso: String
    var rosso = false
    var colore: Color = .primary

    var body: some View {
        HStack(spacing: 4) {
            Text(etichetta).frame(width: 36, alignment: .leading)
            Text(entrate).frame(maxWidth: .infinity, alignment: .trailing)
            Text(spese).frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(rosso ? Tinta.spese : colore)
            Text(risparmio).frame(maxWidth: .infinity, alignment: .trailing)
            Text(tasso).frame(width: 44, alignment: .trailing)
                .foregroundStyle(rosso ? Tinta.spese : colore)
        }
        .foregroundStyle(colore)
        .font(.footnote.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
