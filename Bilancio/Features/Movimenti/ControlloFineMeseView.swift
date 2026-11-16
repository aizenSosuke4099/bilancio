import SwiftUI
import SwiftData

/// Controllo di fine mese: movimenti da confermare, scontrini senza pagamento bancario,
/// pagamenti senza scontrino, saldo contanti. Vista "pushata".
struct ControlloFineMeseView: View {
    var mese: Date

    @Environment(\.modelContext) private var context
    @Query private var movimenti: [Movimento]
    @Query private var contiContanti: [Conto]
    @State private var daModificare: Movimento?

    /// Categorie in cui di solito c'è uno scontrino da scansionare (nomi iniziali italiani, confrontati con `DatiIniziali.corrisponde`).
    private static let categorieDaScontrino: Set<String> = ["Spesa alimentare", "Casa e pulizia", "Cura personale", "Salute"]

    init(mese: Date) {
        self.mese = mese.inizioMese
        let da = mese.inizioMese, a = mese.inizioMeseSuccessivo
        _movimenti = Query(filter: #Predicate { $0.data >= da && $0.data < a }, sort: \.data, order: .reverse)
        let contanti = TipoConto.contanti.rawValue
        _contiContanti = Query(filter: #Predicate { $0.tipoRaw == contanti })
    }

    /// Gli scontrini in attesa della banca hanno la loro sezione.
    private var daConfermare: [Movimento] { movimenti.filter { $0.daConfermare && !Abbinamento.attendeBanca($0) } }
    /// Scontrini pagati con carta o conto senza il movimento arrivato dalla banca, non ancora verificati.
    private var scontriniSenzaBanca: [Movimento] { movimenti.filter { $0.daConfermare && Abbinamento.attendeBanca($0) } }
    private var pagamentiSenzaScontrino: [Movimento] {
        movimenti.filter { m in
            m.idEsterno != nil && m.scontrino == nil && m.tipo == .spesa && !m.daConfermare   // quelli da confermare stanno già sopra
                && Self.categorieDaScontrino.contains { DatiIniziali.corrisponde(m.categoria?.nome, a: $0) }
        }
    }

    private func salva() { try? context.save() }

    private func eraInContanti(_ m: Movimento) {
        m.conto = DatiIniziali.contoContanti(in: context)
        m.conferma()
        salva()
    }

    /// Sposta lo scontrino sul movimento bancario ed elimina il doppione.
    private func collega(_ m: Movimento, a banca: Movimento) {
        guard let s = m.scontrino else { return }
        s.movimento = banca
        // lo scontrino l'hai già controllato: la sua categoria vale più di quella indovinata dalla descrizione della banca.
        // L'importo resta quello dell'addebito (mancia, valuta estera).
        if let c = m.categoria { banca.categoria = c }
        if banca.nota.isEmpty { banca.nota = m.nota }
        banca.conferma()
        context.delete(m)
        salva()
    }

    private func riga(_ m: Movimento) -> some View {
        Button { daModificare = m } label: {
            RigaMovimento(movimento: m).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        let confermare = daConfermare
        let scontrini = scontriniSenzaBanca
        let senzaScontrino = pagamentiSenzaScontrino
        let problemi = confermare.count + scontrini.count + senzaScontrino.count

        List {
            Section {
                if problemi == 0 {
                    Label("Tutto in ordine ✅", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    Label(problemi == 1 ? "1 cosa da controllare" : "\(problemi) cose da controllare", systemImage: "exclamationmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
            }

            if !confermare.isEmpty {
                Section {
                    ForEach(confermare) { m in
                        HStack(spacing: 12) {
                            riga(m)
                            Button { m.conferma(); salva() } label: {
                                Image(systemName: "checkmark.circle").font(.title2)
                            }
                            .buttonStyle(.borderless)
                            .tint(.green)
                            .accessibilityLabel("Conferma")
                        }
                    }
                    Button("Conferma tutti") {
                        for m in confermare { m.conferma() }
                        salva()
                    }
                } header: {
                    Text("Da confermare")
                }
            }

            if !scontrini.isEmpty {
                Section {
                    ForEach(scontrini) { m in
                        let compatibili = Abbinamento.pagamentiCollegabili(a: m, in: context)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                riga(m)
                                Button { m.conferma(); salva() } label: {
                                    Image(systemName: "checkmark.circle").font(.title2)
                                }
                                .buttonStyle(.borderless)
                                .tint(.green)
                                .accessibilityLabel("Conferma")
                            }
                            HStack {
                                Button("Era in contanti") { eraInContanti(m) }
                                Menu("Collega a un pagamento") {
                                    ForEach(compatibili) { b in
                                        Button([b.titolo.isEmpty ? b.tipo.etichetta : b.titolo, b.data.giornoMese, b.importo.euro, b.conto?.nome ?? ""].joined(separator: " · ")) {
                                            collega(m, a: b)
                                        }
                                    }
                                }
                                .disabled(compatibili.isEmpty)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            if compatibili.isEmpty {
                                Text(Abbinamento.giorni(da: m.data, a: Date()) <= Abbinamento.giorniAddebito
                                     ? "L'addebito non è ancora arrivato: di solito arriva entro qualche giorno e si collega da solo."
                                     : "Nessun pagamento bancario compatibile nelle settimane dopo lo scontrino.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Scontrini senza pagamento bancario")
                } footer: {
                    Text("Se l'hai pagato in contanti spostalo sul conto Contanti; se il pagamento è arrivato dalla banca collegalo, così non conta due volte. Se va bene così (per esempio una carta non collegata), confermalo con ✓.")
                }
            }

            if !senzaScontrino.isEmpty {
                Section {
                    ForEach(senzaScontrino) { riga($0) }
                } header: {
                    Text("Pagamenti senza scontrino")
                } footer: {
                    Text("Promemoria: se hai ancora lo scontrino, scansionalo. Le righe finiscono nelle categorie giuste e nella pagina Inflazione.")
                }
            }

            Section {
                if let contanti = contiContanti.first {
                    LabeledContent("Saldo contanti", value: Contabilita.saldo(contanti).euro)
                }
                NavigationLink {
                    ContiView()
                } label: {
                    Label("Conta i contanti", systemImage: "banknote")
                }
            } header: {
                Text("Contanti")
            } footer: {
                Text("Conta i soldi nel portafoglio: se il saldo non torna, correggilo dalla pagina Conti.")
            }
        }
        .navigationTitle("Controllo di fine mese")
        .navigationSubtitle(mese.meseAnno)
        .sheet(item: $daModificare) { m in
            NavigationStack { MovimentoEditorView(movimento: m) }
        }
    }
}
