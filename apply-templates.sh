#!/usr/bin/env bash
#
set -euo pipefail

# apply-templates.sh
#
# Argomenti:
#   -o        (opzionale) sovrascrive i file già presenti nella destinazione
#   $1 PROJECT_DIR
#   $2 P_TYPE

OVERWRITE=0
while getopts ":o" opt; do
    case "$opt" in
        o)  OVERWRITE=1;;
        \?) echo "[files] ERRORE: opzione non valida: -$OPTARG" >&2; exit 1;;
    esac
done
shift $((OPTIND - 1))

PROJECT_DIR="$1"
P_TYPE="$2"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TEMPLATES_DIR="${SCRIPT_DIR}/langs/${P_TYPE}/templates"
SETTINGS_DIR="${SCRIPT_DIR}/.settings"
STANDARD_BASHRC="${SETTINGS_DIR}/.bashrc"

# Sotto cartella consegnata a ogni progetto, composta e non copiata dai templates
DC_DIR_NAME=".docker_container"

if [[ ! -d "$TEMPLATES_DIR" ]]; then
    echo "[files] ERROR: Missing template folder: $TEMPLATES_DIR" >&2
    exit 1
fi

if [[ ! -f "$STANDARD_BASHRC" ]]; then
    echo "[files] ERROR: Missing standard bashrc: $STANDARD_BASHRC" >&2
    exit 1
fi

copy_file_no_clobber() {
    local src_file="$1"
    local dst_file="$2"
    local dst_dir
    dst_dir="$(dirname -- "$dst_file")"

    if [[ ! -d "$dst_dir" ]]; then
        mkdir -p -- "$dst_dir"
    fi

    if [[ -e "$dst_file" ]]; then
        if [[ "$OVERWRITE" -eq 1 ]]; then
            cp -- "$src_file" "$dst_file"
            echo "[files] Sovrascritto: $dst_file"
        else
            echo "[files] Skip (già presente): $dst_file"
        fi
    else
        cp -- "$src_file" "$dst_file"
        echo "[files] Copiato: $dst_file"
    fi
}

# Copia ricorsiva, senza sovrascrivere file esistenti.
# Nota: la cartella .docker_container dei templates è esclusa (prune):
# il contenuto consegnato al progetto viene generato da
# apply_docker_container() componendo i pezzi opzionali per linguaggio
# con lo standard .settings/.bashrc.
copy_tree_no_clobber() {
    local src_root="$1"
    local dst_root="$2"

    mkdir -p -- "$dst_root"

    while IFS= read -r -d '' src_file; do
        local rel_path="${src_file#"${src_root}"/}"
        local dst_file="${dst_root}/${rel_path}"
        copy_file_no_clobber "$src_file" "$dst_file"
    done < <(find "$src_root" -type d -name "$DC_DIR_NAME" -prune -o -type f -print0)
}

# Composizione di <project>/.docker_container/.bashrc
#
# Pezzi opzionali in ${TEMPLATES_DIR}/.docker_container/
# (devono terminare con newline):
#   .bashrc.head
#   .bashrc.body  (oppure .bashrc)
#   .bashrc.tail
#
# Regole:
#   - .bashrc.body (o .bashrc) presente -> [head][body][tail]  (standard escluso)
#   - solo head e/o tail                -> [head][standard][tail]
#   - nessun pezzo                      -> copia di .settings/.bashrc
#
# Viene inoltre consegnato .settings/.gitignore come
# <project>/.docker_container/.gitignore (ignora .bash_history).
apply_docker_container() {
    local dc_src="${TEMPLATES_DIR}/${DC_DIR_NAME}"
    local dc_dst="${PROJECT_DIR}/${DC_DIR_NAME}"
    local dst_file="${dc_dst}/.bashrc"

    local head_file="${dc_src}/.bashrc.head"
    local body_file="${dc_src}/.bashrc.body"
    local tail_file="${dc_src}/.bashrc.tail"

    # .bashrc.body assente: .bashrc e' la versione specifica del linguaggio
    if [[ ! -f "$body_file" && -f "${dc_src}/.bashrc" ]]; then
        body_file="${dc_src}/.bashrc"
    fi

    mkdir -p -- "$dc_dst"

    if [[ -e "$dst_file" && "$OVERWRITE" -ne 1 ]]; then
        echo "[files] Skip (già presente): $dst_file"
    else
        {
            if [[ -f "$head_file" ]]; then
                cat -- "$head_file"
            fi
            if [[ ! -f "$body_file" ]]; then
                cat -- "$STANDARD_BASHRC"
            fi
            if [[ -f "$body_file" ]]; then
                cat -- "$body_file"
            fi
            if [[ -f "$tail_file" ]]; then
                cat -- "$tail_file"
            fi
        } > "$dst_file"
        echo "[files] Generato: $dst_file"
    fi

    copy_file_no_clobber "${SETTINGS_DIR}/.gitignore" "${dc_dst}/.gitignore"
}

echo "[apply_templates] start..."
copy_tree_no_clobber "$TEMPLATES_DIR" "$PROJECT_DIR"
apply_docker_container
echo "[apply_templates] end"
