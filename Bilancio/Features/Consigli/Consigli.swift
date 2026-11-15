import SwiftUI
import SwiftData

/// Consigli del mese e dell'anno: regole locali, frasi brevi con numeri concreti, al massimo 5, dalla più importante.
enum Consigli {

    private typealias Voce = (priorita: Int, testo: String)
    private static let massimo = 5

    #if DEBUG
    private static let verificaEseguita: Void = CalcoliConsigli.autoverifica()
    #endif

    private static func ordina(_ voci: [Voce]) -> [String] {
        Array(voci.sorted { $0.priorita > $1.priorita }.prefix(massimo).map(\.testo))
    }

    private static func pct(_ x: Double) -> String { CalcoliDashboard.percentoTondo(x) }
    private static func pctSegno(_ x: Double) -> String { CalcoliDashboard.percentoTondoConSegno(x) }

    private static let invitoBudget = String(localized: "Imposta un budget mensile per le categorie principali (Altro › Categorie e budget): vedrai subito quanto ti resta.")

    private static func fraseAbbonamenti(in context: ModelContext) -> String? {
        let abb = CalcoliDashboard.abbonamenti(in: context)
        guard !abb.isEmpty else { return nil }
        let totale = abb.reduce(0) { $0 + $1.importoAnnuo }
        let nomi = abb.prefix(4).map(\.nome).joined(separator: ", ") + (abb.count > 4 ? "…" : "")
        return abb.count == 1
            ? String(localized: "1 abbonamento ti costa \(totale.euroTondo)/anno: \(nomi).")
            : String(localized: "\(abb.count) abbonamenti ti costano \(totale.euroTondo)/anno: \(nomi).")
    }

    // MARK: - Mese

    static func delMese(_ mese: Date, in context: ModelContext) -> [String] {
        #if DEBUG
        _ = verificaEseguita
        #endif
        let inizio = mese.inizioMese
        let oggi = Date()
        let corrente = inizio == oggi.inizioMese
        let giorniMese = CalcoliDashboard.giorniNelMese(inizio)
        let giorno = corrente ? oggi.giorno : giorniMese
        let rimanenti = giorniMese - giorno
        let movimenti = Contabilita.movimenti(mese: inizio, in: context)
        let totali = Contabilita.totali(movimenti)
        let perCategoria = Contabilita.spesePerCategoria(movimenti)
        let precedenti = (1...3).map { Contabilita.movimenti(mese: inizio.aggiungendo(mesi: -$0), in: context) }
        let categorie = (try? context.fetch(FetchDescriptor<Categoria>())) ?? []
        var voci: [Voce] = []

        if movimenti.isEmpty {
            voci.append((5, String(localized: "Nessun movimento in questo mese: collega una banca, importa un estratto conto o scansiona uno scontrino.")))
        }

        // Categorie oltre budget
        for v in perCategoria {
            guard let c = v.categoria, let budget = c.budgetMensile, budget > 0, v.importo > budget else { continue }
            var t = String(localized: "\(c.nome) oltre il budget: \(v.importo.euroTondo) su \(budget.euroTondo) (+\((v.importo - budget).euroTondo))")
            if corrente && rimanenti > 0 { t += rimanenti == 1 ? String(localized: ", e manca 1 giorno") : String(localized: ", e mancano \(rimanenti) giorni") }
            voci.append((100, t + "."))
        }

        // Categoria in forte aumento rispetto alla media dei mesi precedenti
        let mesiConSpese = precedenti.filter { $0.contains { $0.tipo == .spesa } }.count
        if mesiConSpese > 0 {
            var media: [String: Double] = [:]
            for lista in precedenti {
                for v in Contabilita.spesePerCategoria(lista) { media[v.id, default: 0] += v.importo / Double(mesiConSpese) }
            }
            let aumenti = perCategoria.compactMap { v -> (nome: String, importo: Double, media: Double, delta: Double)? in
                guard let m = media[v.id], m >= 20, let d = CalcoliConsigli.variazione(da: m, a: v.importo), d >= 0.3 else { return nil }
                return (v.nome, v.importo, m, d)
            }
            if let top = aumenti.max(by: { $0.delta < $1.delta }) {
                voci.append((80, String(localized: "\(top.nome): \(top.importo.euroTondo) questo mese, \(pctSegno(top.delta)) rispetto alla media degli ultimi mesi (\(top.media.euroTondo)).")))
            }
        }

        // Proiezione di fine mese
        if corrente && giorno >= 5 && rimanenti > 0 && totali.spese > 0 {
            let proiezione = CalcoliConsigli.proiezioneFineMese(spesaFinora: totali.spese, giorno: giorno, giorniNelMese: giorniMese)
            let spesePrec = Contabilita.totali(precedenti[0]).spese
            let t = spesePrec > 0
                ? String(localized: "A questo ritmo chiudi il mese con \(proiezione.euroTondo) di spese (\(inizio.aggiungendo(mesi: -1).meseInFrase): \(spesePrec.euroTondo)).")
                : String(localized: "A questo ritmo chiudi il mese con \(proiezione.euroTondo) di spese.")
            voci.append((spesePrec > 0 && proiezione > spesePrec ? 75 : 55, t))
        }

        // Da confermare
        let daConfermare = movimenti.filter(\.daConfermare).count
        if daConfermare > 0 {
            voci.append((85, daConfermare == 1 ? String(localized: "Hai 1 movimento da confermare.") : String(localized: "Hai \(daConfermare) movimenti da confermare.")))
        }

        // Spesa singola più alta
        if let piuAlta = movimenti.filter({ $0.tipo == .spesa && $0.importo < 0 }).min(by: { $0.importo < $1.importo }) {
            let nome = piuAlta.titolo.isEmpty ? (piuAlta.categoria?.nome ?? String(localized: "Spesa")) : piuAlta.titolo
            voci.append((35, String(localized: "La spesa più alta del mese: \(nome), \((-piuAlta.importo).euro) (\(piuAlta.data.giornoMese)).")))
        }

        // Abbonamenti
        if let t = fraseAbbonamenti(in: context) { voci.append((45, t)) }

        // Prodotti rincarati
        if let r = CalcoliDashboard.rincari(mese: inizio, in: context).first {
            let quando = r.dataPrima.anno == inizio.anno ? r.dataPrima.meseInFrase : r.dataPrima.meseAnno
            voci.append((60, String(localized: "\(r.nome) costa \(r.prezzo.euro), a \(quando) \(r.prezzoPrima.euro) (\(pctSegno(r.variazione))).")))
        }

        // Dicembre: quota deducibile residua dei fondi pensione italiani
        if inizio.mese == 12 {
            let fondi = CalcoliDashboard.versatoFondiPensione(anno: inizio.anno, in: context)
            if !fondi.isEmpty {
                let versato = fondi.reduce(0) { $0 + $1.importo }
                let residuo = CalcoliConsigli.residuoDeducibile(versato: versato)
                if residuo > 0 {
                    voci.append((90, String(localized: "Nel fondo pensione puoi versare ancora \(residuo.euro) entro il 31 dicembre restando deducibile (quest'anno: \(versato.euro) su \(CalcoliConsigli.massimoDeducibileFondoPensione.euro)).")))
                }
            }
        }

        // Interessi dei conti remunerati
        let conti = (try? context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { !$0.archiviato }))) ?? []
        let remunerati = conti.filter { ($0.tassoAnnuo ?? 0) > 0 }
        let interessi = remunerati.reduce(0) { $0 + CalcoliConsigli.interessiMensili(saldo: Contabilita.saldo($1), tassoAnnuo: $1.tassoAnnuo ?? 0) }
        if interessi >= 0.5 {
            let nomi = remunerati.map(\.nome).joined(separator: ", ")
            voci.append((20, String(localized: "I conti remunerati (\(nomi)) ti rendono circa \(interessi.euro) di interessi al mese.")))
        }

        // Tasso di risparmio vs media
        if totali.tassoSignificativo {
            let tassi = precedenti.map(Contabilita.totali).filter { $0.entrate > 0 }.map(\.tassoRisparmio)
            if !tassi.isEmpty {
                let media = tassi.reduce(0, +) / Double(tassi.count)
                let tasso = totali.tassoRisparmio
                if tasso < media - 0.05 {
                    voci.append((65, String(localized: "Questo mese risparmi \(CalcoliConsigli.conArticolo(pct(tasso))) delle entrate, sotto la tua media recente (\(pct(media))).")))
                } else {
                    voci.append((25, String(localized: "Questo mese risparmi \(CalcoliConsigli.conArticolo(pct(tasso))) delle entrate (media recente: \(pct(media))).")))
                }
            }
        }

        if !categorie.contains(where: { ($0.budgetMensile ?? 0) > 0 }) { voci.append((10, invitoBudget)) }

        return ordina(voci)
    }

    // MARK: - Anno

    static func dellAnno(_ anno: Int, in context: ModelContext) -> [String] {
        #if DEBUG
        _ = verificaEseguita
        #endif
        let oggi = Date()
        let corrente = anno == oggi.anno
        let movimenti = Contabilita.movimenti(anno: anno, in: context)
        let totali = Contabilita.totali(movimenti)
        let perCategoria = Contabilita.spesePerCategoria(movimenti)
        // anno precedente: se l'anno è in corso, solo fino allo stesso giorno
        let finePrecedente = corrente ? oggi.aggiungendo(mesi: -12) : inizioAnno(anno)
        let movPrec = Contabilita.movimenti(da: inizioAnno(anno - 1), a: finePrecedente, in: context)
        let totaliPrec = Contabilita.totali(movPrec)
        let categorie = (try? context.fetch(FetchDescriptor<Categoria>())) ?? []
        var voci: [Voce] = []

        if movimenti.isEmpty {
            voci.append((5, String(localized: "Nessun movimento nel \(String(anno)): i consigli arrivano man mano che registri entrate e spese.")))
        }

        // Categoria cresciuta di più rispetto all'anno precedente
        let prec = Dictionary(Contabilita.spesePerCategoria(movPrec).map { ($0.id, $0.importo) }, uniquingKeysWith: +)
        let crescite = perCategoria.compactMap { v -> (nome: String, ora: Double, prima: Double, delta: Double)? in
            guard let p = prec[v.id], p >= 50, let d = CalcoliConsigli.variazione(da: p, a: v.importo), d > 0.1 else { return nil }
            return (v.nome, v.importo, p, d)
        }
        if let top = crescite.max(by: { $0.delta < $1.delta }) {
            voci.append((70, corrente
                ? String(localized: "\(top.nome) \(pctSegno(top.delta)) rispetto al \(String(anno - 1)) (stesso periodo): \(top.ora.euroTondo) contro \(top.prima.euroTondo). È la categoria cresciuta di più.")
                : String(localized: "\(top.nome) \(pctSegno(top.delta)) rispetto al \(String(anno - 1)): \(top.ora.euroTondo) contro \(top.prima.euroTondo). È la categoria cresciuta di più.")))
        }

        // Tasso di risparmio annuo
        if totali.entrate > 0 {
            var t = totali.risparmio >= 0
                ? String(localized: "Nel \(String(anno)) hai risparmiato \(totali.risparmio.euroTondo), \(CalcoliConsigli.conArticolo(pct(totali.tassoRisparmio))) delle entrate")
                : String(localized: "Nel \(String(anno)) hai speso \((-totali.risparmio).euroTondo) più di quanto hai incassato")
            if totaliPrec.entrate > 0 { t += " (\(anno - 1): \(pct(totaliPrec.tassoRisparmio)))" }
            voci.append((totali.risparmio < 0 ? 95 : 60, t + "."))
        }

        // Spese detraibili nel 730
        let detraibili = perCategoria.filter { $0.categoria?.detraibile == true }
        let totaleDetraibile = detraibili.reduce(0) { $0 + $1.importo }
        if totaleDetraibile > 0 {
            let nomi = detraibili.map(\.nome).joined(separator: ", ")
            let detrazione = CalcoliConsigli.detrazione730(spese: totaleDetraibile)
            voci.append(detrazione > 0
                ? (65, String(localized: "Hai \(totaleDetraibile.euro) di spese detraibili (\(nomi)): mettile nel 730, valgono circa \(detrazione.euro) di detrazione (19% oltre la franchigia di \(CalcoliConsigli.franchigia730.euro))."))
                : (30, String(localized: "Hai \(totaleDetraibile.euro) di spese detraibili (\(nomi)): sotto la franchigia di \(CalcoliConsigli.franchigia730.euro) non danno detrazione, ma conserva gli scontrini.")))
        }

        // Fondo pensione: deducibilità
        let fondi = CalcoliDashboard.versatoFondiPensione(anno: anno, in: context).filter { $0.importo > 0 }
        if !fondi.isEmpty {
            let versato = fondi.reduce(0) { $0 + $1.importo }
            let nomi = fondi.map(\.nome).joined(separator: ", ")
            let t = versato > CalcoliConsigli.massimoDeducibileFondoPensione
                ? String(localized: "Hai versato \(versato.euroTondo) su \(nomi): solo \(CalcoliConsigli.massimoDeducibileFondoPensione.euro) sono deducibili, la parte in più no.")
                : String(localized: "Hai versato \(versato.euroTondo) su \(nomi): fino a \(CalcoliConsigli.massimoDeducibileFondoPensione.euro) sono deducibili, quindi ricordati di metterli nel 730.")
            voci.append((55, t))
        }

        if corrente {
            // Fondo di emergenza
            if totali.spese > 0 {
                let mediaMensile = totali.spese / Double(CalcoliDashboard.mesiConDati(movimenti))
                let liquidita = Contabilita.liquidita(in: context)
                let mesi = liquidita / mediaMensile
                let mesiTesto = mesi.formatted(.number.precision(.fractionLength(1)))
                let obiettivo = mediaMensile * 6
                if mesi < 6 {
                    voci.append((mesi < 3 ? 80 : 50, String(localized: "La liquidità copre \(mesiTesto) mesi di spese: per un fondo di emergenza di 6 mesi servono \(obiettivo.euroTondo), mancano \((obiettivo - liquidita).euroTondo).")))
                } else {
                    voci.append((30, String(localized: "La liquidità copre \(mesiTesto) mesi di spese: oltre i 6 del fondo di emergenza ci sono \((liquidita - obiettivo).euroTondo) che potresti investire.")))
                }
            }

            // Rendimento investimenti
            let strumenti = (try? context.fetch(FetchDescriptor<Strumento>(predicate: #Predicate { !$0.archiviato }))) ?? []
            let versato = strumenti.reduce(0) { $0 + Portafoglio.versatoEUR($1) }
            let valore = strumenti.reduce(0) { $0 + Portafoglio.valoreEUR($1) }
            if versato > 0 {
                let guadagno = valore - versato
                voci.append((40, String(localized: "I tuoi investimenti valgono \(valore.euroTondo) con \(versato.euroTondo) versati: \(guadagno >= 0 ? "+" : "−")\(abs(guadagno).euroTondo) (\(pctSegno(guadagno / versato))).")))
            }
        }

        // Inflazione personale (prezzi dei prodotti che ricompri) contro l'ISTAT, scaricato da solo
        if let inflazione = CalcoliDashboard.inflazionePersonale(anno: anno, in: context) {
            let tua = inflazione.percento
            if let istat = ISTAT.ultimaVariazioneAnnua() {
                voci.append((inflazione > istat.valore ? 50 : 35, String(localized: "La tua inflazione personale è \(CalcoliConsigli.conArticolo(tua)), contro \(CalcoliConsigli.conArticolo(istat.valore.percento)) ISTAT.")))
            } else {
                voci.append((35, String(localized: "La tua inflazione personale (prezzi dei prodotti riacquistati) è \(CalcoliConsigli.conArticolo(tua)). Il dettaglio prodotto per prodotto è in Altro › Inflazione.")))
            }
        }

        // Abbonamenti
        if let t = fraseAbbonamenti(in: context) { voci.append((30, t)) }

        // Crescita del patrimonio
        let punti = CalcoliDashboard.patrimonio(mesi: [inizioAnno(anno).aggiungendo(mesi: -1), inizioMese(anno: anno, mese: corrente ? oggi.mese : 12)], in: context)
        if punti.count == 2, punti[0].totale != 0 || punti[1].totale != 0 {
            let delta = punti[1].totale - punti[0].totale
            var t = delta >= 0
                ? String(localized: "Il patrimonio è cresciuto di \(abs(delta).euroTondo) da inizio anno")
                : String(localized: "Il patrimonio è sceso di \(abs(delta).euroTondo) da inizio anno")
            if punti[0].totale > 0 { t += " (\(pctSegno(delta / punti[0].totale)))" }
            voci.append((delta < 0 ? 75 : 45, t + "."))
        }

        if !categorie.contains(where: { ($0.budgetMensile ?? 0) > 0 }) { voci.append((10, invitoBudget)) }

        return ordina(voci)
    }
}
