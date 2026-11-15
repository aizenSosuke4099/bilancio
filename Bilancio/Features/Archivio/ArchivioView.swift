import SwiftUI
import SwiftData
import UIKit

/// Archivio degli scontrini, raggruppati per negozio (la "macro") o per mese.
struct ArchivioView: View {
    @Query(sort: \Scontrino.data, order: .reverse) private var scontrini: [Scontrino]
    @State private var ricerca = ""
    @State private var perMese = false

    var body: some View {
        let filtrati = scontrini.filter { corrisponde($0, ricerca) }
        let negozi = Dictionary(grouping: filtrati, by: \.negozio)
            .map { (nome: $0.key, scontrini: $0.value) }
            .sorted { ($0.scontrini.first?.data ?? .distantPast) > ($1.scontrini.first?.data ?? .distantPast) }
        let mesi = Dictionary(grouping: filtrati) { $0.data.inizioMese }
            .map { (mese: $0.key, scontrini: $0.value) }
            .sorted { $0.mese > $1.mese }
        let nomiNegozi = Set(scontrini.map(\.negozio)).sorted()

        List {
            Picker("Raggruppa", selection: $perMese) {
                Text("Per negozio").tag(false)
                Text("Per mese").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if perMese {
                ForEach(mesi, id: \.mese) { g in
                    Section {
                        ForEach(g.scontrini) { s in
                            NavigationLink { ScontrinoDettaglioView(scontrino: s) } label: { RigaScontrinoArchivio(scontrino: s, conNegozio: true) }
                        }
                    } header: {
                        HStack {
                            Text(g.mese.meseAnno.capitalized(with: .current))
                            Spacer()
                            Text(g.scontrini.reduce(0) { $0 + $1.totale }.euro)
                        }
                    }
                }
            } else {
                Section {
                    ForEach(negozi, id: \.nome) { g in
                        NavigationLink {
                            ScontriniNegozioArchivio(negozio: g.nome, ricerca: ricerca, altriNegozi: nomiNegozi.filter { $0 != g.nome })
                        } label: {
                            RigaNegozioArchivio(nome: g.nome, scontrini: g.scontrini)
                        }
                    }
                }
            }
        }
        .overlay {
            if scontrini.isEmpty {
                ContentUnavailableView("Nessuno scontrino", systemImage: "archivebox", description: Text("Gli scontrini scansionati finiscono qui, divisi per negozio."))
            } else if filtrati.isEmpty {
                ContentUnavailableView.search(text: ricerca)
            }
        }
        .navigationTitle("Archivio scontrini")
        .searchable(text: $ricerca, prompt: "Negozio o prodotto")
    }
}

/// Ricerca per negozio o testo delle righe (anche nome del prodotto).
private func corrisponde(_ s: Scontrino, _ ricerca: String) -> Bool {
    let q = ricerca.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return true }
    return s.negozio.localizedStandardContains(q)
        || s.righe.contains { $0.testo.localizedStandardContains(q) || ($0.prodotto?.nome.localizedStandardContains(q) ?? false) }
}

private struct RigaNegozioArchivio: View {
    let nome: String
    let scontrini: [Scontrino]

    var body: some View {
        HStack(spacing: 12) {
            Text(String(nome.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(coloreNegozio(nome), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                let ultimo = scontrini.map(\.data).max()?.breve ?? ""
                Text(nome.isEmpty ? String(localized: "Senza negozio") : nome).lineLimit(1)
                Text(scontrini.count == 1 ? "1 scontrino · ultimo \(ultimo)" : "\(scontrini.count) scontrini · ultimo \(ultimo)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(scontrini.reduce(0) { $0 + $1.totale }.euro).font(.callout.monospacedDigit())
        }
    }
}

/// Colore stabile per nome (hashValue cambia a ogni avvio).
private func coloreNegozio(_ nome: String) -> Color {
    let tavolozza = ["#2563EB", "#16A34A", "#F59E0B", "#EF4444", "#A855F7", "#0EA5E9", "#EC4899", "#14B8A6", "#64748B"]
    let somma = nome.lowercased().unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return Color(hex: tavolozza[somma % tavolozza.count])
}

private struct RigaScontrinoArchivio: View {
    let scontrino: Scontrino
    var conNegozio = false

    var body: some View {
        HStack(spacing: 12) {
            // ponytail: miniatura calcolata a ogni rendering della riga; cache se l'archivio diventa lento
            Group {
                if let dati = scontrino.immagine, let img = UIImage(data: dati)?.preparingThumbnail(of: CGSize(width: 96, height: 96)) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(conNegozio ? scontrino.negozio : scontrino.data.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    .lineLimit(1)
                Text("\(conNegozio ? scontrino.data.breve + " · " : "")\(scontrino.righe.count) righe")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(scontrino.totale.euro).font(.callout.monospacedDigit())
        }
    }
}

/// Scontrini di un negozio, con rinomina/unione del negozio.
private struct ScontriniNegozioArchivio: View {
    let negozio: String
    let ricerca: String
    let altriNegozi: [String]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var scontrini: [Scontrino]
    @State private var rinomina = false
    @State private var nuovoNome = ""
    @State private var unireCon: String?

    init(negozio: String, ricerca: String, altriNegozi: [String]) {
        self.negozio = negozio
        self.ricerca = ricerca
        self.altriNegozi = altriNegozi
        _scontrini = Query(filter: #Predicate<Scontrino> { $0.negozio == negozio }, sort: \Scontrino.data, order: .reverse)
    }

    var body: some View {
        let elenco = scontrini.filter { corrisponde($0, ricerca) }
        List {
            Section {
                LabeledContent("Scontrini", value: "\(scontrini.count)")
                LabeledContent("Totale speso", value: scontrini.reduce(0) { $0 + $1.totale }.euro)
            }
            Section(ricerca.isEmpty ? "Scontrini" : "Che contengono «\(ricerca)»") {
                ForEach(elenco) { s in
                    NavigationLink { ScontrinoDettaglioView(scontrino: s) } label: { RigaScontrinoArchivio(scontrino: s) }
                }
            }
        }
        .navigationTitle(negozio.isEmpty ? String(localized: "Senza negozio") : negozio)
        .toolbar {
            Menu {
                Button { nuovoNome = negozio; rinomina = true } label: { Label("Rinomina negozio…", systemImage: "pencil") }
                if !altriNegozi.isEmpty {
                    Menu {
                        ForEach(altriNegozi, id: \.self) { n in Button(n) { unireCon = n } }
                    } label: { Label("Unisci con…", systemImage: "arrow.triangle.merge") }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .alert("Rinomina negozio", isPresented: $rinomina) {
            TextField("Nome", text: $nuovoNome)
            Button("Annulla", role: .cancel) {}
            Button("Rinomina") { applica(nuovoNome) }
        } message: {
            Text("Cambia il nome su tutti i \(scontrini.count) scontrini. Se scrivi il nome di un altro negozio, vengono uniti.")
        }
        .confirmationDialog("Unire i negozi?", isPresented: Binding(get: { unireCon != nil }, set: { if !$0 { unireCon = nil } }), titleVisibility: .visible) {
            Button("Unisci in «\(unireCon ?? "")»") { if let n = unireCon { applica(n) } }
        } message: {
            Text("I \(scontrini.count) scontrini di «\(negozio)» passano a «\(unireCon ?? "")».")
        }
    }

    private func applica(_ nome: String) {
        let nuovo = nome.trimmingCharacters(in: .whitespaces)
        guard !nuovo.isEmpty, nuovo != negozio else { return }
        for s in scontrini {
            s.negozio = nuovo
            // il movimento creato dallo scontrino porta lo stesso nome
            if let m = s.movimento, m.titolo == negozio { m.titolo = nuovo }
        }
        try? context.save()
        dismiss()
    }
}
