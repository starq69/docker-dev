# Ipotesi di design: istanze di progetto associate a un model

## Stato

Documento di discussione. Descrive un'ipotesi di evoluzione del resolver di
`docker-dev`; non modifica né sostituisce la specifica attuale dei subcomandi e
non implica che il comportamento sia già implementato.

Le decisioni sono divise in:

- **Confermato per questa ipotesi**: perimetro della scansione, metadato
  specifico per l'istanza e criterio di precedenza tra tag di istanza e
  convenzione legacy.
- **Da confermare**: comportamento in caso di conflitto con `--model`
  esplicito e base di risoluzione dei target relativi.

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

## 3. Ipotesi proposta

Associare esplicitamente un'istanza a un model mediante un tag di istanza
separato dal tag del singolo progetto. La ricerca del tag parte da `$PWD` e
risale i parent directory fino al primo tag trovato, senza oltrepassare `$BASE`.
Il primo tag incontrato è quello dell'istanza applicabile.

### 3.1 Metadato dell'istanza

Posizione proposta:

```text
<instance-root>/.docker-dev/instance-tag
```

Formato proposto:

```text
schema_version=1
model=Bun
```

Il percorso e il nome `instance-tag` sono una proposta concreta da confermare.
Il file è distinto da:

```text
<project>/.docker-dev/project-tag
```

Il tag di istanza descrive la directory condivisa da più progetti; il tag di
progetto continua a descrivere il model registrato per uno specifico progetto.
Il parser dovrebbe applicare validazioni analoghe a quelle del project tag:
schema supportato, un solo model non vuoto, model gestito e nessun campo
duplicato o sconosciuto.

### 3.2 Comando per taggare un'istanza

Interfaccia proposta:

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

1. Normalizzare `$PWD` e `$BASE`.
2. Esaminare `$PWD` e i suoi parent, risalendo fino a `$BASE` incluso.
3. Fermarsi al **primo** `.docker-dev/instance-tag` trovato e validarlo.
4. Se non si trova un tag di istanza, applicare il fallback legacy: riconoscere
   una directory root il cui nome coincide con un model gestito.
5. Se non si trova né un tag né una root legacy, il model non è deducibile e
   l'operazione che ne richiede uno fallisce con un errore esplicito.

La scansione non deve continuare sopra `$BASE`: un tag in una directory
genitrice esterna all'albero dei progetti non deve influenzare il risultato.
Tag di istanza annidati sono compatibili con la regola del primo tag: prevale
quello più vicino a `$PWD`.

Il fallback basato sul nome preserva il layout corrente, per esempio
`$BASE/Bun/app` senza tag di istanza. La presenza di un tag di istanza più
vicino prevale sulla convenzione del nome.

Se il tag più vicino è malformato, l'ipotesi raccomandata è fallire
esplicitamente, senza ignorarlo e continuare la ricerca nei parent.

### 3.4 Comando informativo

Interfaccia proposta:

```text
docker-dev info --tag
```

Il comando dovrebbe aiutare a diagnosticare i metadati applicabili partendo
dalla directory corrente. Una proposta utile è mostrare:

- il project tag presente nel progetto corrente, se esiste;
- il tag di istanza più vicino trovato entro `$BASE`, se esiste;
- il model effettivo dedotto e la sua origine (project tag, instance tag o
  fallback legacy);
- eventuali conflitti o tag non validi.

Resta da confermare se `info --tag` debba mostrare solo il tag effettivo oppure
tutti i tag rilevanti trovati.

## 4. Decisioni confermate per questa ipotesi

1. **Limite della ricerca**: la scansione dei parent si arresta a `$BASE`.
2. **Metadato separato**: il tag di istanza ha un nome/percorso distinto dal
   tag del progetto.
3. **Precedenza dell'istanza**: prevale il primo tag di istanza trovato
   risalendo da `$PWD`; se non esiste, si mantiene il fallback legacy basato
   sulla corrispondenza del nome della directory con un model gestito.

Queste decisioni definiscono il comportamento ipotizzato di ricerca delle
istanze, non tutti i dettagli di precedenza tra i metadati di istanza e di
progetto.

## 5. Decisioni ancora da confermare

### 5.1 `--model` esplicito in conflitto con il tag di istanza

Esempio:

```bash
cd "$BASE/bun-team"   # instance-tag: model=Bun
docker-dev build --model=Python --target=app
```

Possibili politiche:

- fallire con un errore di mismatch;
- consentire l'override esplicito e documentarlo;
- usare sempre il model del tag, rendendo `--model` ridondante in quel
  contesto.

**Raccomandazione**: fallire sul conflitto. Un tag di istanza deve esprimere
un'associazione affidabile e il rifiuto evita di creare progetti nella root
con template/pipeline inattesi. L'eventuale override dovrebbe richiedere
un'opzione separata e intenzionale, non essere implicito.

### 5.2 Base di risoluzione di `--target` relativo

Esempio:

```bash
cd "$BASE/bun-team"
docker-dev build --target=test/hello
```

Se il model viene dedotto dal tag, sono possibili due destinazioni:

- **Root dell'istanza**: `$BASE/bun-team/test/hello`.
- **Root canonica del model**: `$BASE/Bun/test/hello`.

**Raccomandazione**: creare il target sotto la root dell'istanza che ha
fornito il contesto (`$BASE/bun-team/test/hello`). In questo modo una root
taggata identifica sia il model applicabile sia il contenitore dei suoi
progetti; scrivere nella root canonica renderebbe la directory personalizzata
simile a un alias e potrebbe sorprendere l'utente.

Con `--model` esplicito eseguito fuori da un'istanza riconosciuta, il
comportamento esistente può restare invariato: target relativo sotto
`$BASE/<model>/<target>`. Se `--model` è esplicito dentro un'istanza taggata,
la destinazione dipende dalla decisione del punto 5.1.

## 6. Relazione tra project tag e instance tag

Il project tag esistente registra il model dopo una build riuscita. Il tag di
istanza dà invece un contesto ai progetti contenuti nella directory, inclusi
quelli senza project tag.

Politica raccomandata:

- se il project tag è presente e valido, usarlo come identità specifica del
  progetto;
- se è presente anche un instance tag, richiedere che i due model coincidano;
- se il project tag manca, usare il model dell'instance tag più vicino;
- senza instance tag, mantenere l'inferenza legacy dal nome della root;
- senza nessuna fonte valida, fallire: non dedurre il model da nomi o contenuti
  arbitrari del progetto.

Un project tag malformato non dovrebbe essere ignorato per ripiegare sul tag
di istanza. La gestione precisa del conflitto project/instance tag va
confermata prima dell'implementazione; la raccomandazione è fallire
esplicitamente.

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
- **Build**: separare il model (selezione pipeline/template) dalla root di
  destinazione; attualmente `ddev_resolve_build_project()` usa
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
  subcomandi solo dopo la conferma delle decisioni aperte.

## 8. Esempio del flusso ipotizzato

```bash
mkdir -p "$BASE/bun-team"
docker-dev tag --model Bun --target "$BASE/bun-team"

cd "$BASE/bun-team"
docker-dev info --tag
docker-dev build --target=test/hello
```

Con la raccomandazione del punto 5.2, il progetto viene creato in
`$BASE/bun-team/test/hello`, usa template e pipeline di `Bun` e riceve il
proprio `.docker-dev/project-tag` al termine positivo della build.

Il comportamento esatto dell'ultimo comando resta subordinato alla conferma
delle decisioni 5.1 e 5.2.
