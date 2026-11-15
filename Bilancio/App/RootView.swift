import SwiftUI

struct RootView: View {
    @State private var fileDaImportare: FileDaImportare?
    /// Scheda iniziale: 0 di default; per i test si può avviare con l'argomento `-tab N`.
    @State private var scheda = UserDefaults.standard.integer(forKey: "tab")

    var body: some View {
        TabView(selection: $scheda) {
            Tab("Anno", systemImage: "chart.bar.xaxis", value: 0) { AnnoView() }
            Tab("Mese", systemImage: "calendar", value: 1) { MeseView() }
            Tab("Scansiona", systemImage: "doc.viewfinder", value: 2) { ScansioneView() }
            Tab("Investimenti", systemImage: "chart.line.uptrend.xyaxis", value: 3) { InvestimentiView() }
            Tab("Altro", systemImage: "ellipsis.circle", value: 4) { AltroView() }
        }
        // "Apri con Bilancio" da File/Mail/banca: CSV o PDF dell'estratto conto
        .onOpenURL { fileDaImportare = FileDaImportare(url: $0) }
        .sheet(item: $fileDaImportare) { f in
            NavigationStack { ImportaEstrattoView(fileURL: f.url) }
        }
    }
}

struct FileDaImportare: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Hub della scheda "Altro".
struct AltroView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Analisi") {
                    NavigationLink { InflazioneView() } label: { Label("Inflazione dei prodotti", systemImage: "chart.line.uptrend.xyaxis") }
                    NavigationLink { ArchivioView() } label: { Label("Archivio scontrini", systemImage: "archivebox") }
                }
                Section("Soldi") {
                    NavigationLink { ContiView() } label: { Label("Conti e contanti", systemImage: "building.columns") }
                    NavigationLink { RicorrentiView() } label: { Label("Pagamenti ricorrenti", systemImage: "repeat") }
                    NavigationLink { BancheView() } label: { Label("Banche collegate", systemImage: "link") }
                    NavigationLink { ImportaEstrattoView() } label: { Label("Importa estratto conto", systemImage: "square.and.arrow.down") }
                }
                Section("Impostazioni") {
                    NavigationLink { CategorieView() } label: { Label("Categorie e budget", systemImage: "tag") }
                    NavigationLink { BackupView() } label: { Label("Backup", systemImage: "externaldrive") }
                    NavigationLink { ImpostazioniView() } label: { Label("Impostazioni", systemImage: "gearshape") }
                }
            }
            .navigationTitle("Altro")
        }
    }
}
