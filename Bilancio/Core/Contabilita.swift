import Foundation
import SwiftData

/// Calcoli condivisi da Anno, Mese, Consigli: totali, categorie, saldi, patrimonio.
enum Contabilita {

    struct Totali {
        var entrate = 0.0
        var spese = 0.0
        var investito = 0.0
        var risparmio: Double { entrate - spese }
        var tassoRisparmio: Double { entrate > 0 ? risparmio / entrate : 0 }
        /// Il tasso ha senso da mostrare: c'è un'entrata e le spese non superano il doppio
        /// (a metà mese, prima dello stipendio, verrebbe "-7726% delle entrate").
        var tassoSignificativo: Bool { entrate > 0 && tassoRisparmio >= -1 }
    }

    struct VoceCategoria: Identifiable {
        let categoria: Categoria?
        var importo: Double
        var id: String { categoria?.nome ?? String(localized: "Senza categoria") }
        var nome: String { categoria?.nome ?? String(localized: "Senza categoria") }
        var coloreHex: String { categoria?.coloreHex ?? "#9CA3AF" }
    }

    /// Movimenti con data in [da, a), dal più recente.
    static func movimenti(da: Date, a: Date, in context: ModelContext) -> [Movimento] {
        let descr = FetchDescriptor<Movimento>(
            predicate: #Predicate { $0.data >= da && $0.data < a },
            sortBy: [SortDescriptor(\.data, order: .reverse)]
        )
        return (try? context.fetch(descr)) ?? []
    }

    static func movimenti(mese: Date, in context: ModelContext) -> [Movimento] {
        movimenti(da: mese.inizioMese, a: mese.inizioMeseSuccessivo, in: context)
    }

    static func movimenti(anno: Int, in context: ModelContext) -> [Movimento] {
        movimenti(da: inizioAnno(anno), a: inizioAnno(anno + 1), in: context)
    }

    /// Entrate, spese e investito. I giroconti non contano. Una spesa con importo positivo (rimborso) riduce le spese.
    static func totali(_ movimenti: [Movimento]) -> Totali {
        var t = Totali()
        for m in movimenti {
            switch m.tipo {
            case .spesa: t.spese -= m.importo
            case .entrata: t.entrate += m.importo
            case .investimento: t.investito -= m.importo
            case .giroconto: break
            }
        }
        return t
    }

    /// Spese per categoria, dalla più alta. Gli scontrini con righe vengono ripartiti riga per riga,
    /// così una spesa al supermercato può finire in più categorie.
    static func spesePerCategoria(_ movimenti: [Movimento]) -> [VoceCategoria] {
        var accumulo: [String: VoceCategoria] = [:]
        func aggiungi(_ c: Categoria?, _ importo: Double) {
            let chiave = c?.nome ?? String(localized: "Senza categoria")
            accumulo[chiave, default: VoceCategoria(categoria: c, importo: 0)].importo += importo
        }
        for m in movimenti where m.tipo == .spesa {
            let totale = -m.importo
            if let s = m.scontrino, !s.righe.isEmpty {
                let somma = s.righe.reduce(0) { $0 + $1.totale }
                if somma != 0 {
                    for r in s.righe { aggiungi(r.categoria ?? m.categoria, totale * r.totale / somma) }
                    continue
                }
            }
            aggiungi(m.categoria, totale)
        }
        return accumulo.values.filter { abs($0.importo) >= 0.005 }.sorted { $0.importo > $1.importo }
    }

    /// Saldo nella valuta del conto: quello letto dalla banca se c'è, altrimenti saldo iniziale + movimenti.
    static func saldoInValuta(_ conto: Conto) -> Double {
        if let b = conto.saldoBanca { return b }
        return conto.saldoIniziale + conto.movimenti.reduce(0) { $0 + ($1.importoOriginale ?? $1.importo) }
    }

    /// Saldo in euro (i conti in valuta estera al cambio di oggi).
    static func saldo(_ conto: Conto) -> Double { saldoInValuta(conto) * Portafoglio.cambio(conto.valuta) }

    /// Importo nella valuta di un conto → euro, all'ultimo cambio noto (poi `applicaCambiStorici` usa quello del giorno).
    static func inEuro(_ importo: Double, valuta: String) -> Double {
        valuta == "EUR" ? importo : (importo * Portafoglio.cambio(valuta)).centesimi
    }

    /// Imposta l'importo di un movimento dato nella valuta del suo conto: `importo` in euro, l'originale a parte.
    static func imposta(_ m: Movimento, importoInValuta v: Double, valuta: String) {
        m.importo = inEuro(v, valuta: valuta)
        m.importoOriginale = valuta == "EUR" ? nil : v
        m.valutaOriginale = valuta == "EUR" ? nil : valuta
        m.cambioStorico = false
    }

    /// Ricalcola in euro i movimenti in valuta estera col cambio BCE del loro giorno (serve internet; chi resta
    /// senza cambio riprova alla prossima apertura). Ricalcola anche il costo dei cambi tra conti propri.
    static func applicaCambiStorici(in context: ModelContext) async {
        let daFare = ((try? context.fetch(FetchDescriptor<Movimento>(predicate: #Predicate { $0.valutaOriginale != nil && !$0.cambioStorico }))) ?? [])
        var cache: [String: Double] = [:]
        for m in daFare {
            guard let v = m.valutaOriginale, let originale = m.importoOriginale else { continue }
            let chiave = "\(v)-\(calendario.startOfDay(for: m.data).timeIntervalSince1970)"
            var cambio = cache[chiave]
            if cambio == nil { cambio = await Prezzi.cambio(v, al: m.data); cache[chiave] = cambio }
            guard let cambio else { continue }
            m.importo = (originale * cambio).centesimi
            m.cambioStorico = true
            if m.tipo == .giroconto { Abbinamento.segnaGiroconto(m, in: context) }
        }
        if !daFare.isEmpty { try? context.save() }
    }

    /// Somma dei saldi dei conti attivi (le carte di credito pesano in negativo).
    static func liquidita(in context: ModelContext) -> Double {
        let conti = (try? context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { !$0.archiviato }))) ?? []
        return conti.reduce(0) { $0 + saldo($1) }
    }

    static func investimenti(in context: ModelContext) -> Double {
        let strumenti = (try? context.fetch(FetchDescriptor<Strumento>(predicate: #Predicate { !$0.archiviato }))) ?? []
        return strumenti.reduce(0) { $0 + Portafoglio.valoreEUR($1) }
    }

    static func patrimonio(in context: ModelContext) -> Double {
        liquidita(in: context) + investimenti(in: context)
    }

    /// Aggiorna (o crea) la fotografia del patrimonio del mese corrente.
    static func aggiornaSnapshot(in context: ModelContext) {
        let mese = Date().inizioMese
        let esistente = try? context.fetch(FetchDescriptor<SnapshotPatrimonio>(predicate: #Predicate { $0.mese == mese })).first
        let liq = liquidita(in: context)
        let inv = investimenti(in: context)
        if let s = esistente {
            s.liquidita = liq
            s.investimenti = inv
            s.aggiornatoIl = Date()
        } else {
            context.insert(SnapshotPatrimonio(mese: mese, liquidita: liq, investimenti: inv))
        }
    }

    static func daConfermare(in context: ModelContext) -> [Movimento] {
        let stato = StatoMovimento.daConfermare.rawValue
        let descr = FetchDescriptor<Movimento>(predicate: #Predicate { $0.statoRaw == stato }, sortBy: [SortDescriptor(\.data, order: .reverse)])
        return (try? context.fetch(descr)) ?? []
    }
}

extension Movimento {
    /// Conferma il movimento. Se l'importo cambia e ci sono operazioni collegate (PAC),
    /// le riproporziona al nuovo importo.
    func conferma(nuovoImporto: Double? = nil) {
        if let nuovo = nuovoImporto, nuovo != importo, importo != 0 {
            let rapporto = nuovo / importo
            for op in operazioni {
                op.quote *= rapporto
                op.importo *= rapporto
            }
            importo = nuovo
        }
        stato = .confermato
    }
}
