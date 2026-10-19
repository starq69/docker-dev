# Guida d'uso di `docker-dev`

Questa guida descrive i subcomandi `build` e `run` disponibili nello script
`docker-dev.sh`. Gli esempi assumono che lo script sia nel `PATH` con nome
`docker-dev`; altrimenti sostituire `docker-dev` con `./docker-dev.sh` o con il
percorso dello script.

## Comandi

```text
docker-dev build [--model <model>] [--target <target>] [-x] [-y]
docker-dev run [--target <target>]
docker-dev tag --model <model> [--target <directory>]
docker-dev info --tag
```

Le opzioni lunghe possono essere passate sia separate sia con `=`:

```bash
docker-dev build --model Bun --target foo
docker-dev build --model=Bun --target=foo
```

Un model esplicito deve corrispondere a una directory gestita sotto `langs/`,
`services/` o `stacks/`. Il valore è sensibile alle maiuscole e minuscole;
il nome deve essere univoco fra queste root. `--lang` resta disponibile come
alias compatibile per `--model` in `build`. Se omesso, `build` deduce il model
dal project tag, dall'instance tag o dalla root legacy. Se non è deducibile,
fallisce esplicitamente.

## Build

`build` applica i template del modello, esegue gli step di setup e build e,
solo se questi terminano correttamente, scrive il tag del progetto.

```bash
# Crea o aggiorna il progetto in $ORG/REP/DEV/Bun/foo
docker-dev build --model Bun --target foo

# Dalla root di un'istanza taggata, deduce il model e crea foo sotto l'istanza
cd "$HOME/REP/DEV/bun-team"
docker-dev build --target foo

# Usa la directory corrente come progetto
docker-dev build --model Bun


# Costruisce e, dopo il successo della build, avvia anche il container
docker-dev build --model Bun --target foo -x

# Esegue la build senza chiedere conferma
docker-dev build --model Bun --target foo -y
```

- `--model` è facoltativo. Se specificato, deve essere gestito e coerente con
  i tag applicabili.
- Senza `--target`, il progetto è `$PWD`, che deve già esistere ed essere
  accessibile in lettura e scrittura.
- Un target relativo, per esempio `foo/bar`, non include il modello e viene
  risolto sotto `$ORG/REP/DEV/<model>/foo/bar`.
- Il valore predefinito di `ORG` è `$HOME`; quindi il percorso predefinito è,
  per esempio, `$HOME/REP/DEV/Bun/foo`.
- Un target assoluto deve indicare una directory già esistente e accessibile.
- Se il target assoluto è dentro `$BASE`, la ricerca dell'instance tag parte
  dalla directory selezionata e risale fino a `$BASE`. Se è esterno a `$BASE`,
  non vengono cercati tag nei parent: il model deve provenire da `--model` o
  dal project tag della directory selezionata.
- Un project tag malformato o in conflitto con il model effettivo causa errore
  prima di applicare template o avviare setup/build; non viene sovrascritto.
- `-x` aggiunge il run dopo il successo di setup e build. Se la build fallisce,
  il container non viene avviato e il tag non viene scritto.
- `-y` salta il prompt di conferma di `build`; non disabilita validazioni o
  controlli.

Se l'immagine esiste già localmente, lo script di build del modello può
riutilizzarla senza ricostruirla. Per eseguire un aggiornamento dell'immagine,
seguire la procedura specifica del progetto/modello.

## Run

`run` avvia un progetto senza effettuare una build implicita.

```bash
# Dalla directory del progetto, che deve contenere un tag valido
cd "$HOME/REP/DEV/Bun/foo"
docker-dev run

# Da una directory radice modello, seleziona un progetto figlio
cd "$HOME/REP/DEV/Bun"
docker-dev run --target foo
```

- Senza `--target`, `run` usa `$PWD` e richiede il tag del progetto in quella
  directory.
- Con un target relativo, cerca esclusivamente `$PWD/<target>`. Non cerca nelle
  altre directory linguistiche né sotto `$BASE`.
- Se il target relativo non esiste sotto `$PWD`, `run` termina con un errore
  indicando il percorso cercato; non avvia Docker e non tenta una ricerca
  alternativa.
- Se il progetto locale non ha ancora il tag, ma la directory corrente è sotto
  una root modello gestita, per esempio `$HOME/REP/DEV/Bun`, il modello viene
  dedotto da tale percorso. Un tag presente ma non valido, o incoerente con la
  root modello, causa un errore.
- Un target assoluto seleziona la directory indicata e richiede un tag valido
  al suo interno:

  ```bash
  docker-dev run --target "$HOME/REP/DEV/Bun/foo"
  ```

- `run` richiede che l'immagine Docker calcolata per il progetto sia già
  disponibile localmente. In caso contrario mostra un errore e suggerisce il
  comando `build` corrispondente.
- `run` chiede conferma. `-y` è previsto solo per `build` e viene rifiutato da
  `run`.

## Tag del progetto

Una build riuscita scrive:

```text
<progetto>/.docker-dev/project-tag
```

Il contenuto della versione corrente è testuale:

```text
schema_version=1
model=Bun
```

Il tag identifica il modello per `run`. I tag precedenti con il campo `lang=`
restano leggibili; le nuove build scrivono `model=`. Il tag viene pubblicato atomicamente solo
dopo il successo degli step di setup e build; se `build -x` completa la build ma
il run successivo fallisce, il tag resta valido perché la build è riuscita.

Se il tag è mancante o non valido, `run` su `$PWD` o su un target assoluto
termina con un errore esplicito. Per un progetto legacy senza tag, eseguire
`run --target <progetto>` dalla directory radice del modello, per esempio
`$HOME/REP/DEV/Bun`.

## Tag dell'istanza

Un instance tag associa una directory esistente sotto `$BASE` a un model e
consente di dedurre il model per i progetti contenuti.

```bash
docker-dev tag --model Bun --target "$HOME/REP/DEV/bun-team"
```

Senza `--target`, viene taggata la directory corrente. Un target relativo è
risolto da `$PWD`; un target assoluto viene normalizzato. La directory deve
esistere ed essere leggibile/scrivibile. Il comando rifiuta di sovrascrivere un
`instance-tag` già presente.

## Diagnostica tag

`docker-dev info --tag` mostra il project tag corrente, il contesto d'istanza
più vicino entro `$BASE` e il model effettivo con la relativa origine. Segnala
tag malformati o conflitti senza applicare fallback.

## Sintassi legacy

Le invocazioni senza subcomando sono ancora supportate e mantengono il flusso
legacy completo (setup, build condizionale e run), con il formato target storico
che include il linguaggio:

```bash
docker-dev --target=Bun/foo
```

Questa forma non equivale al nuovo `run`: per avviare esplicitamente un progetto
senza build implicita usare `docker-dev run`. La sintassi legacy conserva anche
le opzioni documentate dal suo usage (`--penv`, `-i`, `-o` e gli argomenti
inoltrati al container). Al momento il percorso legacy non mostra ancora un
avviso di deprecazione.

## Errori comuni

| Messaggio/situazione | Causa e azione |
|---|---|
| `model cannot be inferred` | Specificare `--model`, creare un instance tag o eseguire il comando sotto una root legacy gestita; per un target assoluto esterno a `$BASE`, usare il project tag della directory o `--model`. |
| `unknown or unmanaged model` | Il valore di `--model` non corrisponde a una directory sotto `langs/`, `services/` o `stacks/`; verificare anche maiuscole e minuscole. |
| `target ... does not exist under the current directory` | Il target relativo di `run` non è un figlio di `$PWD`; spostarsi nella directory genitore corretta oppure usare un percorso assoluto. |
| `project metadata directory is missing or invalid` / tag mancante o non leggibile | Eseguire una build riuscita oppure, per un progetto legacy senza tag, usare `run --target` dalla sua root modello. |
| `unsupported project tag schema_version` / tag non valido | Correggere o rigenerare il tag con una build riuscita. |
| `image ... is not available locally` | Eseguire prima `docker-dev build --model <model> --target <progetto>`. |
| `... is only valid with build` | Spostare l'opzione build-only (`--model`, `-x` o `-y`) sul comando `build`. |

Per gli errori di sintassi, `docker-dev build --help` e `docker-dev run --help`
mostrano l'usage del subcomando.
