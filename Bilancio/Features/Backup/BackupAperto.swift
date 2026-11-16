import Foundation
import SwiftData

/// Backup in formato aperto, leggibile da qualsiasi sistema (Android, Windows, Linux):
///   bilancio.json   tutti i dati (JSON UTF-8, descritto in LEGGIMI.txt)
///   foto/           immagini degli scontrini, una per file
///   movimenti.csv   i movimenti per Excel / Fogli Google
///   LEGGIMI.txt     descrizione del formato
/// Il ripristino ricostruisce il database da bilancio.json e foto/.
enum BackupAperto {
    static let fileDati = "bilancio.json"
    static let cartellaFoto = "foto"

    // MARK: Formato (versione 1)

    struct Archivio: Codable {
        var formato = "bilancio-backup"
        var versione = 1
        var creatoIl = Date()
        var conti: [ContoJ] = []
        var categorie: [CategoriaJ] = []
        var movimenti: [MovimentoJ] = []
        var ricorrenze: [RicorrenzaJ] = []
        var scontrini: [ScontrinoJ] = []
        var righeScontrino: [RigaJ] = []
        var prodotti: [ProdottoJ] = []
        var regoleApprese: [RegolaJ] = []
        var strumenti: [StrumentoJ] = []
        var operazioni: [OperazioneJ] = []
        var valutazioni: [ValutazioneJ] = []
        var pianiPAC: [PianoJ] = []
        var allocazioniPAC: [AllocazioneJ] = []
        var snapshotPatrimonio: [SnapshotJ] = []
        var connessioniBanca: [ConnessioneJ] = []
        var profiliImport: [ProfiloJ] = []
    }

    struct ContoJ: Codable {
        var id, nome, tipo, istituto, valuta: String
        var saldoIniziale: Double
        var saldoBanca: Double?, saldoBancaData: Date?, tassoAnnuo: Double?
        var ebAccountUid: String?, iban: String?
        var coloreHex: String, ordine: Int, archiviato: Bool
    }
    struct CategoriaJ: Codable {
        var id, nome, icona, coloreHex, tipo: String
        var budgetMensile: Double?, detraibile: Bool, ordine: Int
    }
    struct MovimentoJ: Codable {
        var id: String, data: Date, importo: Double
        var importoOriginale: Double?, valutaOriginale: String?, cambioStorico: Bool?
        var tipo, titolo, nota, descrizioneOriginale, stato, origine: String
        var idEsterno: String?, creatoIl: Date
        var conto: String?, categoria: String?, ricorrenza: String?
    }
    struct RicorrenzaJ: Codable {
        var id, nome: String, importo: Double, tipo: String, giorno, ogniMesi: Int, attiva: Bool
        var ultimaGenerazione: Date?, conto: String?, categoria: String?
    }
    struct ScontrinoJ: Codable {
        var id, negozio, indirizzo, partitaIva: String, data: Date, totale: Double
        /// Nome del file in foto/ (nil = senza foto).
        var foto: String?
        var testoOCR: String, creatoIl: Date, movimento: String?
    }
    struct RigaJ: Codable {
        var id, testo: String, quantita, prezzoUnitario, totale: Double, ordine: Int
        var scontrino: String?, categoria: String?, prodotto: String?
    }
    struct ProdottoJ: Codable {
        var id, nome, unita: String, formato: Double?, categoria: String?
    }
    struct RegolaJ: Codable {
        var id, chiave, ambito: String, categoria: String?, tipo: String?, nomeProdotto: String?, titolo: String?
        var utilizzi: Int, aggiornataIl: Date
    }
    struct StrumentoJ: Codable {
        var id, nome, isin: String, ticker: String?, tipo, piattaforma, valuta: String
        var ultimoPrezzo: Double?, ultimoPrezzoData: Date?, valoreManuale: Bool
        var cedola: Double?, scadenza: Date?, fondoPensioneItaliano, archiviato: Bool, creatoIl: Date
    }
    struct OperazioneJ: Codable {
        var id: String, data: Date, tipo: String, quote, prezzo, importo, commissioni, cambioEUR: Double, nota: String
        var strumento: String?, movimento: String?
    }
    struct ValutazioneJ: Codable {
        var id: String, data: Date, valore: Double, strumento: String?
    }
    struct PianoJ: Codable {
        var id, nome, piattaforma: String, importoMensile: Double, giorno: Int, attivo: Bool
        var ultimaGenerazione: Date?, conto: String?
    }
    struct AllocazioneJ: Codable {
        var id: String, percentuale: Double, validaDal: Date, piano: String?, strumento: String?
    }
    struct SnapshotJ: Codable {
        var id: String, mese: Date, liquidita, investimenti: Double, aggiornatoIl: Date
    }
    struct ConnessioneJ: Codable {
        var id, banca, paese, sessionId: String, scadenza: Date, ultimaSync: Date?, accountUids: [String]
    }
    struct ProfiloJ: Codable {
        var id, nome, firmaIntestazione, separatore: String, righeDaSaltare, colData, colDescrizione: Int
        var colImporto: Int?, colAddebito: Int?, colAccredito: Int?
        var formatoData: String, virgolaDecimale, invertiSegno: Bool, conto: String?
    }

    // MARK: Scrittura

    /// Scrive bilancio.json, foto/, movimenti.csv e LEGGIMI.txt dentro `cartella` (che deve esistere).
    static func scrivi(_ ctx: ModelContext, in cartella: URL) throws {
        func tutti<T: PersistentModel>(_: T.Type) -> [T] { (try? ctx.fetch(FetchDescriptor<T>())) ?? [] }
        let conti = tutti(Conto.self), categorie = tutti(Categoria.self), movimenti = tutti(Movimento.self)
        let ricorrenze = tutti(Ricorrenza.self), scontrini = tutti(Scontrino.self), righe = tutti(RigaScontrino.self)
        let prodotti = tutti(Prodotto.self), regole = tutti(RegolaAppresa.self), strumenti = tutti(Strumento.self)
        let operazioni = tutti(Operazione.self), valutazioni = tutti(Valutazione.self), piani = tutti(PianoPAC.self)
        let allocazioni = tutti(AllocazionePAC.self), snapshot = tutti(SnapshotPatrimonio.self)
        let connessioni = tutti(ConnessioneBanca.self), profili = tutti(ProfiloImport.self)

        // id leggibili e stabili dentro il file: "conto-1", "movimento-42"…
        var ids: [ObjectIdentifier: String] = [:]
        func numera(_ lista: [AnyObject], _ prefisso: String) {
            for (i, o) in lista.enumerated() { ids[ObjectIdentifier(o)] = "\(prefisso)-\(i + 1)" }
        }
        numera(conti, "conto"); numera(categorie, "categoria"); numera(movimenti, "movimento"); numera(ricorrenze, "ricorrenza")
        numera(scontrini, "scontrino"); numera(righe, "riga"); numera(prodotti, "prodotto"); numera(regole, "regola")
        numera(strumenti, "strumento"); numera(operazioni, "operazione"); numera(valutazioni, "valutazione"); numera(piani, "piano")
        numera(allocazioni, "allocazione"); numera(snapshot, "snapshot"); numera(connessioni, "connessione"); numera(profili, "profilo")
        func id(_ o: AnyObject) -> String { ids[ObjectIdentifier(o)]! }
        func rif(_ o: AnyObject?) -> String? { o.flatMap { ids[ObjectIdentifier($0)] } }

        let fm = FileManager.default
        let dirFoto = cartella.appending(path: cartellaFoto, directoryHint: .isDirectory)
        var a = Archivio()
        a.conti = conti.map { ContoJ(id: id($0), nome: $0.nome, tipo: $0.tipoRaw, istituto: $0.istituto, valuta: $0.valuta,
                                     saldoIniziale: $0.saldoIniziale, saldoBanca: $0.saldoBanca, saldoBancaData: $0.saldoBancaData,
                                     tassoAnnuo: $0.tassoAnnuo, ebAccountUid: $0.ebAccountUid, iban: $0.iban,
                                     coloreHex: $0.coloreHex, ordine: $0.ordine, archiviato: $0.archiviato) }
        a.categorie = categorie.map { CategoriaJ(id: id($0), nome: $0.nome, icona: $0.icona, coloreHex: $0.coloreHex, tipo: $0.tipoRaw,
                                                 budgetMensile: $0.budgetMensile, detraibile: $0.detraibile, ordine: $0.ordine) }
        a.movimenti = movimenti.map { MovimentoJ(id: id($0), data: $0.data, importo: $0.importo, importoOriginale: $0.importoOriginale,
                                                 valutaOriginale: $0.valutaOriginale, cambioStorico: $0.cambioStorico, tipo: $0.tipoRaw, titolo: $0.titolo, nota: $0.nota,
                                                 descrizioneOriginale: $0.descrizioneOriginale, stato: $0.statoRaw, origine: $0.origineRaw,
                                                 idEsterno: $0.idEsterno, creatoIl: $0.creatoIl,
                                                 conto: rif($0.conto), categoria: rif($0.categoria), ricorrenza: rif($0.ricorrenza)) }
        a.ricorrenze = ricorrenze.map { RicorrenzaJ(id: id($0), nome: $0.nome, importo: $0.importo, tipo: $0.tipoRaw, giorno: $0.giorno,
                                                    ogniMesi: $0.ogniMesi, attiva: $0.attiva, ultimaGenerazione: $0.ultimaGenerazione,
                                                    conto: rif($0.conto), categoria: rif($0.categoria)) }
        if scontrini.contains(where: { $0.immagine != nil }) { try fm.createDirectory(at: dirFoto, withIntermediateDirectories: true) }
        a.scontrini = try scontrini.map { s in
            var foto: String?
            if let dati = s.immagine {
                foto = "\(id(s)).\(estensione(dati))"
                try dati.write(to: dirFoto.appending(path: foto!))
            }
            return ScontrinoJ(id: id(s), negozio: s.negozio, indirizzo: s.indirizzo, partitaIva: s.partitaIva, data: s.data, totale: s.totale,
                              foto: foto, testoOCR: s.testoOCR, creatoIl: s.creatoIl, movimento: rif(s.movimento))
        }
        a.righeScontrino = righe.map { RigaJ(id: id($0), testo: $0.testo, quantita: $0.quantita, prezzoUnitario: $0.prezzoUnitario,
                                             totale: $0.totale, ordine: $0.ordine, scontrino: rif($0.scontrino),
                                             categoria: rif($0.categoria), prodotto: rif($0.prodotto)) }
        a.prodotti = prodotti.map { ProdottoJ(id: id($0), nome: $0.nome, unita: $0.unita, formato: $0.formato, categoria: rif($0.categoria)) }
        a.regoleApprese = regole.map { RegolaJ(id: id($0), chiave: $0.chiave, ambito: $0.ambitoRaw, categoria: rif($0.categoria), tipo: $0.tipoRaw,
                                               nomeProdotto: $0.nomeProdotto, titolo: $0.titolo, utilizzi: $0.utilizzi, aggiornataIl: $0.aggiornataIl) }
        a.strumenti = strumenti.map { StrumentoJ(id: id($0), nome: $0.nome, isin: $0.isin, ticker: $0.ticker, tipo: $0.tipoRaw,
                                                 piattaforma: $0.piattaforma, valuta: $0.valuta, ultimoPrezzo: $0.ultimoPrezzo,
                                                 ultimoPrezzoData: $0.ultimoPrezzoData, valoreManuale: $0.valoreManuale, cedola: $0.cedola,
                                                 scadenza: $0.scadenza, fondoPensioneItaliano: $0.fondoPensioneItaliano,
                                                 archiviato: $0.archiviato, creatoIl: $0.creatoIl) }
        a.operazioni = operazioni.map { OperazioneJ(id: id($0), data: $0.data, tipo: $0.tipoRaw, quote: $0.quote, prezzo: $0.prezzo,
                                                    importo: $0.importo, commissioni: $0.commissioni, cambioEUR: $0.cambioEUR, nota: $0.nota,
                                                    strumento: rif($0.strumento), movimento: rif($0.movimento)) }
        a.valutazioni = valutazioni.map { ValutazioneJ(id: id($0), data: $0.data, valore: $0.valore, strumento: rif($0.strumento)) }
        a.pianiPAC = piani.map { PianoJ(id: id($0), nome: $0.nome, piattaforma: $0.piattaforma, importoMensile: $0.importoMensile,
                                        giorno: $0.giorno, attivo: $0.attivo, ultimaGenerazione: $0.ultimaGenerazione, conto: rif($0.conto)) }
        a.allocazioniPAC = allocazioni.map { AllocazioneJ(id: id($0), percentuale: $0.percentuale, validaDal: $0.validaDal,
                                                          piano: rif($0.piano), strumento: rif($0.strumento)) }
        a.snapshotPatrimonio = snapshot.map { SnapshotJ(id: id($0), mese: $0.mese, liquidita: $0.liquidita,
                                                        investimenti: $0.investimenti, aggiornatoIl: $0.aggiornatoIl) }
        a.connessioniBanca = connessioni.map { ConnessioneJ(id: id($0), banca: $0.banca, paese: $0.paese, sessionId: $0.sessionId,
                                                            scadenza: $0.scadenza, ultimaSync: $0.ultimaSync, accountUids: $0.accountUids) }
        a.profiliImport = profili.map { ProfiloJ(id: id($0), nome: $0.nome, firmaIntestazione: $0.firmaIntestazione, separatore: $0.separatore,
                                                 righeDaSaltare: $0.righeDaSaltare, colData: $0.colData, colDescrizione: $0.colDescrizione,
                                                 colImporto: $0.colImporto, colAddebito: $0.colAddebito, colAccredito: $0.colAccredito,
                                                 formatoData: $0.formatoData, virgolaDecimale: $0.virgolaDecimale,
                                                 invertiSegno: $0.invertiSegno, conto: rif($0.conto)) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(a).write(to: cartella.appending(path: fileDati), options: .atomic)
        try Data(Backup.csvMovimenti(in: ctx).utf8).write(to: cartella.appending(path: "movimenti.csv"))
        try Data(leggimi.utf8).write(to: cartella.appending(path: "LEGGIMI.txt"))
    }

    static func estensione(_ d: Data) -> String {
        let b = [UInt8](d.prefix(12))
        if b.starts(with: [0xFF, 0xD8]) { return "jpg" }
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if b.count == 12, String(bytes: b[4..<12], encoding: .ascii)?.hasPrefix("ftyphei") == true { return "heic" }
        return "bin"
    }

    // MARK: Lettura

    enum Errore: LocalizedError {
        case formato
        var errorDescription: String? { String(localized: "Il file bilancio.json non è un backup di Bilancio leggibile da questa versione dell'app.") }
    }

    /// Ricostruisce tutti i dati di `cartella` dentro `ctx` (che dovrebbe essere vuoto) e salva.
    /// Restituisce quante foto elencate nel JSON non c'erano nella cartella (lo scontrino resta senza immagine).
    @discardableResult
    static func leggi(da cartella: URL, in ctx: ModelContext) throws -> Int {
        var fotoMancanti = 0
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let a = try decoder.decode(Archivio.self, from: Data(contentsOf: cartella.appending(path: fileDati)))
        guard a.formato == "bilancio-backup", a.versione == 1 else { throw Errore.formato }

        var conti: [String: Conto] = [:], categorie: [String: Categoria] = [:], movimenti: [String: Movimento] = [:]
        var ricorrenze: [String: Ricorrenza] = [:], scontrini: [String: Scontrino] = [:], prodotti: [String: Prodotto] = [:]
        var strumenti: [String: Strumento] = [:], piani: [String: PianoPAC] = [:]

        for j in a.categorie {
            let c = Categoria(nome: j.nome, icona: j.icona, coloreHex: j.coloreHex, detraibile: j.detraibile, ordine: j.ordine)
            c.tipoRaw = j.tipo; c.budgetMensile = j.budgetMensile
            ctx.insert(c); categorie[j.id] = c
        }
        for j in a.conti {
            let c = Conto(nome: j.nome, tipo: .corrente, istituto: j.istituto, saldoIniziale: j.saldoIniziale, coloreHex: j.coloreHex, ordine: j.ordine)
            c.tipoRaw = j.tipo; c.valuta = j.valuta; c.saldoBanca = j.saldoBanca; c.saldoBancaData = j.saldoBancaData
            c.tassoAnnuo = j.tassoAnnuo; c.ebAccountUid = j.ebAccountUid; c.iban = j.iban; c.archiviato = j.archiviato
            ctx.insert(c); conti[j.id] = c
        }
        for j in a.prodotti {
            let p = Prodotto(nome: j.nome, unita: j.unita, formato: j.formato)
            ctx.insert(p); p.categoria = j.categoria.flatMap { categorie[$0] }; prodotti[j.id] = p
        }
        for j in a.regoleApprese {
            let r = RegolaAppresa(chiave: j.chiave, ambito: .rigaScontrino)
            r.ambitoRaw = j.ambito; r.tipoRaw = j.tipo; r.nomeProdotto = j.nomeProdotto; r.titolo = j.titolo
            r.utilizzi = j.utilizzi; r.aggiornataIl = j.aggiornataIl
            ctx.insert(r); r.categoria = j.categoria.flatMap { categorie[$0] }
        }
        for j in a.ricorrenze {
            let r = Ricorrenza(nome: j.nome, importo: j.importo, tipo: .spesa, giorno: j.giorno, ogniMesi: j.ogniMesi)
            r.tipoRaw = j.tipo; r.attiva = j.attiva; r.ultimaGenerazione = j.ultimaGenerazione
            ctx.insert(r); r.conto = j.conto.flatMap { conti[$0] }; r.categoria = j.categoria.flatMap { categorie[$0] }
            ricorrenze[j.id] = r
        }
        for j in a.movimenti {
            let m = Movimento(data: j.data, importo: j.importo, tipo: .spesa, titolo: j.titolo, origine: .manuale)
            m.importoOriginale = j.importoOriginale; m.valutaOriginale = j.valutaOriginale; m.cambioStorico = j.cambioStorico ?? false
            m.tipoRaw = j.tipo; m.nota = j.nota; m.descrizioneOriginale = j.descrizioneOriginale
            m.statoRaw = j.stato; m.origineRaw = j.origine; m.idEsterno = j.idEsterno; m.creatoIl = j.creatoIl
            ctx.insert(m)
            m.conto = j.conto.flatMap { conti[$0] }; m.categoria = j.categoria.flatMap { categorie[$0] }
            m.ricorrenza = j.ricorrenza.flatMap { ricorrenze[$0] }
            movimenti[j.id] = m
        }
        for j in a.scontrini {
            let s = Scontrino(negozio: j.negozio, data: j.data, totale: j.totale)
            s.indirizzo = j.indirizzo; s.partitaIva = j.partitaIva; s.testoOCR = j.testoOCR; s.creatoIl = j.creatoIl
            if let f = j.foto {
                // solo il nome del file: un percorso scritto nel JSON non deve far leggere altro
                let file = cartella.appending(path: cartellaFoto).appending(path: (f as NSString).lastPathComponent)
                if let dati = try? Data(contentsOf: file) { s.immagine = dati } else { fotoMancanti += 1 }
            }
            ctx.insert(s); s.movimento = j.movimento.flatMap { movimenti[$0] }
            scontrini[j.id] = s
        }
        for j in a.righeScontrino {
            let r = RigaScontrino(testo: j.testo, quantita: j.quantita, prezzoUnitario: j.prezzoUnitario, totale: j.totale, ordine: j.ordine)
            ctx.insert(r)
            r.scontrino = j.scontrino.flatMap { scontrini[$0] }; r.categoria = j.categoria.flatMap { categorie[$0] }
            r.prodotto = j.prodotto.flatMap { prodotti[$0] }
        }
        for j in a.strumenti {
            let s = Strumento(nome: j.nome, isin: j.isin, tipo: .etf, piattaforma: j.piattaforma, valuta: j.valuta)
            s.tipoRaw = j.tipo; s.ticker = j.ticker; s.ultimoPrezzo = j.ultimoPrezzo; s.ultimoPrezzoData = j.ultimoPrezzoData
            s.valoreManuale = j.valoreManuale; s.cedola = j.cedola; s.scadenza = j.scadenza
            s.fondoPensioneItaliano = j.fondoPensioneItaliano; s.archiviato = j.archiviato; s.creatoIl = j.creatoIl
            ctx.insert(s); strumenti[j.id] = s
        }
        for j in a.operazioni {
            let o = Operazione(data: j.data, tipo: .acquisto, quote: j.quote, prezzo: j.prezzo, importo: j.importo,
                               commissioni: j.commissioni, cambioEUR: j.cambioEUR)
            o.tipoRaw = j.tipo; o.nota = j.nota
            ctx.insert(o); o.strumento = j.strumento.flatMap { strumenti[$0] }; o.movimento = j.movimento.flatMap { movimenti[$0] }
        }
        for j in a.valutazioni {
            let v = Valutazione(data: j.data, valore: j.valore)
            ctx.insert(v); v.strumento = j.strumento.flatMap { strumenti[$0] }
        }
        for j in a.pianiPAC {
            let p = PianoPAC(nome: j.nome, piattaforma: j.piattaforma, importoMensile: j.importoMensile, giorno: j.giorno)
            p.attivo = j.attivo; p.ultimaGenerazione = j.ultimaGenerazione
            ctx.insert(p); p.conto = j.conto.flatMap { conti[$0] }; piani[j.id] = p
        }
        for j in a.allocazioniPAC {
            let al = AllocazionePAC(percentuale: j.percentuale, validaDal: j.validaDal)
            ctx.insert(al); al.piano = j.piano.flatMap { piani[$0] }; al.strumento = j.strumento.flatMap { strumenti[$0] }
        }
        for j in a.snapshotPatrimonio {
            let s = SnapshotPatrimonio(mese: j.mese, liquidita: j.liquidita, investimenti: j.investimenti)
            s.aggiornatoIl = j.aggiornatoIl
            ctx.insert(s)
        }
        for j in a.connessioniBanca {
            let c = ConnessioneBanca(banca: j.banca, sessionId: j.sessionId, scadenza: j.scadenza)
            c.paese = j.paese; c.ultimaSync = j.ultimaSync; c.accountUids = j.accountUids
            ctx.insert(c)
        }
        for j in a.profiliImport {
            let p = ProfiloImport(nome: j.nome)
            p.firmaIntestazione = j.firmaIntestazione; p.separatore = j.separatore; p.righeDaSaltare = j.righeDaSaltare
            p.colData = j.colData; p.colDescrizione = j.colDescrizione; p.colImporto = j.colImporto
            p.colAddebito = j.colAddebito; p.colAccredito = j.colAccredito; p.formatoData = j.formatoData
            p.virgolaDecimale = j.virgolaDecimale; p.invertiSegno = j.invertiSegno
            ctx.insert(p); p.conto = j.conto.flatMap { conti[$0] }
        }
        try ctx.save()
        return fotoMancanti
    }

    // MARK: Descrizione del formato

    static let leggimi = """
    BILANCIO – BACKUP IN FORMATO APERTO (versione 1)   ·   English below

    Questa cartella contiene tutti i dati dell'app Bilancio in un formato leggibile da qualsiasi sistema.

    bilancio.json   Tutti i dati, JSON UTF-8. Ogni elenco (conti, categorie, movimenti, ricorrenze, scontrini,
                    righeScontrino, prodotti, regoleApprese, strumenti, operazioni, valutazioni, pianiPAC,
                    allocazioniPAC, snapshotPatrimonio, connessioniBanca, profiliImport) contiene oggetti con un "id";
                    i collegamenti tra oggetti usano quell'id (es. un movimento ha "conto": "conto-3").
    foto/           Le foto degli scontrini; il campo "foto" dello scontrino è il nome del file.
    movimenti.csv   Tutti i movimenti, per Excel o Fogli Google (separatore ;).

    Convenzioni:
    - Date in ISO 8601 (es. 2026-11-15T17:30:00Z).
    - "importo" dei movimenti è in euro, con segno: negativo = uscita, positivo = entrata.
      Per i conti in valuta estera "importoOriginale" e "valutaOriginale" danno l'importo nella valuta del conto.
      "cambioStorico": true se l'importo in euro usa il cambio BCE del giorno del movimento.
    - "tipo" di un movimento: spesa, entrata, giroconto (spostamento tra conti propri, non conta nei totali), investimento.
    - "stato": daConfermare o confermato.
    - Non sono incluse la chiave privata e l'Application ID di Enable Banking: si reimportano dall'app.

    ----

    BILANCIO – OPEN FORMAT BACKUP (version 1)

    bilancio.json   All data, UTF-8 JSON. Every list holds objects with an "id"; links between objects use that id
                    (e.g. a movement has "conto": "conto-3", i.e. its account). Field names are Italian:
                    conto = account, movimento = transaction, categoria = category, scontrino = receipt,
                    riga = receipt line, strumento = investment, operazione = trade, ricorrenza = recurring payment.
    foto/           Receipt photos; a receipt's "foto" field is the file name.
    movimenti.csv   All transactions for spreadsheets (separator ;).

    Dates are ISO 8601. Transaction "importo" is in euros, signed: negative = money out, positive = money in;
    for foreign-currency accounts "importoOriginale"/"valutaOriginale" give the amount in the account currency.
    Transaction "tipo": spesa (expense), entrata (income), giroconto (transfer between own accounts), investimento.
    The Enable Banking private key and Application ID are not included.
    """

    // MARK: Verifica

    #if DEBUG
    /// Avvio con `-verifica`: dati demo → backup aperto → nuovo database: stessi conteggi e stessi totali.
    @MainActor static func autoverifica() {
        func contenitore() -> ModelContainer {
            try! ModelContainer(for: Persistenza.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        let ca = contenitore(), cb = contenitore()
        let a = ModelContext(ca), b = ModelContext(cb)
        DatiDemo.carica(in: a)
        let scontrinoConFoto = try! a.fetch(FetchDescriptor<Scontrino>()).first!
        scontrinoConFoto.immagine = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        try! a.save()

        let cartella = FileManager.default.temporaryDirectory.appending(path: "verifica-backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try! FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cartella) }
        try! scrivi(a, in: cartella)
        try! leggi(da: cartella, in: b)

        func n<T: PersistentModel>(_: T.Type, _ c: ModelContext) -> Int { (try? c.fetchCount(FetchDescriptor<T>())) ?? -1 }
        func uguali<T: PersistentModel>(_ t: T.Type) { assert(n(t, a) == n(t, b) && n(t, a) >= 0, "conteggio diverso: \(t)") }
        uguali(Conto.self); uguali(Categoria.self); uguali(Movimento.self); uguali(Ricorrenza.self); uguali(Scontrino.self)
        uguali(RigaScontrino.self); uguali(Prodotto.self); uguali(RegolaAppresa.self); uguali(Strumento.self); uguali(Operazione.self)
        uguali(Valutazione.self); uguali(PianoPAC.self); uguali(AllocazionePAC.self); uguali(SnapshotPatrimonio.self)
        uguali(ConnessioneBanca.self); uguali(ProfiloImport.self)

        let ma = try! a.fetch(FetchDescriptor<Movimento>()), mb = try! b.fetch(FetchDescriptor<Movimento>())
        let ta = Contabilita.totali(ma), tb = Contabilita.totali(mb)
        assert(abs(ta.entrate - tb.entrate) < 0.001 && abs(ta.spese - tb.spese) < 0.001 && abs(ta.investito - tb.investito) < 0.001)
        assert(ma.filter { $0.conto != nil }.count == mb.filter { $0.conto != nil }.count)
        assert(ma.filter { $0.categoria != nil }.count == mb.filter { $0.categoria != nil }.count)
        assert(ma.filter { $0.scontrino != nil }.count == mb.filter { $0.scontrino != nil }.count)
        let oa = try! a.fetch(FetchDescriptor<Operazione>()), ob = try! b.fetch(FetchDescriptor<Operazione>())
        assert(oa.filter { $0.strumento != nil && $0.movimento != nil }.count == ob.filter { $0.strumento != nil && $0.movimento != nil }.count)
        let sa = try! a.fetch(FetchDescriptor<Scontrino>()), sb = try! b.fetch(FetchDescriptor<Scontrino>())
        assert(sa.reduce(0) { $0 + $1.righe.count } == sb.reduce(0) { $0 + $1.righe.count })
        assert(sb.filter { $0.immagine == Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]) }.count == 1)
        for c in try! a.fetch(FetchDescriptor<Conto>()) {
            let gemello = try! b.fetch(FetchDescriptor<Conto>()).first { $0.nome == c.nome }!
            assert(abs(Contabilita.saldo(c) - Contabilita.saldo(gemello)) < 0.001, "saldo diverso: \(c.nome)")
        }
        print("BackupAperto.autoverifica OK")
    }
    #endif
}
