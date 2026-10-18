# Design: subcomandi espliciti di `docker-dev`

## Stato e perimetro

Documento di progettazione per il branch `subcommands`. Specifica il comportamento atteso dei subcomandi `build` e `run`, il dispatch, la risoluzione dei progetti, i metadati necessari e il piano di verifica. Non modifica la CR rev. 2, che potrà essere integrata successivamente.

Questo documento descrive il design approvato per i requisiti concordati. Il parsing, gli helper di risoluzione progetto/tag e i flussi operativi `build`/`run` sono implementati e testati con Docker simulato. La guida utente definitiva e la verifica su Docker reale restano da completare.

### Decisioni approvate

- Mantenere temporaneamente il dispatch legacy senza subcomando e preservarne il comportamento. L'avviso di deprecazione è ancora da implementare.
- Accettare target assoluti per `build` e `run`, rispettando il tag del progetto.
- Usare il tag testuale `.docker-dev/project-tag` con `schema_version` e `model`; leggere anche i tag legacy con `lang`.
- `run --target` relativo cerca esclusivamente sotto `$PWD`; se il target non esiste lì, fallisce senza ricerca globale.

## 1. Specifica CLI e compatibilità

### Comandi proposti

```text
docker-dev build [--model <model>] [--target <target>] [-x] [-y]
docker-dev run [--target <target>]
```

Le forme `--model=<model>` e `--target=<target>` sono accettate insieme alle forme separate. `--model` è facoltativo per `build`; `--lang` è mantenuto come alias. Se omesso, il model viene dedotto dai metadati del progetto o dell'istanza oppure dalla root legacy gestita. Se non è deducibile, `build` fallisce esplicitamente. Non è previsto per `run`, che ricava il model dai metadati del progetto o dell'istanza.

| Opzione | Comando | Comportamento |
|---|---|---|
| `--model <model>` | `build` | Modello esplicito facoltativo; deve essere gestito e coerente con i tag applicabili. Se omesso, viene dedotto dal progetto/istanza o dalla root legacy. |
| `--target <target>` | entrambi | Identifica il progetto. Il target relativo non contiene il modello. |
| `-x` | `build` | Dopo il completamento positivo di setup e build, esegue anche il run. Senza `-x`, non avvia il container. |
| `-y` | `build` | Sopprime la richiesta di conferma; non disabilita validazione o controlli. |

La conferma di `build` deve avvenire una sola volta, prima degli effetti collaterali, e coprire l'intera operazione richiesta. Con `-x`, la conferma copre quindi setup, build e successivo run. `run` mantiene la conferma del flusso attuale; non è previsto `-y` per `run` in questa specifica.

### Sintassi precedente

La sintassi senza subcomando avvia oggi la pipeline completa, che comprende preparazione, build condizionale e run. Non va reinterpretata come il nuovo `run`, perché `run` non effettua build implicite.

Mantenere temporaneamente un dispatch legacy per le invocazioni senza subcomando, preservandone il comportamento e il parsing attuali. La vecchia forma del target, che include il linguaggio (per esempio `Python/foo`), resta valida solo nel percorso legacy. L'avviso di deprecazione è auspicabile ma non è presente nel codice corrente; la rimozione del percorso legacy richiede una decisione successiva e documentata.

Il parser deve distinguere il subcomando iniziale dalle opzioni e inoltrare gli argomenti del container solo quando previsto dal contratto del comando; non deve reinterpretare opzioni dopo un eventuale delimitatore `--`.

## 2. Dispatch e risoluzione target

### Dispatch

Il main deve selezionare l'operazione prima di iniziare il flusso di progetto:

1. Se il primo argomento è `build`, applicare il parser e il flusso `build`.
2. Se il primo argomento è `run`, applicare il parser e il flusso `run`.
3. Altrimenti, applicare il parser legacy, mantenendo la compatibilità transitoria.

Un'opzione sconosciuta, un argomento mancante o un'opzione non ammessa per il subcomando selezionato deve produrre un errore esplicito, l'uso pertinente e un codice di uscita non zero.

### Risoluzione del progetto

Il target relativo non include il modello: `foo/bar` è un percorso interno al modello, non `Python/foo/bar`.

Nei comandi espliciti, `BASE` nella formula `$BASE/$lang/$target` indica la radice effettiva dei progetti. Per mantenere la collocazione attuale con l'ambiente predefinito, questa corrisponde a `$ORG/REP/DEV`; il `BASE` interno legacy (`$ORG/REP`) viene esteso con l'ambiente prima di individuare il progetto.

#### `build`

- `--model` è facoltativo; `--lang` resta alias. Un valore esplicito deve essere gestito e coerente con i tag applicabili.
- Senza `--target`, il progetto è la directory corrente (`$PWD`).
- Con un target relativo, il progetto è `$BASE/$model/$target`. Per esempio, con `--model Python --target foo/bar`, il percorso è `$BASE/Python/foo/bar`.
- Con un'istanza riconosciuta, il target relativo viene creato sotto la root dell'istanza; senza un'istanza, un `--model` esplicito mantiene la risoluzione canonica `$BASE/$model/$target`.
- Accettare anche un target assoluto se indica una directory progetto esistente e accessibile. Se il target selezionato è `$BASE` o una sua discendente, la ricerca dell'instance tag parte dalla directory assoluta selezionata e normalizzata e risale i parent fino a `$BASE`. Se è esterno a `$BASE`, non cercare instance tag nei parent né applicare l'inferenza legacy: il model può provenire soltanto da `--model` esplicito e gestito o dal project tag valido nella directory selezionata. Se nessuna fonte è disponibile, `build` fallisce.
- Il model effettivo deriva da `--model`, se esplicito, oppure dai metadati applicabili e dalla convenzione legacy. Tag malformati o in conflitto con il model effettivo causano errore prima degli effetti collaterali.

#### `run`

- Senza `--target`, il progetto è `$PWD`; il modello è determinato dal tag file valido nella directory.
- Con un target assoluto, la directory indicata è il progetto esatto e il modello è letto dal suo tag file.
- Con un target relativo, cercare esclusivamente `$PWD/<target>`. Se la directory non esiste, terminare subito con un errore che indichi il percorso cercato; non cercare sotto `$BASE` o nelle altre root di modelli.
- Se `$PWD/<target>` esiste, usarla anche se esistono progetti omonimi in altre root. Il modello si legge dal tag valido; per mantenere utilizzabili progetti legacy senza tag, se la directory corrente è dentro una root modello gestita sotto `$BASE`, inferire il modello da tale root. Se il tag è presente ma non valido o contraddice la root del modello, fallire esplicitamente.
- Un progetto esterno alla root di un modello gestito deve avere un tag valido. Un target che deve selezionare una directory specifica fuori da `$PWD` va passato come percorso assoluto; `run` legge da quella directory il tag e il modello.

Il target relativo deve essere convalidato per impedire che componenti come `..` facciano uscire da `$PWD`. I percorsi devono essere normalizzati prima di controllare e validare la directory.

### Tag file del progetto

Il tag consente a `run` di ricavare il modello, in particolare quando il progetto è `$PWD`.

**Formato approvato per la prima versione:**

```text
<project>/.docker-dev/project-tag
```

Contenuto testuale, UTF-8/ASCII, con campi obbligatori e un valore per riga:

```text
schema_version=1
model=Python
```

La directory `.docker-dev` è riservata ai metadati locali di `docker-dev`; il tag non deve contenere credenziali o valori dipendenti dalla macchina. Un parser semplice e stretto evita di introdurre un runtime YAML solo per leggere questi metadati.

Regole di scrittura e validazione:

- Scrivere o aggiornare il tag solo dopo il successo di setup e build.
- Pubblicare il nuovo file atomicamente (file temporaneo nella stessa directory e rename); un errore non deve lasciare un tag parziale.
- Con `build -x`, il tag registra il successo della build anche se il successivo run fallisce.
- Accettare solo una versione di schema supportata, un solo campo `model` e un modello gestito. Per compatibilità, è leggibile anche un singolo campo legacy `lang`; i due campi insieme sono invalidi. Campi obbligatori mancanti, duplicati, valori vuoti o schema sconosciuto rendono il tag non valido.
- Un project tag esistente deve essere valido e coerente con il model effettivo; non può essere sovrascritto se malformato o in conflitto. Se manca, viene scritto atomicamente solo dopo il successo di setup e build.
- Per un target sotto una root legacy `$BASE/<model>/...`, il model dedotto dalla root deve essere coerente con il tag del progetto. Sotto un'istanza taggata, project tag e instance tag devono riportare lo stesso model.
- Un tag mancante o non valido non deve mai essere trattato come un successo-shaped fallback né deve provocare una build automatica da `run`.

## 3. Flussi e test

### Flussi attesi

```text
build:
  valida CLI e modello
  risolve/crea il progetto secondo le regole approvate
  chiede conferma, salvo -y
  applica template e setup necessari
  esegue gli step di build della lingua
  scrive atomicamente il tag con il modello
  se -x: esegue il run solo dopo il successo della build

run:
  valida CLI e risolve il progetto
  carica e valida il tag
  verifica i prerequisiti di run, inclusa la disponibilità dell'immagine
  chiede conferma
  esegue gli step setup necessari al run e poi il run; non esegue build
```

`run` deve fallire con un messaggio operativo se l'immagine necessaria non è disponibile; non deve avviare implicitamente `build`. Il messaggio può suggerire il comando `docker-dev build --model <model> --target <target>`.

Gli script setup sono eseguiti anche da `run` perché inizializzano i volumi necessari al container e sono prerequisiti separabili dalla build; non sono rieseguiti tra build e run nella singola operazione `build -x`. Il run non richiama mai script di build. La pipeline numerata corrente esegue gli script in sequenza; il dispatcher esplicito seleziona le fasi per nome e garantisce l'ordine setup → build → run, mantenendo l'ordinamento numerico all'interno di ogni fase.

### Verifiche richieste

| Area | Casi minimi |
|---|---|
| Parsing e deduzione | `build` accetta `--model` omesso se deducibile da project tag, instance tag o root legacy; fallisce se non deducibile; `--model` esplicito deve essere gestito e coerente; `run` rifiuta `--model`; opzioni mancanti/sconosciute; alias `--lang`; `-x` solo per build; `-y` salta solo la conferma di build. |
| Compatibilità | L'invocazione legacy non cambia comportamento durante la transizione; l'assenza di subcomando non viene confusa con `run`. |
| Build e tag | Tag creato solo dopo build riuscita; nessun tag parziale se fallisce; tag aggiornato atomicamente; `-x` non esegue run se setup/build fallisce. |
| Default target e model implicito | `build` e `run` senza target usano `$PWD`; `build` e `run` deducono il model dai tag applicabili o dalla root legacy; senza una fonte valida falliscono. |
| Target relativo | `build --model Python --target foo/bar` risolve in `$BASE/Python/foo/bar`; `run --target foo/bar` risolve esclusivamente `$PWD/foo/bar` e fallisce senza ricerca se manca. |
| Target assoluto | Directory esistente e accessibile; dentro `$BASE`, la ricerca instance tag parte dal target selezionato e normalizzato; fuori da `$BASE`, nessuna scansione dei parent o inferenza legacy, solo `--model` esplicito o project tag nella directory; mismatch o fonti mancanti producono errore. |
| Tag | Tag mancante, schema non supportato, modello sconosciuto, campo duplicato/mancante/vuoto, mismatch tra project tag, instance tag e `--model`; progetto legacy locale senza tag sotto una root modello valida; lettura del vecchio campo `lang`. |
| Target run assente | Il target manca sotto `$PWD` ma esiste sotto un'altra root modello: errore immediato, nessuna ricerca globale e nessuna invocazione Docker. |
| No build implicita | `run` con immagine assente fallisce e suggerisce `build`, senza invocare gli script di build o mutare lo stato. |
| Ordine | Verificare tramite stub/mocking che `build` esegua setup prima di build e che il run eventuale venga dopo tag/build. |

Non risulta definito un framework di test nel repository al momento della stesura. Prima di implementare i test, scegliere un approccio Bash leggero già disponibile nell'ambiente o introdurre test shell senza dipendenze runtime aggiuntive. Docker non deve essere necessario per i test unitari di parsing e dispatch; i test d'integrazione possono usare stub dei comandi Docker.

## 4. Documentazione d'uso

La documentazione per gli utenti va aggiornata dopo che parsing, flussi e test sono stabili, in modo da descrivere il comportamento verificato e non soltanto quello progettato.

Gli esempi minimi da documentare sono:

```bash
# Setup e build del progetto nel percorso predefinito $BASE/Python/my-app
docker-dev build --model Python --target my-app

# Build nel progetto corrente
docker-dev build --model Python

# Build e avvio
docker-dev build --model Python --target my-app -x

# Build senza prompt
docker-dev build --model Python --target my-app -y

# Run del progetto corrente; il modello proviene dal tag
docker-dev run

# Run di un target relativo sotto la directory corrente
docker-dev run --target my-app
```

La guida d'uso dovrà inoltre spiegare:

- il formato e la posizione del tag, quando viene creato e come diagnosticare un tag non valido;
- che `run` non costruisce l'immagine e non scrive il tag;
- come vengono risolti target assenti, relativi e assoluti, precisando che un target relativo di `run` non viene cercato fuori da `$PWD`;
- la compatibilità transitoria della sintassi legacy; l'avviso di deprecazione non è ancora implementato;
- gli errori CLI con esempi d'uso corretti e codici di uscita significativi.

## Sequenza di lavoro suggerita

1. Dispatch e parsing isolabili, con test del contratto CLI (implementati).
2. Risoluzione target/tag e test di errore, inclusa la priorità del target locale (implementati).
3. Flussi build/run, con verifica che `run` non costruisca e test dell'ordine setup/build/run (implementati con Docker simulato).
4. Aggiornare la guida utente sui comportamenti effettivamente collaudati (documentato in [docker-dev-usage.md](./docker-dev-usage.md)); resta da completare una verifica con Docker reale.

I commit dovrebbero seguire unità coerenti e verificabili, non singole micro-modifiche: dispatch/CLI, risoluzione e tag, flussi/test, documentazione finale. La CR rev. 2 resta fuori perimetro fino alla successiva integrazione concordata.
