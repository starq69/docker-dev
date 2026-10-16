# Guida d'uso di `docker-dev`

Questa guida descrive i subcomandi `build` e `run` disponibili nello script
`docker-dev.sh`. Gli esempi assumono che lo script sia nel `PATH` con nome
`docker-dev`; altrimenti sostituire `docker-dev` con `./docker-dev.sh` o con il
percorso dello script.

## Comandi

```text
docker-dev build --lang <linguaggio> [--target <target>] [-x] [-y]
docker-dev run [--target <target>]
```

Le opzioni lunghe possono essere passate sia separate sia con `=`:

```bash
docker-dev build --lang Bun --target foo
docker-dev build --lang=Bun --target=foo
```

Il linguaggio deve essere una directory gestita sotto `langs/`, per esempio
`Bun`, `Python`, `Deno`, `Perl` o `Cpp`. Il valore è sensibile alle maiuscole e
minuscole.

## Build

`build` applica i template del linguaggio, esegue gli step di setup e build e,
solo se questi terminano correttamente, scrive il tag del progetto.

```bash
# Crea o aggiorna il progetto in $ORG/REP/DEV/Bun/foo
docker-dev build --lang Bun --target foo

# Usa la directory corrente come progetto
docker-dev build --lang Bun

# Costruisce e, dopo il successo della build, avvia anche il container
docker-dev build --lang Bun --target foo -x

# Esegue la build senza chiedere conferma
docker-dev build --lang Bun --target foo -y
```

- `--lang` è obbligatorio.
- Senza `--target`, il progetto è `$PWD`, che deve già esistere ed essere
  accessibile in lettura e scrittura.
- Un target relativo, per esempio `foo/bar`, non include il linguaggio e viene
  risolto sotto `$ORG/REP/DEV/<linguaggio>/foo/bar`.
- Il valore predefinito di `ORG` è `$HOME`; quindi il percorso predefinito è,
  per esempio, `$HOME/REP/DEV/Bun/foo`.
- Un target assoluto deve indicare una directory già esistente e accessibile.
- `-x` aggiunge il run dopo il successo di setup e build. Se la build fallisce,
  il container non viene avviato e il tag non viene scritto.
- `-y` salta il prompt di conferma di `build`; non disabilita validazioni o
  controlli.

Se l'immagine esiste già localmente, lo script di build della lingua può
riutilizzarla senza ricostruirla. Per eseguire un aggiornamento dell'immagine,
seguire la procedura specifica del progetto/linguaggio.

## Run

`run` avvia un progetto senza effettuare una build implicita.

```bash
# Dalla directory del progetto, che deve contenere un tag valido
cd "$HOME/REP/DEV/Bun/foo"
docker-dev run

# Da una directory radice linguaggio, seleziona un progetto figlio
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
  una root linguaggio gestita, per esempio `$HOME/REP/DEV/Bun`, il linguaggio
  viene dedotto da tale percorso. Un tag presente ma non valido, o incoerente
  con la root linguaggio, causa un errore.
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
lang=Bun
```

Il tag identifica il linguaggio per `run`. Viene pubblicato atomicamente solo
dopo il successo degli step di setup e build; se `build -x` completa la build ma
il run successivo fallisce, il tag resta valido perché la build è riuscita.

Se il tag è mancante o non valido, `run` su `$PWD` o su un target assoluto
termina con un errore esplicito. Per un progetto legacy senza tag, eseguire
`run --target <progetto>` dalla directory radice del linguaggio, per esempio
`$HOME/REP/DEV/Bun`.

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
| `build requires --lang` | Specificare un linguaggio gestito, per esempio `--lang Bun`. |
| `unknown or unmanaged language` | Il valore di `--lang` non corrisponde a una directory sotto `langs/`; verificare anche maiuscole e minuscole. |
| `target ... does not exist under the current directory` | Il target relativo di `run` non è un figlio di `$PWD`; spostarsi nella directory genitore corretta oppure usare un percorso assoluto. |
| `project metadata directory is missing or invalid` / tag mancante o non leggibile | Eseguire una build riuscita oppure, per un progetto legacy senza tag, usare `run --target` dalla sua root linguaggio. |
| `unsupported project tag schema_version` / tag non valido | Correggere o rigenerare il tag con una build riuscita. |
| `image ... is not available locally` | Eseguire prima `docker-dev build --lang <linguaggio> --target <progetto>`. |
| `... is only valid with build` | Spostare l'opzione build-only (`--lang`, `-x` o `-y`) sul comando `build`. |

Per gli errori di sintassi, `docker-dev build --help` e `docker-dev run --help`
mostrano l'usage del subcomando.
