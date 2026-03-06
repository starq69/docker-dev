#!/usr/bin/env bash
set -euo pipefail

is_valid() {
    local input="$1"

    # Condition 1: Only allow a-zA-Z0-9-_\. characters
    if [[ ! "$input" =~ ^[a-zA-Z0-9._\-]+$ ]]; then
        return 1
    fi

    # Condition 2: Can't contain two consecutive dots or backslashes
    if [[ "$input" =~ \.\. ]] || [[ "$input" =~ \\\\ ]]; then
        return 1
    fi

    # Condition 3: Can't contain the sequence '\.'
    if [[ "$input" =~ \\. ]]; then
        return 1
    fi

    # Condition 4: Can't begin or end with a dot or backslash
    if [[ "$input" =~ ^[.\\] ]] || [[ "$input" =~ [.\\]$ ]]; then
        return 1
    fi

    return 0
}

if is_valid "$1"; then
    echo "$1 is Valid"
else
    echo "$1 is NOT valid"
fi

