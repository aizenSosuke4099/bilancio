import SwiftUI
import SwiftData
import UIKit
import WebKit
import AuthenticationServices
import UniformTypeIdentifiers

/// Banche collegate con Enable Banking: configurazione, collegamenti, sincronizzazione.
/// Pushata dalla scheda Altro (niente NavigationStack proprio).
struct BancheView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ConnessioneBanca.scadenza) private var connessioni: [ConnessioneBanca]
    @Query(sort: \Conto.ordine) private var conti: [Conto]
    @AppStorage("banche.redirectURL") private var redirectURL = "https://localhost/bilancio"

    @State private var applicationId = CredenzialiEnableBanking.applicationId ?? ""
    @State private var chiavePresente = CredenzialiEnableBanking.chiavePrivata != nil
    @State private var importaChiave = false
    @State private var incollaChiave = false
    @State private var testoChiave = ""
    @State private var messaggio: String?
    @State private var collega: RichiestaCollegamento?
    @State private var daEliminare: ConnessioneBanca?
    @State private var sincronizzando = false
    @State private var aggiornamento = 0

    private var configurato: Bool { !applicationId.trimmingCharacters(in: .whitespaces).isEmpty && chiavePresente }

    var body: some View {
        List {
            configurazione
            collegamenti
            Section {
                Text("Se una banca non è supportata (per esempio alcune carte di credito) o non vuoi collegarla, importa l'estratto conto CSV o PDF da Altro › Importa estratto conto.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Banche collegate")
        .fileImporter(isPresented: $importaChiave, allowedContentTypes: [UTType(filenameExtension: "pem"), .plainText, .data].compactMap { $0 }) { esito in
            if case .success(let url) = esito { leggiChiave(da: url) }
        }
        .sheet(isPresented: $incollaChiave) { incolla }
        .sheet(item: $collega) { r in
            CollegaBancaView(bancaIniziale: r.banca, redirectURL: redirectURL)
        }
        .confirmationDialog("Eliminare il collegamento?", isPresented: Binding(get: { daEliminare != nil }, set: { if !$0 { daEliminare = nil } }), titleVisibility: .visible) {
            Button("Elimina collegamento", role: .destructive) { if let c = daEliminare { elimina(c) } }
        } message: {
            Text("Il consenso viene revocato. I movimenti già importati restano.")
        }
        .alert("Enable Banking", isPresented: Binding(get: { messaggio != nil }, set: { if !$0 { messaggio = nil } })) {
            Button("OK") {}
        } message: { Text(messaggio ?? "") }
    }

    // MARK: Configurazione

    private var configurazione: some View {
        Section {
            DisclosureGroup("Come si configura") {
                VStack(alignment: .leading, spacing: 8) {
                    passo(1, "Registrati gratis su enablebanking.com ed entra nel Control Panel.")
                    passo(2, "In «API applications» crea una nuova applicazione scegliendo l'ambiente **Production** (non Sandbox).")
                    passo(3, "Come redirect URL inserisci esattamente: \(redirectURL)")
                    passo(4, "Genera la chiave durante la creazione e scarica il file .pem con la chiave privata: non si può riscaricare, conservalo.")
                    passo(5, "Copia qui sotto l'Application ID (è anche il nome del file .pem) e importa il file della chiave.")
                    passo(6, "Nel Control Panel premi «Activate by linking accounts» e collega i tuoi conti: l'applicazione passa in modalità limitata, gratuita per uso personale, e legge solo i conti collegati.")
                    passo(7, "Torna qui e premi «Collega una banca» per ognuna. Il consenso dura fino a 180 giorni, poi va rinnovato (l'app ti avvisa).")
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }
            TextField("Application ID", text: $applicationId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.callout.monospaced())
                .onChange(of: applicationId) { _, nuovo in
                    CredenzialiEnableBanking.applicationId = nuovo.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            HStack {
                Label("Chiave privata", systemImage: "key")
                Spacer()
                Text(chiavePresente ? "Presente" : "Assente")
                    .foregroundStyle(chiavePresente ? Tinta.entrate : .secondary)
            }
            Menu(chiavePresente ? "Sostituisci chiave" : "Aggiungi chiave") {
                Button("Importa file .pem", systemImage: "doc") { importaChiave = true }
                Button("Incolla il testo", systemImage: "doc.on.clipboard") { testoChiave = ""; incollaChiave = true }
                if chiavePresente {
                    Button("Rimuovi chiave", systemImage: "trash", role: .destructive) {
                        CredenzialiEnableBanking.chiavePrivata = nil
                        chiavePresente = false
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Redirect URL").font(.caption).foregroundStyle(.secondary)
                TextField("https://localhost/bilancio", text: $redirectURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.callout.monospaced())
            }
        } header: {
            Text("Configurazione")
        } footer: {
            Text("Chiave e Application ID restano nel Portachiavi di questo iPhone. Con un indirizzo https la banca si apre dentro l'app; con uno schema tuo (es. bilancio://callback) si usa il login sicuro di sistema.")
        }
    }

    private func passo(_ n: Int, _ testo: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.caption.bold()).foregroundStyle(.white).frame(width: 20, height: 20).background(Color.accentColor, in: Circle())
            Text(testo).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var incolla: some View {
        NavigationStack {
            TextEditor(text: $testoChiave)
                .font(.caption.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal)
                .navigationTitle("Incolla la chiave")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { incollaChiave = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salva") { salvaChiave(testoChiave); incollaChiave = false }
                            .disabled(testoChiave.isEmpty)
                    }
                }
        }
    }

    private func leggiChiave(da url: URL) {
        let accesso = url.startAccessingSecurityScopedResource()
        defer { if accesso { url.stopAccessingSecurityScopedResource() } }
        guard let testo = try? String(contentsOf: url, encoding: .utf8) else {
            messaggio = String(localized: "Non riesco a leggere il file.")
            return
        }
        // il file scaricato da Enable Banking si chiama <application id>.pem
        let nome = url.deletingPathExtension().lastPathComponent
        if applicationId.isEmpty, UUID(uuidString: nome) != nil { applicationId = nome }
        // la chiave ora sta nel Portachiavi: una copia lasciata nella cartella di Bilancio (visibile in File) si toglie
        if salvaChiave(testo), url.path.hasPrefix(URL.documentsDirectory.path) { try? FileManager.default.removeItem(at: url) }
    }

    @discardableResult
    private func salvaChiave(_ pem: String) -> Bool {
        do {
            _ = try EnableBanking.chiaveRSA(pem: pem)
            CredenzialiEnableBanking.chiavePrivata = pem.trimmingCharacters(in: .whitespacesAndNewlines)
            chiavePresente = true
            return true
        } catch {
            messaggio = error.localizedDescription
            return false
        }
    }

    // MARK: Collegamenti

    private var collegamenti: some View {
        Section {
            ForEach(connessioni) { c in
                rigaConnessione(c)
                    .swipeActions {
                        Button("Elimina", role: .destructive) { daEliminare = c }
                        Button("Rinnova") { collega = RichiestaCollegamento(banca: c.banca) }.tint(.blue)
                    }
            }
            Button {
                // non disattivato: un pulsante grigio non spiega cosa manca
                let senzaID = applicationId.trimmingCharacters(in: .whitespaces).isEmpty
                switch (senzaID, chiavePresente) {
                case (true, false): messaggio = String(localized: "Prima inserisci l'Application ID e importa la chiave (file .pem) qui sopra.")
                case (true, true): messaggio = String(localized: "Prima inserisci l'Application ID qui sopra.")
                case (false, false): messaggio = String(localized: "Prima importa la chiave (file .pem) qui sopra.")
                case (false, true): collega = RichiestaCollegamento(banca: nil)
                }
            } label: {
                Label("Collega una banca", systemImage: "plus.circle")
            }
            if !connessioni.isEmpty {
                Button {
                    Task {
                        sincronizzando = true
                        await Sincronizzazione.sincronizzaOra(in: context)
                        Contabilita.aggiornaSnapshot(in: context)
                        try? context.save()
                        sincronizzando = false
                        aggiornamento += 1
                    }
                } label: {
                    HStack {
                        Label("Sincronizza ora", systemImage: "arrow.triangle.2.circlepath")
                        if sincronizzando { Spacer(); ProgressView() }
                    }
                }
                .disabled(sincronizzando || !configurato)
            }
        } header: {
            Text("Collegamenti")
        } footer: {
            if !configurato { Text("Completa la configurazione per collegare le banche.") }
            else { Text("La sincronizzazione parte da sola all'apertura e in background, al massimo ogni 6 ore. Scorri su un collegamento per rinnovarlo o eliminarlo.") }
        }
    }

    private func rigaConnessione(_ c: ConnessioneBanca) -> some View {
        let giorni = calendario.dateComponents([.day], from: calendario.startOfDay(for: Date()), to: calendario.startOfDay(for: c.scadenza)).day ?? 0
        let contiCollegati = conti.filter { $0.ebAccountUid.map(c.accountUids.contains) ?? false }
        let errore = aggiornamento >= 0 ? Sincronizzazione.ultimoErrore(per: c) : nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(c.banca).font(.headline)
                Spacer()
                Group {
                    if c.scadenza <= Date() { Text("Scaduto").foregroundStyle(Tinta.spese) }
                    else if giorni <= 7 { Text(giorni <= 1 ? "Scade domani" : "Scade tra \(giorni) giorni").foregroundStyle(.orange) }
                    else { Text("Scade tra \(giorni) giorni").foregroundStyle(.secondary) }
                }
                .font(.caption.bold())
            }
            Text(contiCollegati.isEmpty ? String(localized: "\(c.accountUids.count) conti, nessuno abbinato") : contiCollegati.map(\.nome).joined(separator: ", "))
                .font(.subheadline)
            Text(c.ultimaSync.map { "Ultima sincronizzazione: \($0.formatted(.dateTime.day().month(.abbreviated).hour().minute()))" } ?? "Mai sincronizzato")
                .font(.caption).foregroundStyle(.secondary)
            if let errore {
                Label(errore, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Tinta.spese)
            }
        }
        .padding(.vertical, 2)
    }

    private func elimina(_ c: ConnessioneBanca) {
        let id = c.sessionId
        Task { try? await EnableBanking.eliminaSessione(id) }
        for conto in conti where conto.ebAccountUid.map(c.accountUids.contains) ?? false {
            conto.ebAccountUid = nil
        }
        Sincronizzazione.registraErrore(nil, per: c)
        context.delete(c)
        try? context.save()
        let rimaste = connessioni.filter { $0.sessionId != id }
        Task { await Sincronizzazione.programmaNotificheScadenza(rimaste) }
    }
}

fileprivate struct RichiestaCollegamento: Identifiable {
    let id = UUID()
    let banca: String?
}

// MARK: - Collegamento di una banca

/// Scelta della banca → consenso sul sito della banca → abbinamento dei conti.
fileprivate struct CollegaBancaView: View {
    let bancaIniziale: String?
    let redirectURL: String

    @Environment(\.dismiss) private var dismiss

    private enum Fase {
        case scelta
        case attesa(String)
        case web(URL)
        case abbinamento(EnableBanking.Sessione, EnableBanking.ASPSP, Date)
    }

    @State private var fase = Fase.scelta
    @State private var banche: [EnableBanking.ASPSP] = []
    @State private var caricando = true
    @State private var ricerca = ""
    @State private var errore: String?
    @State private var stato = UUID().uuidString
    @State private var bancaScelta: EnableBanking.ASPSP?
    @State private var scadenzaRichiesta = Date()
    @State private var autenticazione = AutenticazioneWeb()

    var body: some View {
        NavigationStack {
            Group {
                switch fase {
                case .scelta: scelta
                case .attesa(let testo): ProgressView(testo).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .web(let url):
                    WebAutorizzazione(url: url, redirectURL: redirectURL) { ritorno in
                        Task { await completa(ritorno) }
                    }
                    .ignoresSafeArea(edges: .bottom)
                case .abbinamento(let sessione, let banca, let scadenza):
                    AbbinamentoContiView(sessione: sessione, banca: banca, scadenza: scadenza) { dismiss() }
                }
            }
            .navigationTitle(bancaScelta?.name ?? String(localized: "Collega una banca"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
            .alert("Collegamento non riuscito", isPresented: Binding(get: { errore != nil }, set: { if !$0 { errore = nil } })) {
                Button("OK") { fase = .scelta }
            } message: { Text(errore ?? "") }
        }
        .interactiveDismissDisabled()
        .task { await caricaBanche() }
    }

    private var scelta: some View {
        let filtrate = banche.filter { ricerca.isEmpty || $0.name.localizedCaseInsensitiveContains(ricerca) }
        return List(filtrate) { b in
            Button { Task { await avvia(b) } } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: b.logo.flatMap(URL.init(string:))) { img in
                        img.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "building.columns").foregroundStyle(.secondary)
                    }
                    .frame(width: 28, height: 28)
                    Text(b.name).foregroundStyle(.primary)
                    if b.beta == true { Text("beta").font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
        .overlay {
            if banche.isEmpty {
                if caricando { ProgressView("Carico le banche…") }
                else { ContentUnavailableView("Nessuna banca", systemImage: "building.columns", description: Text("Controlla Application ID, chiave privata e connessione, poi riprova.")) }
            }
        }
        .searchable(text: $ricerca, prompt: "Cerca la banca")
    }

    private func caricaBanche() async {
        guard banche.isEmpty else { return }
        defer { caricando = false }
        do {
            banche = try await EnableBanking.banche(paese: "IT")
            if let nome = bancaIniziale, let b = banche.first(where: { $0.name == nome }) { await avvia(b) }
        } catch {
            errore = error.localizedDescription
        }
    }

    private func avvia(_ banca: EnableBanking.ASPSP) async {
        bancaScelta = banca
        fase = .attesa(String(localized: "Contatto \(banca.name)…"))
        // 180 giorni, o meno se la banca concede meno (con 10 minuti di margine sugli orologi)
        let massimo = TimeInterval(banca.maximum_consent_validity ?? 180 * 86400)
        scadenzaRichiesta = Date().addingTimeInterval(min(180 * 86400, massimo) - 600)
        stato = UUID().uuidString
        do {
            let url = try await EnableBanking.avviaAutorizzazione(banca: banca, validoFino: scadenzaRichiesta, redirectURL: redirectURL, state: stato)
            if let schema = URL(string: redirectURL)?.scheme?.lowercased(), schema != "http", schema != "https" {
                // schema personalizzato: login di sistema, che chiude da solo al ritorno
                let ritorno = try await autenticazione.avvia(url: url, schema: schema)
                await completa(ritorno)
            } else {
                fase = .web(url)
            }
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            fase = .scelta
        } catch {
            errore = error.localizedDescription
        }
    }

    /// Ritorno dalla banca: legge code/state/error e crea la sessione.
    private func completa(_ ritorno: URL) async {
        let parametri = URLComponents(url: ritorno, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func valore(_ nome: String) -> String? { parametri.first { $0.name == nome }?.value }
        if let e = valore("error") {
            errore = String(localized: "La banca ha rifiutato il consenso: \(valore("error_description") ?? e)")
            return
        }
        guard valore("state") == stato, let codice = valore("code"), let banca = bancaScelta else {
            errore = String(localized: "Risposta della banca non valida.")
            return
        }
        fase = .attesa(String(localized: "Creo il collegamento…"))
        do {
            let sessione = try await EnableBanking.creaSessione(codice: codice)
            let scadenza = sessione.access?.valid_until.flatMap(EnableBanking.dataOra(da:)) ?? scadenzaRichiesta
            fase = .abbinamento(sessione, banca, scadenza)
        } catch {
            errore = error.localizedDescription
        }
    }
}

// MARK: - Abbinamento conti

fileprivate struct AbbinamentoContiView: View {
    let sessione: EnableBanking.Sessione
    let banca: EnableBanking.ASPSP
    let scadenza: Date
    let fatto: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Conto.ordine) private var conti: [Conto]
    @Query private var connessioni: [ConnessioneBanca]

    /// uid del conto Enable Banking → scelta ("nuovo", "no" o id del Conto).
    @State private var scelte: [String: String] = [:]

    private var contiAbbinabili: [Conto] { conti.filter { $0.tipo != .contanti && !$0.archiviato } }

    var body: some View {
        Form {
            Section {
                ForEach(sessione.accounts.filter { $0.uid != nil }) { a in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(a.descrizione).font(.headline)
                        Text([a.iban, a.currency].compactMap { $0 }.joined(separator: " · ")).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Picker("Conto in Bilancio", selection: Binding(get: { scelte[a.uid!] ?? "nuovo" }, set: { scelte[a.uid!] = $0 })) {
                            ForEach(contiAbbinabili) { c in Text(c.nome).tag(chiave(c)) }
                            Text("Nuovo conto").tag("nuovo")
                            Text("Non importare").tag("no")
                        }
                    }
                }
            } header: {
                Text("Abbina i conti")
            } footer: {
                Text("Scegli a quale conto di Bilancio corrisponde ognuno. Collegamento valido fino al \(scadenza.breve).")
            }
            Section {
                Button("Salva e sincronizza") { salva() }.bold()
            }
        }
        .onAppear(perform: proponi)
    }

    private func chiave(_ c: Conto) -> String { String(describing: c.persistentModelID.hashValue) }

    /// Proposta: stesso IBAN, poi conto già collegato a quel uid, poi stesso istituto/nome della banca (un conto per volta).
    private func proponi() {
        guard scelte.isEmpty else { return }
        let nomeBanca = Classificatore.normalizza(banca.name)
        var usati: Set<String> = []
        for a in sessione.accounts {
            guard let uid = a.uid else { continue }
            let liberi = contiAbbinabili.filter { !usati.contains(chiave($0)) }
            let iban = a.iban?.replacingOccurrences(of: " ", with: "")
            let proposto = liberi.first { iban != nil && $0.iban?.replacingOccurrences(of: " ", with: "") == iban }
                ?? liberi.first { $0.ebAccountUid == uid }
                ?? liberi.first { c in
                    let n = Classificatore.normalizza(c.istituto.isEmpty ? c.nome : c.istituto)
                    return !n.isEmpty && (nomeBanca.contains(n) || n.contains(nomeBanca))
                }
            if let proposto { usati.insert(chiave(proposto)) }
            scelte[uid] = proposto.map(chiave) ?? "nuovo"
        }
    }

    private func salva() {
        let uids = sessione.accounts.compactMap(\.uid)
        // un rinnovo sostituisce il vecchio collegamento della stessa banca
        for vecchia in connessioni where vecchia.banca == banca.name && vecchia.sessionId != sessione.session_id {
            let id = vecchia.sessionId
            Task { try? await EnableBanking.eliminaSessione(id) }
            for c in conti where c.ebAccountUid.map(vecchia.accountUids.contains) ?? false { c.ebAccountUid = nil }
            Sincronizzazione.registraErrore(nil, per: vecchia)
            context.delete(vecchia)
        }
        let connessione = ConnessioneBanca(banca: banca.name, sessionId: sessione.session_id, scadenza: scadenza)
        connessione.paese = banca.country
        connessione.accountUids = uids
        context.insert(connessione)

        for a in sessione.accounts {
            guard let uid = a.uid else { continue }
            let scelta = scelte[uid] ?? "nuovo"
            let conto: Conto
            if scelta == "no" { continue }
            if let esistente = contiAbbinabili.first(where: { chiave($0) == scelta }) {
                conto = esistente
            } else {
                let tipo: TipoConto = a.cash_account_type == "CARD" ? .carta : (a.cash_account_type == "SVGS" ? .remunerato : .corrente)
                conto = Conto(nome: a.name ?? banca.name, tipo: tipo, istituto: banca.name, ordine: (conti.map(\.ordine).max() ?? 0) + 1)
                conto.valuta = a.currency ?? "EUR"
                context.insert(conto)
            }
            conto.ebAccountUid = uid
            if let iban = a.iban { conto.iban = iban }
        }
        try? context.save()
        let ctx = context
        Task {
            await Sincronizzazione.sincronizzaOra(in: ctx)
            Contabilita.aggiornaSnapshot(in: ctx)
            try? ctx.save()
        }
        fatto()
    }
}

// MARK: - Login di sistema (schema personalizzato)

fileprivate final class AutenticazioneWeb: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var sessione: ASWebAuthenticationSession?

    func avvia(url: URL, schema: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuazione in
            let s = ASWebAuthenticationSession(url: url, callback: .customScheme(schema)) { ritorno, errore in
                if let ritorno { continuazione.resume(returning: ritorno) }
                else { continuazione.resume(throwing: errore ?? ASWebAuthenticationSessionError(.canceledLogin)) }
            }
            s.presentationContextProvider = self
            sessione = s
            if !s.start() { continuazione.resume(throwing: ASWebAuthenticationSessionError(.presentationContextInvalid)) }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // il login parte da un tocco dell'utente: una scena attiva c'è sempre
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        return scene.keyWindow ?? scene.windows.first ?? UIWindow(windowScene: scene)
    }
}

// MARK: - Pagina della banca dentro l'app (redirect https)

/// WKWebView che intercetta il ritorno al redirect URL e apre fuori i link alle app delle banche.
fileprivate struct WebAutorizzazione: UIViewRepresentable {
    let url: URL
    let redirectURL: String
    let ritorno: (URL) -> Void

    func makeCoordinator() -> Coordinatore { Coordinatore(redirect: URL(string: redirectURL), ritorno: ritorno) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinatore: NSObject, WKNavigationDelegate, WKUIDelegate {
        let redirect: URL?
        let ritorno: (URL) -> Void
        private var concluso = false

        init(redirect: URL?, ritorno: @escaping (URL) -> Void) {
            self.redirect = redirect
            self.ritorno = ritorno
        }

        private func èRedirect(_ u: URL) -> Bool {
            guard let r = redirect else { return false }
            return u.scheme?.lowercased() == r.scheme?.lowercased() && u.host()?.lowercased() == r.host()?.lowercased()
                && u.path().hasPrefix(r.path())
        }

        private func concludi(_ u: URL) {
            guard !concluso else { return }
            concluso = true
            ritorno(u)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let u = navigationAction.request.url else { return .allow }
            if èRedirect(u) {
                concludi(u)
                return .cancel
            }
            let schema = u.scheme?.lowercased() ?? ""
            if !["http", "https", "about", "blob", "data", "javascript"].contains(schema) {
                // app della banca (SCA): si apre fuori, poi si torna qui
                _ = await UIApplication.shared.open(u)
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            // alcuni redirect arrivano solo come errore di caricamento (localhost non risponde)
            if let u = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL, èRedirect(u) { concludi(u) }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // link target=_blank: li apre nella stessa pagina
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }
}
