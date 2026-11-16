import Foundation

// Parser a regole per scontrini italiani: struttura numerica delle righe (prezzi, quantità, sconti), totale, data, P.IVA;
// più la ricostruzione delle righe visive dall'OCR. Solo Foundation, quindi si verifica da riga di comando:
//   mkdir -p /tmp/vs && echo 'ParserScontrino.autoverifica()' > /tmp/vs/main.swift
//   cd Bilancio && xcrun swiftc -D DEBUG -o /tmp/vs/v Core/Formato.swift Features/Scansione/ParserScontrino.swift /tmp/vs/main.swift && /tmp/vs/v

/// Dati letti da uno scontrino, prima della revisione dell'utente.
struct BozzaScontrino {
    struct Riga: Equatable {
        var testo: String
        var quantita: Double = 1
        var prezzoUnitario: Double
        var totale: Double
        /// Nome di una categoria di spesa proposto (vuoto = nessuna proposta).
        var categoria: String = ""
        var nomeProdotto: String = ""
        /// "pz", "kg" o "l".
        var unita: String = "pz"
        /// Quantità per confezione nell'unità (0,5 per 500 g). nil = sconosciuta.
        var formato: Double? = nil
    }

    var negozio = ""
    var partitaIva = ""
    var indirizzo = ""
    var data: Date?
    var totale: Double?
    var righe: [Riga] = []
    /// true = contanti, false = carta/bancomat, nil = non si capisce.
    var pagatoInContanti: Bool?
}

enum ParserScontrino {

    // MARK: Righe visive dall'OCR

    /// Pezzo di testo riconosciuto, in coordinate normalizzate 0…1 con origine in basso a sinistra (come Vision).
    struct Frammento {
        var testo: String
        var x: Double
        var yCentro: Double
        var altezza: Double
    }

    /// Raggruppa i frammenti che stanno sulla stessa riga (descrizione a sinistra, prezzo a destra),
    /// dall'alto in basso e da sinistra a destra. Le colonne sono separate da due spazi.
    static func ricostruisciRighe(_ frammenti: [Frammento]) -> [String] {
        var righe: [(y: Double, h: Double, pezzi: [Frammento])] = []
        for f in frammenti.sorted(by: { $0.yCentro > $1.yCentro }) where !f.testo.trimmingCharacters(in: .whitespaces).isEmpty {
            // stessa riga se i centri distano meno di metà altezza (tollera scontrini un po' storti)
            if let i = righe.indices.last(where: { abs(righe[$0].y - f.yCentro) < 0.5 * min(righe[$0].h, f.altezza) + 0.002 }) {
                righe[i].pezzi.append(f)
                let n = Double(righe[i].pezzi.count)
                righe[i].y += (f.yCentro - righe[i].y) / n
                righe[i].h += (f.altezza - righe[i].h) / n
            } else {
                righe.append((f.yCentro, f.altezza, [f]))
            }
        }
        return righe.sorted { $0.y > $1.y }.map { r in
            pulisciOCR(r.pezzi.sorted { $0.x < $1.x }.map { $0.testo.trimmingCharacters(in: .whitespaces) }.joined(separator: "  "))
        }
    }

    /// Errori tipici dell'OCR sui numeri: "1, 5L" → "1,5L", "2 × 0,89" resta com'è.
    static func pulisciOCR(_ riga: String) -> String {
        riga.replacingOccurrences(of: #"(\d)([,.]) (\d)"#, with: "$1$2$3", options: .regularExpression)
    }

    // MARK: Analisi del testo

    static func analizza(_ testo: String) -> BozzaScontrino {
        var b = BozzaScontrino()
        let righe = testo.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        b.negozio = negozio(in: righe)
        b.indirizzo = indirizzo(in: righe, dopo: b.negozio)
        b.partitaIva = partitaIva(in: righe)
        b.data = righe.compactMap { leggiData($0) }.first
        b.pagatoInContanti = pagamentoContanti(in: righe)

        var voci: [BozzaScontrino.Riga] = []
        var quantitaInSospeso: (q: Double, pu: Double, unita: String)?
        var descrizioneInSospeso: String?
        var vistoPrezzo = false

        for (i, riga) in righe.enumerated() {
            let norm = normalizza(riga)

            if isTotale(norm) {
                b.totale = prezzoFinale(riga)?.valore ?? (i + 1 < righe.count ? numeroSolo(righe[i + 1]) : nil)
                if b.totale != nil { break }   // dopo il totale ci sono solo pagamenti, IVA, documento
                continue
            }

            if let q = rigaQuantita(riga) {
                // "2 x 0,89  1,78" sotto una descrizione senza prezzo
                if let tot = q.totale, let d = descrizioneInSospeso {
                    voci.append(voce(d, q: q.q, pu: q.pu, totale: tot, unita: q.unita))
                    descrizioneInSospeso = nil
                    vistoPrezzo = true
                } else if let ultima = voci.last, ultima.quantita == 1, abs(q.q * q.pu - ultima.totale) < 0.02 {
                    // quantità stampata dopo la riga
                    voci[voci.count - 1].quantita = q.q
                    voci[voci.count - 1].prezzoUnitario = q.pu
                    if q.unita == "kg" { voci[voci.count - 1].unita = "kg"; voci[voci.count - 1].formato = 1 }
                } else {
                    quantitaInSospeso = (q.q, q.pu, q.unita)
                }
                continue
            }

            if daIgnorare(norm) { continue }

            guard let p = prezzoFinale(riga) else {
                // descrizione senza prezzo: potrebbe essere seguita da "2 x 0,89  1,78" o dal solo prezzo
                if vistoPrezzo || quantitaInSospeso != nil, lettere(riga) >= 2 { descrizioneInSospeso = riga }
                if let v = numeroSolo(riga), let d = descrizioneInSospeso, d != riga {
                    voci.append(voce(d, q: 1, pu: v, totale: v, unita: "pz"))
                    descrizioneInSospeso = nil
                }
                continue
            }

            var descrizione = p.descrizione
            if lettere(descrizione) < 2 {
                guard let d = descrizioneInSospeso else { continue }
                descrizione = d
            }
            descrizioneInSospeso = nil
            vistoPrezzo = true

            var valore = p.valore
            if isSconto(norm) && valore > 0 { valore = -valore }

            if let q = quantitaInSospeso, abs(q.q * q.pu - valore) < 0.02 {
                voci.append(voce(descrizione, q: q.q, pu: q.pu, totale: valore, unita: q.unita))
            } else {
                voci.append(voce(descrizione, q: 1, pu: valore, totale: valore, unita: "pz"))
            }
            quantitaInSospeso = nil
        }

        // le righe a 0,00 (busta in omaggio, componenti del menu) non sono spese
        b.righe = applicaSconti(voci.filter { $0.totale != 0 })
        if b.totale == nil, !b.righe.isEmpty { b.totale = b.righe.reduce(0) { $0 + $1.totale }.centesimi }
        return b
    }

    /// Le righe di sconto (importo negativo) spariscono: si tolgono dalla riga più vicina sopra che le può assorbire,
    /// di solito quella subito sopra; in un menu è il menu (l'aggiunta da 0,40 stampata in mezzo resta intera).
    /// Se nessuna riga basta da sola (sconto sul totale) si toglie risalendo dalle ultime righe.
    /// Il prezzo unitario resta quello pieno: il totale della riga è quello pagato.
    static func applicaSconti(_ righe: [BozzaScontrino.Riga]) -> [BozzaScontrino.Riga] {
        var esito: [BozzaScontrino.Riga] = []
        for r in righe {
            guard r.totale < 0, !esito.isEmpty else { esito.append(r); continue }
            var resto = -r.totale
            let ordine = esito.lastIndex { $0.totale >= resto - 0.005 }.map { [$0] } ?? Array(esito.indices.reversed())
            for i in ordine where resto > 0.005 {
                let tolto = max(0, min(esito[i].totale, resto))
                esito[i].totale = (esito[i].totale - tolto).centesimi
                resto -= tolto
            }
        }
        return esito
    }

    /// dd/mm/yyyy, dd-mm-yy, dd.mm.yyyy. Prima data valida della riga.
    static func leggiData(_ s: String) -> Date? {
        guard let re = try? NSRegularExpression(pattern: #"(?<!\d)(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})(?!\d)"#) else { return nil }
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            let g = (1...3).map { Int(s[Range(m.range(at: $0), in: s)!])! }
            let anno = g[2] < 100 ? 2000 + g[2] : g[2]
            guard (1...31).contains(g[0]), (1...12).contains(g[1]), (2000...2100).contains(anno) else { continue }
            var c = DateComponents(year: anno, month: g[1], day: g[0], hour: 12)
            if let ora = leggiOra(s) { c.hour = ora.0; c.minute = ora.1 }
            if let d = calendario.date(from: c), calendario.component(.day, from: d) == g[0] { return d }
        }
        return nil
    }

    /// Unità e formato dal testo ("LATTE 1L" → l, 1; "PASTA 500G" → kg, 0,5; "ACQUA 6X1,5L" → l, 9).
    static func formato(da testo: String) -> (unita: String, formato: Double)? {
        let pattern = #"(?:(\d+)\s*[X×]\s*)?(\d+(?:[.,]\d+)?)\s*(KG|GR|G|LT|L|ML|CL)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: testo, range: NSRange(testo.startIndex..., in: testo)),
              let rv = Range(m.range(at: 2), in: testo), let ru = Range(m.range(at: 3), in: testo),
              let valore = leggiNumero(String(testo[rv])) else { return nil }
        let pezzi = Range(m.range(at: 1), in: testo).flatMap { Double(testo[$0]) } ?? 1
        let (unita, fattore): (String, Double) = switch testo[ru].uppercased() {
        case "KG": ("kg", 1)
        case "G", "GR": ("kg", 0.001)
        case "L", "LT": ("l", 1)
        case "CL": ("l", 0.01)
        default: ("l", 0.001)
        }
        let totale = (pezzi * valore * fattore * 1000).rounded() / 1000
        return totale > 0 && totale <= 50 ? (unita, totale) : nil   // "0, 312KG" letto male dall'OCR non diventa 312 kg
    }

    // MARK: Riconoscimento delle righe

    private static func voce(_ descrizione: String, q: Double, pu: Double, totale: Double, unita: String) -> BozzaScontrino.Riga {
        var r = BozzaScontrino.Riga(testo: descrizione, quantita: q, prezzoUnitario: pu, totale: totale)
        r.nomeProdotto = nomeLeggibile(descrizione)
        if unita == "kg" {
            r.unita = "kg"
            r.formato = 1
        } else if let f = formato(da: descrizione) {
            r.unita = f.unita
            r.formato = f.formato
        }
        return r
    }

    /// "LATTE INTERO 1L" → "Latte intero 1L"
    private static func nomeLeggibile(_ s: String) -> String {
        let minuscolo = s.lowercased(with: localeIT)
        return minuscolo.prefix(1).uppercased(with: localeIT) + minuscolo.dropFirst()
    }

    /// Prezzo in fondo alla riga, con eventuale € e lettera/aliquota IVA ("PANE 4% 2,10", "LATTE 1,29 B", "SCONTO -0,50", "0,50-").
    private static func prezzoFinale(_ riga: String) -> (descrizione: String, valore: Double)? {
        let pattern = #"^(.*?)\s*(?:€\s*)?(-?\s?\d{1,4}(?:\.\d{3})*,\d{2}|-?\s?\d{1,4}\.\d{2})(-?)\s*(?:€|EUR)?\s*(?:\*|[A-Z]{1,2}|\d{1,2}(?:[.,]\d{1,2})?\s?%)?\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: riga, range: NSRange(riga.startIndex..., in: riga)),
              let rd = Range(m.range(at: 1), in: riga), let rv = Range(m.range(at: 2), in: riga),
              var valore = leggiNumero(String(riga[rv]).replacingOccurrences(of: " ", with: "")) else { return nil }
        if let rm = Range(m.range(at: 3), in: riga), !riga[rm].isEmpty { valore = -valore }
        // toglie aliquota IVA e simboli rimasti tra descrizione e prezzo
        var descrizione = String(riga[rd])
        if let re2 = try? NSRegularExpression(pattern: #"\s*(\d{1,2}(?:[.,]\d{1,2})?\s?%|€|\*)\s*$"#) {
            descrizione = re2.stringByReplacingMatches(in: descrizione, range: NSRange(descrizione.startIndex..., in: descrizione), withTemplate: "")
        }
        return (descrizione.trimmingCharacters(in: .whitespaces), valore)
    }

    /// "2 x 1,29", "N.2 X 0,89  1,78", "0,735 kg x 2,49 €/kg  1,83".
    private static func rigaQuantita(_ riga: String) -> (q: Double, pu: Double, unita: String, totale: Double?)? {
        let pattern = #"^(?:N\.?\s*)?(\d+(?:[.,]\d{1,3})?)\s*(PZ|KG|N\.?)?\s*[X×*]\s*(?:€\s*)?(\d{1,4}[.,]\d{2,3})\s*(?:€|EUR)?\s*(?:/\s*(?:KG|PZ))?(?:\s+(\d{1,4}[.,]\d{2}))?\s*(?:[A-Z]{1,2})?\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: riga, range: NSRange(riga.startIndex..., in: riga)),
              let rq = Range(m.range(at: 1), in: riga), let rp = Range(m.range(at: 3), in: riga),
              let q = leggiNumero(String(riga[rq])), let pu = leggiNumero(String(riga[rp])), q > 0 else { return nil }
        let unitaTesto = Range(m.range(at: 2), in: riga).map { riga[$0].uppercased() } ?? ""
        let unita = unitaTesto == "KG" || riga.uppercased().contains("/KG") || q != q.rounded() ? "kg" : "pz"
        let totale = Range(m.range(at: 4), in: riga).flatMap { leggiNumero(String(riga[$0])) }
        return (q, pu, unita, totale)
    }

    /// Riga che contiene solo un importo.
    private static func numeroSolo(_ riga: String) -> Double? {
        guard let p = prezzoFinale(riga), lettere(p.descrizione) == 0, p.descrizione.allSatisfy({ !$0.isNumber }) else { return nil }
        return p.valore
    }

    private static func isTotale(_ norm: String) -> Bool {
        let t = " \(norm) "
        guard t.contains(" TOTALE ") || t.contains(" TOT ") || t.contains(" IMPORTO PAGATO ") else { return false }
        return !contiene(norm, ["SUBTOTALE", "SUBTOT", "IVA", "SCONTI", "SCONTO", "PEZZI", "ARTICOLI", "PUNTI", "RISPARMIO", "RISPARMIATO", "IMPONIBILE", "IMPOSTA"])
    }

    private static func isSconto(_ norm: String) -> Bool {
        contiene(norm, ["SCONTO", "SCONTI", "SC", "PROMO", "OFFERTA", "RIBASSO", "BUONO", "COUPON", "RIDUZIONE"])
    }

    /// Righe che non sono prodotti.
    private static func daIgnorare(_ norm: String) -> Bool {
        contiene(norm, ["SUBTOTALE", "SUBTOT", "IVA", "IMPONIBILE", "IMPOSTA", "ALIQUOTA", "RESTO", "CONTANTE", "CONTANTI",
                        "PAGAMENTO", "PAGATO", "ELETTRONICO", "BANCOMAT", "POS", "CREDITO", "DEBITO", "RESO",
                        "DOCUMENTO", "DOC", "SCONTRINO", "CASSA", "CASSIERE", "OPERATORE", "TRANSAZIONE", "AUTORIZZAZIONE",
                        "MATRICOLA", "RT", "TESSERA", "SALDO", "ARROTONDAMENTO", "NUMERO", "ARTICOLI", "PEZZI", "TOT",
                        "TELEFONO", "TEL", "GRAZIE", "ARRIVEDERCI", "CF", "PREZZO", "DESCRIZIONE"])
    }

    // MARK: Intestazione

    private static func negozio(in righe: [String]) -> String {
        let scarta = ["DOCUMENTO", "COMMERCIALE", "BENVENUTO", "BENVENUTI", "WELCOME", "SCONTRINO", "FISCALE", "COPIA", "CORTESIA", "VENDITA"]
        guard let prima = righe.prefix(8).first(where: { r in
            lettere(r) >= 3 && !contiene(normalizza(r), scarta) && prezzoFinale(r) == nil && leggiData(r) == nil
        }) else { return "" }
        // senza forma societaria: è il nome con cui l'archivio raggruppa
        var nome = prima
        if let re = try? NSRegularExpression(pattern: #"[\s,]+(S\.?\s?P\.?\s?A\.?|S\.?\s?R\.?\s?L\.?\s?S?\.?|S\.?\s?N\.?\s?C\.?|S\.?\s?A\.?\s?S\.?|SOC\.?\s*COOP.*|SOCIETA'?\s.*|&\s*C\.?)\s*$"#, options: .caseInsensitive) {
            nome = re.stringByReplacingMatches(in: nome, range: NSRange(nome.startIndex..., in: nome), withTemplate: "")
        }
        nome = nome.trimmingCharacters(in: CharacterSet(charactersIn: " *-.,"))
        // MAIUSCOLO → Iniziali maiuscole
        return nome == nome.uppercased() ? nome.capitalized(with: localeIT) : nome
    }

    private static func indirizzo(in righe: [String], dopo negozio: String) -> String {
        let vie = ["VIA", "V", "VIALE", "VLE", "PIAZZA", "PZA", "P", "PZZA", "CORSO", "CSO", "LARGO", "STRADA", "LOC", "LOCALITA", "VICOLO", "PIAZZALE"]
        guard let i = righe.prefix(10).firstIndex(where: { r in
            let parole = normalizza(r).split(separator: " ")
            return parole.first.map { vie.contains(String($0)) } ?? false
        }) else { return "" }
        var esito = righe[i]
        // "20124 MILANO (MI)"
        if i + 1 < righe.count, righe[i + 1].range(of: #"^\d{5}\s+\D"#, options: .regularExpression) != nil {
            esito += ", " + righe[i + 1]
        }
        return esito.capitalized(with: localeIT)
    }

    private static func partitaIva(in righe: [String]) -> String {
        for r in righe {
            let n = normalizza(r)
            guard contiene(n, ["IVA", "PI", "PIVA", "P", "CF"]) || r.uppercased().contains("IT") else { continue }
            if let m = r.range(of: #"(?<!\d)\d{11}(?!\d)"#, options: .regularExpression) { return String(r[m]) }
        }
        return ""
    }

    private static func pagamentoContanti(in righe: [String]) -> Bool? {
        let elettronico = ["ELETTRONICO", "CARTA", "BANCOMAT", "POS", "CREDITO", "DEBITO", "CONTACTLESS", "SATISPAY", "VISA", "MASTERCARD", "MAESTRO", "AMEX", "APPLE PAY"]
        let contanti = ["CONTANTE", "CONTANTI", "CONTANTI EURO", "RESTO"]
        var indizio: Bool?
        for r in righe {
            let n = normalizza(r)
            let importo = prezzoFinale(r)?.valore ?? 0
            if contiene(n, elettronico) {
                if importo > 0 { return false }
                indizio = indizio ?? false
            } else if contiene(n, contanti) {
                if importo > 0 && !contiene(n, ["RESTO"]) { return true }
                indizio = indizio ?? true
            }
        }
        return indizio
    }

    private static func leggiOra(_ s: String) -> (Int, Int)? {
        guard let m = s.range(of: #"(?<!\d)([01]?\d|2[0-3])[:.]([0-5]\d)(?![\d,])"#, options: .regularExpression) else { return nil }
        let parti = s[m].split(whereSeparator: { $0 == ":" || $0 == "." }).compactMap { Int($0) }
        return parti.count == 2 ? (parti[0], parti[1]) : nil
    }

    // MARK: Utilità

    /// MAIUSCOLO, senza accenti né punteggiatura, spazi singoli.
    private static func normalizza(_ s: String) -> String {
        let base = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: localeIT).uppercased()
        let pulito = base.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(pulito).split(separator: " ").joined(separator: " ")
    }

    /// true se il testo normalizzato contiene una delle parole/frasi intere.
    private static func contiene(_ norm: String, _ parole: [String]) -> Bool {
        let t = " \(norm) "
        return parole.contains { t.contains(" \($0) ") }
    }

    private static func lettere(_ s: String) -> Int { s.filter(\.isLetter).count }

    // MARK: Autoverifica

    #if DEBUG
    /// Controllo del parser su scontrini di esempio. Fallisce con un assert se le regole si rompono.
    static func autoverifica() {
        func vicino(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 0.005 } ?? false }

        // 1. Documento commerciale con IVA in colonna, quantità prima della riga, sconto, pagamento elettronico
        let esselunga = """
        ESSELUNGA S.P.A.
        VIA VITTOR PISANI 20
        20124 MILANO (MI)
        P.IVA 01255720169
        DOCUMENTO COMMERCIALE
        di vendita o prestazione
        DESCRIZIONE  IVA  Prezzo(€)
        LATTE INTERO GRANAROLO 1L  4%  1,29
        2 x 0,89
        BANANE CHIQUITA  10%  1,78
        PANE COMUNE  4%  2,10
        SCONTO FIDATY  -0,50
        TOTALE COMPLESSIVO  4,67
        DI CUI IVA  0,25
        PAGAMENTO ELETTRONICO  4,67
        IMPORTO PAGATO  4,67
        14-11-2026 18:32
        DOCUMENTO N. 0123-0456
        """
        let a = analizza(esselunga)
        assert(a.negozio == "Esselunga", "negozio: \(a.negozio)")
        assert(a.partitaIva == "01255720169", "piva: \(a.partitaIva)")
        assert(a.indirizzo.hasPrefix("Via Vittor Pisani"), "indirizzo: \(a.indirizzo)")
        assert(vicino(a.totale, 4.67), "totale: \(String(describing: a.totale))")
        assert(a.righe.count == 3, "righe: \(a.righe)")
        assert(a.righe[0].testo == "LATTE INTERO GRANAROLO 1L" && vicino(a.righe[0].totale, 1.29) && a.righe[0].unita == "l" && a.righe[0].formato == 1)
        assert(a.righe[1].quantita == 2 && vicino(a.righe[1].prezzoUnitario, 0.89) && vicino(a.righe[1].totale, 1.78))
        assert(a.righe[2].testo == "PANE COMUNE" && vicino(a.righe[2].totale, 1.60), "sconto: \(a.righe[2])")
        assert(a.pagatoInContanti == false)
        let c = calendario.dateComponents([.year, .month, .day, .hour], from: a.data!)
        assert(c.year == 2026 && c.month == 11 && c.day == 14 && c.hour == 18, "data: \(c)")

        // 2. Lettera IVA in coda, quantità dopo la riga, peso al kg, TOTALE EURO, contanti, anno a 2 cifre
        let coop = """
        *** BENVENUTI ***
        COOP LOMBARDIA SOC. COOP.
        V.LE FAMAGOSTA 75 MILANO
        P.I. 00865220156
        LATTE PS 1L  1,15 B
        YOGURT BIANCO X4  2,49 A
           2 X 1,25
        ACQUA NAT 6X1,5L  2,50 B
        0,735 kg x 2,49 €/kg
        MELE GOLDEN  1,83 A
        SUBTOTALE  7,97
        TOTALE EURO  7,97
        CONTANTI  10,00
        RESTO  2,03
        13/11/26 12:33 CASSA 3
        """
        let b = analizza(coop)
        assert(b.negozio == "Coop Lombardia", "negozio: \(b.negozio)")
        assert(b.partitaIva == "00865220156")
        assert(vicino(b.totale, 7.97))
        assert(b.righe.count == 4, "righe: \(b.righe)")
        assert(b.righe[1].quantita == 2 && vicino(b.righe[1].prezzoUnitario, 1.25), "quantità dopo: \(b.righe[1])")
        assert(b.righe[2].unita == "l" && vicino(b.righe[2].formato, 9), "multipack: \(b.righe[2])")
        assert(b.righe[3].unita == "kg" && vicino(b.righe[3].quantita, 0.735) && vicino(b.righe[3].prezzoUnitario, 2.49), "peso: \(b.righe[3])")
        assert(b.pagatoInContanti == true)
        assert(calendario.component(.year, from: b.data!) == 2026 && calendario.component(.day, from: b.data!) == 13)

        // 3. Bar senza P.IVA leggibile, senza "TOTALE COMPLESSIVO", descrizione e prezzo su righe diverse
        let bar = """
        Bar Centrale di Rossi Mario
        Piazza Duomo 1
        CAFFE'  1,20
        CORNETTO CREMA
        1,50
        TOTALE  2,70
        PAGAMENTO CONTANTE  2,70
        05.03.2026
        """
        let d = analizza(bar)
        assert(d.negozio == "Bar Centrale di Rossi Mario", "negozio: \(d.negozio)")
        assert(d.righe.count == 2 && d.righe[1].testo == "CORNETTO CREMA" && vicino(d.righe[1].totale, 1.5), "bar: \(d.righe)")
        assert(vicino(d.totale, 2.7))
        assert(d.pagatoInContanti == true)

        // 4. Righe visive: prezzo a destra leggermente più in basso (scontrino storto), stesse righe
        let frammenti = [
            Frammento(testo: "1,29", x: 0.8, yCentro: 0.795, altezza: 0.02),
            Frammento(testo: "LATTE", x: 0.1, yCentro: 0.80, altezza: 0.02),
            Frammento(testo: "PANE", x: 0.1, yCentro: 0.76, altezza: 0.02),
            Frammento(testo: "2,10", x: 0.8, yCentro: 0.756, altezza: 0.02),
            Frammento(testo: "ESSELUNGA", x: 0.3, yCentro: 0.95, altezza: 0.03),
        ]
        assert(ricostruisciRighe(frammenti) == ["ESSELUNGA", "LATTE  1,29", "PANE  2,10"], "\(ricostruisciRighe(frammenti))")
        assert(pulisciOCR("ACQUA 6X1, 5L  2,50") == "ACQUA 6X1,5L  2,50")
        assert(vicino(formato(da: "PARMIGIANO " + pulisciOCR("0, 312KG"))?.formato, 0.312))
        assert(vicino(formato(da: "BIRRA MORETTI 66CL")?.formato, 0.66) && formato(da: "UOVA X6") == nil)

        // 5. Fast food: sconto dopo un menu con aggiunta (va sul menu, non sull'aggiunta da 0,40), righe a 0,00, "OUT Totale EURO"
        let menu = """
        BURGER POINT
        VIA ROMA 1
        20100 MILANO (MI)
        DOCUMENTO COMMERCIALE
        Qta Prodotti  IVA  TOTALE
        1 Menu Bacon Medio  10%  9.10
        1 Panino Bacon  10%
        1 Te Limone 0,4L  22%
        1 Salsa Bacon  10%  0.40
        Sconto:  -1.20
        1 Crocchette x4  10%  3.95
        1 Maionese  10%
        Sconto:  -1.95
        1 Panino Pollo  10%  7.10
        1 Busta  10%  0.00
        OUT Totale EURO  17.40
        Pagamento Contanti  20.00
        Resto  2.60
        """
        let e = analizza(menu)
        assert(vicino(e.totale, 17.4) && e.pagatoInContanti == true, "totale: \(String(describing: e.totale))")
        assert(e.righe.map(\.totale) == [7.9, 0.4, 2, 7.1], "menu: \(e.righe.map { ($0.testo, $0.totale) })")
        assert(vicino(e.righe[0].prezzoUnitario, 9.1))

        func r(_ t: Double) -> BozzaScontrino.Riga { .init(testo: "", prezzoUnitario: t, totale: t) }
        assert(applicaSconti([r(2), r(-0.5)]).map(\.totale) == [1.5])
        assert(applicaSconti([r(1), r(1), r(-1.5)]).map(\.totale) == [0.5, 0], "sconto sul totale")
        print("ParserScontrino: autoverifica superata")
    }
    #endif
}
