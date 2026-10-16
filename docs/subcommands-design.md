# Design: subcomandi espliciti di `docker-dev`

## Stato e perimetro

Documento di progettazione per il branch `subcommands`. Specifica il comportamento atteso dei subcomandi `build` e `run`, il dispatch, la risoluzione dei progetti, i metadati necessari e il piano di verifica. Non modifica la CR rev. 2, che potrà essere integrata successivamente.

Questo documento descrive il design approvato per i requisiti concordati. Il parsing e il riconoscimento iniziale dei subcomandi sono implementati; il dispatch operativo, la risoluzione dei target, i tag e i flussi build/run sono ancora da implementare. Le decisioni ancora raccomandate, ma non approvate, sono indicate come tali.

### Decisioni approvate

- Mantenere temporaneamente il dispatch legacy senza subcomando, con comportamento attuale e avviso.
- Accettare target assoluti per `build` e `run`, rispettando il tag del progetto.
- Usare il tag testuale `.docker-dev/project-tag` con `schema_version` e `lang`.
- Se `run --target` relativo corrisponde a più progetti, fallire indicando tutte le alternative. Per selezionarne una, ripetere il comando con il percorso assoluto del progetto scelto.

## 1. Specifica CLI e compatibilità

### Comandi proposti

```text
docker-dev build --lang <lang> [--target <target>] [-x] [-y]
docker-dev run [--target <target>]
```

Le forme `--lang=<lang>` e `--target=<target>` possono essere accettate insieme alle forme separate, se il parser le supporta senza ambiguità. `--lang` è obbligatorio per `build`; non è previsto per `run`, che ricava il linguaggio dai metadati del progetto.

| Opzione | Comando | Comportamento |
|---|---|---|
| `--lang <lang>` | `build` | Linguaggio obbligatorio; deve corrispondere a un tipo gestito in `langs/`. |
| `--target <target>` | entrambi | Identifica il progetto. Il target relativo non contiene il linguaggio. |
| `-x` | `build` | Dopo il completamento positivo di setup e build, esegue anche il run. Senza `-x`, non avvia il container. |
| `-y` | `build` | Sopprime la richiesta di conferma; non disabilita validazione o controlli. |

La conferma di `build` deve avvenire una sola volta, prima degli effetti collaterali, e coprire l'intera operazione richiesta. Con `-x`, la conferma copre quindi setup, build e successivo run. `run` mantiene la conferma del flusso attuale; non è previsto `-y` per `run` in questa specifica.

### Sintassi precedente

La sintassi senza subcomando avvia oggi la pipeline completa, che comprende preparazione, build condizionale e run. Non va reinterpretata come il nuovo `run`, perché `run` non effettua build implicite.

Mantenere temporaneamente un dispatch legacy per le invocazioni senza subcomando, preservandone il comportamento e il parsing attuali, con un avviso che suggerisca il comando esplicito. La vecchia forma del target, che include il linguaggio (per esempio `Python/foo`), resta valida solo nel percorso legacy. La rimozione del percorso legacy richiede una decisione successiva e documentata.

Il parser deve distinguere il subcomando iniziale dalle opzioni e inoltrare gli argomenti del container solo quando previsto dal contratto del comando; non deve reinterpretare opzioni dopo un eventuale delimitatore `--`.

## 2. Dispatch e risoluzione target

### Dispatch

Il main deve selezionare l'operazione prima di iniziare il flusso di progetto:

1. Se il primo argomento è `build`, applicare il parser e il flusso `build`.
2. Se il primo argomento è `run`, applicare il parser e il flusso `run`.
3. Altrimenti, applicare il parser legacy, mantenendo la compatibilità transitoria.

Un'opzione sconosciuta, un argomento mancante o un'opzione non ammessa per il subcomando selezionato deve produrre un errore esplicito, l'uso pertinente e un codice di uscita non zero.

### Risoluzione del progetto

Il target relativo non include il linguaggio: `foo/bar` è un percorso interno al linguaggio, non `Python/foo/bar`.

#### `build`

- `--lang` è obbligatorio.
- Senza `--target`, il progetto è la directory corrente (`$PWD`).
- Con un target relativo, il progetto è `$BASE/$lang/$target`. Per esempio, con `--lang Python --target foo/bar`, il percorso è `$BASE/Python/foo/bar`.
- Accettare anche un target assoluto se indica una directory progetto esistente e accessibile, in coerenza con il comportamento storico. In questo caso `--lang` resta obbligatorio e il tag scritto deve contenere quel linguaggio.

#### `run`

- Senza `--target`, il progetto è `$PWD`; il linguaggio è determinato dal tag file valido nella directory.
- Con un target assoluto, la directory indicata è il progetto esatto e il linguaggio è letto dal suo tag file.
- Con un target relativo, cercare `$BASE/<lang>/<target>` per ogni linguaggio gestito. Non scegliere arbitrariamente se esistono più progetti validi: terminare con errore e stampare tutti i percorsi candidati. Non avviare una selezione interattiva.
- Per selezionare un candidato, ripetere il comando usando il suo percorso assoluto come target. Per esempio, se la ricerca segnala:

  ```text
  /home/alice/REP/DEV/Python/foo/bar
  /home/alice/REP/DEV/Perl/foo/bar
  ```

  l'utente sceglie il progetto Python ripetendo:

  ```bash
  docker-dev run --target /home/alice/REP/DEV/Python/foo/bar
  ```

  Il target assoluto identifica una sola directory; `run` legge da quella directory il tag e il linguaggio. Non è necessario aggiungere `--lang` a `run`.
- Se non si trova alcuna directory candidata, terminare con errore indicando il target e i linguaggi/percorso base cercati.
- Se una directory candidata esiste ma ha tag mancante o non valido, non avviare il run; riportare il percorso e il motivo. La diagnostica deve distinguere questi casi dall'assenza del progetto.

Il target deve essere convalidato per impedire che componenti come `..` facciano uscire da `$BASE/$lang`. I percorsi devono essere normalizzati prima di confrontare candidati o validare la directory.

### Tag file del progetto

Il tag consente a `run` di ricavare il linguaggio, in particolare quando il progetto è `$PWD`.

**Formato approvato per la prima versione:**

```text
<project>/.docker-dev/project-tag
```

Contenuto testuale, UTF-8/ASCII, con campi obbligatori e un valore per riga:

```text
schema_version=1
lang=Python
```

La directory `.docker-dev` è riservata ai metadati locali di `docker-dev`; il tag non deve contenere credenziali o valori dipendenti dalla macchina. Un parser semplice e stretto evita di introdurre un runtime YAML solo per leggere questi metadati.

Regole di scrittura e validazione:

- Scrivere o aggiornare il tag solo dopo il successo di setup e build.
- Pubblicare il nuovo file atomicamente (file temporaneo nella stessa directory e rename); un errore non deve lasciare un tag parziale.
- Con `build -x`, il tag registra il successo della build anche se il successivo run fallisce.
- Accettare solo una versione di schema supportata, un solo campo `lang` e un linguaggio gestito. Campi obbligatori mancanti, duplicati, valori vuoti o schema sconosciuto rendono il tag non valido.
- Per un target risolto sotto `$BASE/<lang>/...`, il valore `lang` del tag deve coincidere con `<lang>`.
- Un tag mancante o non valido non deve mai essere trattato come un successo-shaped fallback né deve provocare una build automatica da `run`.

## 3. Flussi e test

### Flussi attesi

```text
build:
  valida CLI e linguaggio
  risolve/crea il progetto secondo le regole approvate
  chiede conferma, salvo -y
  applica template e setup necessari
  esegue gli step di build della lingua
  scrive atomicamente il tag con il linguaggio
  se -x: esegue il run solo dopo il successo della build

run:
  valida CLI e risolve il progetto
  carica e valida il tag
  verifica i prerequisiti di run, inclusa la disponibilità dell'immagine
  chiede conferma
  esegue solo gli step necessari al run; non esegue build
```

`run` deve fallire con un messaggio operativo se l'immagine necessaria non è disponibile; non deve avviare implicitamente `build`. Il messaggio può suggerire il comando `docker-dev build --lang <lang> --target <target>`.

Il flusso di run non deve ripetere setup o build salvo prerequisiti che siano strettamente necessari al run e separabili dalla build. La pipeline numerata corrente esegue gli script in sequenza; l'implementazione dovrà introdurre una selezione esplicita degli step o un dispatcher equivalente, evitando di affidarsi all'ordine numerico per rappresentare implicitamente le operazioni.

### Verifiche richieste

| Area | Casi minimi |
|---|---|
| Parsing | `build` richiede `--lang`; `run` rifiuta `--lang` se non previsto; opzioni mancanti/sconosciute; `-x` solo per build; `-y` salta solo la conferma di build. |
| Compatibilità | L'invocazione legacy non cambia comportamento durante la transizione; l'assenza di subcomando non viene confusa con `run`. |
| Build e tag | Tag creato solo dopo build riuscita; nessun tag parziale se fallisce; tag aggiornato atomicamente; `-x` non esegue run se setup/build fallisce. |
| Default target | `build` e `run` senza target usano `$PWD`; `run` ricava il linguaggio dal tag. |
| Target relativo | `build --lang Python --target foo/bar` risolve in `$BASE/Python/foo/bar`; `run --target foo/bar` cerca sotto ogni linguaggio gestito. |
| Target assoluto | Directory esistente e tag validi; directory inesistente o non accessibile; linguaggio del tag valido. |
| Tag | Tag mancante, schema non supportato, linguaggio sconosciuto, campo duplicato/mancante/vuoto, mismatch tra tag e directory. |
| Ambiguità | Più candidati validi: errore non interattivo con elenco completo; nessun container avviato; percorso assoluto seleziona un solo candidato. |
| No build implicita | `run` con immagine assente fallisce e suggerisce `build`, senza invocare gli script di build o mutare lo stato. |
| Ordine | Verificare tramite stub/mocking che `build` esegua setup prima di build e che il run eventuale venga dopo tag/build. |

Non risulta definito un framework di test nel repository al momento della stesura. Prima di implementare i test, scegliere un approccio Bash leggero già disponibile nell'ambiente o introdurre test shell senza dipendenze runtime aggiuntive. Docker non deve essere necessario per i test unitari di parsing e dispatch; i test d'integrazione possono usare stub dei comandi Docker.

## 4. Documentazione d'uso

La documentazione per gli utenti va aggiornata dopo che parsing, flussi e test sono stabili, in modo da descrivere il comportamento verificato e non soltanto quello progettato.

Gli esempi minimi da documentare sono:

```bash
# Setup e build del progetto nel percorso predefinito $BASE/Python/my-app
docker-dev build --lang Python --target my-app

# Build nel progetto corrente
docker-dev build --lang Python

# Build e avvio
docker-dev build --lang Python --target my-app -x

# Build senza prompt
docker-dev build --lang Python --target my-app -y

# Run del progetto corrente; il linguaggio proviene dal tag
docker-dev run

# Ricerca di un target relativo sotto i linguaggi gestiti
docker-dev run --target my-app
```

La guida d'uso dovrà inoltre spiegare:

- il formato e la posizione del tag, quando viene creato e come diagnosticare un tag non valido;
- che `run` non costruisce l'immagine e non scrive il tag;
- come vengono risolti target assenti, relativi e assoluti;
- l'errore in caso di più candidati, includendo i percorsi trovati e il modo previsto per selezionarne uno senza ambiguità;
- la compatibilità transitoria e l'avviso associato alla sintassi legacy;
- gli errori CLI con esempi d'uso corretti e codici di uscita significativi.

## Sequenza di lavoro suggerita

1. Confermare le raccomandazioni di compatibilità legacy, target assoluti e tag file.
2. Implementare dispatch e parsing isolabili, con test del contratto CLI.
3. Implementare risoluzione target/tag e i test di errore, inclusa l'ambiguità.
4. Separare e collaudare i flussi build/run; verificare che run non costruisca.
5. Scrivere/aggiornare la guida utente sui comportamenti effettivamente collaudati.

I commit dovrebbero seguire unità coerenti e verificabili, non singole micro-modifiche: dispatch/CLI, risoluzione e tag, flussi/test, documentazione finale. La CR rev. 2 resta fuori perimetro fino alla successiva integrazione concordata.
