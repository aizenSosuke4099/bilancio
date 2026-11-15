import Foundation
import SwiftData

/// Dati di esempio per i test su simulatore: ~12 mesi di un giovane lavoratore a Milano.
/// Generazione deterministica (seme fisso): stesse date relative a oggi, stessi importi.
enum DatiDemo {

    static func carica(in context: ModelContext) {
        DatiIniziali.inserisciSeVuoto(context)
        let caso = CasoDemo(seme: 20_261_114)
        let oggi = Date()
        let meseCorrente = oggi.inizioMese
        let primoMese = meseCorrente.aggiungendo(mesi: -11)

        var conti = Dictionary(((try? context.fetch(FetchDescriptor<Conto>())) ?? []).map { ($0.nome, $0) }, uniquingKeysWith: { a, _ in a })
        let categorie = Dictionary(((try? context.fetch(FetchDescriptor<Categoria>())) ?? []).map { ($0.nome, $0) }, uniquingKeysWith: { a, _ in a })
        // le tabelle sotto usano i nomi italiani; le categorie sono salvate nella lingua del telefono
        func categoria(_ nome: String) -> Categoria? { categorie[nome] ?? categorie[DatiIniziali.localizzato(nome)] }
        let contanti = DatiIniziali.contoContanti(in: context)
        let tipiDemo: [String: TipoConto] = ["Conto corrente": .corrente, "Conto online": .corrente, "Conto digitale": .corrente,
                                             "Conto deposito": .remunerato, "Carta di credito": .carta]
        // nome italiano del conto demo → nome salvato (lingua del telefono): è la chiave di `conti` e `saldi`
        let nomiConti = ["Conto corrente": String(localized: "Conto corrente"), "Conto online": String(localized: "Conto online"),
                         "Conto digitale": String(localized: "Conto digitale"), "Conto deposito": String(localized: "Conto deposito"),
                         "Carta di credito": String(localized: "Carta di credito"), "Contanti": contanti.nome]
        func nomeLocale(_ nome: String) -> String { nomiConti[nome] ?? nome }   // un nome già salvato resta com'è
        func conto(_ nome: String) -> Conto {
            if let c = conti[nomeLocale(nome)] { return c }
            guard let tipo = tipiDemo[nome] else { return contanti }
            let c = Conto(nome: nomeLocale(nome), tipo: tipo, ordine: conti.count)
            context.insert(c)
            conti[nomeLocale(nome)] = c
            return c
        }

        // Saldi all'inizio dei 12 mesi
        let saldiIniziali: [String: Double] = ["Conto corrente": 4_200, "Conto online": 800, "Conto digitale": 250, "Conto deposito": 6_000, "Contanti": 120]
        for (nome, saldo) in saldiIniziali { conto(nome).saldoIniziale = saldo }
        conto("Conto deposito").tassoAnnuo = 2.0
        var saldi = Dictionary(saldiIniziali.map { (nomeLocale($0.key), $0.value) }, uniquingKeysWith: +)

        // Budget
        for (nome, budget) in [("Spesa alimentare", 350.0), ("Ristoranti e bar", 150), ("Trasporti", 100), ("Svago e cultura", 60), ("Abbigliamento", 80)] {
            categoria(nome)?.budgetMensile = budget
        }
        if UserDefaults.standard.double(forKey: "istat.inflazione") == 0 { UserDefaults.standard.set(1.6, forKey: "istat.inflazione") }
        if UserDefaults.standard.double(forKey: "cambio.CHF") == 0 { Portafoglio.salvaCambio("CHF", 1.07) }

        // MARK: Movimenti

        var contatore = 0
        var spesaCarta = Array(repeating: 0.0, count: 12)
        var k = 0
        @discardableResult
        func mov(_ data: Date, _ importo: Double, _ tipo: TipoMovimento, _ titolo: String, _ nomeConto: String,
                 _ nomeCategoria: String? = nil, origine: Origine = .banca, descrizione: String? = nil, ricorrenza: Ricorrenza? = nil) -> Movimento {
            let m = Movimento(data: data, importo: importo.centesimi, tipo: tipo, titolo: titolo, origine: origine, stato: .confermato)
            context.insert(m)
            m.conto = conto(nomeConto)
            m.categoria = nomeCategoria.flatMap { categoria($0) }
            m.ricorrenza = ricorrenza
            m.descrizioneOriginale = descrizione ?? titolo.uppercased()
            if origine == .banca {
                contatore += 1
                m.idEsterno = "demo-\(contatore)"
            }
            // da confermare: le proposte ricorrenti del mese e gli ultimi giorni
            if (origine == .ricorrente && data >= meseCorrente) || data >= oggi.aggiungendo(giorni: -3) { m.stato = .daConfermare }
            saldi[nomeLocale(nomeConto), default: 0] += m.importo
            if nomeLocale(nomeConto) == nomeLocale("Carta di credito"), tipo == .spesa { spesaCarta[k] -= m.importo }
            return m
        }
        func giroconto(_ data: Date, _ importo: Double, da: String, a: String, _ titolo: String) {
            mov(data, -importo, .giroconto, titolo, da)
            mov(data, importo, .giroconto, titolo, a, origine: a == "Contanti" ? .manuale : .banca)
        }

        // MARK: Ricorrenze

        func ricorrenza(_ nome: String, _ importo: Double, _ tipo: TipoMovimento, giorno: Int, _ nomeConto: String, _ nomeCategoria: String) -> Ricorrenza {
            let r = Ricorrenza(nome: nome, importo: importo, tipo: tipo, giorno: giorno)
            context.insert(r)
            r.conto = conto(nomeConto)
            r.categoria = categoria(nomeCategoria)
            r.ultimaGenerazione = meseCorrente
            return r
        }
        let ricorrenze = [
            ricorrenza(String(localized: "Stipendio"), 2_650, .entrata, giorno: 27, "Conto corrente", "Stipendio"),
            ricorrenza(String(localized: "Affitto"), -750, .spesa, giorno: 1, "Conto corrente", "Casa e bollette"),
            ricorrenza(String(localized: "Abbonamento ATM", comment: "abbonamento mensile ai mezzi pubblici di Milano (ATM)"), -39, .spesa, giorno: 3, "Conto corrente", "Trasporti"),
            ricorrenza("Spotify", -11.99, .spesa, giorno: 8, "Conto digitale", "Abbonamenti"),
            ricorrenza("Fastweb", -27.95, .spesa, giorno: 10, "Conto corrente", "Casa e bollette"),
            ricorrenza("Netflix", -13.99, .spesa, giorno: 12, "Carta di credito", "Abbonamenti"),
            ricorrenza("Iliad", -9.99, .spesa, giorno: 15, "Conto corrente", "Casa e bollette"),
            ricorrenza("iCloud+", -2.99, .spesa, giorno: 20, "Carta di credito", "Abbonamenti"),
        ]

        // MARK: Investimenti

        func strumento(_ nome: String, _ isin: String, _ tipo: TipoStrumento, _ piattaforma: String, valuta: String = "EUR") -> Strumento {
            let s = Strumento(nome: nome, isin: isin, tipo: tipo, piattaforma: piattaforma, valuta: valuta)
            context.insert(s)
            s.creatoIl = primoMese.aggiungendo(mesi: -6)
            return s
        }
        func operazione(_ s: Strumento, _ data: Date, _ tipo: TipoOperazione, quote: Double = 0, prezzo: Double = 0, importo: Double, cambio: Double = 1, movimento: Movimento? = nil, nota: String = "") {
            let op = Operazione(data: data, tipo: tipo, quote: quote, prezzo: prezzo, importo: importo, cambioEUR: cambio)
            context.insert(op)
            op.strumento = s
            op.movimento = movimento
            op.nota = nota
        }

        // ETF del PAC ETF: (strumento, ticker, prezzo attuale, quota del PAC in %)
        let etf: [(Strumento, Double, Double)] = [
            (strumento("Vanguard FTSE All-World UCITS ETF (Acc)", "IE00BK5BQT80", .etf, "Broker ETF"), 148.20, 60),
            (strumento("iShares Core MSCI World UCITS ETF (Acc)", "IE00B4L5Y983", .etf, "Broker ETF"), 112.40, 30),
            (strumento("iShares Core MSCI EM IMI UCITS ETF (Acc)", "IE00BKM4GZ66", .etf, "Broker ETF"), 36.10, 10),
        ]
        for ((s, prezzo, _), ticker) in zip(etf, ["VWCE.DE", "EUNL.DE", "IS3N.DE"]) {
            s.ticker = ticker
            s.ultimoPrezzo = prezzo
            s.ultimoPrezzoData = oggi
        }
        // prezzo del mese k: ~ +12% in un anno, con rumore
        let prezziETF = etf.map { e in (0..<12).map { k in k == 11 ? e.1 : (e.1 * (0.88 + 0.12 * Double(k) / 11) * caso.tra(0.975, 1.025)).centesimi } }
        var quoteETF = Array(repeating: 0.0, count: etf.count)

        let piano = PianoPAC(nome: String(localized: "PAC ETF", comment: "nome di un piano di accumulo (PAC) in ETF"), piattaforma: "Broker ETF", importoMensile: 400, giorno: 2)
        context.insert(piano)
        piano.conto = conto("Conto corrente")
        piano.ultimaGenerazione = meseCorrente
        for (s, _, percentuale) in etf {
            let a = AllocazionePAC(percentuale: percentuale, validaDal: primoMese)
            context.insert(a)
            a.piano = piano
            a.strumento = s
        }

        // Fondi a valore manuale: (strumento, valore attuale in valuta, cambio verso EUR, versamento mensile o trimestrale)
        let fondoPensione = strumento(String(localized: "Fondo pensione – Linea crescita"), "", .fondoPensione, String(localized: "Fondo pensione"))
        fondoPensione.fondoPensioneItaliano = true
        let roboAdvisor = strumento(String(localized: "Robo-advisor – Portafoglio 5"), "", .gestione, "Robo-advisor")
        let previdenzaCH = strumento(String(localized: "Previdenza 3a – Global 100", comment: "fondo del terzo pilastro svizzero (pilastro 3a)"), "", .fondoPensione,
                                     String(localized: "Previdenza CH", comment: "previdenza svizzera"), valuta: "CHF")
        let prima = primoMese.aggiungendo(giorni: -1)
        operazione(fondoPensione, primoMese.aggiungendo(mesi: -30), .versamento, importo: 7_200, nota: String(localized: "Versamenti degli anni precedenti"))
        operazione(roboAdvisor, primoMese.aggiungendo(mesi: -6), .versamento, importo: 3_000, nota: String(localized: "Versamento iniziale"))
        operazione(previdenzaCH, primoMese.aggiungendo(mesi: -8), .versamento, importo: 2_000, cambio: 1.05, nota: String(localized: "Versamento iniziale"))
        var valoriFondi: [(Strumento, Double, Double)] = [(fondoPensione, 8_150, 1), (roboAdvisor, 3_180, 1), (previdenzaCH, 2_080, 1.07)]
        for (s, valore, _) in valoriFondi { let v = Valutazione(data: prima, valore: valore); context.insert(v); v.strumento = s }

        // MARK: Prodotti e scontrini

        var prodotti: [String: Prodotto] = [:]
        for p in prodottiDemo {
            let prodotto = Prodotto(nome: p.nome, unita: p.unita, formato: p.formatoDopo ?? p.formato)
            context.insert(prodotto)
            prodotto.categoria = categoria(p.categoria)
            prodotti[p.nome] = prodotto
        }
        let negozi: [(nome: String, varianteOCR: String, indirizzo: String, fattore: Double, carrello: Double)] = [
            ("Esselunga", "ESSELUNGA SPA", "Viale Papiniano 27, Milano", 1.06, 1.1),
            ("Lidl", "LIDL ITALIA", "Via Washington 50, Milano", 0.85, 0.9),
            ("Coop", "COOP LOMBARDIA", "Piazza Lodi 3, Milano", 1.0, 0.8),
        ]
        func scontrino(_ negozio: Int, _ data: Date, conto nomeConto: String) {
            let n = negozi[negozio]
            let anni = data.timeIntervalSince(primoMese) / (365 * 86_400)
            var righe: [(ProdottoDemo, Double, Double)] = []   // prodotto, quantità, prezzo unitario
            for p in prodottiDemo where caso.probabilita(p.probabilita * n.carrello) {
                var prezzo = p.prezzo * (1 + p.inflazioneAnnua * anni) * n.fattore * caso.tra(0.98, 1.02)
                if caso.probabilita(0.1) { prezzo *= 0.8 }   // offerta
                let quantita = p.sfuso ? caso.tra(0.4, 1.6).centesimi : (caso.probabilita(0.2) ? 2 : 1)
                righe.append((p, quantita, prezzo.centesimi))
            }
            if righe.count < 3 { righe.append((prodottiDemo[0], 1, (prodottiDemo[0].prezzo * n.fattore).centesimi)) }
            let s = Scontrino(negozio: caso.probabilita(0.25) ? n.varianteOCR : n.nome, data: data, totale: 0)
            context.insert(s)
            s.indirizzo = n.indirizzo
            var totale = 0.0
            var ocr = [s.negozio, n.indirizzo]
            let dopoCambio = data >= primoMese.aggiungendo(mesi: 6)
            for (i, (p, quantita, prezzo)) in righe.enumerated() {
                let testo = (dopoCambio ? p.testoDopo : nil) ?? p.testo
                let r = RigaScontrino(testo: testo, quantita: quantita, prezzoUnitario: prezzo, totale: (quantita * prezzo).centesimi, ordine: i)
                context.insert(r)
                r.scontrino = s
                r.prodotto = prodotti[p.nome]
                r.categoria = categoria(p.categoria)
                totale += r.totale
                ocr.append("\(testo)  \(r.totale.formatted(.number.precision(.fractionLength(2)).locale(localeIT)))")
            }
            s.totale = totale.centesimi
            s.testoOCR = (ocr + ["TOTALE EURO \(s.totale.formatted(.number.precision(.fractionLength(2)).locale(localeIT)))"]).joined(separator: "\n")
            let m = mov(data, -s.totale, .spesa, n.nome, nomeConto, "Spesa alimentare",
                        origine: nomeConto == "Contanti" ? .scontrino : .banca,
                        descrizione: "PAGAMENTO POS \(n.nome.uppercased()) MILANO")
            s.movimento = m
        }

        // MARK: Mese per mese

        for indice in 0..<12 {
            k = indice
            let mese = primoMese.aggiungendo(mesi: k)
            let numeroMese = mese.mese
            let giorniNelMese = calendario.range(of: .day, in: .month, for: mese)!.count
            func il(_ giorno: Int, ora: Int? = nil) -> Date? {
                let base = mese.aggiungendo(giorni: min(giorno, giorniNelMese) - 1)
                let d = calendario.date(bySettingHour: ora ?? caso.intero(8, 20), minute: caso.intero(0, 59), second: 0, of: base)!
                return d <= oggi ? d : nil
            }
            func aCaso() -> Date? { il(caso.intero(1, giorniNelMese)) }

            // ricorrenti
            for r in ricorrenze {
                guard let d = il(r.giorno, ora: 9) else { continue }
                var importo = r.importo
                if r.nome == String(localized: "Stipendio") { importo += caso.scegli([0, 0, 0, 85, 140.0]) }   // straordinari
                mov(d, importo, r.tipo, r.nome, r.conto?.nome ?? "Conto corrente", r.categoria?.nome, origine: .ricorrente, ricorrenza: r)
            }
            if numeroMese == 12, let d = il(18, ora: 9) { mov(d, 2_420, .entrata, String(localized: "Tredicesima", comment: "tredicesima mensilità dello stipendio, pagata a dicembre"), "Conto corrente", "Stipendio", descrizione: "ACCREDITO EMOLUMENTI TREDICESIMA") }

            // bollette
            if numeroMese % 2 == 0, let d = il(18) { mov(d, -caso.tra(55, 85), .spesa, "Enel Energia", "Conto corrente", "Casa e bollette", descrizione: "SDD ENEL ENERGIA SPA") }
            if let d = il(22) {
                let inverno = [11, 12, 1, 2, 3].contains(numeroMese)
                mov(d, -(inverno ? caso.tra(70, 110) : caso.tra(18, 30)), .spesa, "Eni Plenitude", "Conto corrente", "Casa e bollette", descrizione: "SDD ENI PLENITUDE GAS")
            }
            if let d = il(28) { mov(d, -2.5, .spesa, String(localized: "Canone conto"), "Conto corrente", "Tasse e commissioni", descrizione: "CANONE MENSILE CONTO") }

            // giroconti, prelievi, interessi
            if let d = il(1, ora: 7) { giroconto(d, 300, da: "Conto corrente", a: "Conto digitale", String(localized: "Ricarica conto digitale")) }
            if let d = il(28, ora: 18) { giroconto(d, 200, da: "Conto corrente", a: "Conto deposito", String(localized: "Giroconto al conto deposito")) }
            if let d = il(6) { giroconto(d, 100, da: "Conto corrente", a: "Contanti", String(localized: "Prelievo contanti")) }
            if let d = il(21) { giroconto(d, 80, da: "Conto corrente", a: "Contanti", String(localized: "Prelievo contanti")) }
            if k > 0, let d = il(15, ora: 6) { giroconto(d, spesaCarta[k - 1].centesimi, da: "Conto corrente", a: "Carta di credito", String(localized: "Addebito carta di credito")) }
            if k > 0, let d = il(1, ora: 6) {
                mov(d, (saldi[nomeLocale("Conto deposito"), default: 0] * 0.02 / 12), .entrata, String(localized: "Interessi conto deposito"), "Conto deposito", "Interessi e dividendi")
            }

            // PAC ETF
            if let d = il(2, ora: 10) {
                let m = mov(d, -400, .investimento, piano.nome, "Conto corrente", origine: .pac, descrizione: "BROKER ETF PAC")
                for (i, (s, _, percentuale)) in etf.enumerated() {
                    let importo = 400 * percentuale / 100
                    let prezzo = prezziETF[i][k]
                    operazione(s, d, .acquisto, quote: importo / prezzo, prezzo: prezzo, importo: importo, movimento: m)
                    quoteETF[i] += importo / prezzo
                }
            }
            // Robo-advisor e previdenza CH (mensili), fondo pensione (TFR a fine trimestre, senza movimento in banca)
            if let d = il(5, ora: 10) {
                operazione(roboAdvisor, d, .versamento, importo: 100, movimento: mov(d, -100, .investimento, "Robo-advisor", "Conto corrente", descrizione: "BONIFICO ROBO ADVISOR"))
                valoriFondi[1].1 += 100
            }
            if let d = il(6, ora: 10) {
                let cambio = caso.tra(1.055, 1.075)
                operazione(previdenzaCH, d, .versamento, importo: 100, cambio: cambio, movimento: mov(d, -100 * cambio, .investimento, previdenzaCH.piattaforma, "Conto digitale", descrizione: "TRANSFER TO PREVIDENZA 3A AG"))
                valoriFondi[2].1 += 100
            }
            if numeroMese % 3 == 0, let d = il(16, ora: 10) {
                operazione(fondoPensione, d, .versamento, importo: 640, nota: String(localized: "TFR e contributi", comment: "TFR = trattamento di fine rapporto (liquidazione) versato al fondo pensione"))
                valoriFondi[0].1 += 640
            }

            // spesa al supermercato
            for _ in 0..<caso.intero(2, 3) { if let d = aCaso() { scontrino(0, d, conto: caso.probabilita(0.7) ? "Carta di credito" : "Conto corrente") } }
            for _ in 0..<2 { if let d = aCaso() { scontrino(1, d, conto: caso.probabilita(0.7) ? "Conto corrente" : "Contanti") } }
            for _ in 0..<caso.intero(1, 2) { if let d = aCaso() { scontrino(2, d, conto: "Conto digitale") } }

            // ristoranti e bar
            let locali: [(String, ClosedRange<Double>, String)] = [
                ("Pizzeria Da Michele", 18...32, "Carta di credito"), ("Sushi Zen", 25...42, "Conto digitale"), ("Deliveroo", 15...28, "Conto digitale"),
                ("Trattoria Milanese", 30...55, "Carta di credito"), ("Starbucks", 5...9, "Carta di credito"), ("Bar Magenta", 2.5...8, "Contanti"),
            ]
            for _ in 0..<caso.intero(4, 6) {
                let l = caso.scegli(locali)
                if let d = aCaso() { mov(d, -caso.tra(l.1.lowerBound, l.1.upperBound), .spesa, l.0, l.2, "Ristoranti e bar", origine: l.2 == "Contanti" ? .manuale : .banca) }
            }
            // contanti
            for _ in 0..<caso.intero(2, 4) { if let d = aCaso() { mov(d, -caso.tra(1.2, 4.5), .spesa, String(localized: "Caffè al bar"), "Contanti", "Ristoranti e bar", origine: .manuale) } }
            if let d = aCaso() { mov(d, -caso.tra(8, 15), .spesa, String(localized: "Mercato rionale"), "Contanti", "Spesa alimentare", origine: .manuale) }
            if k % 2 == 0, let d = aCaso() { mov(d, -18, .spesa, String(localized: "Barbiere"), "Contanti", "Cura personale", origine: .manuale) }

            // trasporti, svago, shopping, salute
            for _ in 0..<caso.intero(1, 2) { if let d = aCaso() { mov(d, -caso.tra(19, 45), .spesa, "Trenitalia", "Carta di credito", "Trasporti") } }
            if caso.probabilita(0.2), let d = aCaso() { mov(d, -caso.tra(12, 24), .spesa, "Uber", "Conto digitale", "Trasporti") }
            if caso.probabilita(0.5), let d = aCaso() { mov(d, -9.9, .spesa, "UCI Cinemas", "Carta di credito", "Svago e cultura") }
            if caso.probabilita(0.3), let d = aCaso() { mov(d, -caso.scegli([9.99, 19.99, 29.99]), .spesa, "Steam", "Conto online", "Svago e cultura") }
            if numeroMese == 6, let d = il(12) { mov(d, -55, .spesa, "TicketOne", "Carta di credito", "Svago e cultura") }
            let saldiStagione = numeroMese == 1 || numeroMese == 7
            if caso.probabilita(saldiStagione ? 0.9 : 0.35), let d = aCaso() {
                mov(d, -caso.tra(25, saldiStagione ? 120 : 70), .spesa, caso.scegli(["Zara", "Decathlon", "Uniqlo"]), "Carta di credito", "Abbigliamento")
            }
            if caso.probabilita(0.4), let d = aCaso() { mov(d, -caso.tra(6, 25), .spesa, "Farmacia Centrale", "Conto corrente", "Salute") }
            if numeroMese == 3, let d = il(14) { mov(d, -120, .spesa, String(localized: "Studio dentistico"), "Conto corrente", "Salute") }
            if caso.probabilita(0.3), let d = aCaso() { mov(d, -caso.tra(8, 20), .spesa, "Tigotà", "Conto digitale", "Cura personale") }
            if caso.probabilita(0.5), let d = aCaso() { mov(d, -caso.tra(15, 60), .spesa, "Amazon", "Conto online", "Altro", descrizione: "AMZN MKTP IT") }
            if numeroMese == 4, let d = il(9) { mov(d, 29.99, .entrata, String(localized: "Rimborso Amazon"), "Conto online", "Rimborsi", descrizione: "AMAZON REFUND") }

            // una tantum
            if numeroMese == 5, let d = il(20) { mov(d, -129, .spesa, "Ryanair", "Carta di credito", "Viaggi") }
            if numeroMese == 7, let d = il(3) { mov(d, -380, .spesa, "Booking.com", "Carta di credito", "Viaggi") }
            if numeroMese == 7, let d = il(19) { mov(d, -279, .spesa, "Apple Store", "Carta di credito", "Tecnologia") }
            if numeroMese == 12 { for g in [10, 15, 20] { if let d = il(g) { mov(d, -caso.tra(30, 80), .spesa, String(localized: "Regali di Natale"), "Carta di credito", "Regali") } } }

            // valore dei fondi e fotografia del patrimonio a fine mese
            for i in valoriFondi.indices { valoriFondi[i].1 *= 1 + caso.tra(-0.004, 0.009) }
            let fineMese = mese.inizioMeseSuccessivo.aggiungendo(giorni: -1)
            if numeroMese % 3 == 0 || k == 11 {
                for (s, valore, _) in valoriFondi {
                    let v = Valutazione(data: min(fineMese, oggi), valore: valore.centesimi)
                    context.insert(v)
                    v.strumento = s
                }
            }
            if k < 11 {
                let investimenti = zip(quoteETF, prezziETF).reduce(0.0) { $0 + $1.0 * $1.1[k] } + valoriFondi.reduce(0.0) { $0 + $1.1 * $1.2 }
                context.insert(SnapshotPatrimonio(mese: mese, liquidita: saldi.values.reduce(0, +).centesimi, investimenti: investimenti.centesimi))
            }
        }

        try? context.save()
        Contabilita.aggiornaSnapshot(in: context)
        try? context.save()
    }

    /// Prodotti ricorrenti della spesa (prezzi di partenza Coop, inflazione annua tipica).
    private static let prodottiDemo: [ProdottoDemo] = [
        ProdottoDemo(nome: String(localized: "Latte intero 1 l"), testo: "LATTE INTERO 1L", unita: "l", formato: 1, prezzo: 1.25, inflazioneAnnua: 0.06, categoria: "Spesa alimentare", probabilita: 0.75),
        ProdottoDemo(nome: String(localized: "Pane comune 500 g"), testo: "PANE COMUNE 500G", unita: "kg", formato: 0.5, prezzo: 1.70, inflazioneAnnua: 0.04, categoria: "Spesa alimentare", probabilita: 0.6),
        ProdottoDemo(nome: String(localized: "Spaghetti 500 g"), testo: "SPAGHETTI N.5 500G", unita: "kg", formato: 0.5, prezzo: 0.95, inflazioneAnnua: 0.08, categoria: "Spesa alimentare", probabilita: 0.6),
        ProdottoDemo(nome: String(localized: "Caffè macinato 250 g"), testo: "CAFFE MACINATO 250G", unita: "kg", formato: 0.25, prezzo: 3.39, inflazioneAnnua: 0.22, categoria: "Spesa alimentare", probabilita: 0.35),
        ProdottoDemo(nome: String(localized: "Uova fresche 6 pz"), testo: "UOVA FRESCHE X6", unita: "pz", formato: 6, prezzo: 2.09, inflazioneAnnua: 0.07, categoria: "Spesa alimentare", probabilita: 0.45),
        ProdottoDemo(nome: String(localized: "Olio extravergine 1 l"), testo: "OLIO EXTRAV. OLIVA 1L", unita: "l", formato: 1, prezzo: 9.49, inflazioneAnnua: -0.12, categoria: "Spesa alimentare", probabilita: 0.15),
        ProdottoDemo(nome: String(localized: "Biscotti frollini"), testo: "BISCOTTI FROLLINI 350G", unita: "kg", formato: 0.35, prezzo: 2.29, inflazioneAnnua: 0.02, categoria: "Spesa alimentare", probabilita: 0.3,
                     testoDopo: "BISCOTTI FROLLINI 320G", formatoDopo: 0.32),
        ProdottoDemo(nome: String(localized: "Mozzarella 125 g"), testo: "MOZZARELLA 125G", unita: "kg", formato: 0.125, prezzo: 0.89, inflazioneAnnua: 0.05, categoria: "Spesa alimentare", probabilita: 0.5),
        ProdottoDemo(nome: String(localized: "Pomodori pelati 400 g"), testo: "POMODORI PELATI 400G", unita: "kg", formato: 0.4, prezzo: 0.79, inflazioneAnnua: 0.10, categoria: "Spesa alimentare", probabilita: 0.4),
        ProdottoDemo(nome: String(localized: "Banane"), testo: "BANANE", unita: "kg", formato: 1, prezzo: 1.79, inflazioneAnnua: 0.03, categoria: "Spesa alimentare", probabilita: 0.5, sfuso: true),
        ProdottoDemo(nome: String(localized: "Mele"), testo: "MELE GOLDEN", unita: "kg", formato: 1, prezzo: 2.29, inflazioneAnnua: 0.02, categoria: "Spesa alimentare", probabilita: 0.35, sfuso: true),
        ProdottoDemo(nome: String(localized: "Petto di pollo"), testo: "PETTO DI POLLO", unita: "kg", formato: 1, prezzo: 11.90, inflazioneAnnua: 0.06, categoria: "Spesa alimentare", probabilita: 0.4, sfuso: true),
        ProdottoDemo(nome: String(localized: "Yogurt bianco 500 g"), testo: "YOGURT BIANCO 500G", unita: "kg", formato: 0.5, prezzo: 1.49, inflazioneAnnua: 0.04, categoria: "Spesa alimentare", probabilita: 0.35),
        ProdottoDemo(nome: String(localized: "Acqua naturale 6×1,5 l"), testo: "ACQUA NATURALE 6X1,5L", unita: "l", formato: 9, prezzo: 2.19, inflazioneAnnua: 0.05, categoria: "Spesa alimentare", probabilita: 0.4),
        ProdottoDemo(nome: String(localized: "Parmigiano Reggiano 300 g"), testo: "PARMIGIANO REGG. 300G", unita: "kg", formato: 0.3, prezzo: 5.49, inflazioneAnnua: 0.09, categoria: "Spesa alimentare", probabilita: 0.2),
        ProdottoDemo(nome: String(localized: "Burro 250 g"), testo: "BURRO 250G", unita: "kg", formato: 0.25, prezzo: 2.49, inflazioneAnnua: 0.11, categoria: "Spesa alimentare", probabilita: 0.25),
        ProdottoDemo(nome: String(localized: "Detersivo piatti 1 l"), testo: "DETERSIVO PIATTI 1L", unita: "l", formato: 1, prezzo: 1.89, inflazioneAnnua: 0.03, categoria: "Casa e pulizia", probabilita: 0.15),
        ProdottoDemo(nome: String(localized: "Dentifricio 75 ml"), testo: "DENTIFRICIO 75ML", unita: "l", formato: 0.075, prezzo: 2.19, inflazioneAnnua: 0.04, categoria: "Cura personale", probabilita: 0.12),
    ]
}

private struct ProdottoDemo {
    let nome: String
    let testo: String
    let unita: String
    let formato: Double
    let prezzo: Double
    let inflazioneAnnua: Double
    let categoria: String
    let probabilita: Double
    var sfuso = false
    /// Dal 7° mese il formato cambia a parità di prezzo ("sgrammatura").
    var testoDopo: String? = nil
    var formatoDopo: Double? = nil
}

/// Generatore pseudo-casuale con seme fisso (SplitMix64): i dati demo sono sempre gli stessi.
private final class CasoDemo: RandomNumberGenerator {
    private var stato: UInt64
    init(seme: UInt64) { stato = seme }

    func next() -> UInt64 {
        stato &+= 0x9E37_79B9_7F4A_7C15
        var z = stato
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    func uniforme() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    func tra(_ a: Double, _ b: Double) -> Double { a + (b - a) * uniforme() }
    func intero(_ a: Int, _ b: Int) -> Int { a + Int(next() % UInt64(b - a + 1)) }
    func probabilita(_ p: Double) -> Bool { uniforme() < p }
    func scegli<T>(_ v: [T]) -> T { v[intero(0, v.count - 1)] }
}
