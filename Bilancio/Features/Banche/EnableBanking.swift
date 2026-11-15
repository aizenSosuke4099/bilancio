import Foundation
import Security

// Client minimo per l'API Enable Banking (PSD2, accesso ai conti).
// Documentazione: https://enablebanking.com/docs/api/reference/
// Autenticazione: JWT RS256 firmato con la chiave privata dell'applicazione (header kid = application id),
// iss "enablebanking.com", aud "api.enablebanking.com", durata massima 24 h (qui 1 h).

enum EnableBanking {

    static let baseURL = URL(string: "https://api.enablebanking.com")!

    // MARK: Risposte dell'API (solo i campi che usiamo)

    nonisolated struct ASPSP: Decodable, Identifiable, Hashable {
        let name: String
        let country: String
        let logo: String?
        let psu_types: [String]?
        /// Durata massima del consenso, in secondi.
        let maximum_consent_validity: Int?
        let beta: Bool?
        var id: String { country + "/" + name }
    }

    nonisolated struct IdentificativoConto: Decodable, Hashable {
        let iban: String?
        let other: Altro?
        nonisolated struct Altro: Decodable, Hashable { let identification: String? }
    }

    nonisolated struct ContoEB: Decodable, Identifiable, Hashable {
        let uid: String?
        let account_id: IdentificativoConto?
        let name: String?
        let details: String?
        let product: String?
        let currency: String?
        let cash_account_type: String?
        var id: String { uid ?? UUID().uuidString }
        var iban: String? { account_id?.iban ?? account_id?.other?.identification }
        /// Nome leggibile: prodotto, dettagli, IBAN; il "nome" per ultimo perché alcune banche ci mettono l'intestatario.
        var descrizione: String {
            [product, details].compactMap { $0 }.first { !$0.isEmpty } ?? iban ?? name ?? String(localized: "Conto")
        }
    }

    nonisolated struct Accesso: Decodable { let valid_until: String? }
    nonisolated struct AspspRef: Decodable { let name: String; let country: String }

    nonisolated struct Sessione: Decodable {
        let session_id: String
        let accounts: [ContoEB]
        let aspsp: AspspRef?
        let access: Accesso?
    }

    nonisolated struct Importo: Decodable { let currency: String?; let amount: String }

    nonisolated struct Saldo: Decodable {
        let name: String?
        let balance_amount: Importo
        let balance_type: String?
        let reference_date: String?
        let last_change_date_time: String?
    }

    nonisolated struct Parte: Decodable { let name: String? }
    nonisolated struct CodiceTransazione: Decodable { let description: String? }

    nonisolated struct Transazione: Decodable {
        let entry_reference: String?
        let transaction_id: String?
        let transaction_amount: Importo
        let creditor: Parte?
        let debtor: Parte?
        let credit_debit_indicator: String?
        let status: String?
        let booking_date: String?
        let value_date: String?
        let transaction_date: String?
        let remittance_information: [String]?
        let bank_transaction_code: CodiceTransazione?
        let note: String?

        /// Importo con segno: DBIT → uscita (negativo), CRDT → entrata.
        var importoConSegno: Double {
            let v = Double(transaction_amount.amount) ?? 0
            switch credit_debit_indicator {
            case "DBIT": return -abs(v)
            case "CRDT": return abs(v)
            default: return v
            }
        }

        /// Testo per classificare: controparte + causale + codice operazione (senza ripetizioni).
        var descrizione: String {
            let controparte = credit_debit_indicator == "CRDT" ? debtor?.name : creditor?.name
            var parti: [String] = []
            for p in [controparte] + (remittance_information ?? []).map(Optional.some) + [note, bank_transaction_code?.description] {
                guard let t = p?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
                      !parti.contains(where: { $0.localizedCaseInsensitiveContains(t) }) else { continue }
                // "ESSELUNGA" + "PAGAMENTO POS ESSELUNGA MILANO" → solo il secondo
                if let i = parti.firstIndex(where: { t.localizedCaseInsensitiveContains($0) }) { parti[i] = t } else { parti.append(t) }
            }
            return parti.joined(separator: " ")
        }

        var data: Date? { (booking_date ?? value_date ?? transaction_date).flatMap(EnableBanking.giorno(da:)) }
    }

    nonisolated struct PaginaTransazioni: Decodable {
        let transactions: [Transazione]
        let continuation_key: String?
    }

    nonisolated struct RispostaErrore: Decodable { let message: String?; let error: String?; let code: Int? }

    enum Errore: LocalizedError {
        case credenzialiMancanti
        case chiaveNonValida(String)
        case api(Int, String)

        var errorDescription: String? {
            switch self {
            case .credenzialiMancanti: String(localized: "Imposta Application ID e chiave privata di Enable Banking.")
            case .chiaveNonValida(let m): String(localized: "Chiave privata non valida: \(m)")
            case .api(let codice, let m): "Enable Banking (\(codice)): \(m)"
            }
        }
    }

    // MARK: Endpoint

    static func banche(paese: String = "IT") async throws -> [ASPSP] {
        nonisolated struct R: Decodable { let aspsps: [ASPSP] }
        let r: R = try await chiama("GET", "/aspsps", query: ["country": paese, "psu_type": "personal"])
        return r.aspsps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Avvia il consenso: restituisce l'URL della banca da aprire.
    static func avviaAutorizzazione(banca: ASPSP, validoFino: Date, redirectURL: String, state: String) async throws -> URL {
        nonisolated struct R: Decodable { let url: String }
        let corpo: [String: Any] = [
            "access": ["valid_until": rfc3339(validoFino)],
            "aspsp": ["name": banca.name, "country": banca.country],
            "state": state,
            "redirect_url": redirectURL,
            "psu_type": "personal",
            "language": "it",
        ]
        let r: R = try await chiama("POST", "/auth", corpo: corpo)
        guard let url = URL(string: r.url) else { throw Errore.api(0, String(localized: "URL di autorizzazione non valido")) }
        return url
    }

    static func creaSessione(codice: String) async throws -> Sessione {
        try await chiama("POST", "/sessions", corpo: ["code": codice])
    }

    static func eliminaSessione(_ id: String) async throws {
        nonisolated struct R: Decodable { let message: String? }
        let _: R = try await chiama("DELETE", "/sessions/\(id)")
    }

    /// `presente`: l'utente sta usando l'app (non è un aggiornamento in background), vedi `intestazioniPSU`.
    static func saldi(conto uid: String, presente: Bool) async throws -> [Saldo] {
        nonisolated struct R: Decodable { let balances: [Saldo] }
        let r: R = try await chiama("GET", "/accounts/\(uid)/balances", presente: presente)
        return r.balances
    }

    /// Tutte le transazioni dal giorno indicato (segue continuation_key).
    static func transazioni(conto uid: String, dal: Date, presente: Bool) async throws -> [Transazione] {
        var tutte: [Transazione] = []
        var chiave: String?
        for _ in 0..<50 { // ponytail: tetto alle pagine per non girare all'infinito su una banca che sbaglia
            var q = ["date_from": giornoISO(dal)]
            if let chiave { q["continuation_key"] = chiave }
            let p: PaginaTransazioni = try await chiama("GET", "/accounts/\(uid)/transactions", query: q, presente: presente)
            tutte += p.transactions
            guard let k = p.continuation_key, !k.isEmpty else { break }
            chiave = k
        }
        return tutte
    }

    /// Saldo da mostrare: contabile di chiusura, poi disponibile infragiornaliero, poi previsto.
    static func saldoPreferito(_ saldi: [Saldo]) -> Saldo? {
        let ordine = ["CLBD", "ITAV", "XPCD", "ITBD", "CLAV", "OPBD", "OPAV"]
        return saldi.min { (ordine.firstIndex(of: $0.balance_type ?? "") ?? 99) < (ordine.firstIndex(of: $1.balance_type ?? "") ?? 99) }
    }

    // MARK: HTTP

    /// Intestazioni PSU: dicono alla banca che l'utente sta usando l'app, così non vale il limite di ~4 letture
    /// al giorno degli aggiornamenti in background (errore 429 ASPSP_RATE_LIMIT_EXCEEDED). Mai in background.
    static func intestazioniPSU() -> [String: String] {
        var h = ["Psu-User-Agent": "Bilancio/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1") (iOS \(ProcessInfo.processInfo.operatingSystemVersionString))"]
        if let ip = indirizzoIP() { h["Psu-Ip-Address"] = ip }
        return h
    }

    /// IPv4 del Wi-Fi o della rete cellulare.
    // ponytail: indirizzo dell'interfaccia (in Wi-Fi è privato); se una banca pretendesse l'IP pubblico servirebbe chiederlo a un servizio esterno
    static func indirizzoIP() -> String? {
        var lista: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&lista) == 0, let primo = lista else { return nil }
        defer { freeifaddrs(lista) }
        var trovati: [String: String] = [:]
        for p in sequence(first: primo, next: { $0.pointee.ifa_next }) {
            guard let a = p.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(a, socklen_t(a.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            trovati[String(cString: p.pointee.ifa_name)] = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return trovati["en0"] ?? trovati["pdp_ip0"] ?? trovati.first { $0.key != "lo0" }?.value
    }

    private static func chiama<T: Decodable>(_ metodo: String, _ percorso: String, query: [String: String] = [:], corpo: [String: Any]? = nil,
                                             presente: Bool = false) async throws -> T {
        guard let appId = CredenzialiEnableBanking.applicationId, let pem = CredenzialiEnableBanking.chiavePrivata else {
            throw Errore.credenzialiMancanti
        }
        var comp = URLComponents(url: baseURL.appending(path: percorso), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comp.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comp.url!, timeoutInterval: 60)
        req.httpMethod = metodo
        req.setValue("Bearer " + (try jwt(applicationId: appId, chiavePEM: pem)), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if presente { for (k, v) in intestazioniPSU() { req.setValue(v, forHTTPHeaderField: k) } }
        if let corpo {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: corpo)
        }
        let (dati, risposta) = try await URLSession.shared.data(for: req)
        let stato = (risposta as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(stato) else {
            let e = try? JSONDecoder().decode(RispostaErrore.self, from: dati)
            let testo = [e?.error, e?.message].compactMap { $0 }.joined(separator: " – ")
            throw Errore.api(stato, testo.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: stato) : testo)
        }
        return try JSONDecoder().decode(T.self, from: dati)
    }

    // MARK: JWT RS256

    /// JWT per l'header Authorization. `ora` è parametrico per il self-check.
    static func jwt(applicationId: String, chiavePEM: String, ora: Date = Date()) throws -> String {
        let iat = Int(ora.timeIntervalSince1970)
        let header: [String: Any] = ["typ": "JWT", "alg": "RS256", "kid": applicationId]
        let payload: [String: Any] = ["iss": "enablebanking.com", "aud": "api.enablebanking.com", "iat": iat, "exp": iat + 3600]
        let h = base64URL(try JSONSerialization.data(withJSONObject: header, options: .sortedKeys))
        let p = base64URL(try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys))
        let daFirmare = Data((h + "." + p).utf8)
        let chiave = try chiaveRSA(pem: chiavePEM)
        var errore: Unmanaged<CFError>?
        guard let firma = SecKeyCreateSignature(chiave, .rsaSignatureMessagePKCS1v15SHA256, daFirmare as CFData, &errore) as Data? else {
            throw Errore.chiaveNonValida(errore?.takeRetainedValue().localizedDescription ?? String(localized: "firma non riuscita"))
        }
        return h + "." + p + "." + base64URL(firma)
    }

    static func base64URL(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// Chiave privata RSA da PEM, PKCS#1 ("BEGIN RSA PRIVATE KEY") o PKCS#8 ("BEGIN PRIVATE KEY").
    /// Security vuole PKCS#1: da un PKCS#8 si estrae l'OCTET STRING interno.
    static func chiaveRSA(pem: String) throws -> SecKey {
        if pem.contains("ENCRYPTED") { throw Errore.chiaveNonValida(String(localized: "la chiave è protetta da password: esportala senza password")) }
        let b64 = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()
        guard var der = Data(base64Encoded: b64, options: .ignoreUnknownCharacters), !der.isEmpty else {
            throw Errore.chiaveNonValida(String(localized: "formato PEM non riconosciuto"))
        }
        if let interna = pkcs1DaPKCS8(der) { der = interna }
        let attributi: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate]
        var errore: Unmanaged<CFError>?
        guard let chiave = SecKeyCreateWithData(der as CFData, attributi as CFDictionary, &errore) else {
            throw Errore.chiaveNonValida(errore?.takeRetainedValue().localizedDescription ?? String(localized: "chiave RSA non leggibile"))
        }
        return chiave
    }

    /// PKCS#8 = SEQUENCE { INTEGER versione, SEQUENCE algoritmo, OCTET STRING pkcs1 }.
    /// In un PKCS#1 il secondo elemento è un INTEGER (modulo): in quel caso restituisce nil.
    private static func pkcs1DaPKCS8(_ der: Data) -> Data? {
        let b = [UInt8](der)
        var i = 0
        func elemento() -> (tag: UInt8, inizio: Int, fine: Int)? {
            guard i + 2 <= b.count else { return nil }
            let tag = b[i]
            var lunghezza = Int(b[i + 1])
            var pos = i + 2
            if lunghezza & 0x80 != 0 {
                let n = lunghezza & 0x7F
                guard n > 0, n <= 4, pos + n <= b.count else { return nil }
                lunghezza = b[pos..<pos + n].reduce(0) { $0 << 8 | Int($1) }
                pos += n
            }
            guard pos + lunghezza <= b.count else { return nil }
            return (tag, pos, pos + lunghezza)
        }
        guard let seq = elemento(), seq.tag == 0x30 else { return nil }
        i = seq.inizio
        guard let versione = elemento(), versione.tag == 0x02 else { return nil }
        i = versione.fine
        guard let algoritmo = elemento(), algoritmo.tag == 0x30 else { return nil }
        i = algoritmo.fine
        guard let ottetti = elemento(), ottetti.tag == 0x04 else { return nil }
        return Data(b[ottetti.inizio..<ottetti.fine])
    }

    // MARK: Date

    /// "2027-05-13T10:00:00+00:00" (RFC 3339 con offset, come chiede /auth).
    nonisolated static func rfc3339(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'+00:00'"
        return f.string(from: d)
    }

    /// Legge date-time ISO 8601 anche con microsecondi ("…T10:00:00.123456+00:00").
    nonisolated static func dataOra(da s: String) -> Date? {
        let senzaFrazione = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: senzaFrazione)
    }

    /// "2026-11-03" → mezzanotte locale di quel giorno.
    nonisolated static func giorno(da s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    nonisolated static func giornoISO(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

// MARK: - Credenziali nel Portachiavi

/// Application ID e chiave privata stanno nel Portachiavi (mai in UserDefaults),
/// leggibili anche in background dopo il primo sblocco, mai copiati su altri dispositivi.
enum CredenzialiEnableBanking {
    private static let servizio = "bilancio.enablebanking"

    static var applicationId: String? {
        get { leggi("applicationId") }
        set { scrivi("applicationId", newValue) }
    }

    static var chiavePrivata: String? {
        get { leggi("chiavePrivata") }
        set { scrivi("chiavePrivata", newValue) }
    }

    static var complete: Bool { !(applicationId ?? "").isEmpty && chiavePrivata != nil }

    private static func base(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: servizio, kSecAttrAccount: account]
    }

    private static func leggi(_ account: String) -> String? {
        var q = base(account)
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var risultato: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &risultato) == errSecSuccess, let d = risultato as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func scrivi(_ account: String, _ valore: String?) {
        SecItemDelete(base(account) as CFDictionary)
        guard let valore, !valore.isEmpty else { return }
        var q = base(account)
        q[kSecValueData] = Data(valore.utf8)
        q[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}

// MARK: - Self-check della firma JWT
// Esegui dalla radice del progetto:
//   swiftc -D VERIFICA_JWT -parse-as-library Bilancio/Features/Banche/EnableBanking.swift -o /tmp/verifica_jwt && /tmp/verifica_jwt
// Genera chiavi RSA di prova con openssl (PKCS#1 e PKCS#8), firma un JWT e verifica la firma con SecKeyVerifySignature.
#if VERIFICA_JWT
@main enum VerificaJWT {
    static func shell(_ comando: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", comando]
        let pipe = Pipe()
        p.standardOutput = pipe
        try! p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
    }

    static func main() throws {
        let cartella = FileManager.default.temporaryDirectory.appending(path: "verifica_jwt_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        let pkcs1 = cartella.appending(path: "k1.pem").path
        _ = shell("openssl genrsa -traditional -out '\(pkcs1)' 2048 2>/dev/null || openssl genrsa -out '\(pkcs1)' 2048 2>/dev/null")
        let pemPKCS1 = shell("cat '\(pkcs1)'")
        let pemPKCS8 = shell("openssl pkcs8 -topk8 -nocrypt -in '\(pkcs1)'")
        assert(pemPKCS1.contains("BEGIN RSA PRIVATE KEY"), "attesa chiave PKCS#1")
        assert(pemPKCS8.contains("BEGIN PRIVATE KEY"), "attesa chiave PKCS#8")

        let ora = Date(timeIntervalSince1970: 1_800_000_000)
        for pem in [pemPKCS1, pemPKCS8] {
            let token = try EnableBanking.jwt(applicationId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", chiavePEM: pem, ora: ora)
            let parti = token.split(separator: ".").map(String.init)
            precondition(parti.count == 3)
            func decodifica(_ s: String) -> Data {
                var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                while b.count % 4 != 0 { b += "=" }
                return Data(base64Encoded: b)!
            }
            let header = try JSONSerialization.jsonObject(with: decodifica(parti[0])) as! [String: Any]
            let payload = try JSONSerialization.jsonObject(with: decodifica(parti[1])) as! [String: Any]
            precondition(header["alg"] as? String == "RS256" && header["typ"] as? String == "JWT")
            precondition(header["kid"] as? String == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
            precondition(payload["iss"] as? String == "enablebanking.com" && payload["aud"] as? String == "api.enablebanking.com")
            precondition(payload["iat"] as? Int == 1_800_000_000 && payload["exp"] as? Int == 1_800_003_600)
            let pubblica = SecKeyCopyPublicKey(try EnableBanking.chiaveRSA(pem: pem))!
            var errore: Unmanaged<CFError>?
            let ok = SecKeyVerifySignature(pubblica, .rsaSignatureMessagePKCS1v15SHA256,
                                           Data((parti[0] + "." + parti[1]).utf8) as CFData, decodifica(parti[2]) as CFData, &errore)
            precondition(ok, "firma non valida")
            // verifica anche con openssl, indipendente da Security
            let base = cartella.appending(path: UUID().uuidString).path
            try Data((parti[0] + "." + parti[1]).utf8).write(to: URL(fileURLWithPath: base + ".txt"))
            try decodifica(parti[2]).write(to: URL(fileURLWithPath: base + ".sig"))
            let esito = shell("openssl rsa -in '\(pkcs1)' -pubout -out '\(base).pub' 2>/dev/null; openssl dgst -sha256 -verify '\(base).pub' -signature '\(base).sig' '\(base).txt'")
            precondition(esito.contains("Verified OK"), "openssl: \(esito)")
        }
        // una chiave cifrata va rifiutata con un messaggio chiaro
        do { _ = try EnableBanking.chiaveRSA(pem: "-----BEGIN ENCRYPTED PRIVATE KEY-----\nAAAA\n-----END ENCRYPTED PRIVATE KEY-----"); preconditionFailure() } catch {}
        precondition(EnableBanking.rfc3339(Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00+00:00")
        precondition(EnableBanking.dataOra(da: "2027-05-13T10:00:00.123456+00:00") == Date(timeIntervalSince1970: 1_810_202_400))
        try? FileManager.default.removeItem(at: cartella)
        print("JWT OK: PKCS#1 e PKCS#8 firmano, la firma è verificata da Security e da openssl")
    }
}
#endif
