import Foundation
import SwiftData

/// Prezzi da Yahoo Finance e cambi BCE da Frankfurter. Tutti gli errori sono silenziosi:
/// senza rete l'app continua con l'ultimo prezzo salvato (o quello inserito a mano).
enum Prezzi {
    typealias Listino = CalcoliInvestimenti.Listino
    typealias Quotazione = CalcoliInvestimenti.Quotazione
    typealias Chiusura = CalcoliInvestimenti.Chiusura

    /// UserDefaults: istante (secondi dal 1970) dell'ultimo aggiornamento riuscito.
    static let chiaveUltimoAggiornamento = "investimenti.prezziAggiornatiIl"

    static var ultimoAggiornamento: Date? {
        let t = UserDefaults.standard.double(forKey: chiaveUltimoAggiornamento)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// All'apertura: aggiorna solo se l'ultimo aggiornamento ha più di 6 ore.
    static func aggiornaSeVecchi(in context: ModelContext) async {
        if let u = ultimoAggiornamento, Date().timeIntervalSince(u) < 6 * 3600 { return }
        await aggiornaTutto(in: context)
    }

    private static var inCorso = false

    /// Aggiornamento manuale (pull-to-refresh): prezzi degli strumenti quotati con ticker e cambi delle valute presenti.
    static func aggiornaTutto(in context: ModelContext) async {
        guard !inCorso else { return }
        inCorso = true
        defer { inCorso = false }

        let strumenti = (try? context.fetch(FetchDescriptor<Strumento>(predicate: #Predicate { !$0.archiviato }))) ?? []
        var riusciti = 0, tentati = 0
        for s in strumenti where !s.valoreManuale {
            guard let t = s.ticker, !t.isEmpty else { continue }
            tentati += 1
            if let q = await quotazione(t) {
                s.ultimoPrezzo = q.prezzo
                s.ultimoPrezzoData = q.data ?? Date()
                riusciti += 1
            }
        }
        let conti = (try? context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { !$0.archiviato }))) ?? []
        for valuta in Set(strumenti.map(\.valuta) + conti.map(\.valuta)) where valuta != "EUR" {
            tentati += 1
            if let c = await cambio(valuta) {
                Portafoglio.salvaCambio(valuta, c)
                riusciti += 1
            }
        }
        // offline: non si segna l'aggiornamento, così si riprova alla prossima apertura
        if riusciti > 0 || tentati == 0 {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: chiaveUltimoAggiornamento)
        }
        try? context.save()
    }

    // MARK: - Yahoo Finance

    /// Listini di uno strumento a partire dall'ISIN, quelli in euro per primi.
    static func cerca(isin: String) async -> [Listino] {
        guard let d = await scarica(urlRicerca(isin)) else { return [] }
        var trovati = CalcoliInvestimenti.listini(daRicerca: d)
        // la ricerca per ISIN spesso restituisce solo il listino principale (es. Londra):
        // cercando il nome completo arrivano anche XETRA, Milano, Amsterdam…
        if let nome = trovati.first(where: { $0.nome != $0.simbolo })?.nome,
           let d2 = await scarica(urlRicerca(nome)) {
            for l in CalcoliInvestimenti.listini(daRicerca: d2) where l.nome == nome && !trovati.contains(where: { $0.simbolo == l.simbolo }) {
                trovati.append(l)
            }
        }
        return CalcoliInvestimenti.ordinaPerEuro(trovati)
    }

    /// Prezzo attuale e valuta di un listino.
    static func quotazione(_ ticker: String) async -> Quotazione? {
        guard let d = await scarica(urlGrafico(ticker, ["range": "5d", "interval": "1d"])) else { return nil }
        return CalcoliInvestimenti.quotazione(daGrafico: d)
    }

    /// Chiusure giornaliere nell'intervallo [da, a].
    static func chiusureGiornaliere(_ ticker: String, da: Date, a: Date) async -> [Chiusura] {
        let parametri = ["period1": String(Int(da.timeIntervalSince1970)),
                         "period2": String(Int(a.timeIntervalSince1970)),
                         "interval": "1d"]
        guard let d = await scarica(urlGrafico(ticker, parametri)) else { return [] }
        return CalcoliInvestimenti.chiusure(daGrafico: d)
    }

    /// Chiusura del giorno (o dell'ultimo giorno di borsa precedente).
    static func prezzo(_ ticker: String, al data: Date) async -> Double? {
        let giorno = calendario.startOfDay(for: data)
        let c = await chiusureGiornaliere(ticker, da: giorno.aggiungendo(giorni: -10), a: giorno.aggiungendo(giorni: 1))
        return CalcoliInvestimenti.chiusura(c, al: giorno)
    }

    /// Storico mensile a 5 anni (per i grafici), con cache di 12 ore nella cartella Caches.
    static func storicoMensile(_ ticker: String) async -> [Chiusura] {
        let nomeFile = "storico-" + ticker.map { $0.isLetter || $0.isNumber || $0 == "." ? String($0) : "_" }.joined() + ".json"
        let file = URL.cachesDirectory.appending(path: nomeFile)
        func daCache() -> [Chiusura]? {
            guard let d = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode([Chiusura].self, from: d)
        }
        if let attributi = try? FileManager.default.attributesOfItem(atPath: file.path),
           let modificato = attributi[.modificationDate] as? Date,
           Date().timeIntervalSince(modificato) < 12 * 3600,
           let c = daCache() {
            return c
        }
        if let d = await scarica(urlGrafico(ticker, ["range": "5y", "interval": "1mo"])) {
            let c = CalcoliInvestimenti.mensili(CalcoliInvestimenti.chiusure(daGrafico: d))
            if !c.isEmpty {
                try? JSONEncoder().encode(c).write(to: file, options: .completeFileProtection)   // il nome del file dice cosa possiedi
                return c
            }
        }
        return daCache() ?? []
    }

    // MARK: - Cambi BCE

    /// 1 unità di `valuta` = x euro, all'ultimo fixing BCE o a una data (fixing del giorno lavorativo precedente).
    static func cambio(_ valuta: String, al data: Date? = nil) async -> Double? {
        if valuta == "EUR" { return 1 }
        let giorno = data.map { d in
            let c = calendario.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        } ?? "latest"
        let url1 = URL(string: "https://api.frankfurter.dev/v1/\(giorno)?base=\(valuta)&symbols=EUR")
        let url2 = URL(string: "https://api.frankfurter.app/\(giorno)?from=\(valuta)&to=EUR")
        for url in [url1, url2] {
            if let d = await scarica(url), let r = try? JSONDecoder().decode(RispostaCambio.self, from: d), let eur = r.rates["EUR"], eur > 0 {
                return eur
            }
        }
        return nil
    }

    private struct RispostaCambio: Decodable { let rates: [String: Double] }

    // MARK: - Rete

    private static func urlRicerca(_ testo: String) -> URL? {
        var c = URLComponents(string: "https://query2.finance.yahoo.com/v1/finance/search")
        c?.queryItems = [URLQueryItem(name: "q", value: testo),
                         URLQueryItem(name: "quotesCount", value: "10"),
                         URLQueryItem(name: "newsCount", value: "0")]
        return c?.url
    }

    private static func urlGrafico(_ ticker: String, _ parametri: [String: String]) -> URL? {
        guard let simbolo = ticker.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var c = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(simbolo)")
        c?.queryItems = parametri.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c?.url
    }

    private static func scarica(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        var richiesta = URLRequest(url: url, timeoutInterval: 10)
        // User-Agent generico: con quello completo di un browser Yahoo risponde 429 (verificato con curl)
        richiesta.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (dati, risposta) = try? await URLSession.senzaTracce.data(for: richiesta),
              (risposta as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return dati
    }
}
