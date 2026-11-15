import Foundation

// Enum del dominio. Nei modelli SwiftData vengono salvati come String (campo *Raw)
// perché i #Predicate sugli enum sono fragili.

enum TipoMovimento: String, CaseIterable, Codable, Identifiable {
    case spesa, entrata, giroconto, investimento
    var id: String { rawValue }
    var etichetta: String {
        switch self {
        case .spesa: "Spesa"
        case .entrata: "Entrata"
        case .giroconto: "Giroconto"
        case .investimento: "Investimento"
        }
    }
    var icona: String {
        switch self {
        case .spesa: "arrow.down.circle"
        case .entrata: "arrow.up.circle"
        case .giroconto: "arrow.left.arrow.right.circle"
        case .investimento: "chart.line.uptrend.xyaxis.circle"
        }
    }
}

enum StatoMovimento: String, Codable {
    case daConfermare, confermato
}

/// Da dove arriva un movimento.
enum Origine: String, Codable {
    case manuale, scontrino, banca, estratto, ricorrente, pac
    var etichetta: String {
        switch self {
        case .manuale: "Inserito a mano"
        case .scontrino: "Scontrino"
        case .banca: "Banca collegata"
        case .estratto: "Estratto conto importato"
        case .ricorrente: "Ricorrente"
        case .pac: "Piano di accumulo"
        }
    }
}

enum TipoConto: String, CaseIterable, Codable, Identifiable {
    case corrente, carta, contanti, remunerato
    var id: String { rawValue }
    var etichetta: String {
        switch self {
        case .corrente: "Conto corrente"
        case .carta: "Carta di credito"
        case .contanti: "Contanti"
        case .remunerato: "Conto remunerato"
        }
    }
    var icona: String {
        switch self {
        case .corrente: "building.columns"
        case .carta: "creditcard"
        case .contanti: "banknote"
        case .remunerato: "percent"
        }
    }
}

enum TipoStrumento: String, CaseIterable, Codable, Identifiable {
    case etf, azione, obbligazione, fondo, fondoPensione, gestione
    var id: String { rawValue }
    var etichetta: String {
        switch self {
        case .etf: "ETF"
        case .azione: "Azione"
        case .obbligazione: "Obbligazione"
        case .fondo: "Fondo"
        case .fondoPensione: "Fondo pensione"
        case .gestione: "Gestione (robo-advisor)"
        }
    }
    /// Ha un prezzo di mercato recuperabile dall'ISIN.
    var quotato: Bool { self == .etf || self == .azione || self == .obbligazione }
}

enum TipoOperazione: String, CaseIterable, Codable, Identifiable {
    case acquisto, vendita, versamento, prelievo, dividendo, cedola, commissione
    var id: String { rawValue }
    var etichetta: String {
        switch self {
        case .acquisto: "Acquisto"
        case .vendita: "Vendita"
        case .versamento: "Versamento"
        case .prelievo: "Prelievo"
        case .dividendo: "Dividendo"
        case .cedola: "Cedola"
        case .commissione: "Commissione"
        }
    }
    /// Operazioni che aumentano il capitale versato.
    var entraCapitale: Bool { self == .acquisto || self == .versamento }
    /// Operazioni che riducono il capitale versato.
    var esceCapitale: Bool { self == .vendita || self == .prelievo }
}

enum AmbitoRegola: String, Codable {
    case rigaScontrino, descrizioneBanca
}
