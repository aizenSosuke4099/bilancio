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
                Text("Il backup è la copia completa del database, foto degli scontrini comprese. Salvalo su iCloud Drive o sul Mac: se perdi l'iPhone, una copia solo sul telefono non basta.")
            }

            Section("Stato") {
                LabeledContent("Ultimo backup locale", value: Backup.ultimoBackup.map(descrivi) ?? "mai")
                LabeledContent("Ultimo salvato fuori dall'iPhone", value: Backup.ultimoEsportato.map(descrivi) ?? "mai")
            }

            Section {
                if locali.isEmpty { Text("Nessun backup locale").foregroundStyle(.secondary) }
                ForEach(locali, id: \.self) { url in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                        Text(Backup.dimensione(url).formatted(.byteCount(style: .file).locale(localeIT)))
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
                Text("Uno automatico a settimana; si tengono gli ultimi 4. Li trovi anche in File › Sul mio iPhone › Bilancio › Backup.")
            }

            Section {
                Button(role: .destructive) { mostraImportazione = true } label: {
                    Label("Ripristina da una cartella di backup…", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Ripristino")
            } footer: {
                Text("Sostituisce tutti i dati attuali con quelli del backup. I dati attuali vengono conservati in una copia di sicurezza.")
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
                    switch risultato {
                    case .success:
                        if esportaBackup { Backup.segnaEsportato() }
                        messaggio = esportaBackup ? "Backup salvato." : "CSV salvato."
                    case .failure(let e):
                        messaggio = e.localizedDescription
                    }
                    aggiorna()
                }
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
        d.formatted(.relative(presentation: .named).locale(localeIT))
    }

    private func aggiorna() {
        locali = Backup.elenco()
        inSospeso = Backup.ripristinoInSospeso
    }

    private func creaEdEsporta() {
        do {
            try context.save()
            esporta(try Backup.crea())
        } catch {
            messaggio = "Backup non riuscito: \(error.localizedDescription)"
        }
        aggiorna()
    }

    private func esporta(_ cartella: URL) {
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
            try Backup.preparaRipristino(da: url)
            messaggio = "Ripristino pronto. Chiudi e riapri l'app per completare."
        } catch {
            messaggio = error.localizedDescription
        }
        aggiorna()
    }
}
