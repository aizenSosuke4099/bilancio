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

    private var daConfermare: [Movimento] { movimenti.filter(\.daConfermare) }
    /// Scontrini registrati su un conto bancario ma senza il movimento arrivato dalla banca.
    private var scontriniSenzaBanca: [Movimento] {
        movimenti.filter { $0.scontrino != nil && $0.idEsterno == nil && $0.conto?.tipo != .contanti }
    }
    private var pagamentiSenzaScontrino: [Movimento] {
        movimenti.filter { m in
            m.idEsterno != nil && m.scontrino == nil && m.tipo == .spesa
                && Self.categorieDaScontrino.contains { DatiIniziali.corrisponde(m.categoria?.nome, a: $0) }
        }
    }

    /// Movimenti bancari compatibili: stesso importo, data ±3 giorni, senza scontrino.
    private func candidati(per m: Movimento) -> [Movimento] {
        let g = Abbinamento.giorniTolleranza
        return Contabilita.movimenti(da: m.data.aggiungendo(giorni: -g), a: m.data.aggiungendo(giorni: g + 1), in: context)
            .filter { $0.idEsterno != nil && $0.scontrino == nil && abs($0.importo - m.importo) < 0.011 && $0.persistentModelID != m.persistentModelID }
    }

    private func salva() { try? context.save() }

    private func eraInContanti(_ m: Movimento) {
        m.conto = DatiIniziali.contoContanti(in: context)
        salva()
    }

    /// Sposta lo scontrino sul movimento bancario ed elimina il doppione.
    private func collega(_ m: Movimento, a banca: Movimento) {
        guard let s = m.scontrino else { return }
        s.movimento = banca
        if banca.categoria == nil { banca.categoria = m.categoria }
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
                        let compatibili = candidati(per: m)
                        VStack(alignment: .leading, spacing: 8) {
                            riga(m)
                            HStack {
                                Button("Era in contanti") { eraInContanti(m) }
                                Menu("Collega a un pagamento") {
                                    ForEach(compatibili) { b in
                                        Button("\(b.titolo.isEmpty ? b.tipo.etichetta : b.titolo) · \(b.data.giornoMese) · \(b.conto?.nome ?? "")") {
                                            collega(m, a: b)
                                        }
                                    }
                                }
                                .disabled(compatibili.isEmpty)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            if compatibili.isEmpty {
                                Text("Nessun pagamento bancario con lo stesso importo entro ±\(Abbinamento.giorniTolleranza) giorni.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Scontrini senza pagamento bancario")
                } footer: {
                    Text("Se l'hai pagato in contanti spostalo sul conto Contanti; se il pagamento è arrivato dalla banca collegalo, così non conta due volte.")
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
