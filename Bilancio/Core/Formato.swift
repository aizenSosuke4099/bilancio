import Foundation

/// Solo per leggere testi italiani (scontrini, estratti conto, parole chiave). Numeri e date si mostrano nella lingua del telefono.
let localeIT = Locale(identifier: "it_IT")

var calendario: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.locale = .current
    c.firstWeekday = 2
    return c
}

extension Double {
    /// "1.234,56 €"
    var euro: String { formatted(.currency(code: "EUR")) }
    /// "1.235 €"
    var euroTondo: String { formatted(.currency(code: "EUR").precision(.fractionLength(0))) }
    /// Importo in una valuta qualsiasi ("CHF 1.234,56").
    func valuta(_ codice: String) -> String { formatted(.currency(code: codice)) }
    /// 0.331 → "33,1%"
    var percento: String { formatted(.percent.precision(.fractionLength(1))) }
    /// 0.331 → "+33,1%"
    var percentoConSegno: String { (self >= 0 ? "+" : "") + percento }
    /// Numero con max 4 decimali (quote).
    var quote: String { formatted(.number.precision(.fractionLength(0...4))) }
    /// Arrotondamento al centesimo.
    var centesimi: Double { (self * 100).rounded() / 100 }
}

extension Date {
    var inizioMese: Date { calendario.date(from: calendario.dateComponents([.year, .month], from: self))! }
    var inizioMeseSuccessivo: Date { calendario.date(byAdding: .month, value: 1, to: inizioMese)! }
    var inizioAnno: Date { calendario.date(from: calendario.dateComponents([.year], from: self))! }
    var inizioAnnoSuccessivo: Date { calendario.date(byAdding: .year, value: 1, to: inizioAnno)! }
    var anno: Int { calendario.component(.year, from: self) }
    var mese: Int { calendario.component(.month, from: self) }
    var giorno: Int { calendario.component(.day, from: self) }
    func aggiungendo(mesi: Int) -> Date { calendario.date(byAdding: .month, value: mesi, to: self)! }
    func aggiungendo(giorni: Int) -> Date { calendario.date(byAdding: .day, value: giorni, to: self)! }

    /// "novembre 2026"
    var meseAnno: String { formatted(.dateTime.month(.wide).year()) }
    /// "Novembre"
    var nomeMese: String { formatted(.dateTime.month(.wide)).capitalized(with: .current) }
    /// "novembre" (minuscolo in italiano, "November" in inglese): per il mese dentro una frase.
    var meseInFrase: String { formatted(.dateTime.month(.wide)) }
    /// "nov"
    var meseBreve: String { formatted(.dateTime.month(.abbreviated)) }
    /// "13 nov"
    var giornoMese: String { formatted(.dateTime.day().month(.abbreviated)) }
    /// "13/11/2026"
    var breve: String { formatted(.dateTime.day(.twoDigits).month(.twoDigits).year()) }
}

/// Data di inizio di un anno.
func inizioAnno(_ anno: Int) -> Date {
    calendario.date(from: DateComponents(year: anno, month: 1, day: 1))!
}

/// Primo giorno di un mese.
func inizioMese(anno: Int, mese: Int) -> Date {
    calendario.date(from: DateComponents(year: anno, month: mese, day: 1))!
}

/// Legge numeri scritti all'italiana o all'inglese ("1.234,56", "1234.56", "-12,30 €").
func leggiNumero(_ testo: String) -> Double? {
    var s = testo.trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "€", with: "")
        .replacingOccurrences(of: "EUR", with: "")
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "\u{00A0}", with: "")
    guard !s.isEmpty else { return nil }
    let ultimaVirgola = s.lastIndex(of: ",")
    let ultimoPunto = s.lastIndex(of: ".")
    switch (ultimaVirgola, ultimoPunto) {
    case let (v?, p?):
        // il separatore decimale è quello più a destra
        if v > p { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        else { s = s.replacingOccurrences(of: ",", with: "") }
    case (_?, nil):
        s = s.replacingOccurrences(of: ",", with: ".")
    default:
        break
    }
    return Double(s)
}
