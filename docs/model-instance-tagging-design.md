# Design: istanze di progetto associate a un model

## Stato

Documento di design per l'evoluzione del resolver di `docker-dev`; non modifica
né sostituisce la specifica attuale dei subcomandi e non implica che il
comportamento descritto sia già implementato. Le decisioni approvate in questo
documento sono requisiti di design per l'implementazione.

Le decisioni sono divise in:

- **Approvato**: il design del punto 3, i nomi e le posizioni `instance-tag` e
  `project-tag`, il formato dei metadati e le politiche dei punti 5 e 6.
- **Da confermare**: dettagli operativi del comando `tag`, in particolare la
  risoluzione dei target relativi/assoluti e la gestione di un tag d'istanza
  già esistente, e la deduzione del model per target assoluti esterni a `$BASE`.

## 1. Terminologia

- **Model**: componente gestito che fornisce template e pipeline, per esempio
  `Bun`, `Postgres` o `Web`.
- **Istanza**: directory nell'albero dei progetti, associata a un solo model,
  che contiene uno o più progetti. Il nome dell'istanza non deve
  necessariamente coincidere con quello del model.
- **Progetto**: directory sulla quale `docker-dev build` o `docker-dev run`
  opera.

Esempio:

```text
$BASE/
  Bun/                         # istanza legacy: nome uguale al model
  bun-team/                    # istanza taggata come model Bun
    app-a/
    app-b/
```

## 2. Comportamento attuale

Il layout relativo convenzionale è:

```text
$BASE/<model>/<target>
```

Ad esempio:

```bash
docker-dev build --model=Bun --target=test/hello
```

crea `$BASE/Bun/test/hello`. Per alcuni casi di `run` il model può essere
dedotto dal nome della directory sotto `$BASE`; il tag del singolo progetto
`.docker-dev/project-tag` registra invece il model e viene scritto dopo una
build riuscita.

Il nome della directory e il model sono quindi implicitamente accoppiati per
le istanze senza tag. Un nome personalizzato come `$BASE/bun-team` non offre
attualmente un modo per dedurre `Bun` dalla sola struttura del percorso.

## 3. Design approvato

Associare esplicitamente un'istanza a un model mediante un tag di istanza
separato dal tag del singolo progetto. La ricerca del tag risale i parent
directory dal contesto selezionato fino al primo tag trovato, senza
oltrepassare `$BASE`. Il primo tag incontrato è quello dell'istanza applicabile.

### 3.1 Metadato dell'istanza

Posizione e nome del file-tag confermati (`instance-tag`):

```text
<instance-root>/.docker-dev/instance-tag
```

Formato confermato:

```text
schema_version=1
model=Bun
```

Il file dell'istanza è distinto dal file del progetto, collocato nella posizione
confermata:

```text
<project>/.docker-dev/project-tag
```

Il tag di istanza descrive la directory condivisa da più progetti; il tag di
progetto continua a descrivere il model registrato per uno specifico progetto.
Il parser deve applicare validazioni analoghe a quelle del project tag:
schema supportato, un solo model non vuoto, model gestito e nessun campo
duplicato o sconosciuto.

### 3.2 Comando per taggare un'istanza

Interfaccia confermata:

```text
docker-dev tag --model <model> [--target <directory>]
```

- `--target` assente: tagga `$PWD`.
- `--target` presente: tagga la directory specificata.
- La directory deve esistere; `tag` non crea implicitamente un'istanza.
- Il comando deve validare che il model sia gestito e gestire esplicitamente un
  eventuale tag già presente, evitando sovrascritture silenziose.
- Le regole esatte per target assoluti/relativi, overwrite e collocazione
  ammessa sotto `$BASE` restano da definire.

Una volta taggata `$BASE/bun-team` come `Bun`, la directory può contenere più
progetti senza che il suo nome debba essere `Bun`.

### 3.3 Risoluzione di un'istanza

Per determinare il contesto di un progetto:

1. Normalizzare `$PWD`, il target selezionato e `$BASE`.
2. Usare `$PWD` come punto di partenza quando il target non è assoluto. Per un
  target assoluto, usare la directory selezionata come punto di partenza.
3. Esaminare il punto di partenza e i suoi parent, risalendo fino a `$BASE`
  incluso.
4. Fermarsi al **primo** `.docker-dev/instance-tag` trovato e validarlo.
5. Se non si trova un tag di istanza, applicare il fallback legacy: riconoscere
   una directory root il cui nome coincide con un model gestito.
6. Se non si trova né un tag né una root legacy, il model non è deducibile e
   l'operazione che ne richiede uno fallisce con un errore esplicito.

La scansione non deve continuare sopra `$BASE`: un tag in una directory
genitrice esterna all'albero dei progetti non deve influenzare il risultato.
Tag di istanza annidati sono compatibili con la regola del primo tag: prevale
quello più vicino a `$PWD`.

Il fallback basato sul nome preserva il layout corrente, per esempio
`$BASE/Bun/app` senza tag di istanza. La presenza di un tag di istanza più
vicino prevale sulla convenzione del nome.

Se il tag più vicino è malformato, la risoluzione deve fallire esplicitamente,
senza ignorarlo e continuare la ricerca nei parent.

### 3.4 Comando informativo

Interfaccia confermata:

```text
docker-dev info --tag
```

Il comando deve aiutare a diagnosticare i metadati applicabili partendo dalla
directory corrente e mostrare:

- il project tag presente nel progetto corrente, se esiste;
- il tag di istanza più vicino trovato entro `$BASE`, se esiste;
- il model effettivo dedotto e la sua origine (project tag, instance tag o
  fallback legacy);
- eventuali conflitti o tag non validi.

## 4. Decisioni approvate

1. **Limite della ricerca**: la scansione dei parent si arresta a `$BASE`.
2. **Metadato separato**: il tag di istanza ha un nome/percorso distinto dal
   tag del progetto.
3. **Precedenza dell'istanza**: prevale il primo tag di istanza trovato
  risalendo dal contesto selezionato; per un target assoluto il contesto è la
  directory selezionata, altrimenti è `$PWD`. Se non esiste un tag, si mantiene
  il fallback legacy basato sulla corrispondenza del nome della directory con
  un model gestito.

Queste decisioni definiscono il comportamento approvato di ricerca delle
istanze. La precedenza tra i metadati di istanza e di progetto è definita al
punto 6.

## 5. Decisioni approvate

### 5.1 `--model` esplicito in conflitto con il tag di istanza

Esempio:

```bash
cd "$BASE/bun-team"   # instance-tag: model=Bun
docker-dev build --model=Python --target=app
```

Se `--model` esplicito contrasta con il model del tag d'istanza, `build` deve
fallire con un errore di mismatch prima di creare o modificare il progetto.
L'eventuale override richiederebbe un'opzione separata e intenzionale; non è
implicito.

### 5.2 Base di risoluzione di `--target` relativo

Esempio:

```bash
cd "$BASE/bun-team"
docker-dev build --target=test/hello
```

Con un'istanza riconosciuta, il target relativo va creato sotto la root
dell'istanza che fornisce il contesto, per esempio
`$BASE/bun-team/test/hello`, usando il model associato per template e pipeline.
Non va reindirizzato alla root canonica `$BASE/Bun`.

Con `--model` esplicito eseguito fuori da un'istanza riconosciuta, il
target relativo resta sotto `$BASE/<model>/<target>`. Se `--model` è esplicito
dentro un'istanza taggata, si applica il controllo di mismatch del punto 5.1;
se coincide, il target resta sotto la root dell'istanza.

## 6. Relazione tra project tag e instance tag

Il project tag esistente registra il model dopo una build riuscita. Il tag di
istanza dà invece un contesto ai progetti contenuti nella directory, inclusi
quelli senza project tag.

Politiche approvate:

- se il project tag è presente e valido, usarlo come identità specifica del
  progetto;
- se è presente anche un instance tag, richiedere che i due model coincidano;
- se il project tag manca, usare il model dell'instance tag più vicino;
- senza instance tag, mantenere l'inferenza legacy dal nome della root;
- un `--model` esplicito e gestito può fornire il model quando non è disponibile
  una fonte deducibile; deve comunque coincidere con i tag presenti;
- senza project tag valido, instance tag, root legacy o `--model` esplicito
  gestito, fallire: non dedurre il model da nomi o contenuti arbitrari del
  progetto.

- Un project tag malformato deve causare un errore esplicito; non va ignorato
  per ripiegare sul tag di istanza o sull'inferenza legacy.
- In `build`, se il project tag esiste, va letto e validato prima di applicare
  template o avviare setup/build. Un tag malformato o il cui model non coincide
  con il model effettivo selezionato causa un errore e non viene sovrascritto.
- Se il project tag manca, `build` può procedere con il model effettivo; scrive
  il project tag in modo atomico solo dopo il successo di setup e build.
- In `run`, un project tag malformato o in conflitto con il tag d'istanza causa
  un errore esplicito; non si applica alcun fallback. Se il project tag manca,
  si usa il tag d'istanza più vicino o, in sua assenza, l'inferenza legacy
  approvata.

## Elenco dei punti critici, indesiderati o da rettificare

- **Target assoluto esterno a `$BASE`**: la ricerca dell'instance tag parte
  dalla directory selezionata e risale i parent. Se tale directory non è
  `$BASE` né una sua discendente, `$BASE` non verrà mai incontrata; un ciclo
  che continui fino a esaurire i parent raggiungerebbe `/`. Potrebbe così
  trovare un `.docker-dev/instance-tag` estraneo al perimetro del progetto e
  usarlo per dedurre il model, con risultati inattesi e un confine di ricerca
  troppo ampio.
  **Da decidere prima dell'implementazione**: il resolver deve verificare la
  discendenza da `$BASE` prima della scansione. Mitigazione raccomandata: fuori
  da `$BASE` non cercare instance tag nei parent; accettare come fonti del model
  soltanto il project tag della directory selezionata o un `--model` esplicito
  e coerente, altrimenti fallire. Non proseguire mai implicitamente la ricerca
  fino a `/`.

## 7. Impatto d'integrazione stimato

Impatto qualitativo: **medio**, concentrato nel resolver e nel dispatch CLI.
Non è una modifica confinata alla sola visualizzazione dei tag.

### Componenti coinvolti

- **Parsing e dispatch CLI** in `docker-dev-cli.sh` e `docker-dev.sh`:
  aggiungere `tag` e `info --tag`; rendere possibile la deduzione del model
  quando `build` non riceve `--model`.
- **Risoluzione dei model e delle istanze** in `docker-dev-cli.sh`:
  aggiungere lettura/validazione del tag di istanza, ricerca dei parent
  limitata a `$BASE`, fallback legacy e restituzione sia del model sia della
  root dell'istanza selezionata.
- **Build**: rendere `--model` facoltativo e dedurlo dai tag o dalla root
  legacy; per target assoluti avviare la ricerca dell'instance tag dalla
  directory selezionata. Separare il model (selezione pipeline/template) dalla
  root di destinazione; attualmente `ddev_resolve_build_project()` usa
  `$BASE/<model>/<target>`, quindi non può rappresentare da solo una root
  personalizzata.
- **Run**: integrare il model dedotto dall'istanza con il project tag e
  validare i mismatch secondo le decisioni sopra.
- **Scrittura metadati**: implementare la scrittura sicura/atomica del tag di
  istanza e definire il comportamento in caso di tag già esistente.
- **Info**: implementare la visualizzazione dei metadati e della fonte del
  model effettivo.
- **Test**: coprire root canoniche senza tag, root personalizzate taggate,
  tag annidati, scansione che non supera `$BASE`, target relativi, model
  esplicito concorde/in conflitto, project tag mancante/valido/malformato e
  `info --tag`.
- **Documentazione**: aggiornare la guida e integrare la specifica dei
  subcomandi dopo aver definito i dettagli operativi ancora aperti.

## 8. Esempio del flusso approvato

```bash
mkdir -p "$BASE/bun-team"
docker-dev tag --model Bun --target "$BASE/bun-team"

cd "$BASE/bun-team"
docker-dev info --tag
docker-dev build --target=test/hello
```

Il progetto viene creato in
`$BASE/bun-team/test/hello`, usa template e pipeline di `Bun` e riceve il
proprio `.docker-dev/project-tag` al termine positivo della build.
