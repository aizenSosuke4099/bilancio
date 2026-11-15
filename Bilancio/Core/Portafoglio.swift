import Foundation

/// Calcoli su una posizione di investimento. Valute: lo strumento ha la sua (es. CHF per un fondo svizzero),
/// i totali sono in EUR usando l'ultimo cambio salvato in UserDefaults ("cambio.CHF").
enum Portafoglio {

    /// Quote possedute (acquisti − vendite).
    static func quote(_ s: Strumento) -> Double {
        s.operazioni.reduce(0) { acc, op in
            switch op.tipo {
            case .acquisto: acc + op.quote
            case .vendita: acc - op.quote
            default: acc
            }
        }
    }

    /// Capitale versato netto in EUR (acquisti/versamenti + commissioni − vendite/prelievi), al cambio storico.
    static func versatoEUR(_ s: Strumento) -> Double {
        s.operazioni.reduce(0) { acc, op in
            if op.tipo.entraCapitale { return acc + (op.importo + op.commissioni) * op.cambioEUR }
            if op.tipo.esceCapitale { return acc - op.importo * op.cambioEUR }
            if op.tipo == .commissione { return acc + op.importo * op.cambioEUR }
            return acc
        }
    }

    /// Prezzo medio di carico (valuta strumento).
    static func prezzoMedio(_ s: Strumento) -> Double? {
        let acquisti = s.operazioni.filter { $0.tipo == .acquisto }
        let q = acquisti.reduce(0) { $0 + $1.quote }
        guard q > 0 else { return nil }
        return acquisti.reduce(0) { $0 + $1.importo + $1.commissioni } / q
    }

    /// Valore attuale nella valuta dello strumento.
    static func valore(_ s: Strumento) -> Double {
        let ultimaValutazione = s.valutazioni.max { $0.data < $1.data }
        if s.valoreManuale || s.ultimoPrezzo == nil {
            if let v = ultimaValutazione {
                // versamenti fatti dopo l'ultima valutazione si sommano al valore
                let successivi = s.operazioni.filter { $0.data > v.data }
                let delta = successivi.reduce(0.0) { acc, op in
                    op.tipo.entraCapitale ? acc + op.importo : (op.tipo.esceCapitale ? acc - op.importo : acc)
                }
                return v.valore + delta
            }
            // nessun valore noto: si assume il versato
            return versatoEUR(s) / cambio(s.valuta)
        }
        let prezzo = s.ultimoPrezzo ?? 0
        return s.tipo == .obbligazione ? quote(s) * prezzo / 100 : quote(s) * prezzo
    }

    static func valoreEUR(_ s: Strumento) -> Double { valore(s) * cambio(s.valuta) }

    static func guadagnoEUR(_ s: Strumento) -> Double { valoreEUR(s) - versatoEUR(s) }

    static func rendimento(_ s: Strumento) -> Double {
        let v = versatoEUR(s)
        return v > 0 ? guadagnoEUR(s) / v : 0
    }

    /// Ultimo cambio noto: 1 unità di `valuta` = x EUR.
    static func cambio(_ valuta: String) -> Double {
        if valuta == "EUR" { return 1 }
        let v = UserDefaults.standard.double(forKey: "cambio.\(valuta)")
        return v > 0 ? v : 1
    }

    static func salvaCambio(_ valuta: String, _ valore: Double) {
        UserDefaults.standard.set(valore, forKey: "cambio.\(valuta)")
    }

    /// Piattaforme proposte quando si aggiunge uno strumento.
    static let piattaformeNote = ["Scalable Capital", "Trade Republic", "Directa", "Fineco", "Degiro", "Interactive Brokers", "eToro", "XTB",
                                  "Moneyfarm", "Amundi", "finpension"]
}
