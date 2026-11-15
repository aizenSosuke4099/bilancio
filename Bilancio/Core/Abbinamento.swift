import Foundation
import SwiftData

/// Collega scontrini e movimenti bancari che rappresentano lo stesso pagamento,
/// così una spesa non viene contata due volte.
enum Abbinamento {

    /// Tolleranza sulla data (giorni) tra scontrino e addebito.
    static let giorniTolleranza = 3

    /// Movimento arrivato dalla banca/estratto, senza scontrino, compatibile con uno scontrino appena scansionato.
    static func movimentoBancaPer(totale: Double, data: Date, in context: ModelContext) -> Movimento? {
        let da = data.aggiungendo(giorni: -giorniTolleranza)
        let a = data.aggiungendo(giorni: giorniTolleranza + 1)
        let candidati = Contabilita.movimenti(da: da, a: a, in: context).filter {
            $0.scontrino == nil && $0.idEsterno != nil && abs($0.importo + totale) < 0.011
        }
        return candidati.min { abs($0.data.timeIntervalSince(data)) < abs($1.data.timeIntervalSince(data)) }
    }

    /// Movimento creato a mano/da scontrino/da ricorrenza/da PAC che corrisponde a un movimento bancario in arrivo.
    /// Se lo trova, la sincronizzazione lo aggiorna invece di crearne uno nuovo.
    static func movimentoEsistentePer(importo: Double, data: Date, conto: Conto?, in context: ModelContext) -> Movimento? {
        let da = data.aggiungendo(giorni: -giorniTolleranza)
        let a = data.aggiungendo(giorni: giorniTolleranza + 1)
        let candidati = Contabilita.movimenti(da: da, a: a, in: context).filter { m in
            m.idEsterno == nil
                && abs(m.importo - importo) < 0.011
                && m.conto?.tipo != .contanti
                && (m.conto == nil || conto == nil || m.conto?.persistentModelID == conto?.persistentModelID)
        }
        return candidati.min { abs($0.data.timeIntervalSince(data)) < abs($1.data.timeIntervalSince(data)) }
    }

    /// Giroconto tra conti propri (ricarica di un conto online, bonifico al conto deposito, saldo della carta di credito…): cerca su un ALTRO conto
    /// lo stesso importo con segno opposto entro ±giorniTolleranza. Se lo trova, segna entrambi come giroconto,
    /// così non gonfiano entrate e spese. Le scelte già confermate dall'utente (non giroconto) non si toccano.
    static func segnaGiroconto(_ m: Movimento, in context: ModelContext) {
        guard let conto = m.conto, conto.tipo != .contanti, m.importo != 0 else { return }
        let candidati = Contabilita.movimenti(da: m.data.aggiungendo(giorni: -giorniTolleranza),
                                              a: m.data.aggiungendo(giorni: giorniTolleranza + 1), in: context).filter { c in
            // tra valute diverse (es. EUR → CHF) il cambio della banca non coincide col nostro: 3% di margine
            let margine = m.valutaOriginale != c.valutaOriginale ? max(0.011, abs(m.importo) * 0.03) : 0.011
            return c.persistentModelID != m.persistentModelID
                && abs(c.importo + m.importo) < margine
                && c.conto != nil && c.conto?.tipo != .contanti
                && c.conto?.persistentModelID != conto.persistentModelID
                && (c.tipo == .giroconto || c.daConfermare)
        }
        // ponytail: vince la data più vicina; due ricariche identiche nello stesso giorno possono incrociarsi, i totali non cambiano
        guard let c = candidati.min(by: { abs($0.data.timeIntervalSince(m.data)) < abs($1.data.timeIntervalSince(m.data)) }) else { return }
        for x in [m, c] where x.tipo != .giroconto {
            x.tipo = .giroconto
            x.categoria = nil
        }
    }

    #if DEBUG
    /// Avvio con `-verifica`: controlla l'abbinamento dei giroconti su un database in memoria.
    @MainActor static func autoverifica() {
        let container = try! ModelContainer(for: Persistenza.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let corrente = Conto(nome: "Corrente", tipo: .corrente), deposito = Conto(nome: "Deposito", tipo: .remunerato), contanti = Conto(nome: "Contanti", tipo: .contanti)
        [corrente, deposito, contanti].forEach(ctx.insert)
        let oggi = Date()
        func arriva(_ importo: Double, _ descr: String, _ conto: Conto, giorni: Int = 0) -> Movimento {
            let id: String? = UUID().uuidString
            Sincronizzazione.registraMovimento(data: oggi.aggiungendo(giorni: giorni), importo: importo, descrizione: descr,
                                               idEsterno: id!, conto: conto, origine: .banca, in: ctx)
            return try! ctx.fetch(FetchDescriptor<Movimento>(predicate: #Predicate { $0.idEsterno == id })).first!
        }
        // uscita riconosciuta dalle parole chiave, entrata generica due giorni dopo: diventano entrambe giroconto
        let uscita = arriva(-200, "GIROCONTO A CONTO DEPOSITO", corrente)
        let entrata = arriva(200, "Deposito", deposito, giorni: 2)
        assert(uscita.tipo == .giroconto && entrata.tipo == .giroconto && entrata.categoria == nil)
        // nessuna parola chiave da nessuna parte: basta l'abbinamento
        let a = arriva(-55.5, "BONIFICO SEPA XYZ", corrente), b = arriva(55.5, "Payment from L Q", deposito, giorni: -1)
        assert(a.tipo == .giroconto && b.tipo == .giroconto)
        // stesso conto, importo diverso, troppo lontano, entrata già confermata: niente giroconto
        let c1 = arriva(-30, "ESSELUNGA", corrente), c2 = arriva(30, "Rimborso amico", corrente)
        assert(c1.tipo == .spesa && c2.tipo != .giroconto)
        let d1 = arriva(-40, "ESSELUNGA", corrente), d2 = arriva(40.5, "Bonifico Mario", deposito)
        assert(d1.tipo == .spesa && d2.tipo != .giroconto)
        let e1 = arriva(-70, "ESSELUNGA", corrente), e2 = arriva(70, "Bonifico Mario", deposito, giorni: 5)
        assert(e1.tipo == .spesa && e2.tipo != .giroconto)
        let f1 = arriva(90, "Bonifico Mario", deposito); f1.stato = .confermato
        let f2 = arriva(-90, "ESSELUNGA", corrente)
        assert(f1.tipo == .entrata && f2.tipo == .spesa)
        // i giroconti non entrano nei totali
        let t = Contabilita.totali([uscita, entrata, a, b])
        assert(t.entrate == 0 && t.spese == 0)
        // conto in franchi: importo in euro al cambio, saldo nella valuta del conto, giroconto EUR → CHF col 3% di margine
        let cambioPrima = UserDefaults.standard.double(forKey: "cambio.CHF")
        defer { UserDefaults.standard.set(cambioPrima, forKey: "cambio.CHF") }
        Portafoglio.salvaCambio("CHF", 1.07)
        let svizzero = Conto(nome: "Svizzero", tipo: .corrente)
        svizzero.valuta = "CHF"
        ctx.insert(svizzero)
        let chf = arriva(-100, "COOP PRONTO", svizzero)
        assert(chf.importo == -107 && chf.importoOriginale == -100 && chf.valutaOriginale == "CHF")
        assert(Contabilita.saldoInValuta(svizzero) == -100 && abs(Contabilita.saldo(svizzero) + 107) < 0.001)
        let versoCH = arriva(-1_000, "BONIFICO SEPA SWISS", corrente, giorni: 10)
        let inCH = arriva(950, "ACCREDITO", svizzero, giorni: 11)   // 950 CHF = 1016,50 € al nostro cambio: dentro il 3%
        assert(versoCH.tipo == .giroconto && inCH.tipo == .giroconto)
        print("Abbinamento.autoverifica OK")
    }
    #endif
}

