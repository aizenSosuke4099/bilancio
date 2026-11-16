import UIKit
import Vision
import FoundationModels

/// Dalla foto ai dati: OCR con Vision, poi Apple Intelligence on-device (o il parser a regole).
enum LettoreScontrino {

    struct Esito {
        var bozza: BozzaScontrino
        var conAI: Bool
        /// Spiegazione da mostrare quando Apple Intelligence non è stata usata.
        var nota: String?
    }

    enum Errore: LocalizedError {
        case immagineIllegibile
        var errorDescription: String? { "Non riesco a leggere l'immagine dello scontrino." }
    }

    // MARK: OCR

    /// Testo dello scontrino, una riga per riga stampata. Più foto = scontrino lungo, in ordine.
    static func leggiTesto(da immagini: [UIImage]) async throws -> String {
        var righe: [String] = []
        for img in immagini {
            guard let cg = img.cgImage else { throw Errore.immagineIllegibile }
            var richiesta = RecognizeTextRequest()
            richiesta.recognitionLevel = .accurate
            richiesta.recognitionLanguages = [Locale.Language(identifier: "it-IT")]
            richiesta.usesLanguageCorrection = true
            let osservazioni = try await richiesta.perform(on: cg, orientation: orientamento(img.imageOrientation))
            let frammenti = osservazioni.compactMap { o -> ParserScontrino.Frammento? in
                guard let t = o.topCandidates(1).first?.string else { return nil }
                return ParserScontrino.Frammento(
                    testo: t,
                    x: Double(min(o.topLeft.x, o.bottomLeft.x)),
                    yCentro: Double(o.topLeft.y + o.bottomLeft.y + o.topRight.y + o.bottomRight.y) / 4,
                    altezza: Double(abs(o.topLeft.y - o.bottomLeft.y) + abs(o.topRight.y - o.bottomRight.y)) / 2
                )
            }
            righe += ParserScontrino.ricostruisciRighe(frammenti)
        }
        return righe.joined(separator: "\n")
    }

    private static func orientamento(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }

    // MARK: Estrazione

    /// Estrae i dati dal testo. Il parser a regole dà la struttura numerica (righe, quantità, sconti, totale, data, P.IVA):
    /// è deterministico e il modello on-device sbaglia spesso l'aritmetica. Apple Intelligence classifica le righe
    /// (categoria, nome prodotto, unità, formato); se le regole non tornano col totale, estrae lei anche le righe.
    static func estrai(testo: String, categorie: [String], avanzamento: (String) -> Void) async -> Esito {
        let regole = ParserScontrino.analizza(testo)

        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let motivo):
            let nota: String = switch motivo {
            case .deviceNotEligible: String(localized: "Questo iPhone non supporta Apple Intelligence: scontrino letto con le regole.")
            case .appleIntelligenceNotEnabled: String(localized: "Attiva Apple Intelligence in Impostazioni per una lettura migliore. Scontrino letto con le regole.")
            case .modelNotReady: String(localized: "Apple Intelligence si sta ancora preparando: scontrino letto con le regole.")
            @unknown default: String(localized: "Apple Intelligence non disponibile: scontrino letto con le regole.")
            }
            return Esito(bozza: regole, conAI: false, nota: nota)
        }

        // le regole non tornano col totale: il modello estrae le righe, ma vale solo se torna esattamente
        // (altrimenti tende a inventare prezzi per far quadrare i conti)
        if scarto(regole.righe, regole.totale) >= 0.01,
           let ai = try? await estraiConAI(testo: testo, categorie: categorie, avanzamento: avanzamento) {
            let unita = unisci(ai: ai, regole: regole)
            if scarto(unita.righe, unita.totale) < 0.01 {
                return Esito(bozza: unita, conAI: true, nota: nil)
            }
        }

        guard !regole.righe.isEmpty else {
            return Esito(bozza: regole, conAI: false, nota: String(localized: "Non ho trovato le righe dei prodotti: aggiungile a mano se ti servono."))
        }
        do {
            var b = regole
            b.righe = try await classifica(regole.righe, negozio: regole.negozio, categorie: categorie, avanzamento: avanzamento)
            return Esito(bozza: b, conAI: true, nota: nil)
        } catch {
            return Esito(bozza: regole, conAI: false,
                         nota: String(localized: "Apple Intelligence non è riuscita a classificare le righe (\(error.localizedDescription)): proposte fatte con le regole."))
        }
    }

    /// Differenza tra somma delle righe e totale (infinita se non ci sono righe).
    private static func scarto(_ righe: [BozzaScontrino.Riga], _ totale: Double?) -> Double {
        guard !righe.isEmpty else { return .infinity }
        return abs(righe.reduce(0) { $0 + $1.totale } - (totale ?? 0))
    }

    /// Righe per blocco: il contesto on-device è piccolo (~4k token) e la risposta occupa più dell'input.
    private static let righePerBlocco = 25

    private static func blocchi<T>(_ a: [T]) -> [[T]] {
        stride(from: 0, to: a.count, by: righePerBlocco).map { Array(a[$0..<min($0 + righePerBlocco, a.count)]) }
    }

    /// Categoria e nome prodotto per ogni riga già letta dalle regole. Unità e formato restano quelli delle regole
    /// (letti dal testo, "500G" → 0,5 kg): il modello li sbaglia spesso e allungherebbe la risposta.
    private static func classifica(_ righe: [BozzaScontrino.Riga], negozio: String, categorie: [String], avanzamento: (String) -> Void) async throws -> [BozzaScontrino.Riga] {
        let parti = blocchi(Array(righe.enumerated()))
        var esito = righe
        for (i, parte) in parti.enumerated() {
            avanzamento(parti.count > 1 ? String(localized: "Capisco le voci… (\(i + 1) di \(parti.count))") : String(localized: "Capisco le voci…"))
            for v in try await classificaBlocco(parte.map { ($0.offset + 1, $0.element.testo) }, negozio: negozio, categorie: categorie) {
                guard (1...esito.count).contains(v.numero) else { continue }
                if let c = categoria(v.categoria, tra: categorie) { esito[v.numero - 1].categoria = c }
                let nome = v.nomeProdotto.trimmingCharacters(in: .whitespaces)
                if !nome.isEmpty { esito[v.numero - 1].nomeProdotto = nome }
            }
        }
        return esito
    }

    private static func classificaBlocco(_ righe: [(Int, String)], negozio: String, categorie: [String]) async throws -> [VoceGenerata] {
        let sessione = LanguageModelSession(instructions: istruzioniClassifica(categorie: categorie))
        let prompt = (negozio.isEmpty ? "" : "Negozio: \(negozio)\n") + "Righe dello scontrino:\n"
            + righe.map { "\($0.0). \($0.1)" }.joined(separator: "\n")
        do {
            return try await sessione.respond(to: prompt, generating: ClassificazioneGenerata.self, options: GenerationOptions(samplingMode: .greedy)).content.voci
        } catch where contestoSuperato(error) && righe.count > 3 {
            let meta = righe.count / 2
            return try await classificaBlocco(Array(righe[..<meta]), negozio: negozio, categorie: categorie)
                + classificaBlocco(Array(righe[meta...]), negozio: negozio, categorie: categorie)
        }
    }

    private static func estraiConAI(testo: String, categorie: [String], avanzamento: (String) -> Void) async throws -> BozzaScontrino {
        let righe = testo.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let parti = blocchi(righe)
        var esito = BozzaScontrino()
        for (i, blocco) in parti.enumerated() {
            avanzamento(parti.count > 1 ? String(localized: "Leggo le voci con Apple Intelligence… (\(i + 1) di \(parti.count))") : String(localized: "Leggo le voci con Apple Intelligence…"))
            for parte in try await rispondi(blocco, parte: i + 1, di: parti.count, categorie: categorie) {
                if esito.negozio.isEmpty { esito.negozio = parte.negozio }
                if esito.partitaIva.isEmpty { esito.partitaIva = parte.partitaIva }
                if esito.indirizzo.isEmpty { esito.indirizzo = parte.indirizzo }
                esito.data = esito.data ?? parte.data
                if let t = parte.totale { esito.totale = t }   // il totale sta in fondo: vince l'ultimo blocco
                esito.righe += parte.righe
            }
        }
        return esito
    }

    /// Chiede al modello un blocco di righe; se il contesto non basta lo divide a metà.
    private static func rispondi(_ righe: [String], parte: Int, di totaleParti: Int, categorie: [String]) async throws -> [BozzaScontrino] {
        let sessione = LanguageModelSession(instructions: istruzioniEstrazione(categorie: categorie))
        let prompt = (totaleParti > 1
            ? "Parte \(parte) di \(totaleParti) dello scontrino. Se in questa parte non ci sono negozio, data o totale lasciali vuoti o a 0.\n"
            : "Testo dello scontrino:\n") + righe.joined(separator: "\n")
        do {
            let r = try await sessione.respond(to: prompt, generating: ScontrinoGenerato.self, options: GenerationOptions(samplingMode: .greedy))
            return [r.content.bozza(categorie: categorie)]
        } catch where contestoSuperato(error) && righe.count > 6 {
            let meta = righe.count / 2
            return try await rispondi(Array(righe[..<meta]), parte: parte, di: totaleParti, categorie: categorie)
                + rispondi(Array(righe[meta...]), parte: parte, di: totaleParti, categorie: categorie)
        }
    }

    private static func contestoSuperato(_ error: Error) -> Bool {
        if #available(iOS 27.0, *), let e = error as? LanguageModelError, case .contextSizeExceeded = e { return true }
        if let e = error as? LanguageModelSession.GenerationError, case .exceededContextWindowSize = e { return true }
        return false
    }

    /// Nome di categoria esistente: uguale, oppure uno contenuto nell'altro ("alimentare" → "Spesa alimentare").
    fileprivate static func categoria(_ nome: String, tra categorie: [String]) -> String? {
        let n = nome.trimmingCharacters(in: .whitespaces)
        guard n.count >= 3 else { return nil }
        let opzioni: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return categorie.first { $0.compare(n, options: opzioni) == .orderedSame }
            ?? categorie.first { $0.range(of: n, options: opzioni) != nil || n.range(of: $0, options: opzioni) != nil }
    }

    private static func regoleNomi(_ categorie: [String]) -> String {
        """
        - categoria: esattamente uno di questi nomi: \(categorie.joined(separator: ", ")). Cibo e bevande del supermercato → "Spesa alimentare"; \
        detersivi, carta igienica, prodotti per la casa → "Casa e pulizia"; shampoo, dentifricio, cosmetici → "Cura personale"; farmaci → "Salute".
        - nomeProdotto: nome comprensibile, con le abbreviazioni sciolte, marca e formato, per esempio \
        "LATTE INT GRANAROLO 1L" → "Latte intero Granarolo 1 l", "SPAGH BARILLA N5 500G" → "Spaghetti Barilla n.5 500 g".
        - Ristoranti, bar, pizzerie: cibo, bevande e coperto → "Ristoranti e bar".
        """
    }

    private static func istruzioniClassifica(categorie: [String]) -> String {
        "Classifichi i prodotti di scontrini italiani. Ricevi righe numerate con la descrizione abbreviata stampata sullo scontrino. "
            + "Per ogni riga restituisci una voce con lo stesso numero.\n"
            + regoleNomi(categorie)
    }

    private static func istruzioniEstrazione(categorie: [String]) -> String {
        """
        Leggi scontrini italiani. Ricevi il testo OCR di uno scontrino, una riga per ogni riga stampata \
        (descrizione a sinistra, prezzo a destra). Estrai solo ciò che è scritto, senza inventare.
        - Le righe di prodotto hanno una descrizione e un prezzo. Una riga come "2 x 1,29" indica quantità e prezzo unitario della riga di prodotto il cui prezzo è 2 × 1,29.
        - Le righe di sconto (SCONTO, PROMO, OFFERTA, importi negativi) restano righe a sé, con totale negativo: non sottrarle tu.
        - Ignora totali, subtotali, IVA, pagamenti, resto, numero documento, cassa, tessera punti.
        - I numeri sullo scontrino usano la virgola per i decimali: "1,29" vale 1.29.
        - testo: la descrizione senza il prezzo.
        - unita: "kg" per prodotti venduti a peso, "l" per liquidi, altrimenti "pz". formato: quantità della confezione nell'unità (500 g = 0.5), 0 se non si sa.

        """ + regoleNomi(categorie)
    }

    /// Dati dell'AI, con negozio/totale/data/P.IVA delle regole quando le hanno trovati (sono letterali).
    private static func unisci(ai: BozzaScontrino, regole: BozzaScontrino) -> BozzaScontrino {
        var b = ai
        if !regole.negozio.isEmpty { b.negozio = regole.negozio }
        if b.indirizzo.isEmpty { b.indirizzo = regole.indirizzo }
        if !regole.partitaIva.isEmpty { b.partitaIva = regole.partitaIva }
        b.data = regole.data ?? ai.data
        b.totale = regole.totale ?? ai.totale
        b.righe = ParserScontrino.applicaSconti(ai.righe)
        b.pagatoInContanti = regole.pagatoInContanti
        return b
    }
}

// MARK: - Generazione guidata

@Generable(description: "Dati di uno scontrino italiano")
fileprivate struct ScontrinoGenerato {
    @Guide(description: "Nome del negozio o dell'azienda, di solito la prima riga, senza forma societaria (S.p.A., S.r.l.)")
    var negozio: String
    @Guide(description: "Partita IVA di 11 cifre, vuota se assente")
    var partitaIva: String
    @Guide(description: "Indirizzo del negozio, vuoto se assente")
    var indirizzo: String
    @Guide(description: "Data dello scontrino nel formato yyyy-MM-dd, vuota se assente")
    var data: String
    @Guide(description: "Totale pagato in euro (TOTALE COMPLESSIVO), 0 se assente")
    var totale: Double
    @Guide(description: "Prodotti acquistati, nell'ordine dello scontrino")
    var righe: [RigaGenerata]
}

@Generable(description: "Un prodotto dello scontrino")
fileprivate struct RigaGenerata {
    @Guide(description: "Descrizione così come stampata")
    var testo: String
    @Guide(description: "Quantità (pezzi, o kg per i prodotti a peso), 1 se non indicata")
    var quantita: Double
    @Guide(description: "Prezzo unitario in euro")
    var prezzoUnitario: Double
    @Guide(description: "Totale della riga in euro, negativo per le righe di sconto")
    var totale: Double
    @Guide(description: "Categoria di spesa, una di quelle elencate nelle istruzioni")
    var categoria: String
    @Guide(description: "Nome del prodotto normalizzato con marca e formato")
    var nomeProdotto: String
    @Guide(description: "Unità di misura", .anyOf(["pz", "kg", "l"]))
    var unita: String
    @Guide(description: "Quantità della confezione nell'unità, 0 se sconosciuta")
    var formato: Double
}

@Generable(description: "Classificazione dei prodotti di uno scontrino")
fileprivate struct ClassificazioneGenerata {
    @Guide(description: "Una voce per ogni riga ricevuta, nello stesso ordine")
    var voci: [VoceGenerata]
}

@Generable(description: "Classificazione di una riga")
fileprivate struct VoceGenerata {
    @Guide(description: "Numero della riga ricevuta")
    var numero: Int
    @Guide(description: "Categoria di spesa, una di quelle elencate nelle istruzioni")
    var categoria: String
    @Guide(description: "Nome del prodotto normalizzato con marca e formato")
    var nomeProdotto: String
}

fileprivate extension ScontrinoGenerato {
    /// Converte e ripulisce la risposta del modello (numeri impossibili, categorie inventate, date fuori luogo).
    func bozza(categorie: [String]) -> BozzaScontrino {
        var b = BozzaScontrino()
        b.negozio = negozio.trimmingCharacters(in: .whitespaces)
        let cifre = partitaIva.filter(\.isNumber)
        b.partitaIva = cifre.count == 11 ? cifre : ""
        b.indirizzo = indirizzo.trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendario
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: data), d < Date().aggiungendo(giorni: 2), d > Date().aggiungendo(mesi: -36) {
            b.data = d.addingTimeInterval(12 * 3600)
        }
        b.totale = totale > 0 ? totale.centesimi : nil
        b.righe = righe.compactMap { r in
            // il modello a volte lascia il prezzo in coda alla descrizione
            let testo = r.testo.replacingOccurrences(of: #"\s+-?\d{1,4}[.,]\d{2}\s*[A-Z]?$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !testo.isEmpty || r.totale != 0 else { return nil }
            let q = r.quantita > 0 ? r.quantita : 1
            var tot = r.totale
            var pu = r.prezzoUnitario
            if tot == 0, pu != 0 { tot = q * pu }
            if pu == 0 { pu = tot / q }
            if tot > 0, q * pu < tot - 0.01 { pu = tot / q }   // il prezzo di listino non può essere meno del pagato
            let cat = LettoreScontrino.categoria(r.categoria, tra: categorie) ?? ""
            let daTesto = ParserScontrino.formato(da: testo)
            return BozzaScontrino.Riga(testo: testo, quantita: q, prezzoUnitario: pu.centesimi, totale: tot.centesimi, categoria: cat,
                                       nomeProdotto: r.nomeProdotto.trimmingCharacters(in: .whitespaces),
                                       unita: daTesto?.unita ?? (["kg", "l"].contains(r.unita) ? r.unita : "pz"),
                                       formato: daTesto?.formato ?? (["kg", "l"].contains(r.unita) && r.formato > 0 && r.formato < 50 ? r.formato : nil))
        }
        return b
    }
}
