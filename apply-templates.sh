#!/usr/bin/env bash
#
set -euo pipefail

# apply-templates.sh
#
# Argomenti:
#   $1 PROJECT_DIR
#   $2 P_TYPE

PROJECT_DIR="$1"
P_TYPE="$2"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TEMPLATES_DIR="${SCRIPT_DIR}/langs/${P_TYPE}/.templates"

if [[ ! -d "$TEMPLATES_DIR" ]]; then
    echo "[files] ERRORE: cartella template non trovata: $TEMPLATES_DIR" >&2
    exit 1
fi

# Copia ricorsiva, senza sovrascrivere file esistenti.
# -n  : no clobber (non sovrascrive destinazione esistente)
# -a  : archive (mantiene struttura, permessi, ecc.)
# -v  : verbose (opzionale, per debug)
#
# Nota: cp -n non crea directory di destinazione se non esistono, quindi usiamo
#       un ciclo su ogni file per garantire il comportamento desiderato.

copy_tree_no_clobber() {
    local src_root="$1"
    local dst_root="$2"

    # Assicurati che la radice di destinazione esista
    mkdir -p -- "$dst_root"

    # Trova tutti i file (non le directory) sotto src_root
    while IFS= read -r -d '' src_file; do
        # Calcola il percorso relativo rispetto a src_root
        local rel_path="${src_file#"${src_root}"/}"
        local dst_file="${dst_root}/${rel_path}"
        local dst_dir
        dst_dir="$(dirname -- "$dst_file")"

        # Crea la directory di destinazione se non esiste
        if [[ ! -d "$dst_dir" ]]; then
            mkdir -p -- "$dst_dir"
        fi

        # Copia solo se il file di destinazione non esiste
        if [[ -e "$dst_file" ]]; then
            echo "[files] Skip (già presente): $dst_file"
        else
            cp -- "$src_file" "$dst_file"
            echo "[files] Copiato: $dst_file"
        fi
    done < <(find "$src_root" -type f -print0)
}

copy_tree_no_clobber "$TEMPLATES_DIR" "$PROJECT_DIR"
