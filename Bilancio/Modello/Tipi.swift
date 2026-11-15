import Foundation

// Enum del dominio. Nei modelli SwiftData vengono salvati come String (campo *Raw)
// perché i #Predicate sugli enum sono fragili.

enum TipoMovimento: String, CaseIterable, Codable, Identifiable {
    case spesa, entrata, giroconto, investimento
    var id: String { rawValue }
    var etichetta: String {
        switch self {
        case .spesa: String(localized: "Spesa")
        case .entrata: String(localized: "Entrata")
        case .giroconto: String(localized: "Giroconto")
        case .investimento: String(localized: "Investimento")
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
        case .manuale: String(localized: "Inserito a mano")
        case .scontrino: String(localized: "Scontrino")
        case .banca: String(localized: "Banca collegata")
        case .estratto: String(localized: "Estratto conto importato")
        case .ricorrente: String(localized: "Ricorrente")
        case .pac: String(localized: "Piano di accumulo")
        }
    }
}

enum TipoConto: String, CaseIterable, Codable, Identifiable {
    case corrente, carta, contanti, remunerato
    var id: String { rawValue }
    var etichetta: String {
        switch self {
        case .corrente: String(localized: "Conto corrente")
        case .carta: String(localized: "Carta di credito")
        case .contanti: String(localized: "Contanti")
        case .remunerato: String(localized: "Conto remunerato")
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
        case .etf: String(localized: "ETF")
        case .azione: String(localized: "Azione")
        case .obbligazione: String(localized: "Obbligazione")
        case .fondo: String(localized: "Fondo")
        case .fondoPensione: String(localized: "Fondo pensione")
        case .gestione: String(localized: "Gestione (robo-advisor)")
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
        case .acquisto: String(localized: "Acquisto")
        case .vendita: String(localized: "Vendita")
        case .versamento: String(localized: "Versamento")
        case .prelievo: String(localized: "Prelievo")
        case .dividendo: String(localized: "Dividendo")
        case .cedola: String(localized: "Cedola")
        case .commissione: String(localized: "Commissione")
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
