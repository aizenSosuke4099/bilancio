import SwiftUI
import SwiftData

/// Dettaglio di uno scontrino salvato (usato anche dall'Archivio). Vista "pushata": niente NavigationStack.
struct ScontrinoDettaglioView: View {
    let scontrino: Scontrino

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var immagine: UIImage?
    @State private var mostraImmagine = false
    @State private var mostraModifica = false
    @State private var chiediEliminazione = false
    @State private var errore: String?
    /// Dopo l'eliminazione la vista non deve più leggere il modello (SwiftData andrebbe in crash).
    @State private var eliminato = false

    var body: some View {
        if eliminato {
            Color(.systemGroupedBackground).ignoresSafeArea()
        } else {
            contenuto
        }
    }

    private var contenuto: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let immagine {
                    Button { mostraImmagine = true } label: {
                        Image(uiImage: immagine).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.bold()).padding(6)
                                    .background(.thinMaterial, in: Circle()).padding(8)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ingrandisci la foto dello scontrino")
                }

                Scheda {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(scontrino.negozio.isEmpty ? String(localized: "Scontrino") : scontrino.negozio).font(.title2.bold())
                        if !scontrino.indirizzo.isEmpty { Text(scontrino.indirizzo).font(.subheadline).foregroundStyle(.secondary) }
                        HStack {
                            Label(scontrino.data.formatted(.dateTime.day().month(.wide).year().hour().minute()), systemImage: "calendar")
                                .font(.subheadline)
                            Spacer()
                            Text(scontrino.totale.euro).font(.title3.bold().monospacedDigit())
                        }
                        if !scontrino.partitaIva.isEmpty {
                            Text("P.IVA \(scontrino.partitaIva)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Scheda(titolo: "Righe", etichetta: "\(scontrino.righe.count)") {
                    if scontrino.righe.isEmpty {
                        Text("Nessuna riga").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(scontrino.righeOrdinate) { r in
                        HStack(spacing: 10) {
                            IconaCategoria(categoria: r.categoria, dimensione: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.prodotto?.nome ?? r.testo).font(.subheadline).lineLimit(1)
                                Text(dettaglio(r)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(r.totale.euro).font(.callout.monospacedDigit())
                        }
                        .padding(.vertical, 2)
                    }
                    let somma = scontrino.righe.reduce(0) { $0 + $1.totale }
                    if !scontrino.righe.isEmpty, abs(somma - scontrino.totale) >= 0.01 {
                        Label("Somma righe \(somma.euro) diversa dal totale", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Scheda(titolo: "Pagamento") {
                    if let m = scontrino.movimento {
                        RigaMovimento(movimento: m)
                        HStack(spacing: 6) {
                            Image(systemName: m.conto?.tipo.icona ?? "questionmark.circle")
                            Text(m.conto?.nome ?? String(localized: "Conto non indicato"))
                            Text("·")
                            Text(m.origine == .scontrino ? "creato dallo scontrino" : "collegato a \(m.origine.etichetta.lowercased())")
                            Spacer()
                            Text(m.daConfermare ? "Da confermare" : "Confermato").foregroundStyle(m.daConfermare ? .blue : .green)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Nessun movimento collegato").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(scontrino.negozio.isEmpty ? String(localized: "Scontrino") : scontrino.negozio)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let immagine {
                    ShareLink(item: Image(uiImage: immagine), preview: SharePreview("Scontrino \(scontrino.negozio)", image: Image(uiImage: immagine)))
                }
                Menu {
                    Button("Modifica", systemImage: "pencil") { mostraModifica = true }
                    Button("Elimina scontrino", systemImage: "trash", role: .destructive) { chiediEliminazione = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task {
            guard immagine == nil, let dati = scontrino.immagine else { return }
            immagine = UIImage(data: dati)
        }
        .fullScreenCover(isPresented: $mostraImmagine) {
            if let immagine { FotoSchermoInteroScansione(immagine: immagine) }
        }
        .sheet(isPresented: $mostraModifica) {
            NavigationStack { ModificaScontrinoScansioneView(scontrino: scontrino) }
        }
        .confirmationDialog("Eliminare lo scontrino?", isPresented: $chiediEliminazione, titleVisibility: .visible) {
            if let m = scontrino.movimento, m.origine == .scontrino {
                Button("Elimina scontrino e spesa", role: .destructive) { elimina(conMovimento: true) }
                Button("Elimina solo lo scontrino", role: .destructive) { elimina(conMovimento: false) }
            } else {
                Button("Elimina scontrino", role: .destructive) { elimina(conMovimento: false) }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            if let m = scontrino.movimento, m.origine == .scontrino {
                Text("La spesa di \(abs(m.importo).euro) è stata creata da questo scontrino: puoi eliminarla insieme allo scontrino o tenerla.")
            } else if scontrino.movimento != nil {
                Text("Il movimento della banca resta: si elimina solo lo scontrino con le sue righe.")
            } else {
                Text("Lo scontrino e le sue righe verranno eliminati.")
            }
        }
        .alert("Eliminazione non riuscita", isPresented: Binding(get: { errore != nil }, set: { if !$0 { errore = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errore ?? "") }
    }

    private func dettaglio(_ r: RigaScontrino) -> String {
        var parti: [String] = []
        if r.prodotto != nil { parti.append(r.testo) }
        if r.quantita != 1 { parti.append("\(r.quantita.quote) × \(r.prezzoUnitario.euro)") }
        let sconto = (r.quantita * r.prezzoUnitario - r.totale).centesimi
        if sconto >= 0.01 { parti.append(String(localized: "sconto \(sconto.euro)")) }
        parti.append(r.categoria?.nome ?? String(localized: "Senza categoria"))
        return parti.joined(separator: " · ")
    }

    private func elimina(conMovimento: Bool) {
        eliminato = true
        let movimento = scontrino.movimento
        scontrino.movimento = nil
        if conMovimento, let movimento { context.delete(movimento) }
        context.delete(scontrino)
        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            eliminato = false
            errore = error.localizedDescription
        }
    }
}

// MARK: - Modifica di uno scontrino salvato (le correzioni vengono imparate)

private struct ModificaScontrinoScansioneView: View {
    let scontrino: Scontrino

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Categoria> { $0.tipoRaw == "spesa" }, sort: \Categoria.ordine) private var categorie: [Categoria]
    @State private var negozio: String
    @State private var data: Date
    @State private var totale: Double
    @State private var righe: [RigaInRevisione]
    @State private var errore: String?

    init(scontrino: Scontrino) {
        self.scontrino = scontrino
        _negozio = State(initialValue: scontrino.negozio)
        _data = State(initialValue: scontrino.data)
        _totale = State(initialValue: scontrino.totale)
        _righe = State(initialValue: scontrino.righeOrdinate.map {
            RigaInRevisione(testo: $0.testo, quantita: $0.quantita, prezzoUnitario: $0.prezzoUnitario, totale: $0.totale,
                            categoria: $0.categoria, nomeProdotto: $0.prodotto?.nome ?? "", unita: $0.prodotto?.unita ?? "pz",
                            formato: $0.prodotto?.formato, imparata: true)
        })
    }

    var body: some View {
        Form {
            Section("Scontrino") {
                TextField("Negozio", text: $negozio)
                DatePicker("Data", selection: $data, displayedComponents: [.date, .hourAndMinute])
                LabeledContent("Totale") {
                    TextField("0,00", value: $totale, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                let somma = righe.reduce(0) { $0 + $1.totale }.centesimi
                if !righe.isEmpty, abs(somma - totale) >= 0.01 {
                    Button("Usa la somma delle righe (\(somma.euro))") { totale = somma }.font(.footnote)
                }
            }
            SezioneRigheScansione(righe: $righe, categorie: categorie)
        }
        .navigationTitle("Modifica scontrino")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva", action: salva).disabled(negozio.trimmingCharacters(in: .whitespaces).isEmpty || totale <= 0)
            }
        }
        .interactiveDismissDisabled()
        .alert("Salvataggio non riuscito", isPresented: Binding(get: { errore != nil }, set: { if !$0 { errore = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errore ?? "") }
    }

    private func salva() {
        let nome = negozio.trimmingCharacters(in: .whitespaces)
        scontrino.negozio = nome
        scontrino.data = data
        scontrino.totale = totale.centesimi
        SalvataggioScansione.scriviRighe(righe, in: scontrino, context: context)
        if let m = scontrino.movimento {
            if let c = SalvataggioScansione.categoriaPrevalente(righe) { m.categoria = c }
            // la spesa creata dallo scontrino segue lo scontrino; quella della banca resta com'è
            if m.origine == .scontrino {
                m.titolo = nome
                m.data = data
                m.importo = -totale.centesimi
            }
        }
        do {
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            context.rollback()
            errore = error.localizedDescription
        }
    }
}
