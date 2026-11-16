# Bilancio

App iPhone per il bilancio personale: entrate, spese, risparmio, investimenti, scontrini e inflazione dei prodotti che compri.
I conti arrivano da soli dalle banche (Enable Banking, PSD2, sola lettura) o dagli estratti conto. **Tutti i dati restano sul
telefono**: niente server, niente account, niente cloud dell'app.

Scritta in SwiftUI + SwiftData, senza dipendenze esterne. Interfaccia in italiano e in inglese.

> **Se riprendi il progetto dopo tanto tempo**, leggi prima [In breve](#in-breve), poi il capitolo che ti serve.
> Il diario di lavoro dettagliato (decisioni, insidie, cosa è stato provato) è in [`tasks/todo.md`](tasks/todo.md).

---

## Indice

1. [In breve](#in-breve)
2. [Cosa fa l'app](#cosa-fa-lapp)
3. [Dove stanno i dati e i segreti](#dove-stanno-i-dati-e-i-segreti)
4. [Installare, rinnovare e aggiornare l'app](#installare-rinnovare-e-aggiornare-lapp)
5. [Banche collegate (Enable Banking)](#banche-collegate-enable-banking)
6. [Estratti conto (CSV e PDF)](#estratti-conto-csv-e-pdf)
7. [Conti in valuta estera](#conti-in-valuta-estera)
8. [Come vengono classificati i movimenti](#come-vengono-classificati-i-movimenti)
9. [Scontrini e inflazione](#scontrini-e-inflazione)
10. [Investimenti](#investimenti)
11. [Backup, ripristino, cambio di telefono (anche Android)](#backup-ripristino-cambio-di-telefono-anche-android)
12. [Sicurezza](#sicurezza)
13. [Servizi esterni](#servizi-esterni)
14. [Cosa scade e quando](#cosa-scade-e-quando)
15. [Problemi frequenti](#problemi-frequenti)
16. [Per lo sviluppo](#per-lo-sviluppo)

---

## In breve

| Cosa | Dove / come |
|---|---|
| Codice | questa repository; sul Mac in `~/Developer/bilancio` |
| Installare o aggiornare sull'iPhone | iPhone collegato al Mac, poi `./installa.sh` dalla cartella del progetto |
| La firma dell'app scade | **ogni 7 giorni** (Apple ID gratuito): rilancia `./installa.sh`, i dati restano |
| Il collegamento con ogni banca scade | dopo **180 giorni** (alcune banche 90): in app *Altro › Banche collegate*, scorri sulla banca › **Rinnova** |
| Segreti (chiave privata Enable Banking, Application ID, password dei backup) | nel tuo **gestore di password**; sull'iPhone nel Portachiavi |
| Account Enable Banking | <https://enablebanking.com/cp/applications> (accesso con la tua email, link via mail) |
| Aggiungere un conto o una banca | prima **Control Panel › Link accounts**, poi nell'app **Collega una banca** ([dettagli](#aggiungere-un-nuovo-conto-o-una-nuova-banca)) |
| Backup | *Altro › Backup*: automatico ogni settimana sul telefono; **esportalo** ogni tanto (protetto da password) |
| Nuove versioni | *Altro › Aggiorna app* dice se su GitHub c'è qualcosa di nuovo |

---

## Cosa fa l'app

Cinque schede in basso:

- **Anno** – entrate, spese, risparmio (con il tasso sulle entrate), investito, patrimonio netto; grafico mese per mese con la linea
  del risparmio; spese per categoria; patrimonio nel tempo; tabella dei mesi; consigli dell'anno.
- **Mese** – scelta del mese; avviso "N movimenti da confermare"; spesa accumulata giorno per giorno confrontata col mese prima;
  categorie con budget; ultimi movimenti; consigli del mese; controllo di fine mese.
- **Scansiona** – fotografi uno scontrino (anche lungo, in più foto): l'app legge negozio, data, righe e totale, propone categoria e
  nome del prodotto, tu controlli e confermi. Se il pagamento è già arrivato dalla banca, lo collega invece di contarlo due volte.
- **Investimenti** – strumenti (ETF, azioni, obbligazioni, fondi pensione, gestioni), piani di accumulo (PAC) con le percentuali per
  ETF, prezzi aggiornati da soli, versato, valore, guadagno, ripartizione per piattaforma.
- **Altro**
  - *Inflazione dei prodotti* – la tua inflazione (prezzi dei prodotti che ricompri) contro quella ufficiale ISTAT, il tuo "paniere"
    nel tempo, il grafico del prezzo di ogni prodotto con gli scontrini come prova.
  - *Archivio scontrini* – tutte le foto, per negozio.
  - *Conti e contanti* – saldi, conti in valuta estera, prelievi, "conta i contanti".
  - *Pagamenti ricorrenti* – stipendio, abbonamenti, affitto… proposti ogni mese da confermare.
  - *Banche collegate* – configurazione di Enable Banking, collegamenti, sincronizzazione.
  - *Importa estratto conto* – CSV o PDF delle banche non collegabili.
  - *Categorie e budget*, *Backup*, *Impostazioni*, *Aggiorna app*.

Altro da sapere:

- **Movimenti "da confermare"**: quelli arrivati dalla banca aspettano la tua conferma (banner blu in *Mese*). Ogni correzione di
  tipo, categoria o titolo viene ricordata e applicata da sola la volta dopo.
- **Tipi di movimento**: *spesa*, *entrata*, *giroconto* (spostamento tra conti tuoi: non conta nei totali), *investimento*.
- **Face ID** all'apertura e al ritorno nell'app; nel multitasking il contenuto è sfocato.
- **Notifiche**: firma dell'app in scadenza, collegamenti con le banche in scadenza, promemoria di backup.
- **Lingua**: segue quella dell'iPhone (italiano o inglese). Le categorie iniziali nascono nella lingua del telefono.

---

## Dove stanno i dati e i segreti

| Cosa | Dove | Note |
|---|---|---|
| Database (movimenti, conti, scontrini, investimenti…) | iPhone, cartella privata dell'app (SwiftData) | cifrato da iOS, illeggibile a telefono bloccato |
| Foto degli scontrini | dentro il database | |
| Backup locali | iPhone, *File › Sul mio iPhone › Bilancio › Backup* | uno a settimana, si tengono gli ultimi 4 |
| Backup esportati | dove li salvi tu (iCloud Drive, Google Drive, Mac) | cifrati con la **tua password** |
| Chiave privata Enable Banking (`.pem`) | Portachiavi dell'iPhone (solo quel telefono) + **copia nel gestore di password** | senza, l'app non può leggere le banche |
| Application ID Enable Banking | Portachiavi dell'iPhone + gestore di password + Control Panel di Enable Banking | non è segreto, ma serve |
| Password dei backup esportati | **solo nel gestore di password** | se la perdi, quei backup non si aprono |
| Elenco delle banche collegate | app (*Banche collegate*) e Control Panel di Enable Banking | volutamente **non** in questa repository pubblica |

Questa repository è **pubblica**: non deve mai contenere nomi dei tuoi conti, IBAN, chiavi, password o email.
I commit usano l'email anonima di GitHub (`…@users.noreply.github.com`, già impostata nel repository locale).

---

## Installare, rinnovare e aggiornare l'app

L'app non è sull'App Store: la installi tu dal Mac, firmata col tuo Apple ID gratuito.

### Cosa serve

- Un Mac con **Xcode** (App Store). In *Xcode › Settings › Accounts* il tuo **Apple ID** (va bene quello gratuito).
- L'iPhone con iOS 26 o successivo, la **Modalità sviluppatore** attiva
  (*Impostazioni › Privacy e sicurezza › Modalità sviluppatore*; se la voce non c'è, collega l'iPhone col Mac e apri Xcode:
  compare dopo qualche secondo).
- Il codice: `git clone https://github.com/aizenSosuke4099/bilancio.git ~/Developer/bilancio`

### Installare (e ogni 7 giorni, per rinnovare la firma)

1. Collega l'iPhone al Mac col cavo e sbloccalo.
2. Dal Terminale:

   ```bash
   ~/Developer/bilancio/installa.sh
   ```

   Lo script trova da solo il tuo Apple ID (team) e l'iPhone collegato, **scarica da GitHub l'ultima versione** (se non hai
   modifiche locali), compila in Release, installa e apre l'app.
3. **Solo la prima volta**: iOS blocca l'app ("sviluppatore non autorizzato"). Vai in
   *Impostazioni › Generali › VPN e gestione dispositivi*, tocca il tuo Apple ID › **Autorizza**.

Con l'Apple ID gratuito la firma dura **7 giorni**: poi l'app non si apre più finché non rilanci `installa.sh`. **I dati non si
perdono.** L'app ti avvisa due giorni prima, il giorno prima e la mattina della scadenza. Con l'account sviluppatore a pagamento
(99 €/anno) la firma durerebbe un anno.

### Aggiornare

*Altro › Aggiorna app* confronta la versione installata con l'ultima su GitHub ed elenca le novità. iOS non permette a un'app
installata così di aggiornarsi da sola: l'aggiornamento lo fa `installa.sh` (stesso comando del rinnovo).

### Se l'app non si apre

- **Firma scaduta** → `installa.sh`.
- **"Sviluppatore non autorizzato"** → *VPN e gestione dispositivi* › Autorizza.
- **Lo script dice "Nessun iPhone collegato"** → sblocca l'iPhone, tocca "Autorizza questo computer", controlla la Modalità sviluppatore.
- **Errore di firma o "No profiles"** → apri Xcode una volta con l'iPhone collegato e controlla l'Apple ID in *Settings › Accounts*.

---

## Banche collegate (Enable Banking)

### Come funziona

[Enable Banking](https://enablebanking.com) è un intermediario autorizzato (PSD2) che permette di **leggere** saldi e movimenti dei
conti europei. Per uso personale è **gratuito** in modalità "restricted": l'applicazione può leggere **solo i conti che hai
collegato a mano nel Control Panel**. L'accesso è **in sola lettura**: con questa configurazione nessuno può fare pagamenti.

I pezzi:

1. **Account Enable Banking**: accesso su <https://enablebanking.com/sign-in/> con la tua email (arriva un link).
2. **Applicazione "Bilancio"** nel Control Panel (*API applications*), ambiente **Production**, con:
   - **Application ID** (un codice tipo `xxxxxxxx-xxxx-…`; è anche il nome del file `.pem`);
   - **chiave privata** `.pem`, generata nel browser alla creazione e **non riscaricabile** (copia nel gestore di password);
   - **Redirect URLs** registrati:
     - `https://aizensosuke4099.github.io/bilancio/callback/` – la **pagina ponte** usata dall'app (vedi sotto);
     - `https://localhost/bilancio` – vecchio metodo, resta come riserva.
   - email per la protezione dei dati e link a termini e privacy (va bene il link a questa repository).
3. **Conti collegati** nel Control Panel (*Link accounts*): l'elenco dei conti che l'applicazione può leggere.
4. **Collegamenti nell'app** (*Altro › Banche collegate*): un consenso per banca, valido 180 giorni (o meno se la banca lo limita).

#### La pagina ponte

Enable Banking accetta solo indirizzi di ritorno `https`. Il login con la banca si apre nel **browser sicuro di iOS** (così può
passare all'app della banca per la conferma e tornare); alla fine la banca rimanda a
`https://aizensosuke4099.github.io/bilancio/callback/?code=…&state=…`. Quella pagina ([`docs/callback/index.html`](docs/callback/index.html),
pubblicata con GitHub Pages da questa repository, cartella `docs`) riapre subito l'app con `bilancio://callback?code=…&state=…`.
Non salva nulla; il `code` da solo non serve a niente senza la chiave privata. L'app accetta il ritorno solo se lo `state` è quello
del login in corso.

> Se un giorno la repository cambia nome o proprietario, l'indirizzo della pagina cambia: aggiornalo **sia** nei Redirect URLs del
> Control Panel **sia** nell'app (*Banche collegate › Come si configura › Redirect URL*, e il valore predefinito in
> `BancheView.redirectPredefinito`).

### Aggiungere un nuovo conto o una nuova banca

**Passo 1 – Control Panel (sul Mac, una volta per conto)**

1. Vai su <https://enablebanking.com/cp/applications> e accedi.
2. Sotto l'applicazione **Bilancio** premi **Link accounts**.
3. Scegli **Country** (es. *Italy*), la banca (**ASPSP**) e **Usage type: personal**, poi **Link**.
4. Accetta i termini di Enable Banking, accedi alla banca e conferma (spesso nell'app della banca).
5. Seleziona i conti da condividere. Tornato al Control Panel, li vedi in *Linked accounts*.

Senza questo passo, l'app riceve un **elenco di conti vuoto** da quella banca.

**Passo 2 – App (sull'iPhone)**

1. *Altro › Banche collegate › Collega una banca*.
2. Scegli la banca: si apre il login nel browser di iOS (tocca **Continua** se iOS chiede il permesso).
3. Accedi e conferma. Se la banca ti porta nella sua app e poi in Safari, sulla pagina "Torno a Bilancio…" tocca **Apri Bilancio**.
4. **Abbina i conti**: per ogni conto della banca scegli un conto esistente in Bilancio o "nuovo". I conti nuovi prendono il nome
   della banca (con "– carta" per le carte e la valuta se non è in euro); puoi rinominarli in *Conti e contanti*.
5. Parte subito la prima sincronizzazione: arrivano gli **ultimi 90 giorni** di movimenti, da confermare.

### Rinnovare un collegamento

*Banche collegate*: accanto a ogni banca c'è "Scade tra N giorni" (arancione nell'ultima settimana, rosso se scaduto). Scorri sulla
riga › **Rinnova** e rifai il login. I movimenti già importati restano. Le notifiche arrivano 7 giorni prima, il giorno prima e il
giorno della scadenza.

### Sincronizzazione

- Parte da sola **quando apri l'app**, al massimo ogni 30 minuti; *Sincronizza ora* la forza.
- **Niente aggiornamento in background**: è il prezzo della cifratura completa del database ([Sicurezza](#sicurezza)).
- Ogni sincronizzazione riprende da 5 giorni prima dell'ultima (le banche contabilizzano in ritardo); i doppioni vengono scartati
  grazie agli identificativi delle transazioni.
- Con l'app aperta l'app invia le **intestazioni PSU** (IP e identificativo dell'app): la banca sa che sei presente e non applica il
  limite di ~4 letture al giorno previsto per gli accessi senza utente.

### Se la chiave privata va persa

Non si può riscaricare. Si rifà tutto con una nuova applicazione:

1. Control Panel › *Add a new application*: **Production**, chiave generata nel browser (scarica il `.pem` e mettilo nel gestore
   di password), stessi Redirect URLs, email e link.
2. **Link accounts** per ogni conto (come sopra).
3. Nell'app: *Banche collegate* › nuovo **Application ID** e **Sostituisci chiave** (importa il file o incolla il testo).
4. Ricollega ogni banca con *Collega una banca*.

### Banche che non ci sono

Non tutte le banche e le carte sono su Enable Banking (in particolare alcune carte di credito e le **banche svizzere**: la Svizzera
non è nel PSD2). Per quelle usa gli [estratti conto](#estratti-conto-csv-e-pdf). L'elenco aggiornato è nel Control Panel
(*Link accounts* › Country › ASPSP).

---

## Estratti conto (CSV e PDF)

*Altro › Importa estratto conto*, oppure "Apri con Bilancio" da File, Mail o dall'app della banca.

1. Scegli il file. Un **CSV** viene letto da solo (separatore, colonne, formato di date e importi); la prima volta puoi correggere le
   colonne con **Colonne** e l'app ricorda il formato di quella banca. Un **PDF** viene letto con Apple Intelligence sul telefono,
   con regole di riserva.
2. Scegli il **conto** di destinazione.
3. **Anteprima**: le righe già presenti (stesso movimento già importato o arrivato dalla banca) sono deselezionate.
   - **Tocca una riga** per correggere titolo, tipo, categoria, data o importo. La correzione vale anche per le altre righe con la
     stessa descrizione e diventa una regola per i prossimi import.
   - Il **cerchio** a sinistra include o esclude la riga; scorrendo la riga puoi **invertire il segno** (PDF senza dare/avere).
4. **Conferma e importa**: i movimenti entrano **già confermati**.

Se il file ha una colonna **commissione** (es. "Fee" negli export di alcune banche online), ogni commissione diventa un movimento a parte in
*Commissioni bancarie*.

Ogni quanto: una volta al mese per le carte e i conti non collegabili, dopo l'arrivo dell'estratto.

---

## Conti in valuta estera

Quando crei un conto (*Conti e contanti* › +) scegli la **valuta** (EUR, CHF, USD, GBP).

- Saldo e movimenti del conto restano **nella sua valuta**; sotto vedi l'equivalente in euro al cambio di oggi.
- Nei totali (entrate, spese, patrimonio) ogni movimento è convertito in euro col **cambio BCE del suo giorno** (ricalcolato da solo
  all'apertura, serve internet).
- I bonifici tra un conto in euro e uno in un'altra valuta sono riconosciuti come giroconti anche se il cambio della banca è un po'
  diverso (tolleranza 3%). La differenza tra quanto è uscito e quanto è entrato al cambio BCE (spread e costi nascosti nel tasso)
  diventa una spesa "**Costo del cambio**" in *Commissioni bancarie*, senza toccare i saldi dei conti.

---

## Come vengono classificati i movimenti

In ordine:

1. **Regole imparate** dalle tue correzioni (stessa descrizione bancaria → stesso tipo, categoria e titolo).
2. **Parole chiave** (in `Core/Classificatore.swift`): supermercati, bollette, trasporti, abbonamenti…, giroconti, investimenti,
   stipendio, commissioni bancarie, tasse.
3. Altrimenti: entrata in "Altre entrate" o spesa in "Altro".

Altri automatismi:

- **Giroconti tra conti tuoi**: un'uscita su un conto e un'entrata dello stesso importo su un altro conto entro 3 giorni diventano
  entrambe giroconto (non contano nei totali). Se correggi a mano una metà in giroconto, cambia anche l'altra.
- **Pagamento della carta di credito** dal conto corrente: se la carta è tracciata nell'app, è un giroconto. La prima volta segnalo
  tu come *Giroconto*: l'app lo impara.
- **Prelievi**: diventano un giroconto verso il conto *Contanti*.
- **Scontrini**: uno scontrino e il pagamento bancario dello stesso importo (±3 giorni) vengono collegati, così la spesa non conta due volte.
- **Commissioni**: canoni, spese dei bonifici, fee, spread, interessi passivi vanno in *Commissioni bancarie*; bolli, F24, imposte in
  *Tasse e imposte*.

---

## Scontrini e inflazione

- **Scansione**: ritaglio automatico (VisionKit), testo letto sul telefono (Vision). Prezzi, quantità e totali li leggono regole
  scritte apposta; **Apple Intelligence** (sul telefono, offline) propone solo categoria e nome normalizzato del prodotto, perché
  inventava i prezzi. Controlli sempre prima di confermare; le correzioni vengono ricordate.
- **Prodotti**: righe scritte in modo diverso (anche in negozi diversi) si uniscono in un unico prodotto (*Inflazione › Gestisci
  prodotti › Unisci*). Il formato (es. 500 g) permette il prezzo al kg o al litro, e scopre le "sgrammature".
- **Inflazione**: per ogni prodotto comprato in almeno due giorni diversi si confronta il prezzo; la tua inflazione è la media pesata
  sulla spesa degli ultimi 12 mesi. Il **paniere** concatena le variazioni mese per mese. Il dato **ISTAT** (indice NIC) si scarica
  da solo una volta al giorno e appare accanto. Tocca un punto del grafico o una riga degli acquisti per aprire lo **scontrino**.

---

## Investimenti

- **Strumenti** dall'ISIN: l'app trova il simbolo su Yahoo Finance e aggiorna i prezzi (al massimo ogni 6 ore, o tirando giù la pagina).
- **PAC**: importo mensile ripartito in percentuale sugli ETF; ogni mese genera le operazioni con le quote frazionate calcolate al
  prezzo del giorno; puoi riallineare le quote con quelle reali.
- **Fondi pensione e gestioni**: valore aggiornato a mano (*Valutazione*); versamenti dal conto.
- **Valute**: strumenti in CHF/USD convertiti con i cambi BCE.

---

## Backup, ripristino, cambio di telefono (anche Android)

### Formato

Un backup è una **cartella** in formato aperto:

| File | Contenuto |
|---|---|
| `bilancio.json` | tutti i dati (JSON UTF-8): conti, movimenti, categorie, ricorrenti, scontrini e righe, prodotti, regole imparate, strumenti, operazioni, valutazioni, PAC, collegamenti, formati di import |
| `foto/` | le foto degli scontrini |
| `movimenti.csv` | i movimenti per Excel / Fogli Google |
| `LEGGIMI.txt` | descrizione completa del formato (italiano e inglese) |

Non contiene la chiave privata né l'Application ID.

**Esportato fuori dall'iPhone** (*Backup › Crea backup e salva in File…*) il backup è **cifrato con la tua password**: ogni file
diventa `*.enc` (AES-256-GCM; chiave da PBKDF2-HMAC-SHA256 con 600.000 iterazioni e sale casuale; parametri in `cifratura.json`).
`LEGGIMI.txt` resta leggibile e spiega come decifrare. **Senza password il backup non si apre**: tienila nel gestore di password.
L'esportazione CSV è invece in chiaro.

### Ripristino

*Backup* › scorri su un backup locale › **Ripristina**, oppure **Ripristina da una cartella di backup…** (per quelli esportati: chiede
la password). Poi **chiudi l'app dal multitasking e riaprila**: i dati attuali vengono sostituiti, e una copia di sicurezza di quelli
vecchi resta nella cartella dell'app. Si ripristinano anche i backup del vecchio formato (copia del database).

### Cambio di iPhone

1. Sul vecchio: *Backup › Crea backup e salva in File…* su iCloud Drive (con password).
2. Sul nuovo: installa con `installa.sh` (Modalità sviluppatore, autorizza lo sviluppatore).
3. *Backup › Ripristina da una cartella di backup…*, password, chiudi e riapri.
4. *Banche collegate*: Application ID e chiave dal gestore di password (*Aggiungi chiave › Incolla il testo*). I collegamenti
   ripristinati dal backup continuano a funzionare fino alla loro scadenza; se danno errore, **Rinnova**.

### Passaggio ad Android

Non esiste (ancora) una versione Android. Il backup è pensato per essere letto da una futura app o da uno script: il formato è
descritto in `LEGGIMI.txt`, la cifratura usa algoritmi standard disponibili anche su Android
(`PBKDF2WithHmacSHA256` + `AES/GCM/NoPadding`).

---

## Sicurezza

- **Dati a riposo**: database, foto, copie di sicurezza e backup locali hanno la protezione *completa* di iOS
  (`FileProtectionType.complete`): cifrati con una chiave legata al codice dell'iPhone, illeggibili a telefono bloccato.
  Per questo l'app non lavora in background.
- **Segreti**: chiave privata e Application ID nel Portachiavi, accessibili solo su quel telefono
  (`AfterFirstUnlockThisDeviceOnly`), mai su iCloud. Copie `.pem` lasciate nella cartella dell'app vengono cancellate; gli appunti
  si svuotano dopo aver incollato la chiave.
- **Accesso alle banche in sola lettura** (Account Information): nessuno può fare pagamenti con questa configurazione.
- **Face ID** (o codice) all'apertura e al ritorno; contenuto sfocato nel multitasking.
- **Rete**: solo HTTPS. Nessuna analitica, nessun servizio riceve dati personali tranne la banca tramite Enable Banking
  ([elenco](#servizi-esterni)).
- **Backup esportati** cifrati con password (vedi sopra).
- **Login delle banche**: nel browser di sistema; il ritorno è accettato solo con lo `state` del login in corso.
- **Repository pubblica** senza dati personali; commit con email anonima.

Cosa resta (scelte consapevoli): la chiave privata vive sul telefono (inevitabile per un'app senza server); chi ha il telefono
**sbloccato** in mano vede tutto, come per qualsiasi app.

---

## Servizi esterni

| Servizio | A cosa serve | Cosa riceve |
|---|---|---|
| Enable Banking (`api.enablebanking.com`) | saldi e movimenti delle banche | richieste firmate con la chiave; IP e versione dell'app (intestazioni PSU) |
| Pagina ponte su GitHub Pages | ritorno dal login della banca | `code` e `state` del login (inutili senza la chiave) |
| Yahoo Finance | simboli e prezzi degli strumenti | ISIN e simboli degli strumenti |
| Frankfurter (dati BCE) | cambi delle valute | codici delle valute e date |
| ISTAT (`esploradati.istat.it`) | indice dei prezzi NIC | nulla di personale |
| GitHub API | *Aggiorna app* | il commit installato |

---

## Cosa scade e quando

| Cosa | Durata | Avviso | Cosa fare |
|---|---|---|---|
| Firma dell'app (Apple ID gratuito) | 7 giorni | notifica 2 giorni prima, il giorno prima, la mattina | `installa.sh` con l'iPhone collegato |
| Collegamento con una banca | 180 giorni (alcune banche 90) | notifica 7 giorni prima, il giorno prima, il giorno stesso, poi ogni giorno | *Banche collegate* › scorri › **Rinnova** |
| Conti collegati nel Control Panel | non scadono | – | – |
| Backup esportato | – | promemoria di backup | esportalo ogni tanto |

---

## Problemi frequenti

| Sintomo | Causa e soluzione |
|---|---|
| L'app non si apre | firma scaduta: `installa.sh` |
| *Collega una banca* dice cosa manca | inserisci Application ID e chiave in *Banche collegate* |
| Errore **429 ASPSP_RATE_LIMIT_EXCEEDED** | troppe letture senza utente: con l'app aperta non succede (intestazioni PSU); riprova più tardi |
| Dopo il login, **nessun conto** da abbinare | quel conto non è in *Linked accounts* nel Control Panel: Link accounts e ricollega |
| Il login resta fermo su "reindirizzamento" | il Redirect URL dell'app non è la pagina ponte: in *Come si configura* deve essere `https://aizensosuke4099.github.io/bilancio/callback/` |
| Resti su Safari dopo aver confermato nell'app della banca | tocca **Apri Bilancio** sulla pagina "Torno a Bilancio…" |
| Il conto si chiama come l'intestatario | rinominalo in *Conti e contanti* (le versioni nuove usano il nome della banca) |
| Spese di una carta contate due volte | il pagamento della carta dal conto va segnato *Giroconto* (una volta, poi lo impara) |
| *Aggiorna app* dice "impossibile controllare" | offline, oppure l'app è stata installata da una versione che non è su GitHub: reinstalla con `installa.sh` |
| Il backup esportato non si apre | serve la password con cui l'hai esportato |

---

## Per lo sviluppo

### Struttura

```
Bilancio/
  App/            BilancioApp (avvio, controlli -verifica), RootView (schede, "Altro", link in arrivo)
  Modello/        Modelli.swift (tutti i @Model SwiftData), Tipi.swift (enum)
  Core/           Persistenza (database e protezione file), Contabilita (totali, saldi, valute), Classificatore,
                  Abbinamento (giroconti, scontrini, costo del cambio), DatiIniziali, Portafoglio, Formato, UI
  Features/
    Anno/ Mese/ Movimenti/ Consigli/     dashboard, elenchi, editor dei movimenti, consigli
    Scansione/                           scontrini: scanner, OCR, parser, Apple Intelligence, revisione
    Investimenti/                        strumenti, PAC, prezzi (Yahoo), cambi (BCE)
    Banche/                              Enable Banking (API, JWT, PSU), sincronizzazione, import estratti, parser
    Conti/ Ricorrenti/ Categorie/        conti e contanti, ricorrenti, categorie e budget
    Inflazione/                          calcoli, pagina, ISTAT
    Backup/                              backup, formato aperto, cifratura, schermata
    Impostazioni/                        Face ID, impostazioni, scadenza firma, Aggiorna app, dati demo
  Localizable.xcstrings                  traduzioni (chiave = testo italiano)
  DatiIniziali.xcstrings                 nomi iniziali di categorie e conti
Bilancio-Info.plist                      chiavi dell'Info.plist (schema bilancio://, file, commit installato…)
docs/callback/index.html                 pagina ponte (GitHub Pages)
installa.sh                              compila e installa sull'iPhone collegato
tasks/todo.md                            diario di lavoro, decisioni, insidie
```

Codice, nomi e commenti in **italiano**. Importi `Double` con segno (< 0 uscita), **sempre in euro** su `Movimento.importo`
(l'originale in valuta in `importoOriginale`/`valutaOriginale`). Enum salvati come stringhe `*Raw`.
Swift 5, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, target iOS 26. Nessuna dipendenza esterna.

### Compilare e provare

```bash
cd ~/Developer/bilancio
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Bilancio.xcodeproj -scheme Bilancio \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/dd ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
```

Argomenti di avvio (solo nelle build di sviluppo), con `xcrun simctl launch booted it.bilanciopersonale.app.k7x2 <argomenti>`:

| Argomento | Effetto |
|---|---|
| `-demo` | niente Face ID e niente richiesta notifiche; 12 mesi di dati di esempio se il database è vuoto |
| `-tab N` | apre la scheda N (0 Anno … 4 Altro) |
| `-verifica` | controlli automatici: giroconti, valute e costo del cambio, giro completo del backup, cifratura, inflazione, ISTAT |
| `-provaRipristino` | backup del database vero → copia cifrata → ripristino in sospeso (applicato al riavvio successivo) |
| `-AppleLanguages "(en)"` | interfaccia in inglese |

Controlli separati (dalla radice del progetto; il comando esatto è in testa a ogni file):
`Features/Banche/ParserEstratto.swift` (estratti conto), `Features/Banche/EnableBanking.swift` (firma JWT),
`Features/Ricorrenti/GeneratoreRicorrenze.swift`, `Features/Scansione/ParserScontrino.swift`,
`Features/Consigli/CalcoliConsigli.swift`, `Features/Investimenti/CalcoliInvestimenti.swift`.

### Insidie note

- Il simulatore impiega 30–60 s a mostrare l'app; nel frattempo iOS mostra l'**ultima istantanea** (anche in un'altra lingua).
  Aspetta prima degli screenshot. Un avviso di sistema mai chiuso resta a schermo anche dopo la disinstallazione: riavvia il simulatore.
- `xcodebuild` **non aggiorna** il catalogo delle traduzioni. Le chiavi estratte dal compilatore sono nei file `*.stringsdata` in
  `build/dd/…/Objects-normal/arm64/`: confrontale con `Localizable.xcstrings` e aggiungi le mancanti con la traduzione inglese.
  Riscrivi il file con `json.dumps(…, ensure_ascii=False, indent=2, separators=(',', ': '))` più a capo finale, senza riordinare le chiavi.
- Non modificare `Bilancio-Info.plist` con PlistBuddy: toglie i commenti e riordina il file.
- Il simulatore non applica la protezione dei file di iOS: la cifratura "completa" si vede solo sull'iPhone vero.
- Con l'Apple ID gratuito niente Associated Domains (Universal Links), niente CloudKit: per questo la pagina ponte e i backup su File.

### Pubblicare

`git push` sul ramo `main`. La pagina ponte si pubblica da sola (GitHub Pages, cartella `docs`). Prima di ogni commit controlla che
non ci siano dati personali (nomi dei conti, IBAN, chiavi, email): la repository è pubblica.
