import SwiftUI
import SwiftData
import UIKit
import UserNotifications

struct ImpostazioniView: View {
    @AppStorage("bloccoFaceID") private var bloccoFaceID = true
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var statoNotifiche: UNAuthorizationStatus?
    @State private var confermaCancella = false
    @State private var messaggio: String?

    var body: some View {
        Form {
            Section {
                Toggle("Blocco con Face ID", isOn: $bloccoFaceID)
            } footer: {
                Text("All'apertura e al ritorno in app serve Face ID (o il codice dell'iPhone). Nel multitasking il contenuto resta sfocato.")
            }

            Section {
                if let s = ScadenzaFirma.dataScadenza {
                    LabeledContent("Scade il", value: s.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                    if let g = ScadenzaFirma.giorniMancanti() {
                        LabeledContent("Mancano", value: g <= 0 ? String(localized: "scade oggi") : (g == 1 ? String(localized: "1 giorno") : String(localized: "\(g) giorni")))
                    }
                } else {
                    Text("Data non disponibile (simulatore o build senza profilo di provisioning).").foregroundStyle(.secondary)
                }
            } header: {
                Text("Scadenza dell'app")
            } footer: {
                Text("Con un Apple ID gratuito l'app va reinstallata ogni 7 giorni: collega l'iPhone al Mac e lancia installa.sh dalla cartella del progetto. I dati restano sul telefono. Ti avviso 2 giorni e 1 giorno prima, e la mattina della scadenza.")
            }

            Section("Notifiche") {
                LabeledContent("Permesso", value: descriviNotifiche)
                if statoNotifiche == .denied {
                    Button("Apri le impostazioni di iOS") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
            }

            Section("Dati") {
                NavigationLink { BancheView() } label: { Label("Banche collegate", systemImage: "link") }
                NavigationLink { BackupView() } label: { Label("Backup", systemImage: "externaldrive") }
            }

            Section {
                Button("Lingua dell'app") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } header: {
                Text("Lingua")
            } footer: {
                Text("Bilancio segue la lingua dell'iPhone: italiano o inglese (con le altre lingue resta in italiano). Per sceglierla solo per questa app apri le impostazioni di iOS da qui e tocca Lingua: la voce compare se l'iPhone ha almeno due lingue preferite.")
            }

            Section("Informazioni") {
                LabeledContent("Versione", value: versione)
            }

            #if DEBUG
            Section {
                Button("Carica dati demo", action: caricaDemo)
                Button("Cancella tutti i dati", role: .destructive) { confermaCancella = true }
            } header: {
                Text("Sviluppo")
            } footer: {
                Text("Solo nelle build di debug. Avvio con l'argomento -demo: niente Face ID e dati demo se il database è vuoto.")
            }
            #endif
        }
        .navigationTitle("Impostazioni")
        .task { statoNotifiche = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        .confirmationDialog("Cancellare tutti i dati?", isPresented: $confermaCancella, titleVisibility: .visible) {
            Button("Cancella tutto", role: .destructive, action: cancellaTutto)
        } message: {
            Text("Movimenti, scontrini, investimenti e impostazioni dei conti vengono eliminati. Non si può annullare (i backup restano).")
        }
        .alert(messaggio ?? "", isPresented: Binding(get: { messaggio != nil }, set: { if !$0 { messaggio = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private var descriviNotifiche: String {
        switch statoNotifiche {
        case .authorized: String(localized: "Concesso")
        case .provisional, .ephemeral: String(localized: "Provvisorio")
        case .denied: String(localized: "Negato")
        case .notDetermined: String(localized: "Non ancora chiesto")
        default: "…"
        }
    }

    private var versione: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    private func caricaDemo() {
        guard ((try? context.fetchCount(FetchDescriptor<Movimento>())) ?? 0) == 0 else {
            messaggio = String(localized: "Ci sono già dei movimenti: cancella prima tutti i dati, altrimenti i dati demo si aggiungerebbero ai tuoi.")
            return
        }
        DatiDemo.carica(in: context)
        messaggio = String(localized: "Dati demo caricati.")
    }

    private func cancellaTutto() {
        func elimina<T: PersistentModel>(_: T.Type) {
            for o in (try? context.fetch(FetchDescriptor<T>())) ?? [] { context.delete(o) }
        }
        elimina(Operazione.self); elimina(Valutazione.self); elimina(AllocazionePAC.self); elimina(PianoPAC.self); elimina(Strumento.self)
        elimina(RigaScontrino.self); elimina(Scontrino.self); elimina(Prodotto.self); elimina(RegolaAppresa.self)
        elimina(Movimento.self); elimina(Ricorrenza.self); elimina(SnapshotPatrimonio.self); elimina(ConnessioneBanca.self); elimina(ProfiloImport.self)
        elimina(Conto.self); elimina(Categoria.self)
        try? context.save()
        Sincronizzazione.eliminati = []
        DatiIniziali.inserisciSeVuoto(context)
        messaggio = String(localized: "Dati cancellati.")
    }
}
