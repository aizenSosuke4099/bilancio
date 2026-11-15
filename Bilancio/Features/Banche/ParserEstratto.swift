import Foundation
import CryptoKit

// Lettura degli estratti conto: funzioni pure (niente SwiftData), verificate dal self-check in fondo al file.

enum ParserEstratto {

    /// Un movimento letto dal file.
    nonisolated struct Riga: Hashable {
        var data: Date
        var descrizione: String
        /// Con segno: < 0 uscita.
        var importo: Double
    }

    /// Come leggere le colonne (rispecchia `ProfiloImport`).
    nonisolated struct Mappatura: Equatable {
        var separatore: Character = ";"
        /// Indice della riga di intestazione tra le righe non vuote: i dati iniziano dalla successiva.
        var righeDaSaltare = 0
        var colData = 0
        var colDescrizione = 1
        var colImporto: Int? = 2
        var colAddebito: Int?
        var colAccredito: Int?
        var formatoData = "dd/MM/yyyy"
        var virgolaDecimale = true
        var invertiSegno = false
    }

    static let formatiData = ["dd/MM/yyyy", "dd/MM/yy", "dd-MM-yyyy", "dd.MM.yyyy", "yyyy-MM-dd", "MM/dd/yyyy"]

    // MARK: Testo

    /// UTF-8 (con o senza BOM), altrimenti Windows-1252, altrimenti ISO-8859-1.
    static func decodifica(_ dati: Data) -> String {
        if let s = String(data: dati, encoding: .utf8) { return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s }
        return String(data: dati, encoding: .windowsCP1252) ?? String(data: dati, encoding: .isoLatin1) ?? ""
    }

    /// Il separatore che divide le prime righe nello stesso numero (massimo) di campi.
    static func separatore(di testo: String) -> Character {
        let campione = testo.split(whereSeparator: \.isNewline).prefix(30).map(String.init)
        var migliore: (Character, Int) = (";", 0)
        for s in [";", ",", "\t"] as [Character] {
            let conteggi = campione.map { campi(riga: $0, separatore: s).count }.filter { $0 > 1 }
            // conta quante righe hanno il numero di campi più frequente: premia la regolarità
            let frequenze = Dictionary(grouping: conteggi, by: { $0 }).mapValues(\.count)
            guard let moda = frequenze.max(by: { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }) else { continue }
            let punteggio = moda.value * moda.key
            if punteggio > migliore.1 { migliore = (s, punteggio) }
        }
        return migliore.0
    }

    /// CSV con virgolette ("" = virgoletta), anche con a capo dentro i campi.
    static func righeCSV(_ testo: String, separatore: Character) -> [[String]] {
        var righe: [[String]] = []
        var riga: [String] = []
        var campo = ""
        var inVirgolette = false
        var i = testo.startIndex
        while i < testo.endIndex {
            let c = testo[i]
            if inVirgolette {
                if c == "\"" {
                    let dopo = testo.index(after: i)
                    if dopo < testo.endIndex, testo[dopo] == "\"" { campo.append("\""); i = dopo } else { inVirgolette = false }
                } else { campo.append(c) }
            } else if c == "\"" {
                inVirgolette = true
            } else if c == separatore {
                riga.append(campo.trimmingCharacters(in: .whitespaces)); campo = ""
            } else if c.isNewline { // "\r\n" è un solo Character
                riga.append(campo.trimmingCharacters(in: .whitespaces)); campo = ""
                if riga.contains(where: { !$0.isEmpty }) { righe.append(riga) }
                riga = []
            } else {
                campo.append(c)
            }
            i = testo.index(after: i)
        }
        riga.append(campo.trimmingCharacters(in: .whitespaces))
        if riga.contains(where: { !$0.isEmpty }) { righe.append(riga) }
        return righe
    }

    private static func campi(riga: String, separatore: Character) -> [String] {
        righeCSV(riga, separatore: separatore).first ?? []
    }

    // MARK: Intestazione e mappatura

    /// Prima riga "piena" senza date né numeri: salta le righe di preambolo (intestatario, numero conto…).
    static func indiceIntestazione(_ righe: [[String]]) -> Int {
        let pieni = righe.map { $0.filter { !$0.isEmpty }.count }
        let massimo = pieni.max() ?? 0
        for (i, r) in righe.enumerated() where pieni[i] >= max(2, Int((Double(massimo) * 0.6).rounded(.up))) {
            let haDati = r.contains { cella in
                formatiData.contains { leggiData(cella, formato: $0) != nil } || leggiImporto(cella, virgolaDecimale: true) != nil
            }
            if !haDati { return i }
        }
        return 0
    }

    /// Firma per riconoscere lo stesso tipo di file la prossima volta.
    static func firma(intestazione: [String]) -> String {
        var celle = intestazione.map(normalizza)
        while celle.last?.isEmpty == true { celle.removeLast() }
        return celle.joined(separator: "|")
    }

    /// Indovina la mappatura dai nomi delle colonne e da qualche riga di dati.
    static func proponiMappatura(righe: [[String]], separatore: Character) -> Mappatura {
        var m = Mappatura(separatore: separatore)
        m.righeDaSaltare = indiceIntestazione(righe)
        let intestazione = righe.isEmpty ? [] : righe[m.righeDaSaltare].map(normalizza)
        let dati = Array(righe.dropFirst(m.righeDaSaltare + 1).prefix(40))

        func colonna(_ parole: [String], escluse: Set<Int> = []) -> Int? {
            for p in parole {
                if let i = intestazione.indices.first(where: { !escluse.contains($0) && " \(intestazione[$0]) ".contains(" \(p) ") }) { return i }
            }
            return nil
        }
        m.colData = colonna(["data contabile", "data operazione", "completed date", "booking date", "data", "date", "started date"]) ?? 0
        m.colDescrizione = colonna(["descrizione operazione", "descrizione", "description", "causale", "dettagli", "operazione", "beneficiario", "merchant", "controparte"], escluse: [m.colData]) ?? min(1, max(intestazione.count - 1, 0))
        let usate: Set<Int> = [m.colData, m.colDescrizione]
        let addebito = colonna(["dare", "addebiti", "addebito", "uscite", "debit", "importo dare"], escluse: usate)
        let accredito = colonna(["avere", "accrediti", "accredito", "entrate", "credit", "importo avere"], escluse: usate)
        if let addebito, let accredito, addebito != accredito {
            m.colImporto = nil
            m.colAddebito = addebito
            m.colAccredito = accredito
        } else {
            m.colImporto = colonna(["importo", "amount", "importo eur", "valore", "totale"], escluse: usate) ?? min(2, max(intestazione.count - 1, 0))
        }

        // formato data: quello che legge più righe (a pari merito il primo: giorno prima del mese)
        let celleData = dati.compactMap { $0.indices.contains(m.colData) ? $0[m.colData] : nil }
        m.formatoData = formatiData.max { a, b in
            celleData.filter { leggiData($0, formato: a) != nil }.count < celleData.filter { leggiData($0, formato: b) != nil }.count
        } ?? m.formatoData

        // separatore decimale: guarda l'ultimo tra "," e "." negli importi
        let colonneImporto = [m.colImporto, m.colAddebito, m.colAccredito].compactMap { $0 }
        var virgole = 0, punti = 0
        for r in dati {
            for c in colonneImporto where r.indices.contains(c) {
                let v = r[c]
                switch (v.lastIndex(of: ","), v.lastIndex(of: ".")) {
                case let (a?, b?): if a > b { virgole += 1 } else { punti += 1 }
                case (_?, nil): virgole += 1
                case (nil, _?): punti += 1
                default: break
                }
            }
        }
        m.virgolaDecimale = virgole == punti ? separatore == ";" : virgole > punti
        return m
    }

    // MARK: Applicazione

    /// Movimenti letti con la mappatura. Le righe senza data o importo validi (saldi, totali) si saltano,
    /// come quelle annullate/in sospeso se il file ha una colonna di stato (es. Revolut "State").
    static func applica(_ m: Mappatura, righe: [[String]]) -> [Riga] {
        guard righe.count > m.righeDaSaltare else { return [] }
        let intestazione = righe[m.righeDaSaltare].map(normalizza)
        let colStato = intestazione.firstIndex { $0 == "state" || $0 == "stato" }
        let statiEsclusi: Set<String> = ["reverted", "declined", "failed", "pending", "annullato", "annullata", "rifiutato", "in sospeso"]
        var risultato: [Riga] = []
        for r in righe.dropFirst(m.righeDaSaltare + 1) {
            func cella(_ i: Int?) -> String { i.flatMap { r.indices.contains($0) ? r[$0] : nil } ?? "" }
            if let colStato, statiEsclusi.contains(normalizza(cella(colStato))) { continue }
            guard let data = leggiData(cella(m.colData), formato: m.formatoData) else { continue }
            var importo: Double
            if let c = m.colImporto {
                guard let v = leggiImporto(cella(c), virgolaDecimale: m.virgolaDecimale) else { continue }
                importo = v
            } else {
                let dare = leggiImporto(cella(m.colAddebito), virgolaDecimale: m.virgolaDecimale)
                let avere = leggiImporto(cella(m.colAccredito), virgolaDecimale: m.virgolaDecimale)
                guard dare != nil || avere != nil else { continue }
                importo = abs(avere ?? 0) - abs(dare ?? 0)
            }
            if m.invertiSegno { importo = -importo }
            guard importo != 0 else { continue }
            let descrizione = cella(m.colDescrizione).replacingOccurrences(of: "\n", with: " ")
            risultato.append(Riga(data: data, descrizione: descrizione, importo: importo.centesimi))
        }
        return risultato
    }

    /// "1.234,56" / "1234.56" / "45,20-" / "(12,00)" / "€ -3,50". `virgolaDecimale` decide l'ambiguità di "1.234".
    static func leggiImporto(_ s: String, virgolaDecimale: Bool) -> Double? {
        var t = s.replacingOccurrences(of: "\u{2212}", with: "-").trimmingCharacters(in: .whitespaces)
        var negativo = false
        if t.hasSuffix("-") { negativo = true; t.removeLast() }
        if t.hasPrefix("("), t.hasSuffix(")") { negativo = true; t = String(t.dropFirst().dropLast()) }
        t = t.filter { "0123456789,.-+".contains($0) }
        guard t.contains(where: \.isNumber) else { return nil }
        // una cella con lettere oltre alla valuta non è un importo (es. una descrizione con cifre)
        let lettere = s.filter(\.isLetter).uppercased()
        guard lettere.isEmpty || lettere == "EUR" else { return nil }
        if virgolaDecimale {
            t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            t = t.replacingOccurrences(of: ",", with: "")
        }
        guard let v = Double(t) else { return nil }
        return negativo ? -abs(v) : v
    }

    /// Legge solo la parte di data ("2026-10-03 09:12:44" → 3 ottobre). Anni plausibili soltanto.
    static func leggiData(_ s: String, formato: String) -> Date? {
        let parte = s.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == " " || $0 == "T" }).first.map(String.init) ?? ""
        guard parte.count >= 6, parte.count <= 10 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.isLenient = false
        f.dateFormat = formato
        guard let d = f.date(from: parte) else { return nil }
        let anno = Calendar(identifier: .gregorian).component(.year, from: d)
        return (1990...2100).contains(anno) ? d : nil
    }

    // MARK: Testo libero (PDF, fallback senza Apple Intelligence)

    /// Righe con una data gg/mm/aaaa e un importo con due decimali. Il segno, se non è scritto,
    /// si deduce dalle parole (accredito, stipendio…): l'anteprima permette di correggerlo.
    static func righeDaTesto(_ testo: String) -> [Riga] {
        let reData = #/(\d{2})[\/.\-](\d{2})[\/.\-](\d{2,4})/#
        let reImporto = #/([\-+]?)\s?(\d{1,3}(?:[.,]\d{3})*[.,]\d{2})(?!\d)\s?(-|\+)?/#
        let paroleEntrata = ["accredito", "stipendio", "a vostro favore", "a tuo favore", "bonifico ricevuto", "rimborso", "versamento", "interessi creditori", "storno"]
        var risultato: [Riga] = []
        for riga in testo.components(separatedBy: .newlines) {
            guard let d = riga.firstMatch(of: reData), riga[..<d.range.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let formato = d.output.3.count == 4 ? "dd/MM/yyyy" : "dd/MM/yy"
            guard let data = leggiData("\(d.output.1)/\(d.output.2)/\(d.output.3)", formato: formato) else { continue }
            // salta un'eventuale seconda data (valuta) subito dopo
            var resto = riga[d.range.upperBound...]
            if let d2 = resto.firstMatch(of: reData), resto[..<d2.range.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty {
                resto = resto[d2.range.upperBound...]
            }
            guard let imp = resto.firstMatch(of: reImporto), var valore = leggiNumero(String(imp.output.2)) else { continue }
            let descrizione = resto[..<imp.range.lowerBound].trimmingCharacters(in: .whitespaces)
            guard !descrizione.isEmpty else { continue }
            let segno = imp.output.1.isEmpty ? (imp.output.3.map(String.init) ?? "") : String(imp.output.1)
            switch segno {
            case "-": valore = -valore
            case "+": break
            default:
                let n = normalizza(descrizione)
                if !paroleEntrata.contains(where: { n.contains($0) }) { valore = -valore }
            }
            risultato.append(Riga(data: data, descrizione: descrizione, importo: valore))
        }
        return risultato
    }

    // MARK: Identificativi

    /// Impronta stabile di un movimento (data, importo, descrizione).
    static func impronta(data: Date, importo: Double, descrizione: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let testo = "\(f.string(from: data))|\(String(format: "%.2f", importo))|\(normalizza(descrizione))"
        return SHA256.hash(data: Data(testo.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    /// idEsterno per ogni riga del file: "file:" + impronta, con un contatore per le righe identiche
    /// (due caffè uguali lo stesso giorno restano due movimenti).
    static func idEsterni(_ righe: [Riga]) -> [String] {
        var visti: [String: Int] = [:]
        return righe.map { r in
            let base = impronta(data: r.data, importo: r.importo, descrizione: r.descrizione)
            let n = visti[base, default: 0]
            visti[base] = n + 1
            return "file:" + base + (n > 0 ? "#\(n)" : "")
        }
    }

    static func normalizza(_ s: String) -> String { Classificatore.normalizza(s) }
}

// MARK: - Self-check
// Dalla radice del progetto:
//   swiftc -D VERIFICA_ESTRATTO -parse-as-library Bilancio/Core/Formato.swift Bilancio/Modello/*.swift Bilancio/Core/Classificatore.swift Bilancio/Features/Banche/ParserEstratto.swift -o /tmp/verifica_estratto && /tmp/verifica_estratto
#if VERIFICA_ESTRATTO
@main enum VerificaEstratto {
    static func giorno(_ a: Int, _ m: Int, _ g: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: a, month: m, day: g))!
    }

    static func main() {
        // Revolut: inglese, virgola, punto decimale, data con ora, colonna State
        let revolut = """
        Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance
        CARD_PAYMENT,Current,2026-10-02 12:31:07,2026-10-03 09:12:44,Esselunga,-45.20,0.00,EUR,COMPLETED,1254.80
        TOPUP,Current,2026-10-01 08:00:00,2026-10-01 08:00:05,Top-Up by *1234,300.00,0.00,EUR,COMPLETED,1300.00
        CARD_PAYMENT,Current,2026-10-05 19:01:00,,Netflix,-12.99,0.00,EUR,REVERTED,
        ATM,Current,2026-10-06 10:00:00,2026-10-06 10:00:01,"Cash withdrawal at ATM, Milano","-1,000.00",0.00,EUR,COMPLETED,254.80
        """
        let sR = ParserEstratto.separatore(di: revolut)
        precondition(sR == ",", "separatore Revolut: \(sR)")
        let righeR = ParserEstratto.righeCSV(revolut, separatore: sR)
        let mR = ParserEstratto.proponiMappatura(righe: righeR, separatore: sR)
        precondition(mR.righeDaSaltare == 0 && mR.colData == 3 && mR.colDescrizione == 4 && mR.colImporto == 5, "\(mR)")
        precondition(mR.formatoData == "yyyy-MM-dd" && !mR.virgolaDecimale, "\(mR)")
        let movR = ParserEstratto.applica(mR, righe: righeR)
        precondition(movR.count == 3, "Revolut: \(movR)")
        precondition(movR[0] == .init(data: giorno(2026, 10, 3), descrizione: "Esselunga", importo: -45.20))
        precondition(movR[1].importo == 300)
        precondition(movR[2].importo == -1000 && movR[2].descrizione == "Cash withdrawal at ATM, Milano")
        precondition(ParserEstratto.firma(intestazione: righeR[0]) == "type|product|started date|completed date|description|amount|fee|currency|state|balance")

        // banca italiana: preambolo, ";", dd/MM/yyyy, "1.234,56", colonne Dare/Avere, riga di saldo finale, Windows-1252
        let italiano = """
        Conto corrente n. 1234;;;;
        Intestatario: Mario Rossi - Città;;;;
        ;;;;
        Data contabile;Data valuta;Descrizione;Dare;Avere
        03/11/2026;03/11/2026;PAGAMENTO POS ESSELUNGA MILANO;45,20;
        05/11/2026;05/11/2026;"ACCREDITO STIPENDIO; ACME SPA";;1.850,00
        10/11/2026;10/11/2026;PRELIEVO BANCOMAT;1.234,56;
        ;;Saldo finale;;2.000,00
        """
        let dati = italiano.replacingOccurrences(of: "\n", with: "\r\n").data(using: .windowsCP1252)!
        let testo = ParserEstratto.decodifica(dati)
        precondition(testo.contains("Città"), "decodifica Windows-1252")
        let sI = ParserEstratto.separatore(di: testo)
        precondition(sI == ";")
        let righeI = ParserEstratto.righeCSV(testo, separatore: sI)
        let mI = ParserEstratto.proponiMappatura(righe: righeI, separatore: sI)
        precondition(mI.righeDaSaltare == 2 && mI.colData == 0 && mI.colDescrizione == 2, "\(mI)")
        precondition(mI.colImporto == nil && mI.colAddebito == 3 && mI.colAccredito == 4, "\(mI)")
        precondition(mI.formatoData == "dd/MM/yyyy" && mI.virgolaDecimale, "\(mI)")
        let movI = ParserEstratto.applica(mI, righe: righeI)
        precondition(movI.count == 3, "italiano: \(movI)")
        precondition(movI[0] == .init(data: giorno(2026, 11, 3), descrizione: "PAGAMENTO POS ESSELUNGA MILANO", importo: -45.20))
        precondition(movI[1].importo == 1850 && movI[1].descrizione == "ACCREDITO STIPENDIO; ACME SPA")
        precondition(movI[2].importo == -1234.56)
        var invertita = mI
        invertita.invertiSegno = true
        precondition(ParserEstratto.applica(invertita, righe: righeI)[0].importo == 45.20)

        // importo unico con segno e tab, UTF-8 con BOM
        let tab = "\u{FEFF}Data\tCausale\tImporto\n01/02/2026\tNETFLIX.COM\t-12,99\n02/02/2026\tRIMBORSO\t+5,00\n"
        let testoTab = ParserEstratto.decodifica(Data(tab.utf8))
        let sT = ParserEstratto.separatore(di: testoTab)
        precondition(sT == "\t")
        let righeT = ParserEstratto.righeCSV(testoTab, separatore: sT)
        let mT = ParserEstratto.proponiMappatura(righe: righeT, separatore: sT)
        precondition(ParserEstratto.applica(mT, righe: righeT).map(\.importo) == [-12.99, 5])

        // importi
        precondition(ParserEstratto.leggiImporto("45,20-", virgolaDecimale: true) == -45.20)
        precondition(ParserEstratto.leggiImporto("(12,00)", virgolaDecimale: true) == -12)
        precondition(ParserEstratto.leggiImporto("€ 1.234", virgolaDecimale: true) == 1234)
        precondition(ParserEstratto.leggiImporto("1.234", virgolaDecimale: false) == 1.234)
        precondition(ParserEstratto.leggiImporto("CARTA 1234", virgolaDecimale: true) == nil)

        // testo da PDF
        let pdf = """
        ESTRATTO CONTO AL 30/11/2026
        03/11/2026 03/11/2026 PAGAMENTO POS ESSELUNGA 45,20
        05/11/26 ACCREDITO STIPENDIO ACME 1.850,00
        07/11/2026 BONIFICO A MARIO -100,00
        Saldo finale 2.000,00
        """
        let movP = ParserEstratto.righeDaTesto(pdf)
        precondition(movP.map(\.importo) == [-45.20, 1850, -100], "pdf: \(movP)")
        precondition(movP[0].descrizione == "PAGAMENTO POS ESSELUNGA" && movP[1].data == giorno(2026, 11, 5))

        // identificativi: stabili, distinti per righe identiche
        let caffe = ParserEstratto.Riga(data: giorno(2026, 1, 1), descrizione: "Bar", importo: -1.2)
        let ids = ParserEstratto.idEsterni([caffe, caffe, movI[0]])
        precondition(ids[0] != ids[1] && ids[0].hasPrefix("file:") && ids == ParserEstratto.idEsterni([caffe, caffe, movI[0]]))

        print("Estratti OK: Revolut, banca italiana (Dare/Avere, Windows-1252), tab, importi, PDF, identificativi")
    }
}
#endif
