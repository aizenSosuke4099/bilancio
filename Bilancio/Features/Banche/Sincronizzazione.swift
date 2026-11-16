import Foundation
import SwiftData
import UserNotifications

/// Scarica saldi e movimenti contabilizzati dalle banche collegate (Enable Banking).
/// Solo con l'app aperta, al massimo ogni 30 minuti: l'utente è presente (intestazioni PSU, niente limite di 4 letture
/// al giorno). Niente aggiornamento in background: il database è leggibile solo a telefono sbloccato (`Persistenza`).
enum Sincronizzazione {

    static let intervallo: TimeInterval = 30 * 60
    private static var inCorso = false

    // MARK: Nomi dei conti

    /// "Banca X", "Banca X – carta", "Banca Y CHF". Non si usa il nome del conto dato dalla banca:
    /// alcune banche italiane ci mettono l'intestatario.
    static func nomeConto(banca: String, tipo: TipoConto, valuta: String?) -> String {
        var nome = banca
        if tipo == .carta { nome += " – " + String(localized: "carta") }
        if let v = valuta, v != "EUR" { nome += " " + v }
        return nome
    }

    /// Una volta sola: i conti collegati che condividono lo stesso nome (l'intestatario) prendono quello della banca.
    static func correggiNomiConti(in context: ModelContext) {
        let chiave = "conti.nomiDallaBanca"
        guard !UserDefaults.standard.bool(forKey: chiave) else { return }
        let collegati = ((try? context.fetch(FetchDescriptor<Conto>())) ?? []).filter { $0.ebAccountUid != nil && !$0.istituto.isEmpty }
        for (_, gruppo) in Dictionary(grouping: collegati, by: \.nome) where gruppo.count > 1 {
            for c in gruppo { c.nome = nomeConto(banca: c.istituto, tipo: c.tipo, valuta: c.valuta) }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: chiave)
    }

    // MARK: Sincronizzazione

    /// All'apertura dell'app.
    static func sincronizzaSeServe(in context: ModelContext) async {
        await sincronizza(in: context, forza: false)
    }

    /// "Sincronizza ora" e subito dopo un collegamento: ignora l'intervallo.
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
                try await sincronizza(c, presente: true, in: context)
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

    private static func sincronizza(_ connessione: ConnessioneBanca, presente: Bool, in context: ModelContext) async throws {
        let conti = (try? context.fetch(FetchDescriptor<Conto>())) ?? []
        // ultima sync − 5 giorni (le banche contabilizzano in ritardo); la prima volta 90 giorni
        let dal = connessione.ultimaSync.map { $0.aggiungendo(giorni: -5) } ?? Date().aggiungendo(giorni: -90)
        for uid in connessione.accountUids {
            guard let conto = conti.first(where: { $0.ebAccountUid == uid }) else { continue } // conto non abbinato
            if let s = EnableBanking.saldoPreferito(try await EnableBanking.saldi(conto: uid, presente: presente)), let v = Double(s.balance_amount.amount) {
                conto.saldoBanca = v
                conto.saldoBancaData = s.last_change_date_time.flatMap(EnableBanking.dataOra(da:)) ?? s.reference_date.flatMap(EnableBanking.giorno(da:)) ?? Date()
            }
            var impronteViste: [String: Int] = [:]
            for t in try await EnableBanking.transazioni(conto: uid, dal: dal, presente: presente) where t.status == nil || t.status == "BOOK" {
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
        // eliminato dall'utente: la banca lo rimanda a ogni sincronizzazione, non deve ricomparire
        if eliminati.contains(idEsterno) { return false }
        let idOpzionale: String? = idEsterno
        let stessoId = (try? context.fetch(FetchDescriptor<Movimento>(predicate: #Predicate { $0.idEsterno == idOpzionale }))) ?? []
        // già registrato. Solo le due metà di un bonifico tra conti propri (altro conto, altro importo) possono avere lo stesso id.
        if stessoId.contains(where: { $0.conto?.persistentModelID == conto?.persistentModelID || abs(Abbinamento.nelConto($0) - importo) < 0.011 }) { return false }

        // gli abbinamenti confrontano l'importo nella valuta del conto
        if origine == .banca, let importato = Abbinamento.movimentoDaEstratto(importo: importo, data: data, conto: conto, in: context) {
            importato.idEsterno = idEsterno
            return false
        }
        if let esistente = Abbinamento.movimentoEsistentePer(importo: importo, data: data, conto: conto, in: context) {
            esistente.idEsterno = idEsterno
            esistente.descrizioneOriginale = descrizione
            if esistente.conto == nil { esistente.conto = conto }
            if esistente.scontrino != nil { esistente.conferma() }   // scontrino e banca combaciano
            return false
        }

        let s = Classificatore.suggerisciBanca(descrizione: descrizione, importo: importo, in: context)
        creaMovimento(data: data, importo: importo, descrizione: descrizione, idEsterno: idEsterno, conto: conto,
                      origine: origine, suggerimento: s, in: context)
        return true
    }

    /// Crea il movimento da confermare; se è un prelievo, anche l'entrata (giroconto) sul conto Contanti.
    static func creaMovimento(data: Date, importo: Double, descrizione: String, idEsterno: String, conto: Conto?,
                              origine: Origine, suggerimento s: Suggerimento, stato: StatoMovimento = .daConfermare,
                              in context: ModelContext) {
        let m = Movimento(data: data, importo: importo, tipo: s.tipo, titolo: s.titolo, origine: origine,
                          stato: stato, conto: conto, categoria: s.categoria)
        Contabilita.imposta(m, importoInValuta: importo, valuta: conto?.valuta ?? "EUR")
        m.idEsterno = idEsterno
        m.descrizioneOriginale = descrizione
        context.insert(m)
        // l'altra metà di un giroconto tra conti propri: si cerca solo se è già un giroconto o se nulla l'ha riconosciuto
        // (una regola imparata o una parola chiave vincono sull'abbinamento)
        if s.tipo == .giroconto || (!s.appreso && Abbinamento.generico(m)) { Abbinamento.segnaGiroconto(m, in: context) }
        if s.prelievoContanti && importo < 0 {
            let contanti = Movimento(data: data, importo: -m.importo, tipo: .giroconto, titolo: String(localized: "Prelievo"), origine: origine,
                                     stato: .confermato, conto: DatiIniziali.contoContanti(in: context))
            contanti.descrizioneOriginale = descrizione
            context.insert(contanti)
        }
    }

    // MARK: Movimenti eliminati e conti scollegati

    /// Id delle transazioni di banca/estratto che l'utente ha eliminato (viaggiano anche nel backup).
    static var eliminati: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "banche.idEliminati") ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: "banche.idEliminati") }
    }

    /// Da chiamare prima di eliminare un movimento: se viene dalla banca, la prossima sincronizzazione non lo ricrea.
    static func ricordaEliminato(_ m: Movimento) {
        guard let id = m.idEsterno, !id.hasPrefix("costo-cambio:") else { return }
        eliminati.insert(id)
    }

    /// Il conto non è più collegato alla banca: il saldo torna a essere calcolato dai movimenti, ripartendo dall'ultimo
    /// letto dalla banca (altrimenti resterebbe fermo per sempre a quel valore).
    static func scollega(_ conto: Conto) {
        if let b = conto.saldoBanca {
            conto.saldoIniziale = (b - conto.movimenti.reduce(0) { $0 + ($1.importoOriginale ?? $1.importo) }).centesimi
        }
        conto.saldoBanca = nil
        conto.saldoBancaData = nil
        conto.ebAccountUid = nil
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
                (c.scadenza.aggiungendo(giorni: -7), "7", String(localized: "Il collegamento con \(c.banca) scade tra 7 giorni.")),
                (c.scadenza.aggiungendo(giorni: -1), "1", String(localized: "Il collegamento con \(c.banca) scade domani.")),
                (c.scadenza, "0", String(localized: "Il collegamento con \(c.banca) è scaduto: i movimenti non arrivano più.")),
            ]
            if c.scadenza <= ora {
                // già scaduta: un promemoria domani mattina (si sposta a ogni apertura dell'app)
                let domani = calendario.date(bySettingHour: 10, minute: 0, second: 0, of: ora.aggiungendo(giorni: 1)) ?? ora.aggiungendo(giorni: 1)
                avvisi = [(domani, "scaduta", String(localized: "Il collegamento con \(c.banca) è scaduto: ricollegalo da Altro › Banche collegate."))]
            }
            for (quando, suffisso, testo) in avvisi where quando > ora {
                let contenuto = UNMutableNotificationContent()
                contenuto.title = String(localized: "Rinnova il collegamento con \(c.banca)")
                contenuto.body = testo
                contenuto.sound = .default
                let componenti = calendario.dateComponents([.year, .month, .day, .hour, .minute], from: quando)
                let trigger = UNCalendarNotificationTrigger(dateMatching: componenti, repeats: false)
                try? await centro.add(UNNotificationRequest(identifier: prefisso + c.sessionId + "." + suffisso, content: contenuto, trigger: trigger))
            }
        }
    }
}
