import Foundation
import SwiftData

// Modello dati SwiftData. Tutto resta sul telefono.
// Convenzione importi: Double con segno sui movimenti (< 0 uscita, > 0 entrata).
// ponytail: Double invece di Decimal per semplicità con Swift Charts; si arrotonda solo in visualizzazione.

// MARK: - Conti e movimenti

@Model final class Conto {
    var nome: String = ""
    var tipoRaw: String = TipoConto.corrente.rawValue
    var istituto: String = ""
    var valuta: String = "EUR"
    /// Saldo di partenza inserito a mano (per i conti non collegati e i contanti).
    var saldoIniziale: Double = 0
    /// Ultimo saldo letto dalla banca collegata: se presente, vince sul calcolo.
    var saldoBanca: Double?
    var saldoBancaData: Date?
    /// Tasso annuo in % (conti remunerati / deposito).
    var tassoAnnuo: Double?
    /// Identificativo del conto su Enable Banking.
    var ebAccountUid: String?
    var iban: String?
    var coloreHex: String = "#2563EB"
    var ordine: Int = 0
    var archiviato: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Movimento.conto) var movimenti: [Movimento] = []
    @Relationship(deleteRule: .nullify, inverse: \Ricorrenza.conto) var ricorrenze: [Ricorrenza] = []
    @Relationship(deleteRule: .nullify, inverse: \ProfiloImport.conto) var profiliImport: [ProfiloImport] = []

    init(nome: String, tipo: TipoConto, istituto: String = "", saldoIniziale: Double = 0, coloreHex: String = "#2563EB", ordine: Int = 0) {
        self.nome = nome
        self.tipoRaw = tipo.rawValue
        self.istituto = istituto
        self.saldoIniziale = saldoIniziale
        self.coloreHex = coloreHex
        self.ordine = ordine
    }

    var tipo: TipoConto {
        get { TipoConto(rawValue: tipoRaw) ?? .corrente }
        set { tipoRaw = newValue.rawValue }
    }
}

@Model final class Movimento {
    var data: Date = Date()
    /// Con segno: < 0 uscita, > 0 entrata.
    var importo: Double = 0
    var tipoRaw: String = TipoMovimento.spesa.rawValue
    /// Negozio o controparte, già "ripulito".
    var titolo: String = ""
    var nota: String = ""
    /// Testo grezzo della banca/estratto (serve per imparare le regole).
    var descrizioneOriginale: String = ""
    var statoRaw: String = StatoMovimento.daConfermare.rawValue
    var origineRaw: String = Origine.manuale.rawValue
    /// Id della transazione bancaria, per non importarla due volte.
    var idEsterno: String?
    var creatoIl: Date = Date()

    var conto: Conto?
    var categoria: Categoria?
    var ricorrenza: Ricorrenza?
    @Relationship(deleteRule: .nullify, inverse: \Scontrino.movimento) var scontrino: Scontrino?
    /// Operazioni di investimento generate da questo movimento (es. PAC ripartito sugli ETF): si cancellano con lui.
    @Relationship(deleteRule: .cascade, inverse: \Operazione.movimento) var operazioni: [Operazione] = []

    init(data: Date, importo: Double, tipo: TipoMovimento, titolo: String, origine: Origine, stato: StatoMovimento = .daConfermare, conto: Conto? = nil, categoria: Categoria? = nil) {
        self.data = data
        self.importo = importo
        self.tipoRaw = tipo.rawValue
        self.titolo = titolo
        self.origineRaw = origine.rawValue
        self.statoRaw = stato.rawValue
        self.conto = conto
        self.categoria = categoria
    }

    var tipo: TipoMovimento {
        get { TipoMovimento(rawValue: tipoRaw) ?? .spesa }
        set { tipoRaw = newValue.rawValue }
    }
    var stato: StatoMovimento {
        get { StatoMovimento(rawValue: statoRaw) ?? .daConfermare }
        set { statoRaw = newValue.rawValue }
    }
    var origine: Origine {
        get { Origine(rawValue: origineRaw) ?? .manuale }
        set { origineRaw = newValue.rawValue }
    }
    var daConfermare: Bool { stato == .daConfermare }
}

@Model final class Categoria {
    var nome: String = ""
    /// Nome di un SF Symbol.
    var icona: String = "tag"
    var coloreHex: String = "#8E8E93"
    /// "spesa" o "entrata".
    var tipoRaw: String = TipoMovimento.spesa.rawValue
    var budgetMensile: Double?
    /// Spese detraibili nel 730 (salute, istruzione…).
    var detraibile: Bool = false
    var ordine: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Movimento.categoria) var movimenti: [Movimento] = []
    @Relationship(deleteRule: .nullify, inverse: \RigaScontrino.categoria) var righe: [RigaScontrino] = []
    @Relationship(deleteRule: .nullify, inverse: \Prodotto.categoria) var prodotti: [Prodotto] = []
    @Relationship(deleteRule: .nullify, inverse: \Ricorrenza.categoria) var ricorrenze: [Ricorrenza] = []
    @Relationship(deleteRule: .nullify, inverse: \RegolaAppresa.categoria) var regole: [RegolaAppresa] = []

    init(nome: String, icona: String, coloreHex: String, tipo: TipoMovimento = .spesa, detraibile: Bool = false, ordine: Int = 0) {
        self.nome = nome
        self.icona = icona
        self.coloreHex = coloreHex
        self.tipoRaw = tipo.rawValue
        self.detraibile = detraibile
        self.ordine = ordine
    }

    var tipo: TipoMovimento {
        get { TipoMovimento(rawValue: tipoRaw) ?? .spesa }
        set { tipoRaw = newValue.rawValue }
    }
}

// MARK: - Scontrini e prodotti

@Model final class Scontrino {
    /// Nome del negozio/azienda: è la "macro" con cui l'archivio raggruppa.
    var negozio: String = ""
    var indirizzo: String = ""
    var partitaIva: String = ""
    var data: Date = Date()
    var totale: Double = 0
    @Attribute(.externalStorage) var immagine: Data?
    var testoOCR: String = ""
    var creatoIl: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \RigaScontrino.scontrino) var righe: [RigaScontrino] = []
    var movimento: Movimento?

    init(negozio: String, data: Date, totale: Double) {
        self.negozio = negozio
        self.data = data
        self.totale = totale
    }

    var righeOrdinate: [RigaScontrino] { righe.sorted { $0.ordine < $1.ordine } }
}

@Model final class RigaScontrino {
    /// Testo così come stampato sullo scontrino.
    var testo: String = ""
    var quantita: Double = 1
    var prezzoUnitario: Double = 0
    /// Totale riga, già scontato.
    var totale: Double = 0
    var ordine: Int = 0

    var scontrino: Scontrino?
    var categoria: Categoria?
    var prodotto: Prodotto?

    init(testo: String, quantita: Double, prezzoUnitario: Double, totale: Double, ordine: Int) {
        self.testo = testo
        self.quantita = quantita
        self.prezzoUnitario = prezzoUnitario
        self.totale = totale
        self.ordine = ordine
    }
}

/// Prodotto "normalizzato": unisce righe scritte in modo diverso (anche in negozi diversi)
/// per seguirne il prezzo nel tempo (pagina Inflazione).
@Model final class Prodotto {
    /// Es. "Latte intero Granarolo 1 l".
    var nome: String = ""
    /// "pz", "kg" o "l".
    var unita: String = "pz"
    /// Quantità per confezione nell'unità (es. 0.5 per 500 g in kg). nil = sconosciuta.
    var formato: Double?
    var categoria: Categoria?

    @Relationship(deleteRule: .nullify, inverse: \RigaScontrino.prodotto) var righe: [RigaScontrino] = []

    init(nome: String, unita: String = "pz", formato: Double? = nil) {
        self.nome = nome
        self.unita = unita
        self.formato = formato
    }
}

/// Memoria delle correzioni dell'utente: testo normalizzato → categoria/tipo/prodotto.
@Model final class RegolaAppresa {
    var chiave: String = ""
    var ambitoRaw: String = AmbitoRegola.rigaScontrino.rawValue
    var categoria: Categoria?
    /// Solo per descrizioni bancarie: tipo di movimento (spesa, giroconto…).
    var tipoRaw: String?
    var nomeProdotto: String?
    /// Nome pulito del negozio/controparte.
    var titolo: String?
    var utilizzi: Int = 0
    var aggiornataIl: Date = Date()

    init(chiave: String, ambito: AmbitoRegola) {
        self.chiave = chiave
        self.ambitoRaw = ambito.rawValue
    }
}

// MARK: - Ricorrenti

@Model final class Ricorrenza {
    var nome: String = ""
    /// Con segno, come i movimenti.
    var importo: Double = 0
    var tipoRaw: String = TipoMovimento.spesa.rawValue
    /// Giorno del mese in cui viene proposto.
    var giorno: Int = 1
    /// 1 = mensile, 3 = trimestrale, 12 = annuale.
    var ogniMesi: Int = 1
    var attiva: Bool = true
    /// Primo giorno dell'ultimo mese per cui è stato proposto il movimento.
    var ultimaGenerazione: Date?
    var conto: Conto?
    var categoria: Categoria?

    @Relationship(deleteRule: .nullify, inverse: \Movimento.ricorrenza) var movimenti: [Movimento] = []

    init(nome: String, importo: Double, tipo: TipoMovimento, giorno: Int, ogniMesi: Int = 1) {
        self.nome = nome
        self.importo = importo
        self.tipoRaw = tipo.rawValue
        self.giorno = giorno
        self.ogniMesi = ogniMesi
    }

    var tipo: TipoMovimento {
        get { TipoMovimento(rawValue: tipoRaw) ?? .spesa }
        set { tipoRaw = newValue.rawValue }
    }
    /// Costo (o entrata) su base annua, sempre positivo.
    var importoAnnuo: Double { abs(importo) * 12 / Double(max(ogniMesi, 1)) }
}

// MARK: - Investimenti

@Model final class Strumento {
    var nome: String = ""
    var isin: String = ""
    /// Simbolo Yahoo Finance (es. "EUNL.DE"), trovato dall'ISIN.
    var ticker: String?
    var tipoRaw: String = TipoStrumento.etf.rawValue
    /// broker, fondo pensione, robo-advisor…
    var piattaforma: String = ""
    var valuta: String = "EUR"
    /// Ultimo prezzo nella valuta dello strumento. Per le obbligazioni è in % del nominale.
    var ultimoPrezzo: Double?
    var ultimoPrezzoData: Date?
    /// Fondi pensione e gestioni: il valore lo aggiorna l'utente (Valutazione).
    var valoreManuale: Bool = false
    /// Obbligazioni: cedola annua in % e scadenza.
    var cedola: Double?
    var scadenza: Date?
    /// Fondo pensione italiano: versamenti deducibili fino a 5.164,57 €/anno.
    var fondoPensioneItaliano: Bool = false
    var archiviato: Bool = false
    var creatoIl: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Operazione.strumento) var operazioni: [Operazione] = []
    @Relationship(deleteRule: .cascade, inverse: \Valutazione.strumento) var valutazioni: [Valutazione] = []
    @Relationship(deleteRule: .cascade, inverse: \AllocazionePAC.strumento) var allocazioni: [AllocazionePAC] = []

    init(nome: String, isin: String, tipo: TipoStrumento, piattaforma: String, valuta: String = "EUR") {
        self.nome = nome
        self.isin = isin
        self.tipoRaw = tipo.rawValue
        self.piattaforma = piattaforma
        self.valuta = valuta
        self.valoreManuale = !tipo.quotato
    }

    var tipo: TipoStrumento {
        get { TipoStrumento(rawValue: tipoRaw) ?? .etf }
        set { tipoRaw = newValue.rawValue }
    }
}

@Model final class Operazione {
    var data: Date = Date()
    var tipoRaw: String = TipoOperazione.acquisto.rawValue
    /// Quote acquistate/vendute (frazioni ammesse). Per le obbligazioni: valore nominale.
    var quote: Double = 0
    /// Prezzo unitario nella valuta dello strumento (obbligazioni: % del nominale).
    var prezzo: Double = 0
    /// Importo dell'operazione nella valuta dello strumento, sempre positivo.
    var importo: Double = 0
    var commissioni: Double = 0
    /// 1 unità di valuta dello strumento = cambioEUR euro, al momento dell'operazione.
    var cambioEUR: Double = 1
    var nota: String = ""

    var strumento: Strumento?
    var movimento: Movimento?

    init(data: Date, tipo: TipoOperazione, quote: Double, prezzo: Double, importo: Double, commissioni: Double = 0, cambioEUR: Double = 1) {
        self.data = data
        self.tipoRaw = tipo.rawValue
        self.quote = quote
        self.prezzo = prezzo
        self.importo = importo
        self.commissioni = commissioni
        self.cambioEUR = cambioEUR
    }

    var tipo: TipoOperazione {
        get { TipoOperazione(rawValue: tipoRaw) ?? .acquisto }
        set { tipoRaw = newValue.rawValue }
    }
}

/// Valore di una posizione aggiornato a mano (fondi pensione, gestioni) o riallineamento quote.
@Model final class Valutazione {
    var data: Date = Date()
    /// Valore totale della posizione nella valuta dello strumento.
    var valore: Double = 0
    var strumento: Strumento?

    init(data: Date, valore: Double) {
        self.data = data
        self.valore = valore
    }
}

/// Piano di accumulo: importo mensile ripartito in % sugli strumenti.
@Model final class PianoPAC {
    var nome: String = ""
    var piattaforma: String = ""
    var importoMensile: Double = 0
    /// Giorno di esecuzione nel mese.
    var giorno: Int = 1
    var attivo: Bool = true
    /// Primo giorno dell'ultimo mese generato.
    var ultimaGenerazione: Date?
    var conto: Conto?

    @Relationship(deleteRule: .cascade, inverse: \AllocazionePAC.piano) var allocazioni: [AllocazionePAC] = []

    init(nome: String, piattaforma: String, importoMensile: Double, giorno: Int) {
        self.nome = nome
        self.piattaforma = piattaforma
        self.importoMensile = importoMensile
        self.giorno = giorno
    }
}

/// Percentuale di un PAC su uno strumento, valida da una certa data (così lo storico resta corretto).
@Model final class AllocazionePAC {
    var percentuale: Double = 0
    var validaDal: Date = Date()
    var piano: PianoPAC?
    var strumento: Strumento?

    init(percentuale: Double, validaDal: Date) {
        self.percentuale = percentuale
        self.validaDal = validaDal
    }
}

// MARK: - Varie

/// Fotografia mensile del patrimonio (liquidità + investimenti) per il grafico annuale.
@Model final class SnapshotPatrimonio {
    /// Primo giorno del mese.
    var mese: Date = Date()
    var liquidita: Double = 0
    var investimenti: Double = 0
    var aggiornatoIl: Date = Date()

    init(mese: Date, liquidita: Double, investimenti: Double) {
        self.mese = mese
        self.liquidita = liquidita
        self.investimenti = investimenti
    }
}

/// Consenso PSD2 su Enable Banking (dura fino a 180 giorni).
@Model final class ConnessioneBanca {
    var banca: String = ""
    var paese: String = "IT"
    var sessionId: String = ""
    var scadenza: Date = Date()
    var ultimaSync: Date?
    var accountUids: [String] = []

    init(banca: String, sessionId: String, scadenza: Date) {
        self.banca = banca
        self.sessionId = sessionId
        self.scadenza = scadenza
    }
}

/// Come leggere il CSV di una certa banca (memorizzato dopo la prima importazione).
@Model final class ProfiloImport {
    var nome: String = ""
    /// Intestazione del CSV normalizzata, per riconoscere la banca.
    var firmaIntestazione: String = ""
    var separatore: String = ";"
    var righeDaSaltare: Int = 0
    var colData: Int = 0
    var colDescrizione: Int = 1
    /// Colonna unica con segno, oppure coppia addebito/accredito.
    var colImporto: Int?
    var colAddebito: Int?
    var colAccredito: Int?
    var formatoData: String = "dd/MM/yyyy"
    var virgolaDecimale: Bool = true
    /// Se true gli importi positivi sono uscite (alcune carte di credito).
    var invertiSegno: Bool = false
    var conto: Conto?

    init(nome: String) {
        self.nome = nome
    }
}
