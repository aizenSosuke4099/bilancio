import SwiftUI
import SwiftData

@main
struct BilancioApp: App {
    @Environment(\.scenePhase) private var fase

    init() {
        // I task in background vanno registrati prima che l'app finisca di avviarsi.
        Sincronizzazione.registraBackground()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-verifica") { Abbinamento.autoverifica(); BackupAperto.autoverifica(); CalcoloInflazione.autoverifica(); ISTAT.autoverifica(); print("Inflazione e ISTAT: autoverifica OK") }
        // prova del giro completo: backup del database vero → ripristino in sospeso, applicato al prossimo avvio
        if ProcessInfo.processInfo.arguments.contains("-provaRipristino") {
            let ctx = Persistenza.container.mainContext
            let url = try! Backup.crea(in: ctx)
            try! Backup.preparaRipristino(da: url)
            print("provaRipristino: pronto da \(url.lastPathComponent)")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            BloccoApp {
                RootView()
            }
        }
        .modelContainer(Persistenza.container)
        .onChange(of: fase, initial: true) { _, nuova in
            if nuova == .active { Task { await Avvio.esegui() } }
            if nuova == .background { Sincronizzazione.programmaBackground() }
        }
    }
}

/// Lavori da fare all'apertura: dati iniziali, ricorrenti, prezzi, PAC, banche, patrimonio.
enum Avvio {
    private static var inCorso = false
    private static var ultimo: Date?

    static func esegui() async {
        guard !inCorso else { return }
        if let u = ultimo, Date().timeIntervalSince(u) < 60 { return }
        inCorso = true
        defer { inCorso = false; ultimo = Date() }

        let ctx = Persistenza.container.mainContext
        DatiIniziali.inserisciSeVuoto(ctx)
        DatiIniziali.aggiornaCategorie(ctx)
        Sincronizzazione.correggiNomiConti(in: ctx)
        CredenzialiEnableBanking.eliminaCopieChiave()
        GeneratoreRicorrenze.genera(in: ctx)
        if !ProcessInfo.processInfo.arguments.contains("-demo") { ScadenzaFirma.programmaNotifiche() }  // in demo il permesso coprirebbe lo schermo
        await Prezzi.aggiornaSeVecchi(in: ctx)
        await PAC.generaSeServe(in: ctx)
        await Sincronizzazione.sincronizzaSeServe(in: ctx)
        await Contabilita.applicaCambiStorici(in: ctx)
        Contabilita.aggiornaSnapshot(in: ctx)
        try? ctx.save()
        await ISTAT.aggiornaSeServe()   // per ultimo: il servizio ISTAT è lento
    }
}
