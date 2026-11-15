import SwiftUI

/// Confronta la versione installata (commit scritto da installa.sh nell'Info.plist) con l'ultima su GitHub.
/// iOS non permette a un'app di installarsi da sola: la versione nuova si installa dal Mac con installa.sh.
struct AggiornaAppView: View {
    static let repository = "aizenSosuke4099/bilancio"
    /// Commit da cui è stata compilata l'app (vuoto se compilata da Xcode senza installa.sh).
    static let commitInstallato = (Bundle.main.object(forInfoDictionaryKey: "BilancioCommit") as? String) ?? ""

    private enum Stato {
        case controllo
        case aggiornata
        case novita([Novita])
        case sconosciuta(ultima: Novita?)
        case errore(String)
    }
    struct Novita: Identifiable {
        let id: String
        let messaggio: String
        let data: Date?
    }

    @State private var stato = Stato.controllo

    var body: some View {
        List {
            Section {
                LabeledContent("Versione installata", value: Self.commitInstallato.isEmpty ? String(localized: "sconosciuta") : String(Self.commitInstallato.prefix(7)))
                switch stato {
                case .controllo:
                    HStack { ProgressView(); Text("Controllo su GitHub…").foregroundStyle(.secondary) }
                case .aggiornata:
                    Label("Hai l'ultima versione.", systemImage: "checkmark.circle.fill").foregroundStyle(Tinta.entrate)
                case .novita(let n):
                    Label(n.count == 1 ? String(localized: "C'è 1 aggiornamento.") : String(localized: "Ci sono \(n.count) aggiornamenti."),
                          systemImage: "arrow.down.circle.fill").foregroundStyle(.blue)
                case .sconosciuta(let ultima):
                    Text("Questa installazione non sa da quale versione è stata compilata: reinstalla con installa.sh per poterla confrontare.")
                        .foregroundStyle(.secondary)
                    if let ultima { riga(ultima) }
                case .errore(let e):
                    Label(e, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                }
            }

            if case .novita(let n) = stato {
                Section("Novità") { ForEach(n) { riga($0) } }
            }

            Section {
                Text("Collega l'iPhone al Mac e lancia installa.sh dalla cartella del progetto: scarica da GitHub la versione nuova e la installa. I dati restano sul telefono.")
                Link(destination: URL(string: "https://github.com/\(Self.repository)")!) {
                    Label("Apri il progetto su GitHub", systemImage: "safari")
                }
            } header: {
                Text("Come si installa")
            } footer: {
                Text("iOS non permette a un'app installata con un Apple ID gratuito di aggiornarsi da sola.")
            }
        }
        .navigationTitle("Aggiorna app")
        .refreshable { await controlla() }
        .task { await controlla() }
    }

    private func riga(_ n: Novita) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n.messaggio)
            if let d = n.data { Text(d.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
        }
    }

    // MARK: GitHub

    private struct RispostaCommit: Decodable {
        struct Commit: Decodable {
            struct Autore: Decodable { let date: Date? }
            let message: String
            let committer: Autore?
        }
        let sha: String
        let commit: Commit
        var novita: Novita {
            Novita(id: sha, messaggio: commit.message.components(separatedBy: "\n").first ?? "", data: commit.committer?.date)
        }
    }
    private struct RispostaConfronto: Decodable {
        let status: String
        let commits: [RispostaCommit]
    }

    private func controlla() async {
        let base = "https://api.github.com/repos/\(Self.repository)"
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            if Self.commitInstallato.isEmpty {
                let ultimo = try decoder.decode(RispostaCommit.self, from: try await scarica("\(base)/commits/main"))
                stato = .sconosciuta(ultima: ultimo.novita)
                return
            }
            let confronto = try decoder.decode(RispostaConfronto.self, from: try await scarica("\(base)/compare/\(Self.commitInstallato)...main"))
            // "ahead": main ha commit in più; "identical"/"behind": niente di nuovo da installare
            stato = confronto.status == "ahead" || confronto.status == "diverged"
                ? .novita(confronto.commits.reversed().map(\.novita))
                : .aggiornata
        } catch {
            stato = .errore(String(localized: "Impossibile controllare: \(error.localizedDescription)"))
        }
    }

    private func scarica(_ indirizzo: String) async throws -> Data {
        var richiesta = URLRequest(url: URL(string: indirizzo)!)
        richiesta.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (dati, risposta) = try await URLSession.shared.data(for: richiesta)
        guard (risposta as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return dati
    }
}
