import Foundation
import SwiftData

/// Categorie e conti creati al primo avvio (modificabili dopo), salvati nella lingua del telefono.
/// Le tabelle restano in italiano perché le usano anche le parole chiave del Classificatore;
/// le traduzioni stanno nel catalogo `DatiIniziali.xcstrings`.
enum DatiIniziali {

    /// Nome iniziale nella lingua del telefono ("Spesa alimentare" → "Groceries").
    static func localizzato(_ nome: String) -> String {
        Bundle.main.localizedString(forKey: nome, value: nome, table: "DatiIniziali")
    }

    /// Vero se `nome` è il nome iniziale `nomeIT`, in italiano o nella lingua del telefono.
    static func corrisponde(_ nome: String?, a nomeIT: String) -> Bool {
        nome == nomeIT || nome == localizzato(nomeIT)
    }

    static let categorieSpesa: [(String, String, String, Bool)] = [
        // nome, SF Symbol, colore, detraibile
        ("Spesa alimentare", "cart", "#F59E0B", false),
        ("Casa e bollette", "house", "#2563EB", false),
        ("Trasporti", "car", "#10B981", false),
        ("Ristoranti e bar", "fork.knife", "#EF4444", false),
        ("Abbonamenti", "repeat", "#A855F7", false),
        ("Salute", "cross.case", "#EC4899", true),
        ("Cura personale", "sparkles", "#F472B6", false),
        ("Casa e pulizia", "bubbles.and.sparkles", "#22C55E", false),
        ("Abbigliamento", "tshirt", "#14B8A6", false),
        ("Svago e cultura", "theatermasks", "#8B5CF6", false),
        ("Viaggi", "airplane", "#0EA5E9", false),
        ("Tecnologia", "desktopcomputer", "#64748B", false),
        ("Regali", "gift", "#F43F5E", false),
        ("Istruzione", "book", "#6366F1", true),
        ("Tasse e imposte", "building.columns", "#78716C", false),
        ("Commissioni bancarie", "creditcard", "#A16207", false),
        ("Altro", "ellipsis.circle", "#9CA3AF", false),
    ]

    static let categorieEntrata: [(String, String, String)] = [
        ("Stipendio", "banknote", "#16A34A"),
        ("Rimborsi", "arrow.uturn.backward.circle", "#65A30D"),
        ("Interessi e dividendi", "percent", "#0D9488"),
        ("Altre entrate", "plus.circle", "#84CC16"),
    ]

    /// Conti iniziali: solo Contanti. Gli altri nascono collegando una banca o da Altro › Conti.
    static let conti: [(String, TipoConto, String, String)] = [
        ("Contanti", .contanti, "", "#16A34A"),
    ]

    static func inserisciSeVuoto(_ context: ModelContext) {
        let n = (try? context.fetchCount(FetchDescriptor<Categoria>())) ?? 0
        guard n == 0 else { return }
        for (i, c) in categorieSpesa.enumerated() {
            context.insert(Categoria(nome: localizzato(c.0), icona: c.1, coloreHex: c.2, tipo: .spesa, detraibile: c.3, ordine: i))
        }
        for (i, c) in categorieEntrata.enumerated() {
            context.insert(Categoria(nome: localizzato(c.0), icona: c.1, coloreHex: c.2, tipo: .entrata, ordine: 100 + i))
        }
        for (i, c) in conti.enumerated() {
            context.insert(Conto(nome: localizzato(c.0), tipo: c.1, istituto: c.2, coloreHex: c.3, ordine: i))
        }
        try? context.save()
    }

    /// Categorie aggiunte dopo la prima versione, per chi ha già l'app (una volta sola: se l'utente
    /// poi le elimina o le rinomina, restano come le ha lasciate).
    static func aggiornaCategorie(_ context: ModelContext) {
        let chiave = "categorie.commissioniBancarie"
        guard !UserDefaults.standard.bool(forKey: chiave) else { return }
        let tutte = (try? context.fetch(FetchDescriptor<Categoria>())) ?? []
        guard !tutte.isEmpty else { return }   // database vuoto: ci pensa inserisciSeVuoto
        if !tutte.contains(where: { corrisponde($0.nome, a: "Commissioni bancarie") }) {
            let ordine = tutte.first { corrisponde($0.nome, a: "Tasse e commissioni") }?.ordine ?? (tutte.map(\.ordine).max() ?? 0)
            context.insert(Categoria(nome: localizzato("Commissioni bancarie"), icona: "creditcard", coloreHex: "#A16207", tipo: .spesa, ordine: ordine))
        }
        // le commissioni hanno ora la loro categoria: "Tasse e commissioni" diventa "Tasse e imposte"
        if let vecchia = tutte.first(where: { corrisponde($0.nome, a: "Tasse e commissioni") }),
           !tutte.contains(where: { corrisponde($0.nome, a: "Tasse e imposte") }) {
            vecchia.nome = localizzato("Tasse e imposte")
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: chiave)
    }

    /// Il conto Contanti (esiste sempre).
    static func contoContanti(in context: ModelContext) -> Conto {
        let tipo = TipoConto.contanti.rawValue
        if let c = try? context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { $0.tipoRaw == tipo })).first {
            return c
        }
        let c = Conto(nome: localizzato("Contanti"), tipo: .contanti, coloreHex: "#16A34A", ordine: 99)
        context.insert(c)
        return c
    }
}
