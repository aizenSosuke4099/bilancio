import Foundation
import SwiftData

/// Propone ogni mese i movimenti ricorrenti (da confermare). Gira all'apertura dell'app.
enum GeneratoreRicorrenze {

    static func genera(in context: ModelContext) {
        genera(in: context, oggi: Date())
    }

    static func genera(in context: ModelContext, oggi: Date) {
        let ricorrenze = (try? context.fetch(FetchDescriptor<Ricorrenza>(predicate: #Predicate { $0.attiva }))) ?? []
        for r in ricorrenze {
            for data in dateDovute(ultimaGenerazione: r.ultimaGenerazione, ogniMesi: r.ogniMesi, giorno: r.giorno, oggi: oggi) {
                r.ultimaGenerazione = data.inizioMese
                // se la banca ha già portato lo stesso pagamento, lo collego invece di duplicarlo
                let giaArrivato = Contabilita.movimenti(da: data.aggiungendo(giorni: -Abbinamento.giorniTolleranza),
                                                        a: data.aggiungendo(giorni: Abbinamento.giorniTolleranza + 1), in: context).first { m in
                    m.idEsterno != nil && m.ricorrenza == nil && abs(Abbinamento.nelConto(m) - r.importo) < 0.011
                        && (r.conto == nil || m.conto?.persistentModelID == r.conto?.persistentModelID)
                }
                if let giaArrivato {
                    giaArrivato.ricorrenza = r
                    continue
                }
                let m = Movimento(data: data, importo: r.importo, tipo: r.tipo, titolo: r.nome, origine: .ricorrente,
                                  stato: .daConfermare, conto: r.conto, categoria: r.categoria)
                Contabilita.imposta(m, importoInValuta: r.importo, valuta: r.conto?.valuta ?? "EUR")   // l'importo è nella valuta del conto
                m.ricorrenza = r
                context.insert(m)
            }
        }
        try? context.save()
    }

    /// Giorni in cui la ricorrenza va proposta: dal mese dopo l'ultima generazione (ogni `ogniMesi`),
    /// oppure dal mese corrente se mai generata, fino a oggi. Il giorno si ferma all'ultimo del mese (31 → 28 febbraio).
    static func dateDovute(ultimaGenerazione: Date?, ogniMesi: Int, giorno: Int, oggi: Date) -> [Date] {
        let passo = max(ogniMesi, 1)
        var mese = ultimaGenerazione.map { $0.inizioMese.aggiungendo(mesi: passo) } ?? oggi.inizioMese
        let fine = calendario.startOfDay(for: oggi)
        var date: [Date] = []
        while mese <= fine {
            let giorniNelMese = calendario.range(of: .day, in: .month, for: mese)?.count ?? 28
            let data = mese.aggiungendo(giorni: min(max(giorno, 1), giorniNelMese) - 1)
            guard data <= fine else { break }
            date.append(data)
            mese = mese.aggiungendo(mesi: passo)
        }
        return date
    }
}

// MARK: - Self-check (avvio con `-verifica`)
#if DEBUG
extension GeneratoreRicorrenze {
    private static func g(_ a: Int, _ m: Int, _ d: Int) -> Date { calendario.date(from: DateComponents(year: a, month: m, day: d))! }

    @MainActor static func autoverifica() {
        do { try verifica() } catch { fatalError("Ricorrenze: \(error)") }
    }

    private static func verifica() throws {
        // date dovute
        precondition(GeneratoreRicorrenze.dateDovute(ultimaGenerazione: g(2026, 1, 1), ogniMesi: 1, giorno: 31, oggi: g(2026, 4, 15)) == [g(2026, 2, 28), g(2026, 3, 31)])
        precondition(GeneratoreRicorrenze.dateDovute(ultimaGenerazione: nil, ogniMesi: 1, giorno: 10, oggi: g(2026, 4, 15)) == [g(2026, 4, 10)])
        precondition(GeneratoreRicorrenze.dateDovute(ultimaGenerazione: nil, ogniMesi: 1, giorno: 20, oggi: g(2026, 4, 15)).isEmpty)
        precondition(GeneratoreRicorrenze.dateDovute(ultimaGenerazione: g(2026, 1, 1), ogniMesi: 3, giorno: 1, oggi: g(2026, 7, 5)) == [g(2026, 4, 1), g(2026, 7, 1)])
        precondition(GeneratoreRicorrenze.dateDovute(ultimaGenerazione: g(2026, 4, 1), ogniMesi: 1, giorno: 15, oggi: g(2026, 4, 30)).isEmpty)

        // generazione su un database in memoria
        let container = try ModelContainer(for: Persistenza.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let netflix = Ricorrenza(nome: "Netflix", importo: -12.99, tipo: .spesa, giorno: 31)
        netflix.ultimaGenerazione = g(2026, 1, 1)
        let spenta = Ricorrenza(nome: "Vecchia palestra", importo: -40, tipo: .spesa, giorno: 1)
        spenta.attiva = false
        let stipendio = Ricorrenza(nome: "Stipendio", importo: 1800, tipo: .entrata, giorno: 27)
        stipendio.ultimaGenerazione = g(2026, 2, 1)
        [netflix, spenta, stipendio].forEach(ctx.insert)
        // lo stipendio di marzo è già arrivato dalla banca: va collegato, non duplicato
        let banca = Movimento(data: g(2026, 3, 26), importo: 1800, tipo: .entrata, titolo: "Acme", origine: .banca)
        banca.idEsterno = "tx-1"
        ctx.insert(banca)

        GeneratoreRicorrenze.genera(in: ctx, oggi: g(2026, 4, 15))
        GeneratoreRicorrenze.genera(in: ctx, oggi: g(2026, 4, 15)) // seconda volta: niente di nuovo
        let movimenti = try ctx.fetch(FetchDescriptor<Movimento>(sortBy: [SortDescriptor(\.data)]))
        let generati = movimenti.filter { $0.origine == .ricorrente }
        precondition(generati.map(\.data) == [g(2026, 2, 28), g(2026, 3, 31)], "\(generati.map(\.data))")
        precondition(generati.allSatisfy { $0.ricorrenza === netflix && $0.importo == -12.99 && $0.daConfermare })
        precondition(netflix.ultimaGenerazione == g(2026, 3, 1) && stipendio.ultimaGenerazione == g(2026, 3, 1))
        precondition(banca.ricorrenza === stipendio && movimenti.count == 3)
        print("Ricorrenze OK: date dovute, fine mese, trimestrali, nessun doppione, pagamento già arrivato collegato")
    }
}

#endif
