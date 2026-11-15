import SwiftUI
import SwiftData
import UIKit
import LocalAuthentication

/// Avvolge tutta l'app: schermata di blocco con Face ID (fallback codice), copertura sfocata
/// nell'app switcher, backup automatico quando l'app va in background.
/// Con l'argomento di avvio `-demo`: niente blocco e dati demo se il database è vuoto.
struct BloccoApp<Contenuto: View>: View {
    @ViewBuilder var contenuto: Contenuto

    @AppStorage("bloccoFaceID") private var bloccoAttivo = true
    @Environment(\.scenePhase) private var fase
    @Environment(\.modelContext) private var context
    @State private var sbloccata = false
    @State private var daChiedere = true
    @State private var errore: String?

    private var demo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    private var bloccata: Bool { bloccoAttivo && !demo && !sbloccata }

    var body: some View {
        contenuto
            // copre il primo fotogramma; la finestra sotto copre anche i fogli aperti
            .overlay { if bloccata || fase != .active { protezione } }
            .onChange(of: fase, initial: true) { _, nuova in
                switch nuova {
                case .background:
                    sbloccata = false
                    daChiedere = true
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    try? context.save()
                    Backup.automaticoSeServe()
                case .active where bloccata && daChiedere:
                    // solo all'avvio o al ritorno dal background: un annullamento non deve riaprire il prompt all'infinito
                    daChiedere = false
                    Task { await sblocca() }
                default:
                    break
                }
                aggiornaFinestra()
            }
            .onChange(of: bloccata) { aggiornaFinestra() }
            .onChange(of: errore) { aggiornaFinestra() }
            .task {
                guard demo, ((try? context.fetchCount(FetchDescriptor<Movimento>())) ?? 0) == 0 else { return }
                DatiDemo.carica(in: context)
            }
    }

    private var protezione: ProtezioneBloccoApp {
        ProtezioneBloccoApp(bloccata: bloccata, errore: errore) { Task { await sblocca() } }
    }

    private func aggiornaFinestra() {
        if bloccata || fase != .active { FinestraProtezione.mostra(protezione) } else { FinestraProtezione.nascondi() }
    }

    private func sblocca() async {
        let ctx = LAContext()
        var problema: NSError?
        // Senza codice impostato sul telefono non c'è modo di autenticarsi: si entra comunque.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problema) else {
            sbloccata = true
            return
        }
        do {
            sbloccata = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Sblocca i tuoi dati finanziari"))
            errore = nil
        } catch {
            errore = String(localized: "Autenticazione non riuscita. Riprova.")
        }
    }
}

/// Schermata di blocco (bloccata) o copertura sfocata (app switcher).
private struct ProtezioneBloccoApp: View {
    let bloccata: Bool
    let errore: String?
    let sblocca: () -> Void

    var body: some View {
        if bloccata {
            VStack(spacing: 16) {
                Image(systemName: "faceid").font(.system(size: 56)).foregroundStyle(.tint)
                Text("Bilancio è bloccato").font(.title2.bold())
                if let errore { Text(errore).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                Button("Sblocca", action: sblocca).buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        } else {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
            }
            .ignoresSafeArea()
        }
    }
}

/// Finestra sopra a tutto (anche ai fogli e agli alert dell'app) che ospita la protezione.
private enum FinestraProtezione {
    static var finestra: UIWindow?

    static func mostra(_ vista: ProtezioneBloccoApp) {
        if let ospite = finestra?.rootViewController as? UIHostingController<ProtezioneBloccoApp> {
            ospite.rootView = vista
            return
        }
        guard let scena = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scena)
        w.windowLevel = .alert + 1
        let ospite = UIHostingController(rootView: vista)
        ospite.view.backgroundColor = .clear
        w.rootViewController = ospite
        w.isHidden = false
        finestra = w
    }

    static func nascondi() {
        finestra?.isHidden = true
        finestra = nil
    }
}
