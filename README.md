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
| Farla usare a un'altra persona | le serve un identificativo dell'app suo e un suo account Enable Banking ([dettagli](#se-la-vuole-usare-unaltra-persona)) |

---

## Cosa fa l'app

Cinque schede in basso:

- **Anno** – entrate, spese, risparmio (con il tasso sulle entrate), investito, patrimonio netto; grafico mese per mese con la linea
  del risparmio; spese per categoria; patrimonio nel tempo; tabella dei mesi; consigli dell'anno.
- **Mese** – scelta del mese; avviso "N movimenti da confermare"; spesa accumulata giorno per giorno confrontata col mese prima;
  categorie con budget; ultimi movimenti; consigli del mese; controllo di fine mese.
- **Scansiona** – fotografi uno scontrino (anche lungo, in più foto): l'app legge negozio, data, righe e totale, propone categoria e
  nome del prodotto, tu controlli e confermi. Se il pagamento è già arrivato dalla banca, lo collega invece di contarlo due volte;
  se non è ancora arrivato, la spesa pagata con carta resta *da confermare* finché non arriva l'addebito.
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

- **Movimenti "da confermare"** (banner blu in *Mese*): quelli arrivati dalla banca aspettano la tua conferma, e così gli
  **scontrini pagati con carta o conto** finché non arriva l'addebito (quelli in contanti nascono confermati). Quando scontrino e
  addebito combaciano diventano un solo movimento, confermato. Ogni correzione di tipo, categoria o titolo viene ricordata e
  applicata da sola la volta dopo.
- **Controllo di fine mese** (in fondo a *Mese*): movimenti da confermare; scontrini senza pagamento bancario, con «Era in
  contanti», «Collega a un pagamento» e ✓ per confermare; pagamenti senza scontrino; saldo dei contanti.
- **Tipi di movimento**: *spesa*, *entrata*, *giroconto* (spostamento tra conti tuoi: non conta nei totali), *investimento*.
- **Face ID** all'apertura e al ritorno nell'app; nel multitasking il contenuto è sfocato.
- **Notifiche**: firma dell'app in scadenza, collegamenti con le banche in scadenza, promemoria di backup.
- **Lingua**: segue quella dell'iPhone (italiano o inglese; con le altre lingue resta in italiano). Per sceglierla solo per
  Bilancio: *Impostazioni › Lingua dell'app* apre le impostazioni di iOS, dove la voce *Lingua* compare se l'iPhone ha almeno due
  lingue preferite. Le categorie iniziali nascono nella lingua del telefono.

---

## Dove stanno i dati e i segreti

| Cosa | Dove | Note |
|---|---|---|
| Database (movimenti, conti, scontrini, investimenti…) | iPhone, cartella privata dell'app (SwiftData) | cifrato da iOS, illeggibile a telefono bloccato |
| Foto degli scontrini | file separati nella cartella del database | stessa protezione del database |
| Backup locali | iPhone, dentro l'app (*Altro › Backup*) | uno a settimana, si tengono gli ultimi 4; non compaiono nell'app File ([Sicurezza](#sicurezza)) |
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

### Se la vuole usare un'altra persona

Il progetto è pubblico e non contiene dati di nessuno: chi lo scarica parte da un'app vuota, e i suoi dati restano sul suo telefono.

1. Le servono le stesse cose di [Cosa serve](#cosa-serve): un Mac con Xcode, il suo Apple ID in Xcode, l'iPhone con la Modalità
   sviluppatore, il codice scaricato con `git clone`.
2. **Sceglie un identificativo dell'app suo**, una volta sola: quello del progetto è già registrato sull'Apple ID dell'autore, e
   Apple non lo concede a un altro. Il file resta sul suo Mac (git lo ignora).

   ```bash
   echo it.iltuonome.bilancio > ~/Developer/bilancio/.identificativo
   ```

3. Lancia `installa.sh`, come sopra.
4. Per collegare le banche crea un **suo** account Enable Banking con la sua chiave ([Banche collegate](#banche-collegate-enable-banking)).
   Come indirizzo di ritorno può registrare la pagina ponte di questo progetto, che rimanda soltanto all'app, oppure quella di una
   sua copia del repository.

Con `installa.sh` riceve anche gli aggiornamenti pubblicati qui.

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
- Un movimento della banca che **elimini** non ricompare alle sincronizzazioni successive (l'elenco degli eliminati viaggia anche
  nel backup). Una transazione già importata da un estratto conto non si duplica quando arriva anche dalla banca collegata.
- Scollegando una banca, il saldo del conto riparte dall'ultimo letto e da lì segue i movimenti.
- Con l'app aperta l'app invia le **intestazioni PSU** (indirizzo IP della rete del telefono, versione dell'app e di iOS): la banca
  sa che sei presente e non applica il limite di ~4 letture al giorno previsto per gli accessi senza utente.

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

Il lettore riconosce da solo: separatore (`;` `,` tab); codifiche comuni (UTF-8, Windows-1252, UTF-16 di Excel); nomi delle colonne
in italiano, inglese e tedesco (anche *Belastung/Gutschrift* delle banche svizzere); una colonna con segno oppure due colonne
Dare/Avere; importi con l'apostrofo per le migliaia o con la valuta (`CHF 45.20`); date numeriche o col mese a lettere. Quando ci
sono sia l'importo nella valuta dell'acquisto sia quello in euro, sceglie quello in euro. Le righe di saldo iniziale e finale non
diventano movimenti. **Se qualche riga ha una data o un importo che non riesce a leggere, la schermata *Colonne* lo dice in
arancione**: controlla il formato della data prima di continuare.

Negli estratti delle **carte di credito** gli acquisti sono scritti in positivo: quando quasi tutti gli importi lo sono, l'app
accende da sola «Inverti il segno» e lo spiega nella schermata *Colonne*. Guarda la prova: le spese devono essere nere, le
entrate verdi.

Nell'anteprima, un movimento che ha già la sua metà su un altro conto (il saldo mensile della carta pagato dal conto corrente, una
ricarica) viene proposto come **giroconto**. Su un conto in valuta gli importi restano nella valuta del conto.

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
- Scontrini, ricorrenze e movimenti inseriti a mano su un conto in valuta sono **nella valuta del conto**; scontrino e addebito si
  riconoscono confrontando quell'importo, non il controvalore in euro.

---

## Come vengono classificati i movimenti

In ordine:

1. **Regole imparate** dalle tue correzioni (stessa descrizione bancaria → stesso tipo, categoria e titolo).
2. **Parole chiave** (in `Core/Classificatore.swift`): supermercati, bollette, trasporti, abbonamenti…, giroconti, investimenti,
   stipendio, commissioni bancarie, tasse.
3. Altrimenti: entrata in "Altre entrate" o spesa in "Altro".

Altri automatismi:

- **Giroconti tra conti tuoi**: un'uscita su un conto e un'entrata dello stesso importo su un altro conto entro 3 giorni diventano
  entrambe giroconto (non contano nei totali). Vale solo per i movimenti che nessuna parola chiave o regola ha riconosciuto: uno
  stipendio e un affitto dello stesso importo restano quello che sono. Se correggi a mano una metà in giroconto, cambia anche l'altra.
- **Pagamento della carta di credito** dal conto corrente: se la carta è tracciata nell'app, è un giroconto. La prima volta segnalo
  tu come *Giroconto*: l'app lo impara.
- **Prelievi**: diventano un giroconto verso il conto *Contanti*.
- **Scontrini**: uno scontrino e l'addebito dello stesso importo sullo stesso conto diventano un solo movimento, così la spesa non
  conta due volte. L'addebito può arrivare fino a **10 giorni dopo** lo scontrino (carte di credito, fine settimana), anche nel
  mese successivo: la spesa resta nel mese dello scontrino. Se non si uniscono da soli (importo diverso per una mancia o una valuta
  estera, addebito ancora più tardivo), nel *Controllo di fine mese* **Collega a un pagamento** propone i pagamenti dei 45 giorni
  successivi con importo uguale o vicino: resta l'importo dell'addebito.
- **Commissioni**: canoni, spese dei bonifici, fee, spread, interessi passivi vanno in *Commissioni bancarie*; bolli, F24, imposte in
  *Tasse e imposte*.

---

## Scontrini e inflazione

- **Scansione**: ritaglio automatico (VisionKit), testo letto sul telefono (Vision). Prezzi, quantità e totali li leggono regole
  scritte apposta; **Apple Intelligence** (sul telefono, offline) propone solo categoria e nome normalizzato del prodotto, perché
  inventava i prezzi. Controlli sempre prima di confermare; le correzioni vengono ricordate.
- **Prodotti**: righe scritte in modo diverso (anche in negozi diversi) si uniscono in un unico prodotto (*Inflazione › Gestisci
  prodotti › Unisci*). Il formato (es. 500 g) permette il prezzo al kg o al litro, e scopre le "sgrammature".
- **Sconti**: una riga di sconto viene tolta dal prodotto a cui si riferisce (di solito la riga sopra; in un menù, il menù e non
  l'aggiunta da pochi centesimi). Il prezzo unitario resta quello di listino, il totale della riga è quello pagato e la riga mostra
  «sconto X». Le righe a 0,00 € non vengono inserite.
- **Totale**: se l'app non riesce a leggerlo propone la somma delle righe e lo scrive in arancione. Controllalo: se una riga è
  sfuggita, la somma è sbagliata.
- **Prezzi anomali**: un prezzo lontanissimo dagli altri acquisti dello stesso prodotto (di solito un errore di lettura) non entra
  nei calcoli; il dettaglio del prodotto lo segnala, con il collegamento allo scontrino da correggere.
- **Inflazione**: per ogni prodotto comprato in almeno due giorni diversi si confronta il prezzo; la tua inflazione è la media pesata
  sulla spesa degli ultimi 12 mesi. Il **paniere** concatena le variazioni mese per mese. Il dato **ISTAT** (indice NIC) si scarica
  da solo una volta al giorno e appare accanto. Tocca un punto del grafico o una riga degli acquisti per aprire lo **scontrino**.

---

## Investimenti

- **Strumenti** dall'ISIN: l'app cerca su Yahoo Finance le borse dove è quotato e ti fa scegliere il **listino** (quelli in euro per
  primi). Se conosci il **ticker** di Yahoo puoi scriverlo a mano: l'app mostra nome, valuta e prezzo trovati, per controllare che
  sia lo strumento giusto. Per gli ETF c'è il collegamento alla scheda su justETF. I prezzi si aggiornano al massimo ogni 6 ore, o
  tirando giù la pagina; un prezzo in una valuta diversa da quella dello strumento viene scartato.
- **Guadagno e rendimento**: il guadagno è il valore di oggi, più dividendi e cedole, meno il capitale versato netto. Il rendimento
  è il guadagno su tutto ciò che hai investito, quindi resta sensato anche dopo una vendita.
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
| `bilancio.json` | tutti i dati (JSON UTF-8): conti, movimenti, categorie, ricorrenti, scontrini e righe, prodotti, regole imparate, strumenti, operazioni, valutazioni, PAC, fotografie mensili del patrimonio, collegamenti, formati di import, identificativi dei movimenti bancari eliminati |
| `foto/` | le foto degli scontrini |
| `movimenti.csv` | i movimenti per Excel / Fogli Google |
| `LEGGIMI.txt` | descrizione completa del formato (italiano e inglese) |

Non contiene la chiave privata né l'Application ID. Un backup compare nell'elenco solo quando è stato scritto per intero.

**Esportato fuori dall'iPhone** (*Backup › Crea backup e salva in File…*) il backup è **cifrato con la tua password**: ogni file
diventa `*.enc` (AES-256-GCM; chiave da PBKDF2-HMAC-SHA256 con 600.000 iterazioni e sale casuale; parametri in `cifratura.json`).
`LEGGIMI.txt` resta leggibile e spiega come decifrare. **Senza password il backup non si apre**: tienila nel gestore di password.
L'esportazione CSV è invece in chiaro.

### Ripristino

*Backup* › scorri su un backup locale › **Ripristina**, oppure **Ripristina da una cartella di backup…** (per quelli esportati: chiede
la password). Poi **chiudi l'app dal multitasking e riaprila**: i dati attuali vengono sostituiti. Prima, l'app salva i dati attuali come
un normale backup nell'elenco: se hai ripristinato quello sbagliato, torni indietro da lì. Se nel backup manca qualche foto i dati
si ripristinano lo stesso, e l'app ti dice quante ne mancano. Si ripristinano anche i backup del vecchio formato (copia del database).

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
- **Segreti**: chiave privata e Application ID nel Portachiavi, accessibili solo su quel telefono e solo quando è sbloccato
  (`WhenUnlockedThisDeviceOnly`), mai su iCloud. Copie `.pem` lasciate nella cartella dell'app vengono cancellate; gli appunti
  si svuotano dopo aver incollato la chiave.
- **Accesso alle banche in sola lettura** (Account Information): nessuno può fare pagamenti con questa configurazione.
- **Face ID** (o codice) all'apertura e al ritorno; contenuto sfocato nel multitasking.
- **Rete**: solo HTTPS. Nessuna analitica, nessun servizio riceve dati personali tranne la banca tramite Enable Banking
  ([elenco](#servizi-esterni)). Le risposte della banca e dei prezzi non vengono conservate nella cache su disco.
- **Backup esportati** cifrati con password (vedi sopra).
- **Login delle banche**: nel browser di sistema; il ritorno è accettato solo con lo `state` del login in corso.
- **Repository pubblica** senza dati personali; commit con email anonima.

Cosa resta (scelte consapevoli):

- la chiave privata vive sul telefono (inevitabile per un'app senza server);
- i **backup locali** sono in chiaro, ma stanno nella cartella dell'app, protetti come il database: non compaiono nell'app File
  e si aprono solo dall'app, dietro Face ID. Se l'app non si apre (firma scaduta) restano lì: basta rilanciare `installa.sh`.
  Per averne una copia fuori dal telefono vanno esportati, e l'esportazione li cifra;
- se il **backup iCloud dell'iPhone** è attivo, database e backup locali ne fanno parte, come per ogni app;
- le notifiche di scadenza mostrano il nome della banca, anche sulla schermata di blocco se le anteprime sono attive.

---

## Servizi esterni

| Servizio | A cosa serve | Cosa riceve |
|---|---|---|
| Enable Banking (`api.enablebanking.com`) | saldi e movimenti delle banche; loghi nell'elenco delle banche | richieste firmate con la chiave; indirizzo IP della rete del telefono, versione dell'app e di iOS (intestazioni PSU) |
| Pagina ponte su GitHub Pages | ritorno dal login della banca | `code` e `state` del login (inutili senza la chiave) |
| Yahoo Finance | simboli e prezzi degli strumenti | ISIN, nomi e simboli degli strumenti |
| justETF | scheda dell'ETF, solo se tocchi *Controlla su justETF* | l'ISIN, nel browser |
| Frankfurter (dati BCE) | cambi delle valute | codici delle valute e date |
| ISTAT (`esploradati.istat.it`) | indice dei prezzi NIC | nulla di personale |
| GitHub API | *Aggiorna app* | il commit installato |

---

## Cosa scade e quando

| Cosa | Durata | Avviso | Cosa fare |
|---|---|---|---|
| Firma dell'app (Apple ID gratuito) | 7 giorni | notifica 2 giorni prima, il giorno prima, la mattina | `installa.sh` con l'iPhone collegato |
| Collegamento con una banca | 180 giorni (alcune banche 90) | notifica 7 giorni prima, il giorno prima, il giorno stesso; poi un promemoria la mattina dopo, rinnovato a ogni apertura dell'app | *Banche collegate* › scorri › **Rinnova** |
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
    Archivio/                            archivio degli scontrini per negozio
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

Argomenti di avvio (nelle build di sviluppo; in quella installata sull'iPhone vale solo `-tab`), con `xcrun simctl launch booted it.bilanciopersonale.app.k7x2 <argomenti>`:

| Argomento | Effetto |
|---|---|
| `-demo` | niente Face ID e niente richiesta notifiche; 12 mesi di dati di esempio se il database è vuoto |
| `-tab N` | apre la scheda N (0 Anno … 4 Altro) |
| `-verifica` | controlli automatici: abbinamenti e giroconti, valute e costo del cambio, investimenti, ricorrenze, giro completo del backup, cifratura, inflazione, ISTAT |
| `-provaRipristino` | backup del database vero → copia cifrata → ripristino in sospeso (applicato al riavvio successivo) |
| `-AppleLanguages "(en)"` | interfaccia in inglese |

Controlli separati (dalla radice del progetto; il comando esatto è in testa a ogni file):
`Features/Banche/ParserEstratto.swift` (estratti conto), `Features/Banche/EnableBanking.swift` (firma JWT),
`Features/Scansione/ParserScontrino.swift`,
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
