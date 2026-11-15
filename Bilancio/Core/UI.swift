import SwiftUI

/// Colori fissi del bilancio, usati in tutte le schermate.
enum Tinta {
    static let entrate = Color.green
    static let spese = Color.red
    static let risparmio = Color.primary
    static let investito = Color.blue
    static let patrimonio = Color.purple
}

extension Color {
    /// "#RRGGBB"
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(s, radix: 16) ?? 0x8E8E93
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Riquadro bianco arrotondato con titolo opzionale (stile delle bozze approvate).
struct Scheda<Contenuto: View>: View {
    var titolo: String?
    var etichetta: String?
    @ViewBuilder var contenuto: Contenuto

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let titolo {
                HStack {
                    Text(titolo).font(.headline)
                    Spacer()
                    if let etichetta { Text(etichetta).font(.caption).foregroundStyle(.secondary) }
                }
            }
            contenuto
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Riquadro KPI: etichetta piccola, valore grande, nota sotto.
struct RiquadroKPI: View {
    let titolo: String
    let valore: String
    var nota: String? = nil
    var colore: Color = .primary
    var coloreNota: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titolo.uppercased()).font(.caption2).foregroundStyle(.secondary).tracking(0.3)
            Text(valore).font(.title3.bold()).foregroundStyle(colore).minimumScaleFactor(0.6).lineLimit(1)
            if let nota { Text(nota).font(.caption2).foregroundStyle(coloreNota).lineLimit(2) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Riquadro giallo dei consigli.
struct SchedaConsigli: View {
    let titolo: String
    let consigli: [String]

    var body: some View {
        if !consigli.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(titolo, systemImage: "lightbulb.fill").font(.headline).foregroundStyle(.orange)
                ForEach(consigli, id: \.self) { c in
                    Text("• " + c).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.yellow.opacity(0.45)))
        }
    }
}

/// Icona tonda di una categoria.
struct IconaCategoria: View {
    let categoria: Categoria?
    var dimensione: CGFloat = 30

    var body: some View {
        Image(systemName: categoria?.icona ?? "questionmark")
            .font(.system(size: dimensione * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: dimensione, height: dimensione)
            .background(Color(hex: categoria?.coloreHex ?? "#9CA3AF"), in: Circle())
    }
}

/// Riga standard di un movimento in una lista.
struct RigaMovimento: View {
    let movimento: Movimento

    var body: some View {
        HStack(spacing: 10) {
            IconaCategoria(categoria: movimento.categoria)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(movimento.titolo.isEmpty ? movimento.tipo.etichetta : movimento.titolo).lineLimit(1)
                    if movimento.daConfermare {
                        Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.blue)
                    }
                }
                Text(sottotitolo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(movimento.importo.euro)
                .font(.callout.monospacedDigit())
                .foregroundStyle(coloreImporto)
        }
    }

    private var sottotitolo: String {
        var parti = [movimento.data.giornoMese]
        if let c = movimento.categoria { parti.append(c.nome) } else if movimento.tipo != .spesa { parti.append(movimento.tipo.etichetta) }
        if movimento.scontrino != nil { parti.append("🧾") }
        if movimento.conto?.tipo == .contanti { parti.append("💶") }
        return parti.joined(separator: " · ")
    }

    private var coloreImporto: Color {
        switch movimento.tipo {
        case .entrata: Tinta.entrate
        case .investimento: Tinta.investito
        case .giroconto: .secondary
        case .spesa: movimento.importo > 0 ? Tinta.entrate : .primary
        }
    }
}
