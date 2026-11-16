import Foundation
import SwiftData

/// Collega scontrini e movimenti bancari che rappresentano lo stesso pagamento,
/// così una spesa non viene contata due volte.
enum Abbinamento {

    /// Tolleranza sulla data (giorni) tra un movimento previsto (ricorrenza, PAC, inserito a mano) e l'addebito,
    /// e tra le due metà di un giroconto.
    static let giorniTolleranza = 3
    /// Tra uno scontrino e il suo addebito: la banca contabilizza dopo l'acquisto, mai prima (carta usata il venerdì
    /// sera, ponte, carta di credito). Un giorno di margine all'indietro per gli acquisti a cavallo della mezzanotte.
    static let giorniAddebito = 10
    /// «Collega a un pagamento» lo decide l'utente: finestra larga e importo anche un po' diverso (mancia, valuta estera).
    static let giorniCollegamento = 45
    static let scartoCollegamento = 0.20

    /// Giorni di calendario da `a` a `b` (positivo se `b` viene dopo): le ore non contano.
    static func giorni(da a: Date, a b: Date) -> Int {
        calendario.dateComponents([.day], from: calendario.startOfDay(for: a), to: calendario.startOfDay(for: b)).day ?? 0
    }

    /// Importo nella valuta del conto: gli abbinamenti confrontano quello (il controvalore in euro cambia col cambio del giorno).
    static func nelConto(_ m: Movimento) -> Double { m.valutaOriginale != nil ? (m.importoOriginale ?? m.importo) : m.importo }

    /// Pagamento arrivato dalla banca o da un estratto, ancora senza scontrino (non un giroconto né un prelievo).
    private static func pagamentoLibero(_ m: Movimento) -> Bool {
        m.idEsterno != nil && m.scontrino == nil && m.tipo == .spesa && m.conto != nil && m.conto?.tipo != .contanti
    }

    /// Movimento arrivato dalla banca/estratto, senza scontrino, compatibile con uno scontrino appena scansionato.
    static func movimentoBancaPer(totale: Double, data: Date, in context: ModelContext) -> Movimento? {
        let giorno = calendario.startOfDay(for: data)
        let candidati = Contabilita.movimenti(da: giorno.aggiungendo(giorni: -1), a: giorno.aggiungendo(giorni: giorniAddebito + 1), in: context).filter {
            pagamentoLibero($0) && abs(nelConto($0) + totale) < 0.011
        }
        return candidati.min { abs($0.data.timeIntervalSince(data)) < abs($1.data.timeIntervalSince(data)) }
    }

    /// Movimento creato a mano/da scontrino/da ricorrenza/da PAC che corrisponde a un movimento bancario in arrivo
    /// (`importo` nella valuta del conto). Se lo trova, la sincronizzazione lo completa invece di crearne uno nuovo.
    /// Uno scontrino può precedere l'addebito fino a `giorniAddebito` giorni; gli altri stanno entro ±`giorniTolleranza`.
    static func movimentoEsistentePer(importo: Double, data: Date, conto: Conto?, escludendo usati: Set<PersistentIdentifier> = [],
                                      in context: ModelContext) -> Movimento? {
        let giorno = calendario.startOfDay(for: data)
        let candidati = Contabilita.movimenti(da: giorno.aggiungendo(giorni: -giorniAddebito), a: giorno.aggiungendo(giorni: giorniTolleranza + 1), in: context).filter { m in
            let dopo = giorni(da: m.data, a: data)   // quanti giorni dopo il movimento arriva la banca
            return m.idEsterno == nil
                && !usati.contains(m.persistentModelID)
                && abs(nelConto(m) - importo) < 0.011
                && m.conto?.tipo != .contanti
                && (m.conto == nil || conto == nil || m.conto?.persistentModelID == conto?.persistentModelID)
                && (m.scontrino != nil ? (-1...giorniAddebito).contains(dopo) : abs(dopo) <= giorniTolleranza)
        }
        return candidati.min { abs($0.data.timeIntervalSince(data)) < abs($1.data.timeIntervalSince(data)) }
    }

    /// La stessa transazione già importata da un estratto conto (`idEsterno` "file:…") sullo stesso conto: quando arriva
    /// anche dalla banca collegata prende l'id della banca, invece di diventare un doppione.
    static func movimentoDaEstratto(importo: Double, data: Date, conto: Conto?, in context: ModelContext) -> Movimento? {
        guard let conto else { return nil }
        let giorno = calendario.startOfDay(for: data)
        return Contabilita.movimenti(da: giorno.aggiungendo(giorni: -giorniTolleranza), a: giorno.aggiungendo(giorni: giorniTolleranza + 1), in: context)
            .filter { ($0.idEsterno ?? "").hasPrefix("file:") && $0.conto?.persistentModelID == conto.persistentModelID && abs(nelConto($0) - importo) < 0.011 }
            .min { abs($0.data.timeIntervalSince(data)) < abs($1.data.timeIntervalSince(data)) }
    }

    /// Pagamenti della banca che l'utente può collegare a mano allo scontrino di `m`: senza scontrino, da pochi giorni prima
    /// a `giorniCollegamento` dopo, con importo uguale o vicino. Prima quelli con l'importo più simile.
    static func pagamentiCollegabili(a m: Movimento, in context: ModelContext) -> [Movimento] {
        let giorno = calendario.startOfDay(for: m.data)
        let atteso = abs(nelConto(m))
        func scarto(_ b: Movimento) -> Double { abs(abs(nelConto(b)) - atteso) }
        return Contabilita.movimenti(da: giorno.aggiungendo(giorni: -giorniTolleranza), a: giorno.aggiungendo(giorni: giorniCollegamento + 1), in: context)
            .filter { pagamentoLibero($0) && $0.importo < 0 && $0.persistentModelID != m.persistentModelID
                && scarto($0) <= max(0.011, atteso * scartoCollegamento) }
            .sorted { scarto($0) < scarto($1) }
    }

    /// Scontrino pagato con carta o conto che la banca non ha ancora confermato (nessun addebito abbinato).
    static func attendeBanca(_ m: Movimento) -> Bool {
        m.scontrino != nil && m.idEsterno == nil && m.conto?.tipo != .contanti
    }

    /// Una volta sola: gli scontrini con carta di questo mese e del precedente ancora senza addebito tornano da verificare
    /// (prima venivano salvati già confermati).
    static func scontriniDaVerificare(in context: ModelContext) {
        let chiave = "scontrini.daVerificare"
        guard !UserDefaults.standard.bool(forKey: chiave) else { return }
        for m in Contabilita.movimenti(da: Date().inizioMese.aggiungendo(mesi: -1), a: Date().aggiungendo(giorni: 1), in: context)
        where attendeBanca(m) { m.stato = .daConfermare }
        try? context.save()
        UserDefaults.standard.set(true, forKey: chiave)
    }

    /// Classificato solo dal segno (nessuna parola chiave, nessuna regola imparata): l'unico caso in cui un'entrata o una
    /// spesa può diventare giroconto perché sull'altro conto c'è la cifra opposta. Uno stipendio e un affitto uguali no.
    static func generico(_ m: Movimento) -> Bool { generico(tipo: m.tipo, categoria: m.categoria) }

    static func generico(tipo: TipoMovimento, categoria: Categoria?) -> Bool {
        guard tipo == .spesa || tipo == .entrata else { return false }   // un investimento riconosciuto resta tale
        return categoria == nil || ["Altro", "Altre entrate"].contains { DatiIniziali.corrisponde(categoria?.nome, a: $0) }
    }

    /// L'altra metà di un possibile giroconto: lo stesso importo (in euro) con segno opposto su un ALTRO conto entro
    /// ±giorniTolleranza. Vale se è già un giroconto, oppure se è ancora da confermare e classificata solo dal segno:
    /// le scelte confermate dall'utente e ciò che le parole chiave hanno riconosciuto non si toccano.
    static func controparte(importo: Double, valuta: String?, data: Date, conto: Conto, escluso: Movimento? = nil, in context: ModelContext) -> Movimento? {
        guard conto.tipo != .contanti, importo != 0 else { return nil }
        let vicini = Contabilita.movimenti(da: data.aggiungendo(giorni: -giorniTolleranza), a: data.aggiungendo(giorni: giorniTolleranza + 1), in: context)
            .filter { $0.persistentModelID != escluso?.persistentModelID && $0.conto != nil && $0.conto?.tipo != .contanti }
        func opposto(_ c: Movimento, a importo: Double, _ valuta: String?, _ conto: Conto) -> Bool {
            // tra valute diverse (es. EUR → CHF) il cambio della banca non coincide col nostro: 3% di margine
            let margine = valuta != c.valutaOriginale ? max(0.011, abs(importo) * 0.03) : 0.011
            return abs(c.importo + importo) < margine && c.conto?.persistentModelID != conto.persistentModelID
        }
        let candidati = vicini.filter { c in
            guard opposto(c, a: importo, valuta, conto), c.tipo == .giroconto || (c.daConfermare && generico(c)) else { return false }
            // ponytail: un giroconto che ha già la sua altra metà non ne prende una seconda (terza cifra uguale su un terzo conto);
            // la metà già presente si cerca solo tra i movimenti vicini a questa data
            guard c.tipo == .giroconto, let contoC = c.conto else { return true }
            return !vicini.contains { $0.persistentModelID != c.persistentModelID && $0.tipo == .giroconto && opposto($0, a: c.importo, c.valutaOriginale, contoC) }
        }
        // ponytail: vince la data più vicina; due ricariche identiche nello stesso giorno possono incrociarsi, i totali non cambiano
        return candidati.min(by: { abs($0.data.timeIntervalSince(data)) < abs($1.data.timeIntervalSince(data)) })
    }

    /// Giroconto tra conti propri (ricarica di un conto online, bonifico al conto deposito, saldo della carta di credito…):
    /// se sull'altro conto c'è la `controparte`, segna entrambi come giroconto, così non gonfiano entrate e spese.
    static func segnaGiroconto(_ m: Movimento, in context: ModelContext) {
        guard let conto = m.conto,
              let c = controparte(importo: m.importo, valuta: m.valutaOriginale, data: m.data, conto: conto, escluso: m, in: context) else { return }
        for x in [m, c] where x.tipo != .giroconto {
            x.tipo = .giroconto
            x.categoria = nil
        }
        if m.valutaOriginale != c.valutaOriginale { registraCostoCambio(m, c, in: context) }
    }

    /// Costo di un cambio tra conti propri in valute diverse (spread e commissioni nascoste nel tasso): quanto è uscito
    /// meno quanto è entrato, in euro al cambio BCE. Diventa una spesa in "Commissioni bancarie" senza conto, perché
    /// i saldi dei conti lo contengono già. Se il cambio è stato migliore di quello BCE non si registra nulla.
    static func registraCostoCambio(_ a: Movimento, _ b: Movimento, in context: ModelContext) {
        guard let estero = [a, b].first(where: { $0.valutaOriginale != nil }), let id = estero.idEsterno else { return }
        let chiave: String? = "costo-cambio:" + id
        var d = FetchDescriptor<Movimento>(predicate: #Predicate { $0.idEsterno == chiave })
        d.fetchLimit = 1
        let esistente = (try? context.fetch(d))?.first
        let costo = (-(a.importo + b.importo)).centesimi
        guard costo >= 0.01 else {
            if let esistente { context.delete(esistente) }
            return
        }
        let (uscita, entrata) = a.importo < 0 ? (a, b) : (b, a)
        let m = esistente ?? {
            let titolo = String(localized: "Costo del cambio \(uscita.valutaOriginale ?? "EUR") → \(entrata.valutaOriginale ?? "EUR")")
            let nuovo = Movimento(data: max(a.data, b.data), importo: 0, tipo: .spesa, titolo: titolo, origine: estero.origine)
            nuovo.idEsterno = chiave
            context.insert(nuovo)
            return nuovo
        }()
        m.importo = -costo
        m.data = max(a.data, b.data)
        if m.categoria == nil { m.categoria = Classificatore.categoria(nome: "Commissioni bancarie", in: context) }
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
        // scontrino pagato con carta: da verificare finché non arriva l'addebito, che lo conferma senza creare doppioni
        let scontrino = Scontrino(negozio: "Bar", data: oggi, totale: 12.34)
        ctx.insert(scontrino)
        let pagato = Movimento(data: oggi, importo: -12.34, tipo: .spesa, titolo: "Bar", origine: .scontrino, stato: .daConfermare, conto: corrente)
        ctx.insert(pagato)
        scontrino.movimento = pagato
        assert(attendeBanca(pagato))
        let addebito = arriva(-12.34, "POS BAR", corrente, giorni: 1)
        assert(addebito === pagato && !pagato.daConfermare && !attendeBanca(pagato), "scontrino non confermato dalla banca")
        // addebito contabilizzato 6 giorni dopo lo scontrino (venerdì sera, ponte): si uniscono lo stesso; un addebito di due giorni PRIMA no
        func scontrinoCarta(_ totale: Double, giorni: Int) -> Movimento {
            let s = Scontrino(negozio: "Negozio", data: oggi.aggiungendo(giorni: giorni), totale: totale)
            ctx.insert(s)
            let m = Movimento(data: s.data, importo: -totale, tipo: .spesa, titolo: "Negozio", origine: .scontrino, stato: .daConfermare, conto: corrente)
            ctx.insert(m)
            s.movimento = m
            return m
        }
        let tardi = scontrinoCarta(23.45, giorni: -6)
        assert(arriva(-23.45, "POS NEGOZIO", corrente) === tardi && !tardi.daConfermare, "addebito 6 giorni dopo lo scontrino")
        let dopo = scontrinoCarta(34.56, giorni: 2)
        assert(arriva(-34.56, "POS ALTRO", corrente) !== dopo && dopo.daConfermare, "un addebito non precede lo scontrino")
        // collegamento a mano: importo vicino (mancia, valuta estera) anche 20 giorni dopo
        let mancia = scontrinoCarta(50, giorni: -20)
        let conMancia = arriva(-55, "POS RISTORANTE", corrente, giorni: -1)
        assert(pagamentiCollegabili(a: mancia, in: ctx).contains { $0 === conMancia }, "collegabili: \(pagamentiCollegabili(a: mancia, in: ctx).map(\.importo))")
        // la stessa transazione importata da un estratto conto e poi arrivata dalla banca collegata: niente doppione
        Sincronizzazione.creaMovimento(data: oggi, importo: -61.7, descrizione: "POS LIBRERIA", idEsterno: "file:prova", conto: corrente, origine: .estratto,
                                       suggerimento: Classificatore.suggerisciBanca(descrizione: "POS LIBRERIA", importo: -61.7, in: ctx), stato: .confermato, in: ctx)
        let daFile = try! ctx.fetch(FetchDescriptor<Movimento>(predicate: #Predicate { $0.importo == -61.7 }))
        assert(daFile.count == 1 && arriva(-61.7, "PAGAMENTO POS LIBRERIA", corrente, giorni: 1) === daFile[0])
        assert(try! ctx.fetchCount(FetchDescriptor<Movimento>(predicate: #Predicate { $0.importo == -61.7 })) == 1, "doppione tra estratto e banca")
        // movimento della banca eliminato dall'utente: alla sincronizzazione successiva non ricompare
        let eliminatiPrima = Sincronizzazione.eliminati
        defer { Sincronizzazione.eliminati = eliminatiPrima }
        let daEliminare = arriva(-9.99, "POS EDICOLA", corrente)
        let idEliminato = daEliminare.idEsterno!
        Sincronizzazione.ricordaEliminato(daEliminare)
        ctx.delete(daEliminare)
        try! ctx.save()
        assert(!Sincronizzazione.registraMovimento(data: oggi, importo: -9.99, descrizione: "POS EDICOLA", idEsterno: idEliminato, conto: corrente, origine: .banca, in: ctx))
        assert(try! ctx.fetchCount(FetchDescriptor<Movimento>(predicate: #Predicate { $0.importo == -9.99 })) == 0, "il movimento eliminato è ricomparso")
        // le due metà di un bonifico tra conti propri con lo stesso id della banca restano due movimenti (e sono un giroconto)
        Sincronizzazione.registraMovimento(data: oggi, importo: -77, descrizione: "BONIFICO INTERNO", idEsterno: "stesso-id", conto: corrente, origine: .banca, in: ctx)
        Sincronizzazione.registraMovimento(data: oggi, importo: 77, descrizione: "BONIFICO INTERNO", idEsterno: "stesso-id", conto: deposito, origine: .banca, in: ctx)
        let stessoId: String? = "stesso-id"
        let meta = try! ctx.fetch(FetchDescriptor<Movimento>(predicate: #Predicate { $0.idEsterno == stessoId }))
        assert(meta.count == 2 && meta.allSatisfy { $0.tipo == .giroconto }, "metà del bonifico: \(meta.map(\.importo))")
        // una spesa riconosciuta dalle parole chiave non diventa giroconto perché sull'altro conto arriva un'entrata uguale
        DatiIniziali.inserisciSeVuoto(ctx)   // servono le categorie: è la categoria a dire che una parola chiave l'ha riconosciuta
        let spesaVera = arriva(-48, "ESSELUNGA", corrente, giorni: -9), entrataVera = arriva(48, "Bonifico Luigi", deposito, giorni: -8)
        assert(spesaVera.tipo == .spesa && entrataVera.tipo == .entrata, "falso giroconto")
        // classificatore: la metro di Milano non è un prelievo; una regola imparata su un'entrata non vale per un'uscita
        assert(Classificatore.suggerisciBanca(descrizione: "ATM MILANO", importo: -2.2, in: ctx).tipo == .spesa)
        Classificatore.impara(descrizioneBanca: "Bonifico Mario Rossi", tipo: .entrata, categoria: nil, titolo: "Mario", in: ctx)
        assert(Classificatore.suggerisciBanca(descrizione: "Bonifico Mario Rossi", importo: 30, in: ctx).tipo == .entrata)
        assert(Classificatore.suggerisciBanca(descrizione: "Bonifico Mario Rossi", importo: -30, in: ctx).tipo == .spesa, "entrata con importo negativo")
        // i giroconti non entrano nei totali
        let t = Contabilita.totali([uscita, entrata, a, b])
        assert(t.entrate == 0 && t.spese == 0)
        // conto in franchi: importo in euro al cambio, saldo nella valuta del conto, giroconto EUR → CHF col 3% di margine
        let cambioPrima = UserDefaults.standard.double(forKey: "cambio.CHF")
        defer { UserDefaults.standard.set(cambioPrima, forKey: "cambio.CHF") }
        Portafoglio.salvaCambio("CHF", 1.07)
        DatiIniziali.inserisciSeVuoto(ctx)   // serve la categoria Commissioni bancarie
        let svizzero = Conto(nome: "Svizzero", tipo: .corrente)
        svizzero.valuta = "CHF"
        ctx.insert(svizzero)
        let chf = arriva(-100, "COOP PRONTO", svizzero)
        assert(chf.importo == -107 && chf.importoOriginale == -100 && chf.valutaOriginale == "CHF")
        assert(Contabilita.saldoInValuta(svizzero) == -100 && abs(Contabilita.saldo(svizzero) + 107) < 0.001)
        let versoCH = arriva(-1_000, "BONIFICO SEPA SWISS", corrente, giorni: 10)
        let inCH = arriva(920, "ACCREDITO", svizzero, giorni: 11)   // 920 CHF = 984,40 € al nostro cambio: dentro il 3%
        assert(versoCH.tipo == .giroconto && inCH.tipo == .giroconto)
        // il cambio è costato 1000 − 984,40 = 15,60 €: spesa senza conto in Commissioni bancarie
        let idCosto: String? = "costo-cambio:" + (inCH.idEsterno ?? "")
        let costo = try! ctx.fetch(FetchDescriptor<Movimento>(predicate: #Predicate { $0.idEsterno == idCosto })).first
        assert(costo?.importo == -15.6 && costo?.tipo == .spesa && costo?.conto == nil, "costo del cambio: \(String(describing: costo?.importo))")
        assert(DatiIniziali.corrisponde(costo?.categoria?.nome, a: "Commissioni bancarie"))
        assert(abs(Contabilita.saldo(corrente) - Contabilita.saldoInValuta(corrente)) < 0.001)   // il costo non tocca i saldi
        // scontrino in franchi sul conto svizzero: si unisce all'addebito in franchi anche se i due controvalori in euro differiscono
        let scontrinoCH = Scontrino(negozio: "Panetteria", data: oggi, totale: 8.5)
        ctx.insert(scontrinoCH)
        let pagatoCH = Movimento(data: oggi, importo: 0, tipo: .spesa, titolo: "Panetteria", origine: .scontrino, stato: .daConfermare, conto: svizzero)
        Contabilita.imposta(pagatoCH, importoInValuta: -8.5, valuta: "CHF")
        pagatoCH.importo -= 0.03   // come se fosse stato convertito col cambio di un altro giorno
        ctx.insert(pagatoCH)
        scontrinoCH.movimento = pagatoCH
        assert(arriva(-8.5, "KARTE PANETTERIA", svizzero, giorni: 1) === pagatoCH && pagatoCH.importoOriginale == -8.5, "scontrino in franchi")
        print("Abbinamento.autoverifica OK")
    }
    #endif
}

