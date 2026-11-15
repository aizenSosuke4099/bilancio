# Bilancio — app iPhone per il bilancio personale

Stato e specifica condivisa. **Se la sessione si interrompe, riparti da qui.**

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
  conto deposito remunerato + obbligazioni, fondi pensione (anche in CHF → EUR), robo-advisor (valore manuale).
  ISIN → prezzo automatico (Yahoo Finance), cambio BCE (Frankfurter). Versato, valore attuale, guadagno, per piattaforma e tipo.
- **Banche collegate**: Enable Banking (PSD2, gratis per uso personale, consenso **180 giorni**, notifica prima della scadenza);
  conti correnti, conti online e carte di credito (se non supportati: import CSV/PDF). Sync all'apertura + background (max 4/giorno).
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
