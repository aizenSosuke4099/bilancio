import SwiftUI
import SwiftData
import UserNotifications

/// L'app firmata con Apple ID gratuito scade dopo 7 giorni: legge la scadenza dal profilo
/// di provisioning incorporato e avvisa per tempo (notifiche + banner).
enum ScadenzaFirma {

    /// Data di scadenza del profilo `embedded.mobileprovision`. nil su simulatore (il file non c'è).
    static let dataScadenza: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let dati = try? Data(contentsOf: url),
              let inizio = dati.range(of: Data("<?xml".utf8)),
              let fine = dati.range(of: Data("</plist>".utf8), in: inizio.lowerBound..<dati.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: dati[inizio.lowerBound..<fine.upperBound], format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }()

    /// Giorni interi mancanti alla scadenza (0 = scade oggi).
    static func giorniMancanti(da oggi: Date = Date()) -> Int? {
        guard let s = dataScadenza else { return nil }
        return calendario.dateComponents([.day], from: calendario.startOfDay(for: oggi), to: calendario.startOfDay(for: s)).day
    }

    static func testoAvviso(_ quando: String) -> String {
        String(localized: "Bilancio scade \(quando): collega l'iPhone al Mac e lancia installa.sh. I tuoi dati restano.", comment: "quando = «domani alle 20:00» ecc.")
    }

    /// Chiamata a ogni avvio: riprogramma gli avvisi di scadenza e il promemoria backup.
    static func programmaNotifiche() {
        Task {
            let centro = UNUserNotificationCenter.current()
            guard (try? await centro.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
            let vecchie = await centro.pendingNotificationRequests().map(\.identifier)
                .filter { $0.hasPrefix("scadenza.") || $0.hasPrefix("backup.") }
            centro.removePendingNotificationRequests(withIdentifiers: vecchie)

            if let scadenza = dataScadenza {
                let ora = scadenza.formatted(.dateTime.hour().minute())
                let avvisi: [(String, Int, Int, String)] = [
                    // id, giorni prima, ora del giorno, quando
                    ("scadenza.2", -2, 20, String(localized: "dopodomani alle \(ora)")),
                    ("scadenza.1", -1, 20, String(localized: "domani alle \(ora)")),
                    ("scadenza.0", 0, 8, String(localized: "oggi alle \(ora)")),
                ]
                for (id, giorni, oraGiorno, quando) in avvisi {
                    let giorno = calendario.startOfDay(for: scadenza).aggiungendo(giorni: giorni)
                    guard let data = calendario.date(bySettingHour: oraGiorno, minute: 0, second: 0, of: giorno),
                          data > Date(), data < scadenza else { continue }
                    try? await centro.add(richiesta(id: id, titolo: String(localized: "Rinnova Bilancio"), testo: testoAvviso(quando), data: data))
                }
            }

            // Promemoria: un backup fuori dall'iPhone almeno ogni 30 giorni.
            let base = Backup.ultimoEsportato ?? Backup.primoUso
            let prossimeDiciannove = calendario.date(bySettingHour: 19, minute: 0, second: 0, of: Date().aggiungendo(giorni: 1))!
            let data = max(base.aggiungendo(giorni: 30), prossimeDiciannove)
            try? await centro.add(richiesta(id: "backup.promemoria", titolo: String(localized: "Backup di Bilancio"),
                                            testo: String(localized: "È passato più di un mese dall'ultimo backup salvato fuori dall'iPhone. Apri Altro › Backup e salvalo su iCloud Drive."),
                                            data: data))
        }
    }

    private static func richiesta(id: String, titolo: String, testo: String, data: Date) -> UNNotificationRequest {
        let contenuto = UNMutableNotificationContent()
        contenuto.title = titolo
        contenuto.body = testo
        contenuto.sound = .default
        let componenti = calendario.dateComponents([.year, .month, .day, .hour, .minute], from: data)
        return UNNotificationRequest(identifier: id, content: contenuto,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: componenti, repeats: false))
    }
}

/// Banner "l'app scade tra N giorni": va messo in cima ad Anno e Mese. Vuoto se manca molto.
struct BannerScadenza: View {
    var body: some View {
        if let scadenza = ScadenzaFirma.dataScadenza, let giorni = ScadenzaFirma.giorniMancanti(), giorni <= 3 {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Bilancio scade tra \(Text(scadenza, style: .relative))").bold()
                }
                Text("\(scadenza.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())). Collega l'iPhone al Mac e lancia installa.sh: i dati restano.")
                    .font(.caption)
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
