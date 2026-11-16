import Foundation
import SwiftData

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

    /// Capitale versato netto in EUR (acquisti/versamenti + commissioni − quanto incassato da vendite e prelievi,
    /// tolte le loro commissioni), al cambio storico.
    static func versatoEUR(_ s: Strumento) -> Double {
        s.operazioni.reduce(0) { acc, op in
            if op.tipo.entraCapitale { return acc + (op.importo + op.commissioni) * op.cambioEUR }
            if op.tipo.esceCapitale { return acc - (op.importo - op.commissioni) * op.cambioEUR }
            if op.tipo == .commissione { return acc + op.importo * op.cambioEUR }
            return acc
        }
    }

    /// Tutto ciò che è stato messo nello strumento (acquisti, versamenti, commissioni) senza togliere le vendite:
    /// è il denominatore del rendimento. Col versato netto, dopo una vendita la percentuale esploderebbe.
    static func investitoEUR(_ s: Strumento) -> Double {
        s.operazioni.reduce(0) { acc, op in
            if op.tipo.entraCapitale { return acc + (op.importo + op.commissioni) * op.cambioEUR }
            if op.tipo == .commissione { return acc + op.importo * op.cambioEUR }
            return acc
        }
    }

    /// Dividendi e cedole incassati (EUR, al netto delle commissioni): fanno parte del guadagno.
    static func incassatoEUR(_ s: Strumento) -> Double {
        s.operazioni.filter { $0.tipo == .dividendo || $0.tipo == .cedola }.reduce(0) { $0 + ($1.importo - $1.commissioni) * $1.cambioEUR }
    }

    /// Prezzo medio di carico delle quote ancora possedute (valuta strumento): una vendita toglie quote al loro costo medio.
    static func prezzoMedio(_ s: Strumento) -> Double? {
        var quote = 0.0, costo = 0.0
        // nello stesso giorno prima gli acquisti: non si vende ciò che non si è ancora comprato
        for op in s.operazioni.sorted(by: { ($0.data, $0.tipo == .vendita ? 1 : 0) < ($1.data, $1.tipo == .vendita ? 1 : 0) }) {
            if op.tipo == .acquisto {
                costo += op.importo + op.commissioni
                quote += op.quote
            } else if op.tipo == .vendita, quote > 0 {
                let vendute = min(op.quote, quote)
                costo -= costo / quote * vendute
                quote -= vendute
            }
        }
        return quote > 1e-9 ? costo / quote : nil
    }

    /// L'operazione «Situazione iniziale» creata aggiungendo lo strumento riassume gli anni passati:
    /// non è un versamento di quest'anno (conta per la deducibilità del fondo pensione).
    static func èSituazioneIniziale(_ op: Operazione) -> Bool {
        ["Situazione iniziale", "Starting position", String(localized: "Situazione iniziale")].contains(op.nota)
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

    /// Valore di oggi + dividendi e cedole incassati − capitale versato netto.
    static func guadagnoEUR(_ s: Strumento) -> Double { valoreEUR(s) - versatoEUR(s) + incassatoEUR(s) }

    static func rendimento(_ s: Strumento) -> Double {
        let v = investitoEUR(s)
        return v > 0 ? guadagnoEUR(s) / v : 0
    }

    #if DEBUG
    /// Avvio con `-verifica`: vendite, prezzo medio di carico, dividendi.
    @MainActor static func autoverifica() {
        let ctx = ModelContext(try! ModelContainer(for: Persistenza.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        func strumento(_ ops: [(TipoOperazione, Double, Double)], prezzo: Double) -> Strumento {
            let s = Strumento(nome: "Prova", isin: "", tipo: .etf, piattaforma: "Prova", valuta: "EUR")
            ctx.insert(s)
            for (i, o) in ops.enumerated() {
                let op = Operazione(data: Date().aggiungendo(giorni: i - 10), tipo: o.0, quote: o.1, prezzo: o.1 > 0 ? o.2 / o.1 : 0, importo: o.2, cambioEUR: 1)
                ctx.insert(op)
                op.strumento = s
            }
            s.ultimoPrezzo = prezzo
            return s
        }
        // compro 10 quote per 1.000 €, il prezzo sale a 150, ne vendo 5 per 750 €: guadagno 500 € su 1.000 investiti (non +200%)
        let a = strumento([(.acquisto, 10, 1000), (.vendita, 5, 750)], prezzo: 150)
        assert(abs(guadagnoEUR(a) - 500) < 0.001 && abs(rendimento(a) - 0.5) < 0.001 && abs(versatoEUR(a) - 250) < 0.001, "vendita parziale: \(rendimento(a))")
        // vendo tutto e ricompro: il carico medio è quello del riacquisto
        let b = strumento([(.acquisto, 10, 1000), (.vendita, 10, 1200), (.acquisto, 10, 1300)], prezzo: 130)
        assert(abs((prezzoMedio(b) ?? 0) - 130) < 0.001, "carico medio: \(String(describing: prezzoMedio(b)))")
        // un dividendo è guadagno
        let c = strumento([(.acquisto, 10, 1000), (.dividendo, 0, 50)], prezzo: 100)
        assert(abs(guadagnoEUR(c) - 50) < 0.001, "dividendo: \(guadagnoEUR(c))")
        print("Portafoglio.autoverifica OK")
    }
    #endif

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
