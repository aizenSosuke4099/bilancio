# Bilancio — app iPhone per il bilancio personale

Diario di lavoro: decisioni, insidie, cosa è stato provato. **La documentazione completa per chi riprende il progetto è nel
[README](../README.md).** Se una sessione di lavoro si interrompe, riparti da qui.

## Requisiti (decisi con l'utente)

- App **nativa iPhone** (iOS 26+, Apple Intelligence per gli scontrini). Dati **solo sul telefono** (SwiftData).
  Firma con Apple ID gratuito → scade ogni 7 giorni: l'app avvisa prima (banner + notifiche).
- **Anno**: KPI entrate / spese / risparmio (+ tasso) / investito / patrimonio netto; grafico barre entrate-spese per mese con linea risparmio;
  ciambella spese per categoria; patrimonio nel tempo (liquidità + investimenti); tabella mese per mese; consigli dell'anno.
- **Mese**: selettore mese; banner "N movimenti da confermare"; KPI; spesa accumulata giorno per giorno vs mese precedente;
  categorie con budget (barre); saldi dei conti; ultimi movimenti; consigli del mese; controllo di fine mese.
- **Scansione scontrino**: VisionKit (ritaglio automatico) → OCR Vision → Apple Intelligence (Foundation Models, on-device)
  estrae negozio, data, totale, righe (prodotto, quantità, prezzo) e propone categoria + nome prodotto normalizzato.
  **Sempre revisione e conferma** dell'utente; le correzioni vengono **imparate** (RegolaAppresa). Foto salvata nell'archivio, per negozio.
  Si sceglie come è stato pagato (contanti o conto/carta); se esiste già il movimento bancario corrispondente, si collega.
- **Inflazione**: prodotti riacquistati ciclicamente → prezzo nel tempo (anche €/kg, €/l), variazione %, grafico, inflazione personale vs ISTAT.
- **Investimenti**: broker con PAC mensile (importo + % per ETF, quote frazionate calcolate col prezzo del giorno, riallineamento con quote reali),
  conto deposito remunerato + obbligazioni, fondi pensione (anche in valuta estera), robo-advisor (valore manuale).
  ISIN → prezzo automatico (Yahoo Finance), cambio BCE (Frankfurter). Versato, valore attuale, guadagno, per piattaforma e tipo.
- **Banche collegate**: Enable Banking (PSD2, gratis per uso personale, consenso **180 giorni**, notifica prima della scadenza);
  conti correnti, conti online e carte di credito (se non supportati: import CSV/PDF). Sync all'apertura dell'app (niente background: vedi Sicurezza).
  Giroconti, prelievi (→ Contanti), saldo carte di credito e versamenti investimenti **non** sono spese. Abbinamento scontrini ↔ movimenti.
- **Contanti**: conto con saldo che si riporta di mese in mese; prelievi lo alimentano; rettifica "conto i contanti".
- **Ricorrenti**: proposti ogni mese da confermare (stipendio, abbonamenti, PAC); elenco con totale annuo.
- **Consigli** mensili e annuali (regole locali).
- **Backup** su File / iCloud Drive (niente CloudKit con account gratuito). Blocco con Face ID.

## Architettura

- Xcode project con cartella sincronizzata `Bilancio/` (ogni file .swift dentro è compilato automaticamente).
- SwiftUI + SwiftData + Swift Charts + VisionKit + Vision + FoundationModels + PDFKit. **Nessuna dipendenza esterna.**
- Swift 5 mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Target iOS 26.0.
- **Codice, nomi e commenti in italiano.** UI in italiano (lingua sorgente) e inglese.
- Importi `Double` con segno sui `Movimento` (< 0 uscita). Enum salvati come `*Raw: String`.

### File condivisi (NON modificare dai sotto-agenti; se serve qualcosa, estensioni nel proprio folder)
- `Modello/Modelli.swift`, `Modello/Tipi.swift` — tutti i @Model e gli enum
- `Core/Persistenza.swift` — container (`Persistenza.container`), cartella DB per backup
- `Core/Contabilita.swift` — totali, spese per categoria (scontrini ripartiti per riga), saldi, patrimonio, snapshot, `Movimento.conferma()`
- `Core/Portafoglio.swift` — quote, versato, valore, rendimento, cambi
- `Core/Classificatore.swift` — regole imparate + parole chiave (banca/righe), `impara(...)`
- `Core/Abbinamento.swift` — scontrino ↔ movimento banca
- `Core/DatiIniziali.swift` — categorie e conti iniziali, `contoContanti(in:)`
- `Core/Formato.swift` — `.euro`, `.percento`, date in italiano, `leggiNumero`
- `Core/UI.swift` — `Scheda`, `RiquadroKPI`, `SchedaConsigli`, `IconaCategoria`, `RigaMovimento`, `Tinta`, `Color(hex:)`
- `App/BilancioApp.swift` (Avvio), `App/RootView.swift` (tab + hub Altro)

### Aree (una per sotto-agente, ognuno solo nei propri file)
| Area | File |
|---|---|
| A Scansione | `Features/Scansione/*` (ScansioneView, ScontrinoDettaglioView + parser/OCR/revisione) |
| B Dashboard | `Features/Anno/*`, `Features/Mese/*`, `Features/Movimenti/*`, `Features/Consigli/*` |
| C Investimenti | `Features/Investimenti/*` (InvestimentiView, Prezzi, PAC) |
| D Banche e conti | `Features/Banche/*`, `Features/Conti/*`, `Features/Ricorrenti/*` |
| E Altro | `Features/Inflazione/*`, `Features/Archivio/*`, `Features/Categorie/*`, `Features/Backup/*`, `Features/Impostazioni/*` |

Build di verifica:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Bilancio.xcodeproj -scheme Bilancio \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build
```

## Avanzamento

Lavoro parallelo: worktree `~/Developer/bilancio-wt/{a,b,c,d,e}` sui branch `area-a` … `area-e`
(creati da `main` @ be9da63). Quando un'area ha il suo commit, va unita in `main` con `git merge area-x`;
poi build completa e correzione degli errori di integrazione. Se un agente si è interrotto, controlla
`git -C ../bilancio-wt/x status` / `log` e completa il lavoro rimasto in quel worktree.

- [x] Requisiti raccolti con l'utente
- [x] Progetto + modello dati + core condiviso (compila)
- [x] A Scansione (unita)
- [x] B Anno / Mese / movimenti / consigli
- [x] C Investimenti
- [x] D Banche, import, conti, contanti, ricorrenti
- [x] E Inflazione, archivio, categorie, backup, impostazioni, Face ID, scadenza firma
- [x] Integrazione (merge dei rami) + build — OK
- [x] Test su simulatore (dati di esempio): le 5 schede si aprono e mostrano i dati. Sottopagine non toccate (accesso al pannello simulatore non concesso).
- [x] Multilingua: italiano + inglese (vedi sotto)
- [x] Installazione su iPhone (15/11): firma con Apple ID gratuito, rinnovo ogni 7 giorni con `./installa.sh` (iPhone collegato).

### Note operative (15/11 notte)
- Progetto spostato in `~/Developer/bilancio` (fuori da iCloud: la Scrivania sincronizzata toglieva i file dal disco). In Scrivania › Claude c'è un collegamento.
- Disco quasi pieno: un aggiornamento macOS occupa 16 GB in /System/Volumes/Update. Build snelle: `ARCHS=arm64 COMPILER_INDEX_STORE_ENABLE=NO`, niente simulatore durante il lavoro parallelo, `rm -rf build` a fine lavoro.
- 5 agenti interrotti dal limite d'uso: lavoro parziale salvato come commit "WIP area x" nei rispettivi branch.
- Test simulatore (15/11 01:40): Anno OK con dati demo (`-demo`). Bloccato: disco pieno (ENOSPC) appena il simulatore si avvia.
  Serve spazio (installare l'aggiornamento macOS libera 16 GB). Poi: `-demo -tab N` per ogni scheda; il permesso notifiche
  va concesso al primo avvio (tap su "Consenti").
- Test simulatore (15/11 03:40): OK dopo l'aggiornamento macOS (21 GB liberi). Al primo avvio dopo il boot l'app impiega ~15-20 s:
  aspettare prima dello screenshot. Corretto il "-7726% delle entrate" a metà mese (`Totali.tassoSignificativo`).

### Multilingua (15/11)
- `Bilancio/Localizable.xcstrings`: chiavi = testo italiano, traduzione inglese. Le stringhe in `Text`/`Label`/`Button` e nei
  parametri `LocalizedStringKey` (`Scheda`, `RiquadroKPI`, `SchedaConsigli`…) si estraggono da sole; le `String` vanno scritte
  con `String(localized: "…")`. Per aggiungere una lingua: aprire il catalogo in Xcode e aggiungerla.
- `Bilancio/DatiIniziali.xcstrings`: nomi di categorie e conto Contanti creati al primo avvio (si salvano nella lingua del telefono).
  Le tabelle in `DatiIniziali.swift` e le parole chiave del `Classificatore` restano in italiano: per cercare una categoria per nome
  usare `Classificatore.categoria(nome:in:)`, `DatiIniziali.localizzato(_:)` o `DatiIniziali.corrisponde(_:a:)`.
- Numeri e date: formato della lingua del telefono (niente `.locale(...)` fisso); gli importi restano in euro.
  `localeIT` serve solo a leggere scontrini, estratti conto e parole chiave, che restano italiani.
- Prova in inglese: `-demo -tab N -AppleLanguages (en)` dopo aver disinstallato l'app (i dati demo si creano solo a database vuoto).

### Valute, aggiornamenti, backup aperto (15/11 sera)
- Conti in valuta estera (es. un conto in CHF): `Conto.valuta`; `Movimento.importo` resta SEMPRE in euro (convertito con
  `Contabilita.inEuro` all'ultimo cambio BCE), l'originale in `importoOriginale`/`valutaOriginale`.
  Saldo: `Contabilita.saldoInValuta` (valuta del conto) e `saldo` (euro al cambio di oggi). Giroconti tra valute diverse: margine 3%.
- "Aggiorna app" (Altro): confronta il commit scritto da `installa.sh` nell'Info.plist (`BilancioCommit`) con `main` su GitHub.
  iOS non permette l'auto-aggiornamento: `installa.sh` fa `git pull` (se non ci sono modifiche locali) e reinstalla.
- Backup = cartella in formato aperto (`BackupAperto`): `bilancio.json` + `foto/` + `movimenti.csv` + `LEGGIMI.txt`.
  Il ripristino costruisce un database nuovo da JSON in RipristinoInSospeso (applicato al riavvio); i vecchi backup
  (copia della cartella del database) si ripristinano ancora. Esclusi chiave ed Application ID di Enable Banking.
- Prove: `-verifica` (giroconti, CHF, giro completo del backup su dati demo); `-provaRipristino` (backup del database vero +
  ripristino in sospeso; al riavvio dopo, confrontare i conteggi con sqlite3 tra `Bilancio/` e `Bilancio-prima-del-ripristino-*`).
- Simulatore: l'app impiega 30-40 s ad apparire e intanto iOS mostra l'ultima istantanea (anche in un'altra lingua):
  aspettare ~60 s prima degli screenshot. Un avviso di sistema mai chiuso resta a schermo anche dopo la disinstallazione: riavviare il simulatore.
- Traduzioni: `xcodebuild` non aggiorna il catalogo; le chiavi nuove vanno aggiunte a mano (le chiavi estratte sono nei
  `*.stringsdata` in build/dd/…/Objects-normal/arm64: confrontarle col catalogo). Il file va riscritto con
  `json.dumps(…, ensure_ascii=False, indent=2, separators=(',', ': '))` + "\n" mantenendo l'ordine delle chiavi.

### Commissioni, costo del cambio, inflazione con ISTAT automatico (15/11 sera)
- Categoria "Commissioni bancarie" (bonifici, canoni, fee, spread, interessi passivi); "Tasse e commissioni" diventa "Tasse e imposte".
  Per chi ha già l'app: `DatiIniziali.aggiornaCategorie` (una volta sola, flag `categorie.commissioniBancarie`).
- CSV con colonna commissione ("Fee"): la commissione diventa un movimento a parte "Commissione: …".
- Giroconto tra valute diverse: la differenza (spread + costi nel tasso) diventa una spesa senza conto in Commissioni bancarie,
  `idEsterno = "costo-cambio:<id del movimento in valuta>"`. `Contabilita.applicaCambiStorici` (all'apertura) ricalcola i movimenti
  in valuta col cambio BCE del loro giorno (`cambioStorico`) e aggiorna il costo.
- Inflazione: indice NIC ISTAT scaricato da solo (`ISTAT`, SDMX 167_744, al massimo una volta al giorno, ~15 s; dati in UserDefaults).
  Pagina: tua inflazione vs ISTAT, paniere su tutto lo storico con la curva ISTAT, prodotto → grafico con punto selezionabile e
  acquisti che aprono lo scontrino. Il campo ISTAT manuale nelle Impostazioni è stato tolto.
- Cartella di Bilancio NON visibile in File dal 17/11: tolto `UIFileSharingEnabled` (i backup locali in chiaro si leggevano senza
  Face ID); resta `LSSupportsOpeningDocumentsInPlace` per aprire gli estratti dove sono, senza copiarli nell'app. Non usare PlistBuddy sull'Info.plist: toglie i commenti.
- Banche (15/11 sera): prime banche collegate, sincronizzazione OK. Errore 429 ASPSP_RATE_LIMIT_EXCEEDED risolto con le
  intestazioni PSU (`EnableBanking.intestazioniPSU`) quando l'utente usa l'app; in background niente intestazioni (limite ~4/giorno).
  Con la pagina ponte funzionano anche le banche che confermano il login nella loro app.
  Carte e banche non presenti su Enable Banking: import dell'estratto conto.
- Login banche (15/11 notte): Enable Banking accetta solo redirect https. Redirect predefinito = pagina ponte GitHub Pages
  https://aizensosuke4099.github.io/bilancio/callback/ (docs/callback/index.html) → bilancio://callback; il login gira in
  ASWebAuthenticationSession (passa alle app delle banche che confermano il login nella loro app). Il ritorno da fuori vale solo con lo state giusto.
  Su Enable Banking i redirect registrati sono https://localhost/bilancio (vecchio, pagina dentro l'app) e la pagina ponte.
- Sicurezza (15/11 notte): database e backup locali con FileProtectionType.complete (illeggibili a telefono bloccato) →
  niente più sincronizzazione in background (UIBackgroundModes tolto), si sincronizza all'apertura (PSU, ogni 30 min).
  Backup esportati cifrati con password (`CifraturaBackup`: PBKDF2-HMAC-SHA256 600k + AES-256-GCM, file *.enc + cifratura.json);
  i backup locali restano in chiaro (protetti da iOS) per il backup automatico. Ripristino: chiede la password se serve.
  Chiave .pem: in Portachiavi sull'iPhone e nel gestore di password dell'utente; le copie in Documents si cancellano da sole.

### Revisione completa (16-17/11)
- Sei revisioni in sola lettura (sicurezza, abbinamenti e banche, scontrini, dati e backup, calcoli, estratti conto), poi le
  correzioni nei commit "Revisione 1/5" … "5/5". Il README è aggiornato a queste modifiche.
- Abbinamenti (`Core/Abbinamento.swift`): `giorniTolleranza` 3 (movimenti previsti e giroconti), `giorniAddebito` 10 (scontrino →
  addebito, mai il contrario), `giorniCollegamento` 45 e `scartoCollegamento` 20% (collegamento a mano). Si confronta l'importo
  nella valuta del conto (`nelConto`). `generico` dice quali movimenti possono diventare giroconto per abbinamento.
- `Sincronizzazione.eliminati`: id delle transazioni eliminate dall'utente (UserDefaults + backup), per non farle ricomparire.
  `Sincronizzazione.scollega`: scollegando una banca il saldo riparte dall'ultimo letto.
- Backup: si scrive in `.in-corso-*` e si rinomina alla fine; il ripristino si prepara in `RipristinoInPreparazione` e diventa
  `RipristinoInSospeso` solo quando è completo; prima di un ripristino si fa un backup dei dati attuali.
- Parser degli scontrini: il totale non letto resta nil (mai la somma delle righe); parole "ambigue" scartano la riga solo se non
  resta altro; quantità in testa alla riga solo con la colonna Qta.
- Estratti conto: colonne in tedesco, `righeNonLette` (righe con data o importo illeggibili), `èSaldo`, giroconto proposto già
  nell'anteprima con `Abbinamento.controparte`.
- Investimenti: `Portafoglio.investitoEUR` è il denominatore del rendimento; `guadagnoEUR` include dividendi e cedole.
- `-verifica` ora controlla anche `Portafoglio` e `GeneratoreRicorrenze` (prima era un programma a parte che non compilava più).
- `installa.sh`: l'identificativo dell'app si può cambiare con il file locale `.identificativo` (per chi usa un altro Apple ID).
- Lasciato così di proposito: con l'addebito arrivato prima dello scontrino resta la data della banca; una ricorrenza con importo
  variabile resta un doppione visibile da eliminare a mano; `leggiNumero("1.500")` vale 1,5 (trattarlo come migliaia romperebbe
  pesi e prezzi con tre decimali sugli scontrini).
- Deciso dall'utente il 17/11: i backup locali non devono comparire nell'app File (fatto). Restano da decidere: dati dell'app nel
  backup iCloud dell'iPhone, nome della banca nelle notifiche di scadenza, elenco generico di banche online nelle parole chiave.
