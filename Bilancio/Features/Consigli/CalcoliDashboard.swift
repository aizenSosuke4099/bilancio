import Foundation
import SwiftData

/// Calcoli in memoria usati da Anno, Mese e Consigli (area B). Quelli generali stanno in `Contabilita`.
enum CalcoliDashboard {

    // MARK: Formattazione

    /// 0.331 → "33%"
    static func percentoTondo(_ x: Double) -> String { x.formatted(.percent.precision(.fractionLength(0))) }
    /// 0.331 → "+33%"
    static func percentoTondoConSegno(_ x: Double) -> String { (x >= 0 ? "+" : "") + percentoTondo(x) }
    /// 2650.4 → "2.650"
    static func numeroTondo(_ x: Double) -> String { x.formatted(.number.precision(.fractionLength(0))) }

    // MARK: Mesi

    static func giorniNelMese(_ mese: Date) -> Int {
        calendario.range(of: .day, in: .month, for: mese)?.count ?? 30
    }

    /// Mesi distinti che hanno almeno un movimento (minimo 1, per fare le medie).
    static func mesiConDati(_ movimenti: [Movimento]) -> Int {
        max(1, Set(movimenti.map { $0.data.inizioMese }).count)
    }

    /// Spesa media mensile: sui mesi già conclusi quando ce ne sono, altrimenti il mese in corso riportato a mese intero
    /// (il 10 del mese, 400 € spesi non sono "400 € al mese").
    static func spesaMediaMensile(_ movimenti: [Movimento], oggi: Date = Date()) -> Double {
        let conclusi = movimenti.filter { $0.data < oggi.inizioMese }
        let media = Contabilita.totali(conclusi).spese / Double(mesiConDati(conclusi))
        if !conclusi.isEmpty, media > 0 { return media }
        return Contabilita.totali(movimenti).spese / max(Double(oggi.giorno) / Double(giorniNelMese(oggi)), 0.25)
    }

    /// Spesa accumulata giorno per giorno nel mese, dal giorno 1 al giorno `giorni` (indice 0 = giorno 1).
    static func spesaCumulata(_ movimenti: [Movimento], mese: Date, giorni: Int) -> [Double] {
        let da = mese.inizioMese, a = mese.inizioMeseSuccessivo
        var giornaliere = Array(repeating: 0.0, count: max(giorni, 1))
        for m in movimenti where m.tipo == .spesa && m.data >= da && m.data < a {
            let g = m.data.giorno
            if g <= giornaliere.count { giornaliere[g - 1] -= m.importo }
        }
        var somma = 0.0
        return giornaliere.map { somma += $0; return somma }
    }

    // MARK: Investimenti

    /// Investito per piattaforma, dalla più alta. La piattaforma viene dallo strumento delle operazioni collegate, altrimenti dal titolo.
    static func investitoPerPiattaforma(_ movimenti: [Movimento]) -> [(nome: String, importo: Double)] {
        var somme: [String: Double] = [:]
        for m in movimenti where m.tipo == .investimento {
            let piattaforma = m.operazioni.first?.strumento?.piattaforma ?? ""
            let nome = !piattaforma.isEmpty ? piattaforma : (m.titolo.isEmpty ? DatiIniziali.localizzato("Altro") : m.titolo)
            somme[nome, default: 0] -= m.importo
        }
        return somme.filter { $0.value > 0.005 }.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    /// Versamenti dell'anno (EUR) sui fondi pensione italiani, per piattaforma. Vuoto se non ci sono fondi pensione italiani.
    static func versatoFondiPensione(anno: Int, in context: ModelContext) -> [(nome: String, importo: Double)] {
        let strumenti = (try? context.fetch(FetchDescriptor<Strumento>(predicate: #Predicate { $0.fondoPensioneItaliano && !$0.archiviato }))) ?? []
        let da = inizioAnno(anno), a = inizioAnno(anno + 1)
        var somme: [String: Double] = [:]
        for s in strumenti {
            let nome = s.piattaforma.isEmpty ? s.nome : s.piattaforma
            somme[nome, default: 0] += s.operazioni
                .filter { $0.tipo.entraCapitale && $0.data >= da && $0.data < a && !Portafoglio.èSituazioneIniziale($0) }
                .reduce(0) { $0 + ($1.importo + $1.commissioni) * $1.cambioEUR }
        }
        return somme.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    /// Ricorrenze attive della categoria Abbonamenti, dalla più cara.
    static func abbonamenti(in context: ModelContext) -> [Ricorrenza] {
        let attive = (try? context.fetch(FetchDescriptor<Ricorrenza>(predicate: #Predicate { $0.attiva == true }))) ?? []
        return attive.filter { DatiIniziali.corrisponde($0.categoria?.nome, a: "Abbonamenti") }.sorted { $0.importoAnnuo > $1.importoAnnuo }
    }

    // MARK: Patrimonio nel tempo

    struct PuntoPatrimonio: Identifiable {
        /// Primo giorno del mese: il valore è quello a fine mese.
        let mese: Date
        let liquidita: Double
        let investimenti: Double
        var totale: Double { liquidita + investimenti }
        var id: Date { mese }
    }

    /// Patrimonio a fine mese per ciascun mese richiesto (si fermano al mese corrente).
    /// - Mese corrente: valori attuali.
    /// - Mesi con `SnapshotPatrimonio`: la fotografia salvata.
    /// - Mesi senza fotografia, ricostruzione approssimata:
    ///   liquidità = liquidità attuale − somma dei movimenti (sui conti attivi) successivi alla fine del mese;
    ///   investimenti ≈ capitale versato cumulato a fine mese (dalle `Operazione`), cioè senza guadagni/perdite di mercato.
    // ponytail: ricostruzione al versato, il grafico può "saltare" dove si passa da ricostruito a fotografia; servono gli storici dei prezzi per fare meglio.
    static func patrimonio(mesi: [Date], in context: ModelContext) -> [PuntoPatrimonio] {
        let oggi = Date().inizioMese
        let fotografie = (try? context.fetch(FetchDescriptor<SnapshotPatrimonio>())) ?? []
        let snapshot = Dictionary(fotografie.map { ($0.mese.inizioMese, $0) }, uniquingKeysWith: { a, b in a.aggiornatoIl > b.aggiornatoIl ? a : b })
        let conti = (try? context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { !$0.archiviato }))) ?? []
        let strumenti = (try? context.fetch(FetchDescriptor<Strumento>(predicate: #Predicate { !$0.archiviato }))) ?? []
        let liquiditaOggi = conti.reduce(0) { $0 + Contabilita.saldo($1) }
        let investimentiOggi = strumenti.reduce(0) { $0 + Portafoglio.valoreEUR($1) }
        let movimentiConti = conti.flatMap(\.movimenti)
        let operazioni = strumenti.flatMap(\.operazioni)

        return mesi.map(\.inizioMese).filter { $0 <= oggi }.map { m in
            if m == oggi { return PuntoPatrimonio(mese: m, liquidita: liquiditaOggi, investimenti: investimentiOggi) }
            if let s = snapshot[m] { return PuntoPatrimonio(mese: m, liquidita: s.liquidita, investimenti: s.investimenti) }
            let fine = m.inizioMeseSuccessivo
            let dopo = movimentiConti.filter { $0.data >= fine }.reduce(0) { $0 + $1.importo }
            let versato = operazioni.filter { $0.data < fine }.reduce(0) { $0 + versatoEUR($1) }
            return PuntoPatrimonio(mese: m, liquidita: liquiditaOggi - dopo, investimenti: versato)
        }
    }

    /// Come `Portafoglio.versatoEUR`, ma per una singola operazione (serve per fermarsi a una data).
    private static func versatoEUR(_ op: Operazione) -> Double {
        if op.tipo.entraCapitale { return (op.importo + op.commissioni) * op.cambioEUR }
        if op.tipo.esceCapitale { return -op.importo * op.cambioEUR }
        if op.tipo == .commissione { return op.importo * op.cambioEUR }
        return 0
    }

    // MARK: Prezzi dei prodotti

    struct Rincaro {
        let nome: String
        let prezzo: Double
        let prezzoPrima: Double
        let dataPrima: Date
        let variazione: Double
    }

    static func prezzoUnitario(_ r: RigaScontrino) -> Double {
        if r.prezzoUnitario > 0 { return r.prezzoUnitario }
        return r.quantita > 0 ? r.totale / r.quantita : r.totale
    }

    /// Acquisti di un prodotto (data dello scontrino, prezzo unitario), dal più vecchio.
    private static func acquisti(_ p: Prodotto) -> [(data: Date, prezzo: Double, totale: Double)] {
        p.righe.compactMap { r in r.scontrino.map { (data: $0.data, prezzo: prezzoUnitario(r), totale: r.totale) } }
            .filter { $0.prezzo > 0 }
            .sorted { $0.data < $1.data }
    }

    /// Prodotti comprati nel mese a un prezzo unitario > 10% rispetto all'acquisto precedente, dal rincaro più forte.
    static func rincari(mese: Date, in context: ModelContext) -> [Rincaro] {
        let prodotti = (try? context.fetch(FetchDescriptor<Prodotto>())) ?? []
        let da = mese.inizioMese, a = mese.inizioMeseSuccessivo
        var risultato: [Rincaro] = []
        for p in prodotti {
            let lista = acquisti(p)
            guard let ultimo = lista.last(where: { $0.data >= da && $0.data < a }) else { continue }
            let giorno = calendario.startOfDay(for: ultimo.data)
            guard let prima = lista.last(where: { $0.data < giorno }),
                  let v = CalcoliConsigli.variazione(da: prima.prezzo, a: ultimo.prezzo), v > 0.10 else { continue }
            risultato.append(Rincaro(nome: p.nome, prezzo: ultimo.prezzo, prezzoPrima: prima.prezzo, dataPrima: prima.data, variazione: v))
        }
        return risultato.sorted { $0.variazione > $1.variazione }
    }

    /// Inflazione personale dell'anno: variazione primo → ultimo acquisto nell'anno dei prodotti riacquistati,
    /// pesata sulla spesa per prodotto. nil se i prodotti riacquistati sono meno di 3.
    // ponytail: variazione non annualizzata (primo e ultimo acquisto possono distare pochi mesi); confronto anno su anno quando ci sarà storico.
    static func inflazionePersonale(anno: Int, in context: ModelContext) -> Double? {
        let prodotti = (try? context.fetch(FetchDescriptor<Prodotto>())) ?? []
        let da = inizioAnno(anno), a = inizioAnno(anno + 1)
        var campioni: [(primo: Double, ultimo: Double, peso: Double)] = []
        for p in prodotti {
            let lista = acquisti(p).filter { $0.data >= da && $0.data < a }
            guard let primo = lista.first, let ultimo = lista.last,
                  calendario.startOfDay(for: primo.data) < calendario.startOfDay(for: ultimo.data) else { continue }
            campioni.append((primo.prezzo, ultimo.prezzo, lista.reduce(0) { $0 + $1.totale }))
        }
        guard campioni.count >= 3 else { return nil }
        return CalcoliConsigli.inflazionePersonale(campioni)
    }
}
