import SwiftUI
import SwiftData

/// Aggiunta o modifica di uno strumento. Dall'ISIN cerca i listini su Yahoo e compila nome, valuta e prezzo.
struct StrumentoEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let strumento: Strumento?
    /// Chiamata quando l'utente elimina lo strumento (chi apre l'editor chiude il dettaglio).
    var onElimina: (() -> Void)? = nil

    private static let altra = "__altra"

    @State private var tipo: TipoStrumento = .etf
    @State private var isin = ""
    @State private var nome = ""
    @State private var nomeAutomatico = ""
    @State private var ticker: String?
    @State private var listini: [Prezzi.Listino] = []
    @State private var cercando = false
    @State private var quotazione: Prezzi.Quotazione?
    @State private var piattaforma = Portafoglio.piattaformeNote[0]
    @State private var piattaformaAltra = ""
    @State private var valuta = "EUR"
    @State private var valoreManuale = false
    @State private var cedola = ""
    @State private var conScadenza = false
    @State private var scadenza = Date()
    @State private var fondoPensioneItaliano = false
    @State private var archiviato = false
    // posizione iniziale (solo per un nuovo strumento)
    @State private var conSituazione = true
    @State private var quoteIniziali = ""
    @State private var versatoIniziale = ""
    @State private var valoreIniziale = ""
    @State private var dataIniziale = Date()
    @State private var caricato = false
    @State private var chiediElimina = false

    private var isinPulito: String { isin.trimmingCharacters(in: .whitespaces).uppercased() }
    private var isinObbligatorio: Bool { tipo.quotato }
    private var isinOK: Bool { isinPulito.isEmpty ? !isinObbligatorio : CalcoliInvestimenti.isinValido(isinPulito) }
    private var nomePiattaforma: String { piattaforma == Self.altra ? piattaformaAltra.trimmingCharacters(in: .whitespaces) : piattaforma }
    private var conQuote: Bool { !valoreManuale }
    private var valute: [String] { Array(Set(["EUR", "CHF", "USD", "GBP", valuta])).sorted { $0 == "EUR" ? true : ($1 == "EUR" ? false : $0 < $1) } }

    private var situazioneOK: Bool {
        guard strumento == nil, conSituazione else { return true }
        let versato = leggiNumero(versatoIniziale) ?? 0
        if conQuote { return (leggiNumero(quoteIniziali) ?? 0) > 0 && versato >= 0 }
        return versato > 0 || (leggiNumero(valoreIniziale) ?? 0) > 0
    }

    private var valido: Bool {
        !nome.trimmingCharacters(in: .whitespaces).isEmpty && isinOK && !nomePiattaforma.isEmpty && situazioneOK
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $tipo) {
                        ForEach(TipoStrumento.allCases) { Text($0.etichetta).tag($0) }
                    }
                    TextField(isinObbligatorio ? "ISIN" : "ISIN (facoltativo)", text: $isin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    if !isinPulito.isEmpty && !CalcoliInvestimenti.isinValido(isinPulito) {
                        Text(isinPulito.count == 12 ? "Cifra di controllo errata: ricontrolla l'ISIN." : "L'ISIN ha 12 caratteri: 2 lettere del paese, 9 caratteri, 1 cifra.")
                            .font(.caption).foregroundStyle(.red)
                    }
                    if cercando {
                        HStack { ProgressView(); Text("Cerco su Yahoo Finance…").foregroundStyle(.secondary) }
                    } else if !listini.isEmpty || ticker != nil {
                        Picker("Listino", selection: $ticker) {
                            Text("Nessuno (prezzo a mano)").tag(String?.none)
                            ForEach(listini) { l in
                                Text("\(l.simbolo) · \(l.borsa)").tag(Optional(l.simbolo))
                            }
                            if let t = ticker, !listini.contains(where: { $0.simbolo == t }) {
                                Text(t).tag(Optional(t))
                            }
                        }
                    } else if CalcoliInvestimenti.isinValido(isinPulito) {
                        Text("Nessun listino trovato: potrai inserire il prezzo a mano dal dettaglio.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let q = quotazione {
                        LabeledContent("Prezzo", value: q.prezzo.valuta(q.valuta) + (tipo == .obbligazione ? " (%)" : ""))
                    }
                    TextField("Nome", text: $nome)
                } header: {
                    Text("Strumento")
                } footer: {
                    if !isinObbligatorio { Text("Per fondi pensione e gestioni l'ISIN è facoltativo: il valore lo aggiorni tu.") }
                }

                Section("Dove") {
                    Picker("Piattaforma", selection: $piattaforma) {
                        ForEach(Portafoglio.piattaformeNote, id: \.self) { Text($0).tag($0) }
                        Text("Altra…").tag(Self.altra)
                    }
                    if piattaforma == Self.altra {
                        TextField("Nome piattaforma", text: $piattaformaAltra)
                    }
                    Picker("Valuta", selection: $valuta) {
                        ForEach(valute, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Valore aggiornato a mano", isOn: $valoreManuale)
                }

                if tipo == .obbligazione {
                    Section {
                        CampoNumeroInvestimenti(titolo: "Cedola annua", testo: $cedola, unita: "%")
                        Toggle("Ha una scadenza", isOn: $conScadenza)
                        if conScadenza { DatePicker("Scadenza", selection: $scadenza, displayedComponents: .date) }
                    } header: {
                        Text("Obbligazione")
                    } footer: {
                        Text("Il prezzo è in % del nominale; le quote sono il valore nominale posseduto.")
                    }
                }

                if tipo == .fondoPensione {
                    Section {
                        Toggle("Fondo pensione italiano (deducibile)", isOn: $fondoPensioneItaliano)
                    } footer: {
                        Text("I versamenti sono deducibili fino a \(CalcoliConsigli.massimoDeducibileFondoPensione.euro) l'anno: il dettaglio mostra quanto hai già versato.")
                    }
                }

                if strumento == nil {
                    Section {
                        Picker("Posizione iniziale", selection: $conSituazione) {
                            Text("Situazione attuale").tag(true)
                            Text("Singole operazioni").tag(false)
                        }
                        .pickerStyle(.segmented)
                        if conSituazione {
                            if conQuote {
                                CampoNumeroInvestimenti(titolo: tipo == .obbligazione ? "Nominale posseduto" : "Quote possedute", testo: $quoteIniziali)
                            }
                            CampoNumeroInvestimenti(titolo: "Totale versato", testo: $versatoIniziale, unita: valuta)
                            CampoNumeroInvestimenti(titolo: "Valore attuale", testo: $valoreIniziale, unita: valuta)
                            DatePicker("Alla data", selection: $dataIniziale, in: ...Date(), displayedComponents: .date)
                        }
                    } header: {
                        Text("Quanto hai già")
                    } footer: {
                        Text(conSituazione
                             ? (conQuote ? "Le quote e il versato li trovi nell'app della piattaforma. Il valore serve solo se Yahoo non trova il prezzo."
                                         : "Da qui in poi aggiorna il valore dal dettaglio quando la piattaforma ti manda il rendiconto.")
                             : "Dopo il salvataggio aggiungi acquisti e versamenti dal dettaglio dello strumento.")
                    }
                }

                if strumento != nil {
                    Section {
                        Toggle("Archiviato", isOn: $archiviato)
                        Button("Elimina strumento", role: .destructive) { chiediElimina = true }
                    } footer: {
                        Text("Gli strumenti archiviati non contano nei totali. Eliminando lo strumento si cancellano anche le sue operazioni.")
                    }
                }
            }
            .navigationTitle(strumento == nil ? "Nuovo strumento" : "Modifica strumento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { salva() }.disabled(!valido) }
            }
            .confirmationDialog("Eliminare \(nome)?", isPresented: $chiediElimina, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    dismiss()
                    onElimina?()
                }
            } message: {
                Text("Si cancellano anche operazioni e valutazioni. I movimenti dei conti restano.")
            }
            .onAppear(perform: carica)
            .onChange(of: tipo) { _, nuovo in
                if strumento == nil { valoreManuale = !nuovo.quotato }
            }
            .task(id: isinPulito) { await cercaListini() }
            .onChange(of: ticker) { _, nuovo in
                Task { await scegliListino(nuovo) }
            }
        }
    }

    // MARK: - Azioni

    private func carica() {
        guard !caricato else { return }
        caricato = true
        guard let s = strumento else { valoreManuale = !tipo.quotato; return }
        tipo = s.tipo
        isin = s.isin
        nome = s.nome
        ticker = s.ticker
        if Portafoglio.piattaformeNote.contains(s.piattaforma) { piattaforma = s.piattaforma } else { piattaforma = Self.altra; piattaformaAltra = s.piattaforma }
        valuta = s.valuta
        valoreManuale = s.valoreManuale
        cedola = CalcoliInvestimenti.testoNumero(s.cedola)
        conScadenza = s.scadenza != nil
        scadenza = s.scadenza ?? Date()
        fondoPensioneItaliano = s.fondoPensioneItaliano
        archiviato = s.archiviato
    }

    private func cercaListini() async {
        guard CalcoliInvestimenti.isinValido(isinPulito) else { listini = []; cercando = false; return }
        // modifica: l'ISIN salvato ha già il suo listino, non si rifà la ricerca all'apertura
        if let s = strumento, s.isin == isinPulito, s.ticker != nil, listini.isEmpty, ticker == s.ticker { return }
        cercando = true
        let trovati = await Prezzi.cerca(isin: isinPulito)
        guard !Task.isCancelled else { return }
        cercando = false
        listini = trovati
        if let primo = trovati.first, ticker == nil || !trovati.contains(where: { $0.simbolo == ticker }) {
            ticker = primo.simbolo
        }
    }

    private func scegliListino(_ simbolo: String?) async {
        guard let simbolo else { quotazione = nil; return }
        if let l = listini.first(where: { $0.simbolo == simbolo }), nome.isEmpty || nome == nomeAutomatico {
            nome = l.nome
            nomeAutomatico = l.nome
        }
        guard let q = await Prezzi.quotazione(simbolo), ticker == simbolo else { return }
        quotazione = q
        valuta = q.valuta
        if nome.isEmpty, let n = q.nome { nome = n; nomeAutomatico = n }
    }

    private func salva() {
        let s = strumento ?? Strumento(nome: nome, isin: isinPulito, tipo: tipo, piattaforma: nomePiattaforma, valuta: valuta)
        if strumento == nil { context.insert(s) }
        s.nome = nome.trimmingCharacters(in: .whitespaces)
        s.isin = isinPulito
        s.tipo = tipo
        if s.ticker != ticker { s.ultimoPrezzo = nil; s.ultimoPrezzoData = nil }
        s.ticker = ticker
        s.piattaforma = nomePiattaforma
        s.valuta = valuta
        s.valoreManuale = valoreManuale
        s.cedola = tipo == .obbligazione ? leggiNumero(cedola) : nil
        s.scadenza = tipo == .obbligazione && conScadenza ? scadenza : nil
        s.fondoPensioneItaliano = tipo == .fondoPensione && fondoPensioneItaliano
        s.archiviato = archiviato
        if let q = quotazione, q.valuta == valuta {
            s.ultimoPrezzo = q.prezzo
            s.ultimoPrezzoData = q.data ?? Date()
        }
        if strumento == nil && conSituazione { creaSituazione(s) }
        try? context.save()
        if valuta != "EUR" {
            // serve subito il cambio per i totali in euro
            let v = valuta
            Task { if let c = await Prezzi.cambio(v) { Portafoglio.salvaCambio(v, c) } }
        }
        dismiss()
    }

    /// Una sola operazione che riassume quanto posseduto oggi (+ la valutazione per i valori manuali).
    private func creaSituazione(_ s: Strumento) {
        let versato = leggiNumero(versatoIniziale) ?? 0
        let valore = leggiNumero(valoreIniziale)
        let fattore = tipo == .obbligazione ? 100.0 : 1
        let cambio = Portafoglio.cambio(valuta)
        if conQuote, let q = leggiNumero(quoteIniziali), q > 0 {
            let op = Operazione(data: dataIniziale, tipo: .acquisto, quote: q, prezzo: versato / q * fattore, importo: versato, cambioEUR: cambio)
            op.nota = String(localized: "Situazione iniziale")
            context.insert(op)
            op.strumento = s
            if s.ultimoPrezzo == nil, let v = valore, v > 0 {
                s.ultimoPrezzo = v / q * fattore
                s.ultimoPrezzoData = dataIniziale
            }
        } else {
            if versato > 0 {
                let op = Operazione(data: dataIniziale, tipo: .versamento, quote: 0, prezzo: 0, importo: versato, cambioEUR: cambio)
                op.nota = String(localized: "Situazione iniziale")
                context.insert(op)
                op.strumento = s
            }
            if let v = valore, v > 0 {
                let val = Valutazione(data: dataIniziale, valore: v)
                context.insert(val)
                val.strumento = s
            }
        }
    }
}

/// Campo numerico all'italiana con unità a destra (usato in tutta l'area Investimenti).
struct CampoNumeroInvestimenti: View {
    let titolo: LocalizedStringKey
    @Binding var testo: String
    var unita: String? = nil

    var body: some View {
        HStack {
            Text(titolo)
            Spacer()
            TextField("0", text: $testo)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
            if let unita { Text(unita).foregroundStyle(.secondary) }
        }
    }
}
