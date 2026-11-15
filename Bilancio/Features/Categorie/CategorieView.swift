import SwiftUI
import SwiftData

/// Categorie di spesa e di entrata: ordine, icona, colore, budget, detraibilità, eliminazione con riassegnazione.
struct CategorieView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Categoria.ordine) private var categorie: [Categoria]
    @State private var editor: RichiestaEditorCategoria?
    @State private var daEliminare: Categoria?

    var body: some View {
        List {
            sezione(.spesa, titolo: "Spese")
            sezione(.entrata, titolo: "Entrate")
        }
        .navigationTitle("Categorie e budget")
        .toolbar {
            EditButton()
            Menu {
                Button("Categoria di spesa") { editor = RichiestaEditorCategoria(categoria: nil, tipo: .spesa) }
                Button("Categoria di entrata") { editor = RichiestaEditorCategoria(categoria: nil, tipo: .entrata) }
            } label: { Image(systemName: "plus") }
        }
        .sheet(item: $editor) { r in
            NavigationStack { EditorCategoria(categoria: r.categoria, tipo: r.tipo) }
        }
        .sheet(item: $daEliminare) { c in
            NavigationStack { EliminaCategoria(categoria: c) }
        }
    }

    private func sezione(_ tipo: TipoMovimento, titolo: LocalizedStringKey) -> some View {
        let elenco = categorie.filter { $0.tipo == tipo }
        return Section {
            ForEach(elenco) { c in
                Button { editor = RichiestaEditorCategoria(categoria: c, tipo: tipo) } label: {
                    HStack(spacing: 10) {
                        IconaCategoria(categoria: c)
                        Text(c.nome).foregroundStyle(.primary)
                        if c.detraibile {
                            Text("730").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.pink.opacity(0.15), in: Capsule()).foregroundStyle(.pink)
                        }
                        Spacer()
                        if let b = c.budgetMensile, b > 0 { Text("\(b.euroTondo)/mese").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .swipeActions {
                    Button("Elimina") { daEliminare = c }.tint(.red)
                }
            }
            .onMove { origine, destinazione in
                var v = elenco
                v.move(fromOffsets: origine, toOffset: destinazione)
                for (i, c) in v.enumerated() { c.ordine = (tipo == .entrata ? 100 : 0) + i }
                try? context.save()
            }
        } header: {
            Text(titolo)
        } footer: {
            if tipo == .spesa { Text("Il budget mensile compare nella pagina Mese. «730» = spesa detraibile.") }
        }
    }
}

private struct RichiestaEditorCategoria: Identifiable {
    let categoria: Categoria?
    let tipo: TipoMovimento
    var id: AnyHashable { categoria.map { AnyHashable($0.persistentModelID) } ?? AnyHashable("nuova-\(tipo.rawValue)") }
}

// MARK: - Editor

private struct EditorCategoria: View {
    let categoria: Categoria?
    let tipo: TipoMovimento
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Categoria.ordine) private var categorie: [Categoria]
    @State private var nome = ""
    @State private var icona = "tag"
    @State private var colore = "#2563EB"
    @State private var budget: Double?
    @State private var detraibile = false

    private static let icone = [
        "cart", "basket", "bag", "house", "bolt", "drop", "flame", "wifi", "phone", "car", "bus", "tram", "bicycle", "fuelpump",
        "fork.knife", "cup.and.saucer", "wineglass", "birthday.cake", "repeat", "play.tv", "music.note", "gamecontroller",
        "theatermasks", "book", "graduationcap", "cross.case", "pills", "heart", "sparkles", "scissors", "tshirt", "shoe",
        "bubbles.and.sparkles", "hammer", "wrench.and.screwdriver", "pawprint", "leaf", "airplane", "suitcase", "bed.double",
        "desktopcomputer", "iphone", "gift", "figure.child", "dumbbell", "building.columns", "doc.text", "creditcard",
        "banknote", "percent", "arrow.uturn.backward.circle", "plus.circle", "tag", "ellipsis.circle",
    ]
    private static let tavolozza = [
        "#EF4444", "#F97316", "#F59E0B", "#EAB308", "#84CC16", "#22C55E", "#10B981", "#14B8A6",
        "#0EA5E9", "#2563EB", "#6366F1", "#8B5CF6", "#A855F7", "#EC4899", "#F43F5E", "#78716C", "#64748B", "#9CA3AF",
    ]

    private var nomePulito: String { nome.trimmingCharacters(in: .whitespaces) }
    /// I totali raggruppano per nome: due categorie con lo stesso nome si confonderebbero.
    private var nomeDoppio: Bool {
        categorie.contains { $0.persistentModelID != categoria?.persistentModelID && $0.nome.compare(nomePulito, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: icona)
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Color(hex: colore), in: Circle())
                    TextField("Nome", text: $nome)
                }
                if nomeDoppio { Text("Esiste già una categoria con questo nome.").font(.caption).foregroundStyle(.red) }
            }
            Section("Icona") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                    ForEach(Self.icone, id: \.self) { i in
                        Image(systemName: i)
                            .font(.system(size: 16))
                            .frame(width: 38, height: 38)
                            .foregroundStyle(i == icona ? .white : .primary)
                            .background(i == icona ? Color(hex: colore) : Color(.tertiarySystemFill), in: Circle())
                            .onTapGesture { icona = i }
                            .accessibilityAddTraits(i == icona ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Colore") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                    ForEach(Self.tavolozza, id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 32, height: 32)
                            .overlay { if hex == colore { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                            .onTapGesture { colore = hex }
                    }
                }
                .padding(.vertical, 4)
            }
            if tipo == .spesa {
                Section {
                    HStack {
                        Text("Budget mensile")
                        Spacer()
                        TextField("nessuno", value: $budget, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("€").foregroundStyle(.secondary)
                    }
                    Toggle("Detraibile nel 730", isOn: $detraibile)
                } footer: {
                    Text("Le spese detraibili (salute, istruzione…) vengono evidenziate per la dichiarazione dei redditi.")
                }
            }
        }
        .navigationTitle(categoria == nil ? "Nuova categoria" : "Modifica categoria")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva", action: salva).disabled(nomePulito.isEmpty || nomeDoppio)
            }
        }
        .onAppear {
            guard let c = categoria else { return }
            nome = c.nome
            icona = c.icona
            colore = c.coloreHex
            budget = c.budgetMensile
            detraibile = c.detraibile
        }
    }

    private func salva() {
        let c: Categoria
        if let esistente = categoria {
            c = esistente
        } else {
            let ordine = (categorie.filter { $0.tipo == tipo }.map(\.ordine).max() ?? (tipo == .entrata ? 99 : -1)) + 1
            c = Categoria(nome: nomePulito, icona: icona, coloreHex: colore, tipo: tipo, ordine: ordine)
            context.insert(c)
        }
        c.nome = nomePulito
        c.icona = icona
        c.coloreHex = colore
        c.budgetMensile = (budget ?? 0) > 0 ? budget : nil
        c.detraibile = tipo == .spesa && detraibile
        try? context.save()
        dismiss()
    }
}

// MARK: - Eliminazione

private struct EliminaCategoria: View {
    let categoria: Categoria
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Categoria.ordine) private var categorie: [Categoria]
    @State private var destinazione: Categoria?

    var body: some View {
        let altre = categorie.filter { $0.tipo == categoria.tipo && $0.persistentModelID != categoria.persistentModelID }
        Form {
            Section {
                Text("«\(categoria.nome)» è usata da \(categoria.movimenti.count) movimenti, \(categoria.righe.count) righe di scontrino, \(categoria.prodotti.count) prodotti, \(categoria.ricorrenze.count) ricorrenti e \(categoria.regole.count) regole imparate. Scegli dove spostarli.")
            }
            if altre.isEmpty {
                Section { Text("È l'unica categoria di questo tipo: creane un'altra prima di eliminarla.").foregroundStyle(.secondary) }
            } else {
                Section("Sposta tutto in") {
                    Picker("Categoria", selection: $destinazione) {
                        ForEach(altre) { c in
                            Label { Text(c.nome) } icon: { IconaCategoria(categoria: c, dimensione: 26) }
                                .tag(Optional(c))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            Section {
                Button("Elimina «\(categoria.nome)»", role: .destructive, action: elimina)
                    .disabled(destinazione == nil)
            }
        }
        .navigationTitle("Elimina categoria")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
    }

    private func elimina() {
        guard let d = destinazione else { return }
        for m in Array(categoria.movimenti) { m.categoria = d }
        for r in Array(categoria.righe) { r.categoria = d }
        for p in Array(categoria.prodotti) { p.categoria = d }
        for r in Array(categoria.ricorrenze) { r.categoria = d }
        for r in Array(categoria.regole) { r.categoria = d }
        context.delete(categoria)
        try? context.save()
        dismiss()
    }
}
