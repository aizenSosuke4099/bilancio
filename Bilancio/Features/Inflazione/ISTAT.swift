import Foundation

/// Indice NIC dell'ISTAT (prezzi al consumo per l'intera collettività, base 2015 = 100), mensile.
/// Scaricato dal servizio SDMX dell'ISTAT (lento: ~15 s) al massimo una volta al giorno e conservato per l'uso offline.
enum ISTAT {
    private static let chiave = "istat.nic"
    private static let chiaveAggiornamento = "istat.nic.aggiornatoIl"
    private static let indirizzo = "https://esploradati.istat.it/SDMXWS/rest/data/IT1,167_744,1.0/M.IT.39.4.00?startPeriod=2016-01"

    /// "2025-12" → 122.6
    static var indice: [String: Double] { (UserDefaults.standard.dictionary(forKey: chiave) as? [String: Double]) ?? [:] }

    static func aggiornaSeServe() async {
        if let u = UserDefaults.standard.object(forKey: chiaveAggiornamento) as? Date,
           Date().timeIntervalSince(u) < 86_400, !indice.isEmpty { return }
        var richiesta = URLRequest(url: URL(string: indirizzo)!, timeoutInterval: 90)
        richiesta.setValue("application/vnd.sdmx.data+csv;version=1.0.0", forHTTPHeaderField: "Accept")
        guard let r = try? await URLSession.shared.data(for: richiesta), (r.1 as? HTTPURLResponse)?.statusCode == 200 else { return }
        let valori = leggiCSV(String(decoding: r.0, as: UTF8.self))
        guard !valori.isEmpty else { return }   // offline o risposta strana: si tengono i dati vecchi
        UserDefaults.standard.set(valori, forKey: chiave)
        UserDefaults.standard.set(Date(), forKey: chiaveAggiornamento)
    }

    /// CSV SDMX: le colonne TIME_PERIOD e OBS_VALUE si trovano dall'intestazione.
    nonisolated static func leggiCSV(_ testo: String) -> [String: Double] {
        let righe = testo.split(whereSeparator: \.isNewline).map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        guard let testa = righe.first, let cPeriodo = testa.firstIndex(of: "TIME_PERIOD"), let cValore = testa.firstIndex(of: "OBS_VALUE") else { return [:] }
        var valori: [String: Double] = [:]
        for r in righe.dropFirst() where r.count > max(cPeriodo, cValore) {
            if let v = Double(r[cValore]), v > 0 { valori[r[cPeriodo]] = v }
        }
        return valori
    }

    static func chiaveMese(_ d: Date) -> String {
        let c = calendario.dateComponents([.year, .month], from: d)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func mese(_ chiave: String) -> Date? {
        let p = chiave.split(separator: "-").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        return calendario.date(from: DateComponents(year: p[0], month: p[1], day: 1))
    }

    /// Inflazione ufficiale dell'ultimo mese pubblicato: indice contro lo stesso mese dell'anno prima.
    static func ultimaVariazioneAnnua(_ valori: [String: Double] = indice) -> (mese: Date, valore: Double)? {
        for k in valori.keys.sorted(by: >) {
            guard let m = mese(k), let ora = valori[k], let prima = valori[chiaveMese(m.aggiungendo(mesi: -12))], prima > 0 else { continue }
            return (m, ora / prima - 1)
        }
        return nil
    }

    /// Indice ISTAT riportato a 100 nel primo dei `mesi` (i mesi non ancora pubblicati restano fuori).
    static func serie(mesi: [Date], valori: [String: Double] = indice) -> [(mese: Date, indice: Double)] {
        guard let base = mesi.lazy.compactMap({ valori[chiaveMese($0)] }).first else { return [] }
        return mesi.compactMap { m in valori[chiaveMese(m)].map { (mese: m, indice: $0 / base * 100) } }
    }

    #if DEBUG
    static func autoverifica() {
        let v = leggiCSV("DATAFLOW,TIME_PERIOD,OBS_VALUE\nIT1:167_744(1.0),2024-12,121.2\nIT1:167_744(1.0),2025-12,122.6\nx,2026-01,\n")
        assert(v == ["2024-12": 121.2, "2025-12": 122.6])
        let u = ultimaVariazioneAnnua(v)
        assert(u.map { chiaveMese($0.mese) } == "2025-12" && abs((u?.valore ?? 0) - (122.6 / 121.2 - 1)) < 1e-9)
        let mesi = [mese("2024-12")!, mese("2025-06")!, mese("2025-12")!]
        let s = serie(mesi: mesi, valori: v)
        assert(s.count == 2 && s[0].indice == 100 && abs(s[1].indice - 122.6 / 121.2 * 100) < 1e-9)
    }
    #endif
}
