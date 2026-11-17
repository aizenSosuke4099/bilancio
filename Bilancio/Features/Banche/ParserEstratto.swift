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

    static let formatiData = ["dd/MM/yyyy", "dd/MM/yy", "dd-MM-yyyy", "dd.MM.yyyy", "yyyy-MM-dd", "MM/dd/yyyy", "yyyy/MM/dd", "yyyyMMdd"]

    // MARK: Testo

    /// UTF-16 con BOM (Excel «Testo Unicode»), UTF-8 (con o senza BOM), altrimenti Windows-1252, altrimenti ISO-8859-1.
    static func decodifica(_ dati: Data) -> String {
        let bom = [UInt8](dati.prefix(2))
        let testo = (bom == [0xFF, 0xFE] || bom == [0xFE, 0xFF] ? String(data: dati, encoding: .utf16) : nil)
            ?? String(data: dati, encoding: .utf8) ?? String(data: dati, encoding: .windowsCP1252) ?? String(data: dati, encoding: .isoLatin1) ?? ""
        return testo.hasPrefix("\u{FEFF}") ? String(testo.dropFirst()) : testo
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
            } else if c == "\"", campo.allSatisfy(\.isWhitespace) {   // solo a inizio campo: MONITOR 24" non apre nulla
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

        func colonna(_ parole: [String], escluse: Set<Int> = [], evita: [String] = []) -> Int? {
            for p in parole {
                if let i = intestazione.indices.first(where: { i in
                    !escluse.contains(i) && " \(intestazione[i]) ".contains(" \(p) ") && !evita.contains { intestazione[i].contains($0) }
                }) { return i }
            }
            return nil
        }
        // nomi delle colonne in italiano, inglese e tedesco (banche svizzere)
        m.colData = colonna(["data contabile", "data operazione", "completed date", "booking date", "buchungsdatum", "data", "date", "datum", "started date"]) ?? 0
        m.colDescrizione = colonna(["descrizione operazione", "descrizione", "description", "causale", "dettagli", "operazione", "beneficiario", "merchant", "controparte",
                                    "buchungstext", "buchungsdetails", "avisierungstext", "beschreibung", "verwendungszweck", "text"],
                                   escluse: [m.colData]) ?? min(1, max(intestazione.count - 1, 0))
        let usate: Set<Int> = [m.colData, m.colDescrizione]
        let addebito = colonna(["dare", "addebiti", "addebito", "uscite", "debit", "importo dare", "belastung", "lastschrift", "soll"], escluse: usate)
        let accredito = colonna(["avere", "accrediti", "accredito", "entrate", "credit", "importo avere", "gutschrift", "haben"], escluse: usate)
        if let addebito, let accredito, addebito != accredito {
            m.colImporto = nil
            m.colAddebito = addebito
            m.colAccredito = accredito
        } else {
            // prima la colonna già in euro; mai quella con l'importo nella valuta originale dell'acquisto
            m.colImporto = colonna(["importo eur", "importo in euro", "importo in eur", "controvalore", "importo", "amount", "betrag", "valore", "totale"],
                                   escluse: usate, evita: ["originale", "original", "estera", "foreign", "divisa"]) ?? min(2, max(intestazione.count - 1, 0))
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
        // Estratti delle carte di credito: gli acquisti sono scritti in positivo. Se quasi tutti gli importi lo sono si propone
        // di invertire il segno (si vede nella schermata delle colonne, dove si può spegnere): altrimenti le spese entrerebbero come entrate.
        if let c = m.colImporto {
            let importi = dati.compactMap { $0.indices.contains(c) ? leggiImporto($0[c], virgolaDecimale: m.virgolaDecimale) : nil }.filter { $0 != 0 }
            m.invertiSegno = importi.count >= 5 && Double(importi.filter { $0 > 0 }.count) >= 0.8 * Double(importi.count)
        }
        return m
    }

    // MARK: Applicazione

    /// Movimenti letti con la mappatura. Le righe senza data o importo validi (saldi, totali) si saltano,
    /// come quelle annullate/in sospeso se il file ha una colonna di stato ("State" negli export di alcune banche online).
    static func applica(_ m: Mappatura, righe: [[String]]) -> [Riga] {
        guard righe.count > m.righeDaSaltare else { return [] }
        let intestazione = righe[m.righeDaSaltare].map(normalizza)
        let colStato = intestazione.firstIndex { $0 == "state" || $0 == "stato" }
        // commissione in una colonna a parte ("Fee"): non è dentro l'importo, diventa un movimento suo
        let colCommissione = intestazione.firstIndex { $0 == "fee" || $0 == "commissione" || $0 == "commissioni" }
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
            let descrizione = cella(m.colDescrizione).replacingOccurrences(of: "\n", with: " ")
            if èSaldo(descrizione) { continue }
            if importo != 0 { risultato.append(Riga(data: data, descrizione: descrizione, importo: importo.centesimi)) }
            if let c = colCommissione, let f = leggiImporto(cella(c), virgolaDecimale: m.virgolaDecimale), f != 0 {
                // "Commissione: …" la manda in Commissioni bancarie (parole chiave del Classificatore)
                risultato.append(Riga(data: data, descrizione: "Commissione: " + descrizione, importo: -abs(f).centesimi))
            }
        }
        return risultato
    }

    /// Righe di saldo o di totale che alcune banche scrivono con una data: non sono movimenti.
    static func èSaldo(_ descrizione: String) -> Bool {
        let n = normalizza(descrizione)
        return ["saldo iniziale", "saldo finale", "saldo contabile", "saldo disponibile", "saldo precedente", "saldo riportato", "nuovo saldo", "saldo al",
                "totale", "totali", "opening balance", "closing balance", "anfangssaldo", "schlusssaldo", "saldovortrag"].contains { n == $0 || n.hasPrefix($0 + " ") }
    }

    /// Quante righe dopo l'intestazione hanno una data o un importo scritti ma non leggibili con questa mappatura
    /// (formato della data sbagliato, importo con del testo): l'utente deve saperlo prima di importare.
    static func righeNonLette(_ m: Mappatura, righe: [[String]]) -> Int {
        guard righe.count > m.righeDaSaltare else { return 0 }
        return righe.dropFirst(m.righeDaSaltare + 1).filter { r in
            func cella(_ i: Int?) -> String { i.flatMap { r.indices.contains($0) ? r[$0] : nil } ?? "" }
            let data = cella(m.colData)
            guard data.first?.isNumber == true else { return false }   // righe senza data: totali, note
            guard leggiData(data, formato: m.formatoData) != nil else { return true }
            let importi = (m.colImporto.map { [$0] } ?? [m.colAddebito, m.colAccredito].compactMap { $0 }).map { cella($0) }.filter { !$0.isEmpty && $0 != "-" }
            return !importi.isEmpty && importi.allSatisfy { leggiImporto($0, virgolaDecimale: m.virgolaDecimale) == nil }
        }.count
    }

    private static let valute: Set<String> = ["EUR", "CHF", "USD", "GBP", "JPY", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "CAD", "AUD"]

    /// "1.234,56" / "1234.56" / "45,20-" / "(12,00)" / "€ -3,50" / "CHF 45.20" / "12,30 DR". `virgolaDecimale` decide l'ambiguità di "1.234".
    static func leggiImporto(_ s: String, virgolaDecimale: Bool) -> Double? {
        var t = s.replacingOccurrences(of: "\u{2212}", with: "-").trimmingCharacters(in: .whitespaces)
        var negativo = false
        if t.hasSuffix("-") { negativo = true; t.removeLast() }
        if t.hasPrefix("("), t.hasSuffix(")") { negativo = true; t = String(t.dropFirst().dropLast()) }
        t = t.filter { "0123456789,.-+".contains($0) }
        guard t.contains(where: \.isNumber) else { return nil }
        // lettere ammesse: un codice valuta e CR/DR in coda (DR = dare). Con altro testo non è un importo (es. una descrizione con cifre)
        var lettere = s.filter(\.isLetter).uppercased()
        if lettere.hasSuffix("DR") { negativo = true; lettere.removeLast(2) } else if lettere.hasSuffix("CR") { lettere.removeLast(2) }
        guard lettere.isEmpty || valute.contains(lettere) else { return nil }
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
        if let d = dataConMese(s) { return d }
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

    private static let mesi: [String: Int] = ["gen": 1, "jan": 1, "feb": 2, "mar": 3, "apr": 4, "mag": 5, "may": 5, "mai": 5, "giu": 6, "jun": 6, "lug": 7, "jul": 7,
                                              "ago": 8, "aug": 8, "set": 9, "sep": 9, "ott": 10, "oct": 10, "okt": 10, "nov": 11, "dic": 12, "dec": 12, "dez": 12]

    /// "31-dic-2026", "31 dic 2026", "31. Dez. 2026": giorno, mese a lettere (italiano, inglese, tedesco), anno. Vale con ogni formato.
    private static func dataConMese(_ s: String) -> Date? {
        guard let m = s.firstMatch(of: #/^\s*(\d{1,2})[\s.\-\/]+(\p{L}{3,10})\.?[\s.\-\/,]+(\d{4}|\d{2})(?!\d)/#),
              let giorno = Int(m.output.1), var anno = Int(m.output.3),
              let mese = mesi[String(normalizza(String(m.output.2)).prefix(3))] else { return nil }
        if anno < 100 { anno += 2000 }
        let calendario = Calendar(identifier: .gregorian)
        guard (1990...2100).contains(anno), let d = calendario.date(from: DateComponents(year: anno, month: mese, day: giorno)),
              calendario.component(.day, from: d) == giorno else { return nil }
        return d
    }

    // MARK: Testo libero (PDF, fallback senza Apple Intelligence)

    /// Righe con una data gg/mm/aaaa e un importo con due decimali. Il segno, se non è scritto,
    /// si deduce dalle parole (accredito, stipendio…): l'anteprima permette di correggerlo.
    static func righeDaTesto(_ testo: String) -> [Riga] {
        let reData = #/(\d{2})[\/.\-](\d{2})[\/.\-](\d{2,4})/#
        // migliaia separate da punto, virgola o apostrofo (svizzero)
        let reImporto = #/([\-+]?)\s?(\d{1,3}(?:[.,'’]\d{3})*[.,]\d{2})(?!\d)\s?(-|\+)?/#
        let paroleEntrata = ["accredito", "stipendio", "a vostro favore", "a tuo favore", "bonifico ricevuto", "rimborso", "versamento", "interessi creditori", "storno",
                             "gutschrift", "lohn"]
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
            guard let imp = resto.firstMatch(of: reImporto), var valore = leggiNumero(String(imp.output.2).filter { $0 != "'" && $0 != "’" }) else { continue }
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
//   swiftc -D VERIFICA_ESTRATTO -parse-as-library Bilancio/Core/Formato.swift Bilancio/Core/DatiIniziali.swift Bilancio/Modello/*.swift Bilancio/Core/Classificatore.swift Bilancio/Features/Banche/ParserEstratto.swift -o /tmp/verifica_estratto && /tmp/verifica_estratto
#if VERIFICA_ESTRATTO
@main enum VerificaEstratto {
    static func giorno(_ a: Int, _ m: Int, _ g: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: a, month: m, day: g))!
    }

    static func main() {
        // banca online: inglese, virgola, punto decimale, data con ora, colonna State
        let online = """
        Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance
        CARD_PAYMENT,Current,2026-10-02 12:31:07,2026-10-03 09:12:44,Esselunga,-45.20,0.00,EUR,COMPLETED,1254.80
        TOPUP,Current,2026-10-01 08:00:00,2026-10-01 08:00:05,Top-Up by *1234,300.00,0.00,EUR,COMPLETED,1300.00
        CARD_PAYMENT,Current,2026-10-05 19:01:00,,Netflix,-12.99,0.00,EUR,REVERTED,
        ATM,Current,2026-10-06 10:00:00,2026-10-06 10:00:01,"Cash withdrawal at ATM, Milano","-1,000.00",0.00,EUR,COMPLETED,254.80
        EXCHANGE,Current,2026-10-07 09:00:00,2026-10-07 09:00:01,Exchanged to CHF,-200.00,1.50,EUR,COMPLETED,53.30
        """
        let sR = ParserEstratto.separatore(di: online)
        precondition(sR == ",", "separatore banca online: \(sR)")
        let righeR = ParserEstratto.righeCSV(online, separatore: sR)
        let mR = ParserEstratto.proponiMappatura(righe: righeR, separatore: sR)
        precondition(mR.righeDaSaltare == 0 && mR.colData == 3 && mR.colDescrizione == 4 && mR.colImporto == 5, "\(mR)")
        precondition(mR.formatoData == "yyyy-MM-dd" && !mR.virgolaDecimale, "\(mR)")
        let movR = ParserEstratto.applica(mR, righe: righeR)
        precondition(movR.count == 5, "banca online: \(movR)")
        precondition(movR[3].importo == -200 && movR[4].importo == -1.5 && movR[4].descrizione == "Commissione: Exchanged to CHF", "\(movR)")
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

        // banca svizzera in tedesco: Belastung/Gutschrift, apostrofo per le migliaia, date col punto, riga di saldo
        let svizzera = """
        Buchungsdatum;Buchungstext;Belastung;Gutschrift;Valuta;Saldo
        30.10.2026;Saldovortrag;;;30.10.2026;1'300.00
        31.10.2026;Kauf/Dienstleistung vom 30.10.2026 Karten-Nr. 1234 LADEN ZUERICH;45.20;;31.10.2026;1'254.80
        02.11.2026;LOHN ACME AG;;5'850.00;02.11.2026;7'104.80
        03.11.2026;MIETE;1'800.00;;03.11.2026;5'304.80
        """
        let righeS = ParserEstratto.righeCSV(svizzera, separatore: ParserEstratto.separatore(di: svizzera))
        let mS = ParserEstratto.proponiMappatura(righe: righeS, separatore: ";")
        precondition(mS.colData == 0 && mS.colDescrizione == 1 && mS.colAddebito == 2 && mS.colAccredito == 3 && !mS.virgolaDecimale, "svizzera: \(mS)")
        precondition(ParserEstratto.applica(mS, righe: righeS).map(\.importo) == [-45.20, 5850, -1800], "svizzera: \(ParserEstratto.applica(mS, righe: righeS))")
        precondition(ParserEstratto.righeNonLette(mS, righe: righeS) == 0)
        precondition(Classificatore.chiaveBanca("Kauf/Dienstleistung vom 30.10.2026 Karten-Nr. 1234 LADEN ZUERICH") == "laden zuerich")

        // carta con l'importo nella valuta dell'acquisto e il controvalore in euro: vale la colonna in euro
        let carta = "Data operazione;Data registrazione;Descrizione;Importo originale;Valuta;Cambio;Importo EUR\n01/10/2026;02/10/2026;NEGOZIO ONLINE;50,00;USD;1,08;46,30\n"
        let righeC = ParserEstratto.righeCSV(carta, separatore: ";")
        let mC = ParserEstratto.proponiMappatura(righe: righeC, separatore: ";")
        precondition(mC.colImporto == 6 && ParserEstratto.applica(mC, righe: righeC).map(\.importo) == [46.30], "carta: \(mC)")

        // saldi con la data, mese a lettere, virgoletta a metà campo, importo con la valuta
        let misto = "Data;Descrizione;Importo\n01-ott-2026;SALDO INIZIALE;1.000,00\n03 ott 2026;MONITOR 24\" NERO;-100,00\n5/10/2026;BAR;EUR -1,20\n31/10/2026;SALDO FINALE;898,80\n"
        let righeM = ParserEstratto.righeCSV(misto, separatore: ";")
        let movM = ParserEstratto.applica(ParserEstratto.proponiMappatura(righe: righeM, separatore: ";"), righe: righeM)
        precondition(movM.map(\.importo) == [-100, -1.2] && movM[0].data == giorno(2026, 10, 3) && movM[1].data == giorno(2026, 10, 5), "misto: \(movM)")
        precondition(movM[0].descrizione == "MONITOR 24\" NERO")
        precondition(ParserEstratto.leggiImporto("CHF -45.20", virgolaDecimale: false) == -45.20 && ParserEstratto.leggiImporto("5'850.00 CHF", virgolaDecimale: false) == 5850)
        precondition(ParserEstratto.leggiImporto("12,30 DR", virgolaDecimale: true) == -12.30 && ParserEstratto.leggiImporto("12,30 CR", virgolaDecimale: true) == 12.30)

        // estratto di una carta di credito: acquisti in positivo, quindi si propone da solo di invertire il segno
        let acquisti = "Data;Descrizione;Importo\n" + (1...6).map { "0\($0)/10/2026;NEGOZIO \($0);\($0)0,00" }.joined(separator: "\n") + "\n07/10/2026;RIMBORSO;-5,00\n"
        let righeA = ParserEstratto.righeCSV(acquisti, separatore: ";")
        let mA = ParserEstratto.proponiMappatura(righe: righeA, separatore: ";")
        precondition(mA.invertiSegno && ParserEstratto.applica(mA, righe: righeA).map(\.importo) == [-10, -20, -30, -40, -50, -60, 5], "carta con acquisti in positivo: \(mA)")
        precondition(!mR.invertiSegno && !mT.invertiSegno)

        // una data scritta in un modo non previsto non fa sparire le righe in silenzio: vengono contate
        var sbagliata = mI
        sbagliata.formatoData = "yyyy-MM-dd"
        precondition(ParserEstratto.righeNonLette(sbagliata, righe: righeI) == 3 && ParserEstratto.righeNonLette(mI, righe: righeI) == 0)

        // Excel «Testo Unicode» (UTF-16 con BOM); testo da PDF svizzero con l'apostrofo nelle migliaia
        let unicode = "Data\tDescrizione\tImporto\n01/10/2026\tCaffè Roma\t-1,20\n"
        precondition(ParserEstratto.decodifica(unicode.data(using: .utf16)!) == unicode, "UTF-16")
        let pdfCH = ParserEstratto.righeDaTesto("31.10.2026 31.10.2026 LADEN ZUERICH 1'234.50\n02.11.2026 LOHN ACME AG 5'850.00 7'104.80")
        precondition(pdfCH.map(\.importo) == [-1234.50, 5850], "pdf svizzero: \(pdfCH)")

        print("Estratti OK: banca online, banca italiana (Dare/Avere, Windows-1252), banca svizzera, carta in valuta, tab, importi, date, PDF, identificativi")
    }
}
#endif
