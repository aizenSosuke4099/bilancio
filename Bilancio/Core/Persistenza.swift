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

    /// Container unico condiviso da app e task in background.
    static let container: ModelContainer = {
        // Un ripristino da backup va applicato prima di aprire il database.
        Backup.applicaRipristinoInSospeso()
        let config = ModelConfiguration(schema: schema, url: urlStore)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Impossibile aprire il database: \(error)")
        }
    }()
}
