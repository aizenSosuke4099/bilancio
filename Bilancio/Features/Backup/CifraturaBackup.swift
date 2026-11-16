import Foundation
import CryptoKit
import CommonCrypto

/// Backup esportato protetto da password. Ogni file della cartella di backup diventa `<nome>.enc`, cifrato con
/// AES-256-GCM (nonce 12 byte | testo cifrato | tag 16 byte); la chiave nasce dalla password con PBKDF2-HMAC-SHA256
/// (600.000 iterazioni, sale casuale di 16 byte). Parametri in `cifratura.json`; `LEGGIMI.txt` resta in chiaro e
/// spiega come decifrare, anche fuori da iOS (es. Android: javax.crypto PBKDF2WithHmacSHA256 + AES/GCM/NoPadding).
enum CifraturaBackup {
    nonisolated static let fileParametri = "cifratura.json"
    nonisolated static let iterazioni = 600_000
    static let lunghezzaMinima = 8

    nonisolated struct Parametri: Codable {
        var formato = "bilancio-backup-cifrato"
        var versione = 1
        var kdf = "PBKDF2-HMAC-SHA256"
        var iterazioni: Int
        /// Base64.
        var sale: String
        var cifrario = "AES-256-GCM: nonce (12 byte) | testo cifrato | tag (16 byte)"
        /// "bilancio" cifrato con la stessa chiave (base64): riconosce subito una password sbagliata.
        var verifica: String
    }

    nonisolated enum Errore: LocalizedError {
        case serveLaPassword, passwordSbagliata, formato
        var errorDescription: String? {
            switch self {
            case .serveLaPassword: String(localized: "Questo backup è protetto da password.")
            case .passwordSbagliata: String(localized: "Password sbagliata.")
            case .formato: String(localized: "Il file cifratura.json non è leggibile da questa versione dell'app.")
            }
        }
    }

    nonisolated static func èCifrato(_ cartella: URL) -> Bool {
        FileManager.default.fileExists(atPath: cartella.appending(path: fileParametri).path)
    }

    nonisolated static func chiave(password: String, sale: Data, iterazioni: Int) -> SymmetricKey {
        var chiave = [UInt8](repeating: 0, count: 32)
        let sale = [UInt8](sale)
        let esito = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count, sale, sale.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterazioni), &chiave, chiave.count)
        precondition(esito == kCCSuccess, "PBKDF2 non riuscito")
        return SymmetricKey(data: chiave)
    }

    /// Copia cifrata di `sorgente` (cartella di backup in chiaro) dentro `destinazione` (creata qui).
    nonisolated static func cifra(_ sorgente: URL, in destinazione: URL, password: String, iterazioni: Int = iterazioni) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destinazione, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let sale = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })   // generatore di sistema, crittografico
        let k = chiave(password: password, sale: sale, iterazioni: iterazioni)
        for (relativo, url) in file(in: sorgente) {
            let dati = try Data(contentsOf: url)
            if relativo == "LEGGIMI.txt" {
                try Data((String(decoding: dati, as: UTF8.self) + leggimi).utf8).write(to: destinazione.appending(path: relativo))
                continue
            }
            let uscita = destinazione.appending(path: relativo + ".enc")
            try fm.createDirectory(at: uscita.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AES.GCM.seal(dati, using: k).combined!.write(to: uscita)
        }
        let verifica = try AES.GCM.seal(Data("bilancio".utf8), using: k).combined!
        let p = Parametri(iterazioni: iterazioni, sale: sale.base64EncodedString(), verifica: verifica.base64EncodedString())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(p).write(to: destinazione.appending(path: fileParametri))
    }

    /// Decifra `sorgente` (backup cifrato) dentro `destinazione` (creata qui): torna una normale cartella di backup.
    nonisolated static func decifra(_ sorgente: URL, in destinazione: URL, password: String) throws {
        let fm = FileManager.default
        guard let p = try? JSONDecoder().decode(Parametri.self, from: Data(contentsOf: sorgente.appending(path: fileParametri))),
              p.formato == "bilancio-backup-cifrato", p.versione == 1, (1_000...10_000_000).contains(p.iterazioni),
              let sale = Data(base64Encoded: p.sale),
              let verifica = Data(base64Encoded: p.verifica) else { throw Errore.formato }
        let k = chiave(password: password, sale: sale, iterazioni: p.iterazioni)
        guard (try? AES.GCM.open(AES.GCM.SealedBox(combined: verifica), using: k)) == Data("bilancio".utf8) else {
            throw Errore.passwordSbagliata
        }
        try fm.createDirectory(at: destinazione, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        for (relativo, url) in file(in: sorgente) where relativo.hasSuffix(".enc") {
            let uscita = destinazione.appending(path: String(relativo.dropLast(4)))
            try fm.createDirectory(at: uscita.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AES.GCM.open(AES.GCM.SealedBox(combined: Data(contentsOf: url)), using: k).write(to: uscita)
        }
    }

    /// File regolari di una cartella con il percorso relativo ("foto/scontrino-1.jpg").
    nonisolated private static func file(in cartella: URL) -> [(String, URL)] {
        let base = cartella.standardizedFileURL.path + "/"
        let e = FileManager.default.enumerator(at: cartella, includingPropertiesForKeys: [.isRegularFileKey])
        var risultato: [(String, URL)] = []
        while let f = e?.nextObject() as? URL {
            guard (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            risultato.append((String(f.standardizedFileURL.path.dropFirst(base.count)), f))
        }
        return risultato
    }

    nonisolated static let leggimi = """


    ----
    BACKUP PROTETTO DA PASSWORD / PASSWORD-PROTECTED BACKUP

    Ogni file è <nome>.enc: AES-256-GCM, contenuto = nonce (12 byte) | testo cifrato | tag (16 byte).
    Chiave (32 byte) = PBKDF2-HMAC-SHA256(password in UTF-8, sale, iterazioni) con sale e iterazioni in cifratura.json.
    "verifica" in cifratura.json è la parola "bilancio" cifrata con la stessa chiave: serve a controllare la password.
    Senza la password i dati non si possono leggere.

    Every file is <name>.enc: AES-256-GCM, content = nonce (12 bytes) | ciphertext | tag (16 bytes).
    Key (32 bytes) = PBKDF2-HMAC-SHA256(UTF-8 password, salt, iterations), salt and iterations in cifratura.json.
    Without the password the data cannot be read.
    """

    #if DEBUG
    /// Avvio con `-verifica`: cifra e decifra una cartella di prova; password sbagliata rifiutata; niente testo in chiaro.
    static func autoverifica() {
        let fm = FileManager.default
        let radice = fm.temporaryDirectory.appending(path: "verifica-cifratura-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: radice) }
        let chiaro = radice.appending(path: "chiaro"), cifrato = radice.appending(path: "cifrato"), di_nuovo = radice.appending(path: "decifrato")
        try! fm.createDirectory(at: chiaro.appending(path: "foto"), withIntermediateDirectories: true)
        let segreto = Data("{\"iban\":\"IT00X0000000000000000000000\"}".utf8)
        try! segreto.write(to: chiaro.appending(path: "bilancio.json"))
        try! Data([0xFF, 0xD8, 1, 2, 3]).write(to: chiaro.appending(path: "foto/scontrino-1.jpg"))
        try! Data("Leggimi".utf8).write(to: chiaro.appending(path: "LEGGIMI.txt"))

        try! cifra(chiaro, in: cifrato, password: "una password lunga", iterazioni: 10_000)
        assert(èCifrato(cifrato))
        let cifrati = file(in: cifrato).map(\.0).sorted()
        assert(cifrati == ["LEGGIMI.txt", "bilancio.json.enc", "cifratura.json", "foto/scontrino-1.jpg.enc"], "\(cifrati)")
        let blob = try! Data(contentsOf: cifrato.appending(path: "bilancio.json.enc"))
        assert(blob.range(of: Data("IT00X".utf8)) == nil && blob.count == segreto.count + 28)

        do { try decifra(cifrato, in: radice.appending(path: "sbagliata"), password: "un'altra password"); assertionFailure("password sbagliata accettata") }
        catch Errore.passwordSbagliata {} catch { assertionFailure("\(error)") }

        try! decifra(cifrato, in: di_nuovo, password: "una password lunga")
        assert(try! Data(contentsOf: di_nuovo.appending(path: "bilancio.json")) == segreto)
        assert(try! Data(contentsOf: di_nuovo.appending(path: "foto/scontrino-1.jpg")) == Data([0xFF, 0xD8, 1, 2, 3]))
        print("CifraturaBackup.autoverifica OK")
    }
    #endif
}
