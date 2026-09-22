#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/app}"
cd "$APP_DIR"

# 1. Ottimizzazione della Cache
# Se esiste una configurazione di progetto, risolviamo le dipendenze subito.
# popola il Docker Volume in modo efficiente prima dell'avvio del watcher.
if [ -f "deno.json" ] || [ -f "deno.jsonc" ]; then
    echo "[entrypoint] Verifica e aggiornamento della cache di Deno..."
    # Se hai un file main.ts o task predefiniti, deno cache li analizzerà.
    # Usiamo '|| true' per evitare che l'entrypoint fallisca se il progetto è vuoto.
    deno cache --quiet deno.json 2>/dev/null || true
fi

if [ -z "${1:-}" ]; then
    echo "[entrypoint] No command provided, using default command"
    # full hostname in prompt 
    echo "export PS1='\u@\H:\w\$ '" > /tmp/custom_bashrc
    exec bash --rcfile /tmp/custom_bashrc -i
else
    echo "[entrypoint] Esecuzione del comando: $(printf "%s " "$@")"
    # Mantiene il processo Deno come PID 1 per gestire correttamente il Ctrl+C del watcher
    exec "$@"
fi

