import Foundation

/// Calcoli puri dei consigli (solo Foundation, niente SwiftData): così si verificano con `autoverifica()`.
/// Verifica da terminale:
///   swiftc -D DEBUG Bilancio/Features/Consigli/CalcoliConsigli.swift <main.swift con `CalcoliConsigli.autoverifica()`>
enum CalcoliConsigli {
    static let franchigia730 = 129.11
    static let aliquotaDetrazione = 0.19
    static let massimoDeducibileFondoPensione = 5164.57

    /// Variazione relativa: 100 → 138 = 0,38. nil se la base è zero.
    static func variazione(da base: Double, a valore: Double) -> Double? {
        guard base != 0 else { return nil }
        return (valore - base) / abs(base)
    }

    /// Spesa prevista a fine mese proseguendo al ritmo medio giornaliero.
    // ponytail: proiezione lineare, sovrastima se le spese grosse (affitto) cadono a inizio mese; escludere le ricorrenti se serve più precisione.
    static func proiezioneFineMese(spesaFinora: Double, giorno: Int, giorniNelMese: Int) -> Double {
        guard giorno > 0 else { return spesaFinora }
        return spesaFinora / Double(giorno) * Double(giorniNelMese)
    }

    /// Detrazione IRPEF stimata nel 730: 19% della parte che supera la franchigia di 129,11 €.
    // ponytail: la franchigia vale per le spese sanitarie; qui si applica al totale detraibile (stima prudente).
    static func detrazione730(spese: Double) -> Double {
        max(0, spese - franchigia730) * aliquotaDetrazione
    }

    /// Quanto si può ancora versare nei fondi pensione italiani restando deducibili.
    static func residuoDeducibile(versato: Double) -> Double {
        max(0, massimoDeducibileFondoPensione - versato)
    }

    /// Media delle variazioni di prezzo (primo → ultimo acquisto) pesata sulla spesa per prodotto.
    static func inflazionePersonale(_ campioni: [(primo: Double, ultimo: Double, peso: Double)]) -> Double? {
        let validi = campioni.filter { $0.primo > 0 && $0.peso > 0 }
        let pesoTotale = validi.reduce(0) { $0 + $1.peso }
        guard pesoTotale > 0 else { return nil }
        return validi.reduce(0) { $0 + ($1.ultimo / $1.primo - 1) * $1.peso } / pesoTotale
    }

    /// Interessi lordi di un mese su un conto remunerato (tasso annuo in %).
    static func interessiMensili(saldo: Double, tassoAnnuo: Double) -> Double {
        max(0, saldo) * tassoAnnuo / 100 / 12
    }

    /// Articolo davanti a un numero ("il 33%", "l'8%", "l'11%"): si elide davanti a 1, 8, 11, 18, 80–89.
    static func conArticolo(_ numero: String, normale: String = "il ", eliso: String = "l'") -> String {
        let intero = Int(numero.prefix { $0.isNumber }) ?? 0
        let vocale = [1, 8, 11, 18].contains(intero) || (80...89).contains(intero) || (800...899).contains(intero)
        return (vocale ? eliso : normale) + numero
    }

    #if DEBUG
    /// Self-check dei calcoli chiave: si ferma se una formula si rompe.
    static func autoverifica() {
        func circa(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 0.005 } ?? false }
        // proiezione: 600 € in 10 giorni su 30 → 1.800 €
        precondition(circa(proiezioneFineMese(spesaFinora: 600, giorno: 10, giorniNelMese: 30), 1800))
        precondition(circa(proiezioneFineMese(spesaFinora: 0, giorno: 14, giorniNelMese: 30), 0))
        // 730: 19% oltre 129,11 €
        precondition(circa(detrazione730(spese: 1129.11), 190))
        precondition(circa(detrazione730(spese: 100), 0))
        // variazione %
        precondition(circa(variazione(da: 100, a: 138), 0.38))
        precondition(circa(variazione(da: 200, a: 150), -0.25))
        precondition(variazione(da: 0, a: 10) == nil)
        // fondo pensione
        precondition(circa(residuoDeducibile(versato: 1800), 3364.57))
        precondition(circa(residuoDeducibile(versato: 6000), 0))
        // inflazione ponderata: +10% su 100 € e 0% su 100 € → +5%
        precondition(circa(inflazionePersonale([(1, 1.1, 100), (2, 2, 100)]), 0.05))
        precondition(inflazionePersonale([]) == nil)
        // interessi: 6.000 € al 2,25% → 11,25 €/mese
        precondition(circa(interessiMensili(saldo: 6000, tassoAnnuo: 2.25), 11.25))
        // articoli
        precondition(conArticolo("33%") == "il 33%")
        precondition(conArticolo("8%") == "l'8%")
        precondition(conArticolo("11%") == "l'11%")
        precondition(conArticolo("1,9%", normale: "del ", eliso: "dell'") == "dell'1,9%")
    }
    #endif
}
