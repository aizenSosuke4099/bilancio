import Foundation
import SwiftData

/// Generazione mensile dei piani di accumulo: un Movimento "da confermare" per l'addebito
/// più un'Operazione per ogni strumento, con le quote calcolate al prezzo del giorno.
enum PAC {
    private static var inCorso = false

    static func generaSeServe(in context: ModelContext) async {
        guard !inCorso else { return }
        inCorso = true
        defer { inCorso = false }

        let piani = (try? context.fetch(FetchDescriptor<PianoPAC>(predicate: #Predicate { $0.attivo }))) ?? []
        let oggi = Date()
        // memorie locali: una richiesta per ticker (tutto l'intervallo) e una per valuta/mese
        var chiusure: [String: [CalcoliInvestimenti.Chiusura]] = [:]
        var cambi: [String: Double] = [:]

        for piano in piani {
            let allocazioni = piano.allocazioni.filter { $0.strumento != nil }
            // piano senza allocazioni: si aspetta che l'utente le inserisca
            guard !allocazioni.isEmpty else { continue }
            let mesi = CalcoliInvestimenti.mesiDaGenerare(ultimaGenerazione: piano.ultimaGenerazione, giorno: piano.giorno, oggi: oggi)
            guard let primo = mesi.first else { continue }
            let inizioStorico = CalcoliInvestimenti.dataEsecuzione(mese: primo, giorno: piano.giorno).aggiungendo(giorni: -10)

            for mese in mesi {
                defer { piano.ultimaGenerazione = mese }
                guard piano.importoMensile > 0 else { continue }
                let data = CalcoliInvestimenti.dataEsecuzione(mese: mese, giorno: piano.giorno)
                let valide = CalcoliInvestimenti.indiciValidi(allocazioni.map(\.validaDal), al: data).map { allocazioni[$0] }

                let movimento = Movimento(data: data, importo: -piano.importoMensile, tipo: .investimento,
                                          titolo: "PAC " + piano.nome, origine: .pac, stato: .daConfermare, conto: piano.conto)
                context.insert(movimento)

                for a in valide {
                    guard let s = a.strumento else { continue }
                    // prezzo del giorno (in valuta dello strumento), altrimenti l'ultimo noto
                    var prezzo: Double?
                    if !s.valoreManuale {
                        if let t = s.ticker, !t.isEmpty {
                            if chiusure[t] == nil { chiusure[t] = await Prezzi.chiusureGiornaliere(t, da: inizioStorico, a: oggi.aggiungendo(giorni: 1)) }
                            prezzo = CalcoliInvestimenti.chiusura(chiusure[t] ?? [], al: data)
                        }
                        prezzo = prezzo ?? s.ultimoPrezzo
                    }
                    var cambio = 1.0
                    if s.valuta != "EUR" {
                        let chiave = "\(s.valuta)-\(mese.anno)-\(mese.mese)"
                        if cambi[chiave] == nil { cambi[chiave] = await Prezzi.cambio(s.valuta, al: data) }
                        cambio = cambi[chiave] ?? Portafoglio.cambio(s.valuta)
                    }
                    let unitario = prezzo.map { s.tipo == .obbligazione ? $0 / 100 : $0 }
                    let r = CalcoliInvestimenti.ripartizione(importoEUR: piano.importoMensile, percentuale: a.percentuale,
                                                             prezzoUnitario: unitario, cambioEUR: cambio)
                    let op = Operazione(data: data, tipo: prezzo == nil ? .versamento : .acquisto,
                                        quote: r.quote, prezzo: prezzo ?? 0, importo: r.importo, cambioEUR: cambio)
                    op.nota = "PAC " + piano.nome + (prezzo == nil && !s.valoreManuale ? " · prezzo non trovato: riallinea le quote" : "")
                    context.insert(op)
                    op.strumento = s
                    op.movimento = movimento
                }
            }
        }
        try? context.save()
    }
}
