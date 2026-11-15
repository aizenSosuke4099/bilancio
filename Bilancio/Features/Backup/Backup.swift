import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Backup = copia dell'intera cartella del database (store, -wal, -shm, allegati esterni)
/// in Documents/Backup/Bilancio-AAAA-MM-GG-HHmm/, visibile in File › Sul mio iPhone › Bilancio.
/// Il ripristino viene preparato in Application Support/RipristinoInSospeso/ e applicato
/// al riavvio, prima di aprire SwiftData.
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

    /// Copia la cartella del database in un nuovo backup locale. Salvare il contesto prima.
    @discardableResult
    static func crea() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: cartellaBackup, withIntermediateDirectories: true)
        let destinazione = cartellaBackup.appending(path: "Bilancio-" + timbro(Date()), directoryHint: .isDirectory)
        if fm.fileExists(atPath: destinazione.path) { try fm.removeItem(at: destinazione) }
        try fm.copyItem(at: cartellaDatabase, to: destinazione)
        UserDefaults.standard.set(Date(), forKey: "backup.ultimo")
        // ponytail: si tengono gli ultimi 4 backup locali (manuali e automatici insieme); quelli importanti vanno esportati.
        for vecchio in elenco().dropFirst(4) { try? fm.removeItem(at: vecchio) }
        return destinazione
    }

    /// Backup locale settimanale, chiamato quando l'app va in background.
    static func automaticoSeServe() {
        if let u = ultimoBackup, Date().timeIntervalSince(u) < 7 * 86_400 { return }
        guard FileManager.default.fileExists(atPath: cartellaDatabase.appending(path: nomeStore).path) else { return }
        _ = try? crea()
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
        var errorDescription: String? { "La cartella scelta non è un backup di Bilancio (manca \(Backup.nomeStore))." }
    }

    /// Copia un backup (anche da iCloud Drive) in RipristinoInSospeso: verrà applicato alla prossima apertura.
    static func preparaRipristino(da sorgente: URL) throws {
        let accesso = sorgente.startAccessingSecurityScopedResource()
        defer { if accesso { sorgente.stopAccessingSecurityScopedResource() } }

        // la lettura coordinata scarica da iCloud i file non ancora presenti sul telefono
        var erroreCoordinatore: NSError?
        var erroreCopia: Error?
        NSFileCoordinator().coordinate(readingItemAt: sorgente, options: [], error: &erroreCoordinatore) { url in
            do {
                let fm = FileManager.default
                guard fm.fileExists(atPath: url.appending(path: nomeStore).path) else { throw ErroreBackup.nonValido }
                if fm.fileExists(atPath: inSospeso.path) { try fm.removeItem(at: inSospeso) }
                try fm.createDirectory(at: supporto, withIntermediateDirectories: true)
                try fm.copyItem(at: url, to: inSospeso)
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
        var righe = ["Data;Tipo;Titolo;Categoria;Conto;Importo;Stato;Origine;Nota;Descrizione originale"]
        for m in movimenti {
            let campi = [
                m.data.breve, m.tipo.etichetta, m.titolo, m.categoria?.nome ?? "", m.conto?.nome ?? "",
                m.importo.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(localeIT)),
                m.daConfermare ? "Da confermare" : "Confermato", m.origine.etichetta, m.nota, m.descrizioneOriginale,
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
