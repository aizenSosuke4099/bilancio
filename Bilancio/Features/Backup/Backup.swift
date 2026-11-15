import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Backup = cartella in formato aperto (vedi `BackupAperto`: JSON + foto, leggibile anche su Android o al computer)
/// in Documents/Backup/Bilancio-AAAA-MM-GG-HHmm/, visibile in File › Sul mio iPhone › Bilancio.
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
        let destinazione = cartellaBackup.appending(path: "Bilancio-" + timbro(Date()), directoryHint: .isDirectory)
        if fm.fileExists(atPath: destinazione.path) { try fm.removeItem(at: destinazione) }
        try fm.createDirectory(at: destinazione, withIntermediateDirectories: true)
        do {
            try BackupAperto.scrivi(context, in: destinazione)
        } catch {
            try? fm.removeItem(at: destinazione)   // niente backup a metà nell'elenco
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
        let fm = FileManager.default
        let completa: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        try fm.createDirectory(at: cartellaBackup, withIntermediateDirectories: true, attributes: completa)
        try? fm.setAttributes(completa, ofItemAtPath: cartellaBackup.path)
        let e = fm.enumerator(at: cartellaBackup, includingPropertiesForKeys: nil)
        while let f = e?.nextObject() as? URL { try? fm.setAttributes(completa, ofItemAtPath: f.path) }
    }

    /// Backup locale settimanale, chiamato quando l'app va in background.
    static func automaticoSeServe(in context: ModelContext) {
        if let u = ultimoBackup, Date().timeIntervalSince(u) < 7 * 86_400 { return }
        guard ((try? context.fetchCount(FetchDescriptor<Movimento>())) ?? 0) > 0 else { return }
        _ = try? crea(in: context)
    }

    /// Backup locali, dal più recente.
    static func elenco() -> [URL] {
        let figli = (try? FileManager.default.contentsOfDirectory(at: cartellaBackup, includingPropertiesForKeys: nil)) ?? []
        return figli.filter { $0.lastPathComponent.hasPrefix("Bilancio-") }
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
        case nonValido
        var errorDescription: String? { String(localized: "La cartella scelta non è un backup di Bilancio (manca \(BackupAperto.fileDati)).") }
    }

    /// Prepara in RipristinoInSospeso il database ricostruito dal backup (anche da iCloud Drive): verrà applicato alla prossima apertura.
    static func preparaRipristino(da sorgente: URL) throws {
        let accesso = sorgente.startAccessingSecurityScopedResource()
        defer { if accesso { sorgente.stopAccessingSecurityScopedResource() } }

        // la lettura coordinata scarica da iCloud i file non ancora presenti sul telefono
        var erroreCoordinatore: NSError?
        var erroreCopia: Error?
        NSFileCoordinator().coordinate(readingItemAt: sorgente, options: [], error: &erroreCoordinatore) { url in
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: inSospeso.path) { try fm.removeItem(at: inSospeso) }
                try fm.createDirectory(at: supporto, withIntermediateDirectories: true)
                if fm.fileExists(atPath: url.appending(path: BackupAperto.fileDati).path) {
                    // formato aperto: database nuovo costruito da bilancio.json e foto/
                    try fm.createDirectory(at: inSospeso, withIntermediateDirectories: true)
                    do {
                        let config = ModelConfiguration(schema: Persistenza.schema, url: inSospeso.appending(path: nomeStore))
                        let contenitore = try ModelContainer(for: Persistenza.schema, configurations: config)
                        try BackupAperto.leggi(da: url, in: ModelContext(contenitore))
                    } catch {
                        try? fm.removeItem(at: inSospeso)
                        throw error
                    }
                } else if fm.fileExists(atPath: url.appending(path: nomeStore).path) {
                    // vecchio formato: copia della cartella del database
                    try fm.copyItem(at: url, to: inSospeso)
                } else {
                    throw ErroreBackup.nonValido
                }
            } catch {
                erroreCopia = error
            }
        }
        if let e = erroreCoordinatore ?? erroreCopia { throw e }
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
