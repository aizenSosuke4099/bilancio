import Foundation
import SwiftData

/// Database locale. La cartella `cartella` è ciò che il backup salva e ripristina.
enum Persistenza {
    static let schema = Schema([
        Conto.self, Movimento.self, Categoria.self,
        Scontrino.self, RigaScontrino.self, Prodotto.self, RegolaAppresa.self,
        Ricorrenza.self,
        Strumento.self, Operazione.self, Valutazione.self, PianoPAC.self, AllocazionePAC.self,
        SnapshotPatrimonio.self, ConnessioneBanca.self, ProfiloImport.self,
    ])

    static var cartella: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Bilancio", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var urlStore: URL { cartella.appending(path: "Bilancio.store") }

    /// Protezione "completa" di iOS: file cifrati con una chiave legata al codice dell'iPhone, illeggibili a telefono
    /// bloccato (anche con strumenti forensi). Per questo l'app non lavora in background. I file nuovi ereditano la
    /// protezione della cartella; qui si aggiornano anche quelli già presenti.
    static func proteggi(_ cartella: URL) {
        let fm = FileManager.default
        let completa: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        try? fm.setAttributes(completa, ofItemAtPath: cartella.path)
        let e = fm.enumerator(at: cartella, includingPropertiesForKeys: nil)
        while let f = e?.nextObject() as? URL { try? fm.setAttributes(completa, ofItemAtPath: f.path) }
    }

    /// Container unico dell'app.
    static let container: ModelContainer = {
        // Un ripristino da backup va applicato prima di aprire il database.
        Backup.applicaRipristinoInSospeso()
        // tutta Application Support: database, copie "prima del ripristino", ripristino in sospeso
        proteggi(URL.applicationSupportDirectory)
        let config = ModelConfiguration(schema: schema, url: urlStore)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Impossibile aprire il database: \(error)")
        }
    }()
}
