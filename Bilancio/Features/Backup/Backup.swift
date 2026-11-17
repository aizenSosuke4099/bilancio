import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Backup = cartella in formato aperto (vedi `BackupAperto`: JSON + foto, leggibile anche su Android o al computer)
/// in Documents/Backup/Bilancio-AAAA-MM-GG-HHmm/. La cartella dell'app non compare nell'app File (vedi Bilancio-Info.plist):
/// i backup locali sono in chiaro e si aprono solo da qui, dietro Face ID; fuori dall'iPhone escono cifrati.
/// Il ripristino ricostruisce un database nuovo in Application Support/RipristinoInSospeso/, che viene
/// messo al posto di quello attuale al riavvio, prima di aprire SwiftData.
/// Si ripristinano anche i backup del vecchio formato (copia della cartella del database).
enum Backup {

    // Percorsi calcolati senza toccare `Persistenza` (niente effetti collaterali prima del container).
    private static var supporto: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
    private static var cartellaDatabase: URL { supporto.appending(path: "Bilancio", directoryHint: .isDirectory) }
    private static var inSospeso: URL { supporto.appending(path: "RipristinoInSospeso", directoryHint: .isDirectory) }
    static var cartellaBackup: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Backup", directoryHint: .isDirectory)
    }
    private static let nomeStore = "Bilancio.store"
    private static let prefissoInCorso = ".in-corso-"
    private static var inPreparazione: URL { supporto.appending(path: "RipristinoInPreparazione", directoryHint: .isDirectory) }

    /// "2026-11-14-1030": ordinabile come testo.
    static func timbro(_ data: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: data)
    }

    // MARK: Date in UserDefaults

    /// Ultimo backup locale (manuale o automatico).
    static var ultimoBackup: Date? { UserDefaults.standard.object(forKey: "backup.ultimo") as? Date }
    /// Ultimo backup salvato fuori dall'iPhone (File / iCloud Drive).
    static var ultimoEsportato: Date? { UserDefaults.standard.object(forKey: "backup.ultimoEsportato") as? Date }
    static func segnaEsportato() { UserDefaults.standard.set(Date(), forKey: "backup.ultimoEsportato") }
    /// Data del primo uso (base per il primo promemoria backup).
    static var primoUso: Date {
        if let d = UserDefaults.standard.object(forKey: "backup.primoUso") as? Date { return d }
        UserDefaults.standard.set(Date(), forKey: "backup.primoUso")
        return Date()
    }

    // MARK: Creazione

    /// Scrive un nuovo backup locale in formato aperto. Salvare il contesto prima.
    @discardableResult
    static func crea(in context: ModelContext) throws -> URL {
        let fm = FileManager.default
        try proteggiCartellaBackup()
        // Si scrive in una cartella provvisoria (che `elenco` non mostra) e la si rinomina alla fine: un backup
        // interrotto a metà (app chiusa mentre va in background) non compare mai tra quelli buoni.
        let figli = (try? fm.contentsOfDirectory(at: cartellaBackup, includingPropertiesForKeys: nil)) ?? []
        for avanzo in figli where avanzo.lastPathComponent.hasPrefix(prefissoInCorso) { try? fm.removeItem(at: avanzo) }
        let nome = "Bilancio-" + timbro(Date())
        let provvisoria = cartellaBackup.appending(path: prefissoInCorso + nome, directoryHint: .isDirectory)
        let destinazione = cartellaBackup.appending(path: nome, directoryHint: .isDirectory)
        try fm.createDirectory(at: provvisoria, withIntermediateDirectories: true)
        do {
            try BackupAperto.scrivi(context, in: provvisoria)
            if fm.fileExists(atPath: destinazione.path) { try fm.removeItem(at: destinazione) }
            try fm.moveItem(at: provvisoria, to: destinazione)
        } catch {
            try? fm.removeItem(at: provvisoria)
            throw error
        }
        UserDefaults.standard.set(Date(), forKey: "backup.ultimo")
        // ponytail: si tengono gli ultimi 4 backup locali (manuali e automatici insieme); quelli importanti vanno esportati.
        for vecchio in elenco().dropFirst(4) { try? fm.removeItem(at: vecchio) }
        return destinazione
    }

    /// I backup locali sono cifrati da iOS anche a telefono bloccato (protezione "completa": leggibili solo da sbloccato).
    /// Si scrivono e si leggono solo con l'app aperta, quindi non serve altro. I file nuovi ereditano la protezione
    /// della cartella; quelli già presenti si aggiornano qui.
    private static func proteggiCartellaBackup() throws {
        try FileManager.default.createDirectory(at: cartellaBackup, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        Persistenza.proteggi(cartellaBackup)
    }

    /// Backup locale settimanale, chiamato quando l'app va in background.
    static func automaticoSeServe(in context: ModelContext) {
        if let u = ultimoBackup, Date().timeIntervalSince(u) < 7 * 86_400 { return }
        guard ((try? context.fetchCount(FetchDescriptor<Movimento>())) ?? 0) > 0 else { return }
        // l'app sta andando in background: si chiede a iOS il tempo per finire di scrivere
        let compito = UIApplication.shared.beginBackgroundTask(withName: "backup")
        defer { UIApplication.shared.endBackgroundTask(compito) }
        do {
            try crea(in: context)
            UserDefaults.standard.removeObject(forKey: "backup.erroreAutomatico")
        } catch {
            UserDefaults.standard.set(error.localizedDescription, forKey: "backup.erroreAutomatico")
        }
    }

    /// Perché l'ultimo backup automatico non è riuscito (nil = tutto bene).
    static var erroreAutomatico: String? { UserDefaults.standard.string(forKey: "backup.erroreAutomatico") }

    /// Backup locali, dal più recente.
    static func elenco() -> [URL] {
        let figli = (try? FileManager.default.contentsOfDirectory(at: cartellaBackup, includingPropertiesForKeys: nil)) ?? []
        // solo le cartelle che sono davvero un backup (formato aperto, vecchio formato o cifrato)
        return figli.filter { c in
            c.lastPathComponent.hasPrefix("Bilancio-") && [BackupAperto.fileDati, nomeStore, CifraturaBackup.fileParametri].contains {
                FileManager.default.fileExists(atPath: c.appending(path: $0).path)
            }
        }
        .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Dimensione totale di una cartella (byte), anche dei file nascosti.
    static func dimensione(_ cartella: URL) -> Int64 {
        let e = FileManager.default.enumerator(at: cartella, includingPropertiesForKeys: [.fileSizeKey])
        var totale: Int64 = 0
        while let f = e?.nextObject() as? URL {
            totale += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return totale
    }

    // MARK: Ripristino

    enum ErroreBackup: LocalizedError {
        case nonValido, rovinato
        var errorDescription: String? {
            switch self {
            case .nonValido: String(localized: "La cartella scelta non è un backup di Bilancio (manca \(BackupAperto.fileDati)).")
            case .rovinato: String(localized: "Il database di questo backup è rovinato e non si apre.")
            }
        }
    }

    /// Prepara in RipristinoInSospeso il database ricostruito dal backup (anche da iCloud Drive): verrà applicato alla prossima apertura.
    /// Un backup protetto da password senza `password` lancia `CifraturaBackup.Errore.serveLaPassword`.
    /// Restituisce quante foto di scontrini mancavano nel backup (i dati si ripristinano lo stesso).
    @discardableResult
    static func preparaRipristino(da sorgente: URL, password: String? = nil) throws -> Int {
        let accesso = sorgente.startAccessingSecurityScopedResource()
        defer { if accesso { sorgente.stopAccessingSecurityScopedResource() } }

        // la lettura coordinata scarica da iCloud i file non ancora presenti sul telefono
        var erroreCoordinatore: NSError?
        var erroreCopia: Error?
        var fotoMancanti = 0
        NSFileCoordinator().coordinate(readingItemAt: sorgente, options: [], error: &erroreCoordinatore) { originale in
            let fm = FileManager.default
            var decifrata: URL?
            defer { if let decifrata { try? fm.removeItem(at: decifrata) } }   // la copia in chiaro non resta in giro
            do {
                var url = originale
                if CifraturaBackup.èCifrato(originale) {
                    guard let password else { throw CifraturaBackup.Errore.serveLaPassword }
                    let t = fm.temporaryDirectory.appending(path: "ripristino-\(UUID().uuidString)", directoryHint: .isDirectory)
                    decifrata = t
                    try CifraturaBackup.decifra(originale, in: t, password: password)
                    url = t
                }
                // Si costruisce in una cartella a parte e la si rinomina solo alla fine: se l'app viene chiusa a metà
                // non resta un database vuoto o incompleto pronto a prendere il posto di quello vero.
                try? fm.removeItem(at: inPreparazione)
                defer { try? fm.removeItem(at: inPreparazione) }
                try fm.createDirectory(at: supporto, withIntermediateDirectories: true)
                if fm.fileExists(atPath: url.appending(path: BackupAperto.fileDati).path) {
                    // formato aperto: database nuovo costruito da bilancio.json e foto/
                    try fm.createDirectory(at: inPreparazione, withIntermediateDirectories: true)
                    fotoMancanti = try { try BackupAperto.leggi(da: url, in: ModelContext(try apri(inPreparazione))) }()
                } else if fm.fileExists(atPath: url.appending(path: nomeStore).path) {
                    // vecchio formato: copia della cartella del database. Deve aprirsi: un database rovinato messo
                    // al posto di quello vero bloccherebbe l'app a ogni avvio.
                    try fm.copyItem(at: url, to: inPreparazione)
                    do { _ = try apri(inPreparazione) } catch { throw ErroreBackup.rovinato }
                } else {
                    throw ErroreBackup.nonValido
                }
                if fm.fileExists(atPath: inSospeso.path) { try fm.removeItem(at: inSospeso) }
                try fm.moveItem(at: inPreparazione, to: inSospeso)
            } catch {
                erroreCopia = error
            }
        }
        if let e = erroreCoordinatore ?? erroreCopia { throw e }
        return fotoMancanti
    }

    private static func apri(_ cartella: URL) throws -> ModelContainer {
        let config = ModelConfiguration(schema: Persistenza.schema, url: cartella.appending(path: nomeStore))
        return try ModelContainer(for: Persistenza.schema, configurations: config)
    }

    static var ripristinoInSospeso: Bool { FileManager.default.fileExists(atPath: inSospeso.path) }

    /// Chiamata da `Persistenza.container` PRIMA di aprire il database: mette il backup scelto
    /// al posto della cartella attuale, che viene conservata in Bilancio-prima-del-ripristino-<data>.
    static func applicaRipristinoInSospeso() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: inSospeso.path) else { return }
        guard fm.fileExists(atPath: inSospeso.appending(path: nomeStore).path) else {
            try? fm.removeItem(at: inSospeso)
            return
        }
        do {
            if fm.fileExists(atPath: cartellaDatabase.path) {
                try fm.moveItem(at: cartellaDatabase, to: supporto.appending(path: "Bilancio-prima-del-ripristino-\(timbro(Date()))", directoryHint: .isDirectory))
            }
            try fm.moveItem(at: inSospeso, to: cartellaDatabase)
            // Le sistemazioni "una volta sola" che si possono ripetere senza danni devono rigirare sui dati ripristinati
            // (un backup vecchio può non avere le categorie nuove). Non quella degli scontrini: annullerebbe conferme fatte a mano.
            for chiave in ["categorie.commissioniBancarie", "conti.nomiDallaBanca"] { UserDefaults.standard.removeObject(forKey: chiave) }
            // i dati di prima sono già un backup dell'elenco (vedi BackupView): di queste copie bastano le ultime due
            let copie = ((try? fm.contentsOfDirectory(at: supporto, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("Bilancio-prima-del-ripristino-") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for vecchia in copie.dropFirst(2) { try? fm.removeItem(at: vecchia) }
        } catch {
            // se lo spostamento fallisce il database attuale resta dov'è (o viene ricreato vuoto): niente crash
            print("Ripristino non applicato: \(error)")
        }
    }

    // MARK: CSV

    /// Tutti i movimenti in CSV per Excel: separatore `;`, decimali con la virgola, UTF-8 con BOM.
    static func csvMovimenti(in context: ModelContext) -> String {
        let movimenti = (try? context.fetch(FetchDescriptor<Movimento>(sortBy: [SortDescriptor(\.data)]))) ?? []
        var righe = [String(localized: "Data;Tipo;Titolo;Categoria;Conto;Importo;Stato;Origine;Nota;Descrizione originale", comment: "Intestazione CSV: tenere i 10 campi separati da punto e virgola")]
        for m in movimenti {
            let campi = [
                m.data.breve, m.tipo.etichetta, m.titolo, m.categoria?.nome ?? "", m.conto?.nome ?? "",
                m.importo.formatted(.number.precision(.fractionLength(2)).grouping(.never)),
                m.daConfermare ? String(localized: "Da confermare") : String(localized: "Confermato"), m.origine.etichetta, m.nota, m.descrizioneOriginale,
            ]
            righe.append(campi.map(campoCSV).joined(separator: ";"))
        }
        return "\u{FEFF}" + righe.joined(separator: "\r\n") + "\r\n"
    }

    nonisolated static func campoCSV(_ s: String) -> String {
        guard s.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Documento per `fileExporter`: una cartella di backup o un file CSV, già pronti come FileWrapper.
struct DocumentoBackupEsportato: FileDocument, @unchecked Sendable {
    static let readableContentTypes: [UTType] = [.folder, .commaSeparatedText]
    let wrapper: FileWrapper

    init(wrapper: FileWrapper) { self.wrapper = wrapper }
    init(configuration: ReadConfiguration) throws { wrapper = configuration.file }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }
}
