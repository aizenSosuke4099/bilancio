import Foundation

// Logica pura dell'area Investimenti: niente rete, niente database.
// Lettura delle risposte Yahoo, ripartizione del PAC, validazione ISIN.
//
// Self-check (dalla cartella del progetto, sul Mac):
//   echo 'CalcoliInvestimenti.autoverifica(cartellaEsempi: CommandLine.arguments.dropFirst().first); print("OK")' > /tmp/main.swift
//   swiftc -D DEBUG Bilancio/Core/Formato.swift Bilancio/Features/Investimenti/CalcoliInvestimenti.swift /tmp/main.swift -o /tmp/verifica && /tmp/verifica [cartella con JSON Yahoo]

enum CalcoliInvestimenti {

    // MARK: - Yahoo Finance

    /// Un listino di borsa di uno strumento (es. "EUNL.DE" su XETRA).
    struct Listino: Hashable, Identifiable {
        let simbolo: String
        let nome: String
        let borsa: String
        let tipo: String
        var id: String { simbolo }
    }

    struct Quotazione {
        let prezzo: Double
        let valuta: String
        let data: Date?
        let nome: String?
    }

    /// Chiusura di un giorno (o di un mese, con data = primo giorno del mese).
    struct Chiusura: Codable, Hashable {
        let data: Date
        let prezzo: Double
    }

    private struct RispostaRicerca: Decodable {
        struct Voce: Decodable {
            let symbol: String?
            let shortname: String?
            let longname: String?
            let exchDisp: String?
            let typeDisp: String?
        }
        let quotes: [Voce]?
    }

    private struct RispostaGrafico: Decodable {
        struct Grafico: Decodable { let result: [Risultato]? }
        struct Risultato: Decodable {
            let meta: Meta
            let timestamp: [Double]?
            let indicators: Indicatori
        }
        struct Meta: Decodable {
            let currency: String?
            let regularMarketPrice: Double?
            let regularMarketTime: Double?
            let longName: String?
            let shortName: String?
        }
        struct Indicatori: Decodable {
            struct Serie: Decodable { let close: [Double?]? }
            let quote: [Serie]?
        }
        let chart: Grafico
    }

    static func listini(daRicerca data: Data) -> [Listino] {
        guard let r = try? JSONDecoder().decode(RispostaRicerca.self, from: data) else { return [] }
        return (r.quotes ?? []).compactMap { v in
            guard let s = v.symbol, !s.isEmpty else { return nil }
            return Listino(simbolo: s, nome: v.longname ?? v.shortname ?? s, borsa: v.exchDisp ?? "", tipo: v.typeDisp ?? "")
        }
    }

    /// Listini in euro prima (XETRA, Milano, Amsterdam, Parigi, altre borse europee), poi gli altri.
    static func ordinaPerEuro(_ listini: [Listino]) -> [Listino] {
        let preferiti = [".DE", ".MI", ".AS", ".PA", ".F", ".SG", ".MU", ".BE", ".DU", ".HM", ".VI", ".BR", ".MC", ".LS", ".IR"]
        func rango(_ l: Listino) -> Int {
            preferiti.firstIndex { l.simbolo.uppercased().hasSuffix($0) } ?? preferiti.count
        }
        return listini.enumerated()
            .sorted { (rango($0.element), $0.offset) < (rango($1.element), $1.offset) }
            .map(\.element)
    }

    /// Borsa di Londra in pence: si riporta in sterline.
    private static func normalizza(_ valuta: String?) -> (valuta: String, fattore: Double) {
        switch valuta {
        case "GBp", "GBX": ("GBP", 0.01)
        case let v?: (v.uppercased(), 1)
        case nil: ("EUR", 1)
        }
    }

    static func quotazione(daGrafico data: Data) -> Quotazione? {
        guard let r = try? JSONDecoder().decode(RispostaGrafico.self, from: data),
              let meta = r.chart.result?.first?.meta,
              let prezzo = meta.regularMarketPrice, prezzo > 0 else { return nil }
        let n = normalizza(meta.currency)
        return Quotazione(prezzo: prezzo * n.fattore, valuta: n.valuta,
                          data: meta.regularMarketTime.map { Date(timeIntervalSince1970: $0) },
                          nome: meta.longName ?? meta.shortName)
    }

    /// Chiusure (giornaliere o mensili, come chieste a Yahoo), senza i buchi.
    static func chiusure(daGrafico data: Data) -> [Chiusura] {
        guard let r = try? JSONDecoder().decode(RispostaGrafico.self, from: data),
              let ris = r.chart.result?.first,
              let tempi = ris.timestamp,
              let prezzi = ris.indicators.quote?.first?.close else { return [] }
        let f = normalizza(ris.meta.currency).fattore
        return zip(tempi, prezzi).compactMap { t, p in
            guard let p, p > 0 else { return nil }
            return Chiusura(data: Date(timeIntervalSince1970: t), prezzo: p * f)
        }
    }

    /// Una chiusura per mese (data = primo giorno del mese, prezzo = ultimo del mese).
    static func mensili(_ chiusure: [Chiusura]) -> [Chiusura] {
        var perMese: [Date: Chiusura] = [:]
        for c in chiusure.sorted(by: { $0.data < $1.data }) {
            // Yahoo mette l'inizio mese alla mezzanotte della borsa (in UTC è il giorno prima): +12 h lo riporta nel mese giusto
            let mese = c.data.addingTimeInterval(12 * 3600).inizioMese
            perMese[mese] = Chiusura(data: mese, prezzo: c.prezzo)
        }
        return perMese.values.sorted { $0.data < $1.data }
    }

    /// Chiusura del giorno indicato o, se la borsa era chiusa, dell'ultimo giorno di borsa precedente.
    static func chiusura(_ chiusure: [Chiusura], al data: Date) -> Double? {
        let fine = calendario.startOfDay(for: data).aggiungendo(giorni: 1)
        return chiusure.filter { $0.data < fine }.max { $0.data < $1.data }?.prezzo
    }

    // MARK: - Piano di accumulo

    /// Indici delle allocazioni valide a `data`: il set con la "valida dal" più recente ≤ data.
    /// Se la data precede tutti i set (PAC generato all'indietro), vale il primo set.
    static func indiciValidi(_ validaDal: [Date], al data: Date) -> [Int] {
        let giorni = validaDal.map { calendario.startOfDay(for: $0) }
        let giorno = calendario.startOfDay(for: data)
        guard let scelto = giorni.filter({ $0 <= giorno }).max() ?? giorni.min() else { return [] }
        return giorni.indices.filter { giorni[$0] == scelto }
    }

    /// Giorno di esecuzione nel mese (il 31 diventa l'ultimo giorno dei mesi corti).
    static func dataEsecuzione(mese: Date, giorno: Int) -> Date {
        let inizio = mese.inizioMese
        let giorniNelMese = calendario.range(of: .day, in: .month, for: inizio)?.count ?? 28
        return inizio.aggiungendo(giorni: min(max(giorno, 1), giorniNelMese) - 1)
    }

    /// Mesi (primo giorno) da generare: dal mese dopo l'ultima generazione (o dal mese di `oggi`)
    /// fino all'ultimo il cui giorno di esecuzione è già arrivato.
    static func mesiDaGenerare(ultimaGenerazione: Date?, giorno: Int, oggi: Date) -> [Date] {
        var mese = ultimaGenerazione.map { $0.inizioMese.aggiungendo(mesi: 1) } ?? oggi.inizioMese
        var mesi: [Date] = []
        while dataEsecuzione(mese: mese, giorno: giorno) <= oggi, mesi.count < 240 {
            mesi.append(mese)
            mese = mese.aggiungendo(mesi: 1)
        }
        return mesi
    }

    /// Quota di un PAC su uno strumento. `percentuale` 0–100, `cambioEUR` = euro per 1 unità della valuta dello strumento,
    /// `prezzoUnitario` nella valuta dello strumento (obbligazioni: prezzo/100). Senza prezzo le quote sono 0.
    static func ripartizione(importoEUR: Double, percentuale: Double, prezzoUnitario: Double?, cambioEUR: Double) -> (importo: Double, quote: Double) {
        let importo = importoEUR * percentuale / 100 / (cambioEUR > 0 ? cambioEUR : 1)
        guard let p = prezzoUnitario, p > 0 else { return (importo, 0) }
        return (importo, importo / p)
    }

    /// Le percentuali di un PAC devono fare 100 (tolleranza di arrotondamento).
    static func sommaCento(_ percentuali: [Double]) -> Bool {
        abs(percentuali.reduce(0, +) - 100) < 0.01
    }

    // MARK: - ISIN

    /// Formato (2 lettere + 9 alfanumerici + 1 cifra) e cifra di controllo (Luhn sulle cifre, lettere A=10…Z=35).
    static func isinValido(_ testo: String) -> Bool {
        let s = Array(testo.uppercased())
        guard s.count == 12,
              s[0...1].allSatisfy({ $0.isASCII && $0.isLetter }),
              s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              s[11].isNumber else { return false }
        let cifre: [Int] = s.flatMap { c -> [Int] in
            if let n = c.wholeNumberValue { return [n] }
            return String(Int(c.asciiValue!) - 55).compactMap(\.wholeNumberValue)
        }
        var somma = 0
        for (i, d) in cifre.reversed().enumerated() {
            if i % 2 == 1 { let x = d * 2; somma += x > 9 ? x - 9 : x } else { somma += d }
        }
        return somma % 10 == 0
    }

    // MARK: - Testo

    /// Numero da mettere in un campo di testo modificabile ("1234,5678").
    static func testoNumero(_ x: Double?) -> String {
        guard let x else { return "" }
        return x.formatted(.number.precision(.fractionLength(0...6)).grouping(.never))
    }

    #if DEBUG
    static func autoverifica(cartellaEsempi: String? = nil) {
        func giorno(_ a: Int, _ m: Int, _ g: Int) -> Date { calendario.date(from: DateComponents(year: a, month: m, day: g))! }
        func circa(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

        // set di allocazioni: 1 gen 2026 (60/40), 1 giu 2026 (70/30)
        let date = [giorno(2026, 1, 1), giorno(2026, 1, 1), giorno(2026, 6, 1), giorno(2026, 6, 1)]
        assert(indiciValidi(date, al: giorno(2026, 3, 15)) == [0, 1])
        assert(indiciValidi(date, al: giorno(2026, 6, 1)) == [2, 3])
        assert(indiciValidi(date, al: giorno(2026, 12, 2)) == [2, 3])
        assert(indiciValidi(date, al: giorno(2025, 5, 1)) == [0, 1], "prima di tutti i set vale il primo")
        assert(indiciValidi([], al: giorno(2026, 1, 1)).isEmpty)
        assert(sommaCento([70, 30]) && sommaCento([33.33, 33.33, 33.34]) && !sommaCento([60, 30]))

        assert(dataEsecuzione(mese: giorno(2026, 2, 1), giorno: 31) == giorno(2026, 2, 28))
        assert(dataEsecuzione(mese: giorno(2026, 11, 1), giorno: 5) == giorno(2026, 11, 5))
        let oggi = giorno(2026, 11, 14).addingTimeInterval(10 * 3600)
        assert(mesiDaGenerare(ultimaGenerazione: giorno(2026, 9, 1), giorno: 5, oggi: oggi) == [giorno(2026, 10, 1), giorno(2026, 11, 1)])
        assert(mesiDaGenerare(ultimaGenerazione: giorno(2026, 9, 1), giorno: 20, oggi: oggi) == [giorno(2026, 10, 1)])
        assert(mesiDaGenerare(ultimaGenerazione: giorno(2026, 9, 1), giorno: 14, oggi: oggi).count == 2, "il giorno stesso si genera")
        assert(mesiDaGenerare(ultimaGenerazione: nil, giorno: 20, oggi: oggi).isEmpty)
        assert(mesiDaGenerare(ultimaGenerazione: giorno(2026, 11, 1), giorno: 1, oggi: oggi).isEmpty)

        // 200 € al 60% di un ETF a 100 € → 120 €, 1,2 quote
        let a = ripartizione(importoEUR: 200, percentuale: 60, prezzoUnitario: 100, cambioEUR: 1)
        assert(circa(a.importo, 120) && circa(a.quote, 1.2))
        // 100 € su un fondo in CHF (1 CHF = 1,08 €), senza prezzo → versamento di 92,59 CHF
        let b = ripartizione(importoEUR: 100, percentuale: 100, prezzoUnitario: nil, cambioEUR: 1.08)
        assert(circa(b.importo, 100 / 1.08) && b.quote == 0)
        assert(circa(b.importo * 1.08, 100), "il versato in euro resta l'importo del PAC")
        // obbligazione a 98 (% del nominale): 490 € → 500 di nominale
        assert(circa(ripartizione(importoEUR: 490, percentuale: 100, prezzoUnitario: 0.98, cambioEUR: 1).quote, 500))

        assert(isinValido("US0378331005") && isinValido("IE00B4L5Y983") && isinValido("ie00bk5bqt80") && isinValido("IT0005518128"))
        assert(!isinValido("IE00B4L5Y984") && !isinValido("IE00B4L5Y98") && !isinValido("1E00B4L5Y983"))

        let l = ordinaPerEuro([Listino(simbolo: "IWDA.L", nome: "", borsa: "", tipo: ""),
                               Listino(simbolo: "SWDA.MI", nome: "", borsa: "", tipo: ""),
                               Listino(simbolo: "EUNL.DE", nome: "", borsa: "", tipo: "")])
        assert(l.map(\.simbolo) == ["EUNL.DE", "SWDA.MI", "IWDA.L"])

        let giornaliere = [Chiusura(data: giorno(2026, 10, 1).addingTimeInterval(7 * 3600), prezzo: 10),
                           Chiusura(data: giorno(2026, 10, 2).addingTimeInterval(7 * 3600), prezzo: 11)]
        assert(chiusura(giornaliere, al: giorno(2026, 10, 4)) == 11, "sabato → venerdì")
        assert(chiusura(giornaliere, al: giorno(2026, 10, 1)) == 10)
        assert(chiusura(giornaliere, al: giorno(2026, 9, 30)) == nil)

        // risposte vere di Yahoo salvate con curl
        if let cartella = cartellaEsempi {
            func leggi(_ f: String) -> Data { try! Data(contentsOf: URL(fileURLWithPath: cartella).appendingPathComponent(f)) }
            let ricerca = listini(daRicerca: leggi("s1.json"))
            assert(ricerca.first?.simbolo == "IWDA.L" && ricerca.first?.nome == "iShares Core MSCI World UCITS ETF USD (Acc)")
            let q = quotazione(daGrafico: leggi("c1.json"))
            assert(q?.valuta == "EUR" && (q?.prezzo ?? 0) > 0 && q?.data != nil)
            assert(chiusure(daGrafico: leggi("c1.json")).count == 5)
            let mesi = mensili(chiusure(daGrafico: leggi("c3.json")))
            assert(mesi.count == 60 || mesi.count == 61, "5 anni mensili: \(mesi.count)")
            assert(Set(mesi.map(\.data)).count == mesi.count && mesi.allSatisfy { $0.data == $0.data.inizioMese })
            let gbp = quotazione(daGrafico: leggi("c5.json"))
            assert(gbp?.valuta == "GBP" && (gbp?.prezzo ?? 0) < 1000, "pence → sterline")
            assert(quotazione(daGrafico: leggi("c6.json")) == nil, "simbolo inesistente")
        }
    }
    #endif
}
