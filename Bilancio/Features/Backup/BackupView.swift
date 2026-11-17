import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupView: View {
    @Environment(\.modelContext) private var context
    @State private var locali: [URL] = []
    @State private var documento: DocumentoBackupEsportato?
    @State private var tipoDocumento: UTType = .folder
    @State private var nomeDocumento = ""
    @State private var esportaBackup = false
    @State private var mostraEsportazione = false
    @State private var mostraImportazione = false
    @State private var messaggio: String?
    @State private var daRipristinare: URL?
    @State private var inSospeso = Backup.ripristinoInSospeso
    /// Backup locale da esportare: prima si chiede la password.
    @State private var daCifrare: URL?
    /// Copia cifrata temporanea, cancellata dopo l'esportazione.
    @State private var temporaneo: URL?
    @State private var cifrando = false
    /// Backup cifrato scelto per il ripristino: serve la password.
    @State private var cifratoDaRipristinare: URL?
    @State private var passwordRipristino = ""

    var body: some View {
        List {
            if inSospeso {
                Section {
                    Label("Ripristino pronto. Chiudi l'app (scorri via dal multitasking) e riaprila per completarlo.", systemImage: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button { creaEdEsporta() } label: { Label("Crea backup e salva in File…", systemImage: "externaldrive.badge.plus") }
                Button { esportaCSV() } label: { Label("Esporta movimenti in CSV (Excel)", systemImage: "tablecells") }
            } header: {
                Text("Esporta")
            } footer: {
                Text("Il backup contiene tutti i dati in formato aperto (JSON) e le foto degli scontrini: si legge anche su Android o al computer. Quando esce dall'iPhone è protetto dalla tua password (AES-256): conservala, per esempio in un gestore di password, perché senza non si apre. Il CSV invece è in chiaro.")
            }

            Section("Stato") {
                LabeledContent("Ultimo backup locale", value: Backup.ultimoBackup.map(descrivi) ?? String(localized: "mai"))
                LabeledContent("Ultimo salvato fuori dall'iPhone", value: Backup.ultimoEsportato.map(descrivi) ?? String(localized: "mai"))
                if let e = Backup.erroreAutomatico {
                    Text("L'ultimo backup automatico non è riuscito: \(e)").font(.footnote).foregroundStyle(.red)
                }
            }

            Section {
                if locali.isEmpty { Text("Nessun backup locale").foregroundStyle(.secondary) }
                ForEach(locali, id: \.self) { url in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                        Text(Backup.dimensione(url).formatted(.byteCount(style: .file)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Elimina", role: .destructive) { try? FileManager.default.removeItem(at: url); aggiorna() }
                        Button("Ripristina") { daRipristinare = url }.tint(.orange)
                    }
                    .contextMenu {
                        Button { esporta(url) } label: { Label("Salva in File…", systemImage: "square.and.arrow.up") }
                        Button { daRipristinare = url } label: { Label("Ripristina questo backup", systemImage: "arrow.counterclockwise") }
                    }
                }
            } header: {
                Text("Backup sul telefono")
            } footer: {
                Text("Uno automatico a settimana; si tengono gli ultimi 4. Restano dentro l'app, dietro Face ID: per portarne uno fuori tienilo premuto e scegli «Salva in File…», che lo protegge con la tua password.")
            }

            Section {
                Button(role: .destructive) { mostraImportazione = true } label: {
                    Label("Ripristina da una cartella di backup…", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Ripristino")
            } footer: {
                Text("Sostituisce tutti i dati attuali con quelli del backup. Prima i dati attuali vengono salvati come backup in questo elenco, così puoi tornare indietro.")
            }
        }
        .navigationTitle("Backup")
        .onAppear(perform: aggiorna)
        .fileImporter(isPresented: $mostraImportazione, allowedContentTypes: [.folder]) { risultato in
            switch risultato {
            case .success(let url): daRipristinare = url
            case .failure(let e): messaggio = e.localizedDescription
            }
        }
        // su una vista separata: due presentatori di file sulla stessa vista possono intralciarsi
        .background {
            Color.clear
                .fileExporter(isPresented: $mostraEsportazione, document: documento, contentType: tipoDocumento, defaultFilename: nomeDocumento) { risultato in
                    if let t = temporaneo { try? FileManager.default.removeItem(at: t); temporaneo = nil }
                    switch risultato {
                    case .success:
                        if esportaBackup { Backup.segnaEsportato() }
                        messaggio = esportaBackup ? String(localized: "Backup salvato.") : String(localized: "CSV salvato.")
                    case .failure(let e):
                        messaggio = e.localizedDescription
                    }
                    aggiorna()
                }
        }
        .sheet(isPresented: Binding(get: { daCifrare != nil }, set: { if !$0 { daCifrare = nil } })) {
            NavigationStack { PasswordBackup { password in esportaCifrato(password) } }
        }
        .overlay { if cifrando { ProgressView("Cifro il backup…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .alert("Password del backup", isPresented: Binding(get: { cifratoDaRipristinare != nil }, set: { if !$0 { cifratoDaRipristinare = nil; passwordRipristino = "" } })) {
            SecureField("Password", text: $passwordRipristino)
            Button("Ripristina", role: .destructive) { ripristinaCifrato() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Questo backup è protetto da password.")
        }
        .confirmationDialog("Ripristinare questo backup?", isPresented: Binding(get: { daRipristinare != nil }, set: { if !$0 { daRipristinare = nil } }), titleVisibility: .visible) {
            Button("Ripristina", role: .destructive) { ripristina() }
        } message: {
            Text("Tutti i dati attuali verranno sostituiti alla prossima apertura dell'app.")
        }
        .alert(messaggio ?? "", isPresented: Binding(get: { messaggio != nil }, set: { if !$0 { messaggio = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func descrivi(_ d: Date) -> String {
        d.formatted(.relative(presentation: .named))
    }

    private func aggiorna() {
        locali = Backup.elenco()
        inSospeso = Backup.ripristinoInSospeso
    }

    private func creaEdEsporta() {
        do {
            try context.save()
            esporta(try Backup.crea(in: context))
        } catch {
            messaggio = String(localized: "Backup non riuscito: \(error.localizedDescription)")
        }
        aggiorna()
    }

    /// Fuori dall'iPhone il backup va solo cifrato: prima la password.
    private func esporta(_ cartella: URL) { daCifrare = cartella }

    private func esportaCifrato(_ password: String) {
        guard let sorgente = daCifrare else { return }
        daCifrare = nil
        cifrando = true
        let destinazione = FileManager.default.temporaryDirectory.appending(path: "esporta-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: sorgente.lastPathComponent, directoryHint: .isDirectory)
        Task {
            do {
                // PBKDF2 e AES su tutte le foto: fuori dal thread principale
                try await Task.detached { try CifraturaBackup.cifra(sorgente, in: destinazione, password: password) }.value
                temporaneo = destinazione.deletingLastPathComponent()
                presentaEsportazione(destinazione)
            } catch {
                try? FileManager.default.removeItem(at: destinazione.deletingLastPathComponent())
                messaggio = error.localizedDescription
            }
            cifrando = false
        }
    }

    private func presentaEsportazione(_ cartella: URL) {
        do {
            documento = DocumentoBackupEsportato(wrapper: try FileWrapper(url: cartella))
            tipoDocumento = .folder
            nomeDocumento = cartella.lastPathComponent
            esportaBackup = true
            mostraEsportazione = true
        } catch {
            messaggio = error.localizedDescription
        }
    }

    private func esportaCSV() {
        let dati = Data(Backup.csvMovimenti(in: context).utf8)
        documento = DocumentoBackupEsportato(wrapper: FileWrapper(regularFileWithContents: dati))
        tipoDocumento = .commaSeparatedText
        nomeDocumento = "Movimenti-\(Backup.timbro(Date())).csv"
        esportaBackup = false
        mostraEsportazione = true
    }

    private func ripristina() {
        guard let url = daRipristinare else { return }
        daRipristinare = nil
        do {
            pronto(try Backup.preparaRipristino(da: url))
        } catch CifraturaBackup.Errore.serveLaPassword {
            cifratoDaRipristinare = url
        } catch {
            messaggio = error.localizedDescription
        }
        aggiorna()
    }

    /// Ripristino preparato: i dati di adesso diventano un backup normale dell'elenco (se era il backup sbagliato si
    /// torna indietro da lì), poi si dice cosa fare.
    private func pronto(_ fotoMancanti: Int) {
        try? context.save()
        if ((try? context.fetchCount(FetchDescriptor<Movimento>())) ?? 0) > 0 { _ = try? Backup.crea(in: context) }
        messaggio = fotoMancanti == 0
            ? String(localized: "Ripristino pronto. Chiudi e riapri l'app per completare.")
            : String(localized: "Ripristino pronto, ma nel backup mancano \(fotoMancanti) foto di scontrini. Chiudi e riapri l'app per completare.")
    }

    private func ripristinaCifrato() {
        guard let url = cifratoDaRipristinare else { return }
        let password = passwordRipristino
        cifratoDaRipristinare = nil
        passwordRipristino = ""
        do {
            pronto(try Backup.preparaRipristino(da: url, password: password))
        } catch {
            messaggio = error.localizedDescription
        }
        aggiorna()
    }
}

/// Password per il backup esportato, scritta due volte.
private struct PasswordBackup: View {
    let conferma: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var ripeti = ""

    private var valida: Bool { password.count >= CifraturaBackup.lunghezzaMinima && password == ripeti }

    var body: some View {
        Form {
            Section {
                SecureField("Password", text: $password)
                SecureField("Ripeti la password", text: $ripeti)
            } footer: {
                Text("Almeno \(CifraturaBackup.lunghezzaMinima) caratteri. Senza questa password il backup non si può aprire in nessun modo: salvala in un gestore di password.")
            }
        }
        .navigationTitle("Proteggi il backup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Esporta") { conferma(password); dismiss() }.disabled(!valida)
            }
        }
    }
}
