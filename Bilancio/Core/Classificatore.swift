import Foundation
import SwiftData

/// Proposta di classificazione per un movimento bancario.
struct Suggerimento {
    var tipo: TipoMovimento
    var categoria: Categoria?
    var titolo: String
    /// true se viene da una correzione dell'utente (più affidabile).
    var appreso: Bool
    /// true se il movimento è un prelievo di contanti (va creato il movimento opposto sul conto Contanti).
    var prelievoContanti: Bool = false
}

/// Classifica movimenti e righe di scontrino. Prima le regole imparate dalle correzioni, poi parole chiave.
enum Classificatore {

    // MARK: Normalizzazione

    /// minuscolo, senza accenti né punteggiatura, spazi singoli.
    static func normalizza(_ s: String) -> String {
        let base = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: localeIT).lowercased()
        let pulito = base.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(pulito).split(separator: " ").joined(separator: " ")
    }

    /// Chiave per descrizioni bancarie: toglie le parole con cifre (date, numeri carta, id) che cambiano ogni volta.
    static func chiaveBanca(_ s: String) -> String {
        let parole = normalizza(s).split(separator: " ").filter { p in !p.contains(where: \.isNumber) }
        let rumore: Set<String> = ["pagamento", "pagam", "pos", "carta", "presso", "del", "ore", "op", "operazione", "acquisto", "pag", "debit", "card", "payment", "to", "da", "a", "di", "il", "in", "su", "eur", "addebito", "sdd", "favore", "con", "bancomat", "contactless", "apple", "pay", "nfc"]
        return parole.filter { !rumore.contains(String($0)) }.prefix(4).joined(separator: " ")
    }

    /// Chiave per una riga di scontrino: tiene le cifre (formati come "1l", "500g").
    static func chiaveRiga(_ s: String) -> String { normalizza(s) }

    // MARK: Regole imparate

    static func regola(chiave: String, ambito: AmbitoRegola, in context: ModelContext) -> RegolaAppresa? {
        guard !chiave.isEmpty else { return nil }
        let a = ambito.rawValue
        var d = FetchDescriptor<RegolaAppresa>(predicate: #Predicate { $0.chiave == chiave && $0.ambitoRaw == a })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    static func categoria(nome: String, in context: ModelContext) -> Categoria? {
        var d = FetchDescriptor<Categoria>(predicate: #Predicate { $0.nome == nome })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Ricorda la scelta dell'utente per una descrizione bancaria.
    static func impara(descrizioneBanca: String, tipo: TipoMovimento, categoria: Categoria?, titolo: String, in context: ModelContext) {
        let chiave = chiaveBanca(descrizioneBanca)
        guard !chiave.isEmpty else { return }
        let r = regola(chiave: chiave, ambito: .descrizioneBanca, in: context) ?? {
            let nuova = RegolaAppresa(chiave: chiave, ambito: .descrizioneBanca)
            context.insert(nuova)
            return nuova
        }()
        r.tipoRaw = tipo.rawValue
        r.categoria = categoria
        r.titolo = titolo
        r.utilizzi += 1
        r.aggiornataIl = Date()
    }

    /// Ricorda la scelta dell'utente per una riga di scontrino.
    static func impara(rigaScontrino: String, categoria: Categoria?, nomeProdotto: String?, in context: ModelContext) {
        let chiave = chiaveRiga(rigaScontrino)
        guard !chiave.isEmpty else { return }
        let r = regola(chiave: chiave, ambito: .rigaScontrino, in: context) ?? {
            let nuova = RegolaAppresa(chiave: chiave, ambito: .rigaScontrino)
            context.insert(nuova)
            return nuova
        }()
        r.categoria = categoria
        r.nomeProdotto = nomeProdotto
        r.utilizzi += 1
        r.aggiornataIl = Date()
    }

    // MARK: Suggerimenti

    /// Categoria e prodotto già imparati per una riga di scontrino (nil se mai vista).
    static func suggerisciRiga(_ testo: String, in context: ModelContext) -> (categoria: Categoria?, nomeProdotto: String?)? {
        guard let r = regola(chiave: chiaveRiga(testo), ambito: .rigaScontrino, in: context) else { return nil }
        return (r.categoria, r.nomeProdotto)
    }

    static func suggerisciBanca(descrizione: String, importo: Double, in context: ModelContext) -> Suggerimento {
        let titoloPulito = titolo(da: descrizione)
        if let r = regola(chiave: chiaveBanca(descrizione), ambito: .descrizioneBanca, in: context),
           let tipo = r.tipoRaw.flatMap(TipoMovimento.init(rawValue:)) {
            return Suggerimento(tipo: tipo, categoria: r.categoria, titolo: r.titolo ?? titoloPulito, appreso: true,
                                prelievoContanti: tipo == .giroconto && contiene(normalizza(descrizione), paroleChiavePrelievo))
        }
        let norm = normalizza(descrizione)
        if contiene(norm, paroleChiavePrelievo) {
            return Suggerimento(tipo: .giroconto, categoria: nil, titolo: "Prelievo contanti", appreso: false, prelievoContanti: true)
        }
        for (parole, tipo, nomeCategoria) in tabella where contiene(norm, parole) {
            // una "spesa" con importo positivo è quasi sempre un rimborso: resta spesa (riduce il totale)
            let cat = nomeCategoria.flatMap { categoria(nome: $0, in: context) }
            return Suggerimento(tipo: tipo, categoria: cat, titolo: titoloPulito, appreso: false)
        }
        if importo > 0 {
            return Suggerimento(tipo: .entrata, categoria: categoria(nome: "Altre entrate", in: context), titolo: titoloPulito, appreso: false)
        }
        return Suggerimento(tipo: .spesa, categoria: categoria(nome: "Altro", in: context), titolo: titoloPulito, appreso: false)
    }

    /// Prima parte leggibile di una descrizione bancaria ("PAGAMENTO POS ESSELUNGA MILANO 12/11" → "Esselunga Milano").
    static func titolo(da descrizione: String) -> String {
        let parole = chiaveBanca(descrizione).split(separator: " ").prefix(3)
        let t = parole.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return t.isEmpty ? descrizione.trimmingCharacters(in: .whitespaces) : t
    }

    /// true se `testo` (normalizzato) contiene una delle parole/frasi intere.
    static func contiene(_ testo: String, _ parole: [String]) -> Bool {
        let t = " \(testo) "
        return parole.contains { t.contains(" \($0) ") }
    }

    static let paroleChiavePrelievo = ["prelievo", "prelevamento", "prel", "atm", "cash withdrawal", "withdrawal", "prelievo contanti"]

    /// Parole chiave → tipo e categoria. L'ordine conta: vince la prima che corrisponde.
    static let tabella: [([String], TipoMovimento, String?)] = [
        // giroconti tra conti propri e saldo carte di credito
        // (le carte di credito e i conti senza parola chiave li riconosce Abbinamento.segnaGiroconto)
        (["giroconto", "giroc", "trasferimento", "ricarica conto", "ricarica carta", "top up", "topup",
          "revolut", "n26", "wise", "bunq", "hype", "trade republic",
          "saldo carta", "estratto conto carta", "addebito carta di credito"], .giroconto, nil),
        // investimenti
        (["fondo pensione", "previdenza complementare", "scalable capital", "directa", "degiro", "etoro", "xtb", "interactive brokers",
          "moneyfarm", "finpension", "amundi"], .investimento, nil),
        // entrate
        (["stipendio", "emolumenti", "salary", "retribuzione", "cedolino", "accredito stipendio"], .entrata, "Stipendio"),
        (["interessi", "interest", "dividendo", "cedola"], .entrata, "Interessi e dividendi"),
        (["rimborso", "refund", "storno"], .entrata, "Rimborsi"),
        // spese
        (["esselunga", "coop", "conad", "lidl", "carrefour", "eurospin", "pam", "aldi", "penny", "md", "iper", "ipercoop", "tigros",
          "bennet", "famila", "despar", "eurospar", "spar", "naturasi", "crai", "sigma", "unes", "il gigante", "basko", "todis", "in s", "tuodi", "supermercato", "market"], .spesa, "Spesa alimentare"),
        (["netflix", "spotify", "disney", "prime video", "amazon prime", "icloud", "apple com bill", "apple com", "youtube", "dazn", "now tv", "chatgpt", "openai", "anthropic", "claude", "microsoft", "google one", "audible", "patreon"], .spesa, "Abbonamenti"),
        (["affitto", "condominio", "enel", "a2a", "hera", "iren", "edison", "eni plenitude", "sorgenia", "acea", "tim", "vodafone", "iliad", "fastweb", "windtre", "wind", "ho mobile", "very mobile", "kena", "tari", "gas", "luce"], .spesa, "Casa e bollette"),
        (["eni", "q8", "ip", "tamoil", "esso", "shell", "api", "carburante", "benzina", "trenitalia", "italo", "trenord", "atm milano", "atac", "gtt", "uber", "free now", "freenow", "bolt", "telepass", "autostrade", "parcheggio", "easypark", "mytaxi", "flixbus", "enjoy", "share now"], .spesa, "Trasporti"),
        (["farmacia", "parafarmacia", "medico", "ospedale", "dentista", "ottica", "analisi", "ticket sanitario", "asl", "ats", "poliambulatorio"], .spesa, "Salute"),
        (["ristorante", "pizzeria", "trattoria", "osteria", "bar", "caffe", "sushi", "mcdonald", "mcdonalds", "burger king", "kfc", "deliveroo", "glovo", "just eat", "justeat", "autogrill", "starbucks", "poke", "kebab", "gelateria", "pasticceria"], .spesa, "Ristoranti e bar"),
        (["zara", "h m", "hm", "uniqlo", "zalando", "decathlon", "primark", "ovs", "bershka", "pull bear", "nike", "adidas", "calzedonia", "intimissimi", "tezenis", "foot locker"], .spesa, "Abbigliamento"),
        (["cinema", "teatro", "steam", "playstation", "nintendo", "xbox", "ticketone", "museo", "concerto", "libreria", "feltrinelli", "mondadori"], .spesa, "Svago e cultura"),
        (["ryanair", "easyjet", "wizz", "ita airways", "booking", "airbnb", "hotel", "expedia", "trivago", "vueling", "lufthansa"], .spesa, "Viaggi"),
        (["mediaworld", "unieuro", "euronics", "apple store", "trony", "expert"], .spesa, "Tecnologia"),
        (["ikea", "leroy merlin", "brico", "obi", "maisons du monde", "tiger", "action", "acqua e sapone", "tigota"], .spesa, "Casa e pulizia"),
        (["sephora", "douglas", "kiko", "parrucchiere", "barbiere", "estetista"], .spesa, "Cura personale"),
        (["commissione", "commissioni", "canone", "imposta di bollo", "bollo", "f24", "agenzia entrate", "tasse", "pagopa"], .spesa, "Tasse e commissioni"),
        (["amazon", "amzn", "ebay", "aliexpress", "temu", "shein", "paypal"], .spesa, "Altro"),
    ]
}
