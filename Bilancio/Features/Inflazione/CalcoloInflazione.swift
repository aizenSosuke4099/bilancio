import Foundation

/// Inflazione personale: funzioni pure (niente SwiftData), verificate da `autoverifica()`.
enum CalcoloInflazione {

    /// Un acquisto di un prodotto. `prezzo` è confrontabile nel tempo (€/kg, €/l o €/pz).
    struct Acquisto {
        let data: Date
        let prezzo: Double
        let spesa: Double
    }

    private static let giorno: TimeInterval = 86_400

    /// Variazione annua del prezzo: media degli ultimi 3 mesi contro la media di un anno prima
    /// (acquisti tra 15 e 9 mesi prima dell'ultimo). Con uno storico più breve: primo contro ultimo acquisto.
    /// In entrambi i casi la variazione è riportata su base annua; servono almeno 90 giorni di distanza.
    static func variazioneAnnua(_ acquisti: [Acquisto]) -> Double? {
        let a = acquisti.filter { $0.prezzo > 0 }.sorted { $0.data < $1.data }
        guard let primo = a.first, let ultimo = a.last else { return nil }
        let rif = ultimo.data
        var recenti = a.filter { $0.data > rif.addingTimeInterval(-90 * giorno) }
        var vecchi = a.filter { $0.data >= rif.addingTimeInterval(-455 * giorno) && $0.data <= rif.addingTimeInterval(-275 * giorno) }
        if vecchi.isEmpty {
            recenti = [ultimo]
            vecchi = [primo]
        }
        let distanza = (dataMedia(recenti) - dataMedia(vecchi)) / giorno
        guard distanza >= 90 else { return nil }
        return pow(media(recenti) / media(vecchi), 365 / distanza) - 1
    }

    /// Media delle variazioni annue pesata con la spesa degli ultimi 12 mesi. nil se nessun prodotto è calcolabile.
    static func inflazionePersonale(_ prodotti: [[Acquisto]], oggi: Date) -> (valore: Double, prodotti: Int)? {
        let inizio = oggi.addingTimeInterval(-365 * giorno)
        var somma = 0.0, pesi = 0.0, n = 0
        for acquisti in prodotti {
            let peso = acquisti.filter { $0.data >= inizio && $0.data <= oggi }.reduce(0) { $0 + $1.spesa }
            guard peso > 0, let v = variazioneAnnua(acquisti) else { continue }
            somma += v * peso
            pesi += peso
            n += 1
        }
        return pesi > 0 ? (somma / pesi, n) : nil
    }

    /// Indice mensile concatenato (base 100 nel primo mese): ogni mese si moltiplica per la variazione
    /// media dei prezzi rispetto al mese prima, pesata sulla spesa totale di ciascun prodotto.
    /// Un prodotto non riacquistato mantiene l'ultimo prezzo noto.
    static func indiceMensile(_ prodotti: [[Acquisto]], mesi: [Date]) -> [(mese: Date, indice: Double)] {
        guard mesi.count > 1 else { return mesi.map { (mese: $0, indice: 100.0) } }
        let pesi = prodotti.map { $0.reduce(0) { $0 + $1.spesa } }
        // prezzo noto a fine di ogni mese (riportato in avanti)
        let noti: [[Double?]] = prodotti.map { acquisti in
            var ultimo: Double?
            return mesi.indices.map { j in
                let fine = j + 1 < mesi.count ? mesi[j + 1] : .distantFuture
                let nelMese = acquisti.filter { $0.data >= mesi[j] && $0.data < fine && $0.prezzo > 0 }
                if !nelMese.isEmpty { ultimo = media(nelMese) }
                return ultimo
            }
        }
        var indice = [100.0]
        for j in 1..<mesi.count {
            var num = 0.0, den = 0.0
            for (p, prezzi) in noti.enumerated() {
                guard let prima = prezzi[j - 1], let ora = prezzi[j], pesi[p] > 0 else { continue }
                num += pesi[p] * ora / prima
                den += pesi[p]
            }
            indice.append(indice[j - 1] * (den > 0 ? num / den : 1))
        }
        return zip(mesi, indice).map { (mese: $0, indice: $1) }
    }

    // MARK: Formato e sgrammatura

    /// Formato letto dal testo della riga: "PASTA 500G" → (0.5, "kg"), "ACQUA 6X1,5L" → (9, "l").
    static func formatoDaTesto(_ testo: String) -> (quantita: Double, unita: String)? {
        let t = testo.lowercased().replacingOccurrences(of: ",", with: ".")
        guard let m = t.firstMatch(of: #/(?:(\d+)\s*[x×*]\s*)?(\d+(?:\.\d+)?)\s*(kg|gr|g|lt|l|ml|cl)\b/#),
              let q = Double(m.output.2), q > 0 else { return nil }
        let pezzi = m.output.1.flatMap { Double($0) } ?? 1
        switch m.output.3 {
        case "kg": return (pezzi * q, "kg")
        case "g", "gr": return (pezzi * q / 1000, "kg")
        case "ml": return (pezzi * q / 1000, "l")
        case "cl": return (pezzi * q / 100, "l")
        default: return (pezzi * q, "l")
        }
    }

    /// Prezzo nell'unità del prodotto: il formato scritto sulla riga vince su quello del prodotto.
    static func prezzoConfrontabile(prezzoConfezione: Double, testo: String, unita: String, formato: Double?) -> Double {
        let f = formatoDaTesto(testo).flatMap { $0.unita == unita ? $0.quantita : nil } ?? formato ?? 1
        return f > 0 ? prezzoConfezione / f : prezzoConfezione
    }

    struct CambioFormato {
        let prima: Double
        let dopo: Double
        let unita: String
        let data: Date
        /// Aumento del prezzo al kg/l dovuto al cambio di formato.
        let aumentoEffettivo: Double
    }

    /// Ultimo cambio di formato verso il basso con prezzo della confezione quasi uguale (±5%).
    static func sgrammatura(_ acquisti: [(data: Date, prezzoConfezione: Double, testo: String)]) -> CambioFormato? {
        let a = acquisti.sorted { $0.data < $1.data }.compactMap { x in formatoDaTesto(x.testo).map { (x.data, x.prezzoConfezione, $0) } }
        var trovato: CambioFormato?
        for i in a.indices.dropFirst() {
            let (f0, f1) = (a[i - 1].2, a[i].2)
            guard f0.unita == f1.unita, f1.quantita < f0.quantita * 0.99 else { continue }
            let prima = a[max(0, i - 3)..<i].map(\.1)
            let dopo = a[i..<min(a.count, i + 3)].map(\.1)
            let pPrima = prima.reduce(0, +) / Double(prima.count)
            let pDopo = dopo.reduce(0, +) / Double(dopo.count)
            guard pPrima > 0, abs(pDopo / pPrima - 1) <= 0.05 else { continue }
            trovato = CambioFormato(prima: f0.quantita, dopo: f1.quantita, unita: f1.unita, data: a[i].0,
                                    aumentoEffettivo: (pDopo / f1.quantita) / (pPrima / f0.quantita) - 1)
        }
        return trovato
    }

    // MARK: Utilità

    private static func media(_ a: [Acquisto]) -> Double { a.reduce(0) { $0 + $1.prezzo } / Double(max(a.count, 1)) }
    private static func dataMedia(_ a: [Acquisto]) -> TimeInterval {
        a.reduce(0) { $0 + $1.data.timeIntervalSinceReferenceDate } / Double(max(a.count, 1))
    }

    #if DEBUG
    /// Self-check: in DEBUG viene eseguito all'apertura della pagina Inflazione (anche da script `swiftc`).
    static func autoverifica() {
        let oggi = Date(timeIntervalSinceReferenceDate: 820_000_000)
        func giorni(_ n: Double) -> Date { oggi.addingTimeInterval(n * giorno) }
        func vicino(_ a: Double?, _ b: Double, _ tolleranza: Double = 0.001) -> Bool { a.map { abs($0 - b) < tolleranza } ?? false }

        assert(vicino(formatoDaTesto("ACQUA NATURALE 6X1,5L")?.quantita, 9))
        assert(formatoDaTesto("PANE COMUNE 500G")?.unita == "kg" && vicino(formatoDaTesto("PANE COMUNE 500G")?.quantita, 0.5))
        assert(vicino(formatoDaTesto("SPAGHETTI N.5 500G")?.quantita, 0.5))
        assert(vicino(formatoDaTesto("DENTIFRICIO 75ML")?.quantita, 0.075))
        assert(formatoDaTesto("UOVA FRESCHE X6") == nil)
        assert(vicino(prezzoConfrontabile(prezzoConfezione: 1, testo: "PASTA 500G", unita: "kg", formato: nil), 2))
        assert(vicino(prezzoConfrontabile(prezzoConfezione: 2.4, testo: "UOVA X6", unita: "pz", formato: 6), 0.4))

        // un anno esatto: +10%
        let annuale = [Acquisto(data: giorni(-365), prezzo: 1.00, spesa: 1), Acquisto(data: oggi, prezzo: 1.10, spesa: 1)]
        assert(vicino(variazioneAnnua(annuale), 0.10))
        // sei mesi: +5% → circa +10,3% annuo
        let semestrale = [Acquisto(data: giorni(-182.5), prezzo: 1.00, spesa: 1), Acquisto(data: oggi, prezzo: 1.05, spesa: 1)]
        assert(vicino(variazioneAnnua(semestrale), 0.1025))
        // troppo vicini: non calcolabile
        assert(variazioneAnnua([Acquisto(data: giorni(-30), prezzo: 1, spesa: 1), Acquisto(data: oggi, prezzo: 2, spesa: 1)]) == nil)

        // pesi: +10% con 100 € e −10% con 300 € → −5%
        let su = [Acquisto(data: giorni(-365), prezzo: 1.0, spesa: 50), Acquisto(data: oggi, prezzo: 1.1, spesa: 50)]
        let giu = [Acquisto(data: giorni(-365), prezzo: 1.0, spesa: 150), Acquisto(data: oggi, prezzo: 0.9, spesa: 150)]
        let p = inflazionePersonale([su, giu], oggi: oggi)
        assert(p?.prodotti == 2 && vicino(p?.valore, -0.05))
        // fuori dagli ultimi 12 mesi non pesa
        assert(inflazionePersonale([[Acquisto(data: giorni(-800), prezzo: 1, spesa: 9), Acquisto(data: giorni(-500), prezzo: 2, spesa: 9)]], oggi: oggi) == nil)

        // indice: 1,00 → 1,10 → (non riacquistato) → 100, 110, 110
        let m0 = giorni(-90), m1 = giorni(-60), m2 = giorni(-30)
        let indice = indiceMensile([[Acquisto(data: m0.addingTimeInterval(giorno), prezzo: 1.0, spesa: 1),
                                     Acquisto(data: m1.addingTimeInterval(giorno), prezzo: 1.1, spesa: 1)]], mesi: [m0, m1, m2])
        assert(indice.count == 3 && vicino(indice[1].indice, 110) && vicino(indice[2].indice, 110))

        // sgrammatura: 350 g → 320 g allo stesso prezzo = +9,4% al kg
        let biscotti = (0..<6).map { i in (data: giorni(Double(i) * 20), prezzoConfezione: 2.29, testo: i < 3 ? "BISCOTTI 350G" : "BISCOTTI 320G") }
        let s = sgrammatura(biscotti)
        assert(s != nil && vicino(s?.prima, 0.35) && vicino(s?.dopo, 0.32) && vicino(s?.aumentoEffettivo, 0.09375))
        // formato cambiato ma prezzo sceso in proporzione: nessun avviso
        assert(sgrammatura([(giorni(0), 2.0, "X 500G"), (giorni(10), 1.6, "X 400G")]) == nil)
    }
    #endif
}
