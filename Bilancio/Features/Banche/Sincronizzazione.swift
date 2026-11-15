import Foundation
import SwiftData
import BackgroundTasks
import UserNotifications

/// Scarica saldi e movimenti contabilizzati dalle banche collegate (Enable Banking).
/// All'apertura e in background, al massimo ogni 6 ore (molte banche concedono 4 accessi al giorno senza l'utente).
enum Sincronizzazione {

    static let idTask = "bilancio.sync"
    static let intervallo: TimeInterval = 6 * 3600
    private static var registrato = false
    private static var inCorso = false

    // MARK: Background

    static func registraBackground() {
        guard !registrato else { return } // registrare due volte lo stesso id fa chiudere l'app
        registrato = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: idTask, using: .main) { task in
            programmaBackground()
            let lavoro = Task { @MainActor in
                let ctx = Persistenza.container.mainContext
                await sincronizza(in: ctx, forza: false)
                try? ctx.save()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { lavoro.cancel() }
        }
    }

    static func programmaBackground() {
        let richiesta = BGAppRefreshTaskRequest(identifier: idTask)
        richiesta.earliestBeginDate = Date(timeIntervalSinceNow: intervallo)
        try? BGTaskScheduler.shared.submit(richiesta)
    }

    // MARK: Sincronizzazione

    static func sincronizzaSeServe(in context: ModelContext) async {
        await sincronizza(in: context, forza: false)
    }

    /// "Sincronizza ora": ignora l'intervallo di 6 ore.
    static func sincronizzaOra(in context: ModelContext) async {
        await sincronizza(in: context, forza: true)
    }

    private static func sincronizza(in context: ModelContext, forza: Bool) async {
        let connessioni = (try? context.fetch(FetchDescriptor<ConnessioneBanca>())) ?? []
        await programmaNotificheScadenza(connessioni)
        guard !inCorso, CredenzialiEnableBanking.complete else { return }
        inCorso = true
        defer { inCorso = false }

        let ora = Date()
        for c in connessioni where c.scadenza > ora {
            if !forza, let u = c.ultimaSync, ora.timeIntervalSince(u) < intervallo { continue }
            do {
                try await sincronizza(c, in: context)
                c.ultimaSync = ora
                registraErrore(nil, per: c)
            } catch is CancellationError {
                return
            } catch {
                registraErrore(error.localizedDescription, per: c)
            }
            try? context.save()
        }
    }

    private static func sincronizza(_ connessione: ConnessioneBanca, in context: ModelContext) async throws {
        let conti = (try? context.fetch(FetchDescriptor<Conto>())) ?? []
        // ultima sync − 5 giorni (le banche contabilizzano in ritardo); la prima volta 90 giorni
        let dal = connessione.ultimaSync.map { $0.aggiungendo(giorni: -5) } ?? Date().aggiungendo(giorni: -90)
        for uid in connessione.accountUids {
            guard let conto = conti.first(where: { $0.ebAccountUid == uid }) else { continue } // conto non abbinato
            if let s = EnableBanking.saldoPreferito(try await EnableBanking.saldi(conto: uid)), let v = Double(s.balance_amount.amount) {
                conto.saldoBanca = v
                conto.saldoBancaData = s.last_change_date_time.flatMap(EnableBanking.dataOra(da:)) ?? s.reference_date.flatMap(EnableBanking.giorno(da:)) ?? Date()
            }
            var impronteViste: [String: Int] = [:]
            for t in try await EnableBanking.transazioni(conto: uid, dal: dal) where t.status == nil || t.status == "BOOK" {
                guard let data = t.data else { continue }
                let importo = t.importoConSegno
                let descrizione = t.descrizione
                var id = t.transaction_id ?? t.entry_reference ?? ""
                if id.isEmpty {
                    // senza id dalla banca: impronta + contatore, così due movimenti identici restano due
                    let impronta = ParserEstratto.impronta(data: data, importo: importo, descrizione: descrizione)
                    let n = impronteViste[impronta, default: 0]
                    impronteViste[impronta] = n + 1
                    id = "eb:" + impronta + (n > 0 ? "#\(n)" : "")
                }
                registraMovimento(data: data, importo: importo, descrizione: descrizione, idEsterno: id, conto: conto, origine: .banca, in: context)
            }
        }
    }

    /// Inserisce un movimento arrivato da banca o estratto, senza duplicati:
    /// stesso idEsterno → niente; movimento già creato da scontrino/ricorrenza/PAC → lo completa; altrimenti lo crea.
    /// I prelievi alimentano anche il conto Contanti. Restituisce true se ha creato un movimento nuovo.
    @discardableResult
    static func registraMovimento(data: Date, importo: Double, descrizione: String, idEsterno: String, conto: Conto?,
                                  origine: Origine, in context: ModelContext) -> Bool {
        let idOpzionale: String? = idEsterno
        var d = FetchDescriptor<Movimento>(predicate: #Predicate { $0.idEsterno == idOpzionale })
        d.fetchLimit = 1
        if ((try? context.fetchCount(d)) ?? 0) > 0 { return false }

        if let esistente = Abbinamento.movimentoEsistentePer(importo: importo, data: data, conto: conto, in: context) {
            esistente.idEsterno = idEsterno
            esistente.descrizioneOriginale = descrizione
            if esistente.conto == nil { esistente.conto = conto }
            return false
        }

        let s = Classificatore.suggerisciBanca(descrizione: descrizione, importo: importo, in: context)
        creaMovimento(data: data, importo: importo, descrizione: descrizione, idEsterno: idEsterno, conto: conto,
                      origine: origine, suggerimento: s, in: context)
        return true
    }

    /// Crea il movimento da confermare; se è un prelievo, anche l'entrata (giroconto) sul conto Contanti.
    static func creaMovimento(data: Date, importo: Double, descrizione: String, idEsterno: String, conto: Conto?,
                              origine: Origine, suggerimento s: Suggerimento, in context: ModelContext) {
        let m = Movimento(data: data, importo: importo, tipo: s.tipo, titolo: s.titolo, origine: origine,
                          stato: .daConfermare, conto: conto, categoria: s.categoria)
        m.idEsterno = idEsterno
        m.descrizioneOriginale = descrizione
        context.insert(m)
        // l'altra metà di un giroconto tra conti propri (se una regola imparata dice altro, vince la regola)
        if s.tipo == .giroconto || !s.appreso { Abbinamento.segnaGiroconto(m, in: context) }
        if s.prelievoContanti && importo < 0 {
            let contanti = Movimento(data: data, importo: -importo, tipo: .giroconto, titolo: "Prelievo", origine: origine,
                                     stato: .confermato, conto: DatiIniziali.contoContanti(in: context))
            contanti.descrizioneOriginale = descrizione
            context.insert(contanti)
        }
    }

    // MARK: Errori (mostrati in BancheView)

    static func ultimoErrore(per c: ConnessioneBanca) -> String? {
        UserDefaults.standard.string(forKey: "banche.errore." + c.sessionId)
    }

    static func registraErrore(_ messaggio: String?, per c: ConnessioneBanca) {
        let chiave = "banche.errore." + c.sessionId
        if let messaggio {
            UserDefaults.standard.set(Date().breve + " – " + messaggio, forKey: chiave)
        } else {
            UserDefaults.standard.removeObject(forKey: chiave)
        }
    }

    // MARK: Notifiche di scadenza del consenso

    /// 7 giorni e 1 giorno prima della scadenza, poi un promemoria quando è scaduta.
    static func programmaNotificheScadenza(_ connessioni: [ConnessioneBanca]) async {
        let centro = UNUserNotificationCenter.current()
        let prefisso = "bilancio.banca."
        let vecchie = await centro.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefisso) }
        centro.removePendingNotificationRequests(withIdentifiers: vecchie)
        guard !connessioni.isEmpty else { return }
        _ = try? await centro.requestAuthorization(options: [.alert, .sound])

        let ora = Date()
        for c in connessioni {
            var avvisi: [(Date, String, String)] = [
                (c.scadenza.aggiungendo(giorni: -7), "7", "Il collegamento con \(c.banca) scade tra 7 giorni."),
                (c.scadenza.aggiungendo(giorni: -1), "1", "Il collegamento con \(c.banca) scade domani."),
                (c.scadenza, "0", "Il collegamento con \(c.banca) è scaduto: i movimenti non arrivano più."),
            ]
            if c.scadenza <= ora {
                // già scaduta: un promemoria domani mattina (si sposta a ogni apertura dell'app)
                let domani = calendario.date(bySettingHour: 10, minute: 0, second: 0, of: ora.aggiungendo(giorni: 1)) ?? ora.aggiungendo(giorni: 1)
                avvisi = [(domani, "scaduta", "Il collegamento con \(c.banca) è scaduto: ricollegalo da Altro › Banche collegate.")]
            }
            for (quando, suffisso, testo) in avvisi where quando > ora {
                let contenuto = UNMutableNotificationContent()
                contenuto.title = "Rinnova il collegamento con \(c.banca)"
                contenuto.body = testo
                contenuto.sound = .default
                let componenti = calendario.dateComponents([.year, .month, .day, .hour, .minute], from: quando)
                let trigger = UNCalendarNotificationTrigger(dateMatching: componenti, repeats: false)
                try? await centro.add(UNNotificationRequest(identifier: prefisso + c.sessionId + "." + suffisso, content: contenuto, trigger: trigger))
            }
        }
    }
}
