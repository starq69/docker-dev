#!/usr/bin/env bash
set -euo pipefail


create_directory() {
  local dir="$1"
  local path="$BASE"

  IFS=/ read -r -a components <<< "$dir"

  local A="${components[0]}"
  local B="${dir#*/}"

  #echo "A=$A"
  #echo "B=$B"
  #if [ -z "$A" ]; then
  #  echo "WARNING: Absolute path passed $dir"
  #  return 1
  #fi

  if [ ! -d "$BASE/$A" ]; then  # readlink ?
    P_TYPES=$(find "$BASE" -maxdepth 1 -mindepth 1 -type d -printf '%f\n')
    echo "WARNING: $BASE/$A does not exist" >&2
    echo "Please select one of the following available project types:"
    echo "$P_TYPES"
    return 1
  fi

  if [ -n "$B" ]; then
    # mkdir only if not exist 
    if [ ! -d "$(readlink -f "$BASE/$A/$B")" ]; then
      echo ":mkdir -p $BASE/$A/$B"
      #mkdir -p "$BASE/$A/$B"
    else
      echo "directory already exist"
    fi
    PROJECT_DIR="$BASE/$A/$B"
  fi

  return 0
}

is_absolute() {

  if [[ "$1" =~ ^/ ]]; then
    echo "test : absolute path?"
    return 0
  fi
    echo "test: relative path?"
    return 1
}

check() {
  #if [ -d "$1" ]; then
  if [ -d "$(readlink -f "$1")" ]; then
    #echo "$1 exist"
    if [ -r "$1" ] && [ -w "$1" ]; then
      echo "$1 is valid"
      PROJECT_DIR="$1"
      return 0
    else
      echo "missing rw permission on $1"
      return 1
    fi
  else
    if is_absolute "$1"; then
      echo "cannot create new absolute path $1"
      echo "use relative path instead"  
      return 1
    else
      echo "relative path passed: $1"
    fi

    # check for invalid characters 
    #
    if ! is_valid $1; then
      echo "$1 is NOT valid"
      exit 1
    else
      echo "$1 is valid"
    fi

    if ! create_directory "$1"; then
      echo "Error creating $1" >&2
      return 1
    fi
    return 0
  fi
}

is_valid() {
    local input="$1"

    # Condition 1: Only allow a-zA-Z0-9-_/. characters
    if [[ ! "$input" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
	echo "Condition 1 FAIL"
        return 1
    fi

    # Condition 2: Can't contain two consecutive dots or backslashes
    if [[ "$input" =~ \.\. ]] || [[ "$input" =~ //// ]]; then
	echo "Condition 2 FAIL"
        return 1
    fi

    # Condition 3: Can't contain the sequence '/.'
    if [[ "$input" =~ //. ]]; then
	echo "Condition 3 FAIL"
        return 1
    fi

    # Condition 4: Can't begin or end with a dot or backslash
    if [[ "$input" =~ ^[.//] ]] || [[ "$input" =~ [.//]$ ]]; then
	echo "Condition 4 FAIL"
        return 1
    fi

    return 0
}

BASE="/home/starq/REP/DEV"

while getopts ":d:i:c:v:" opt; do
  case $opt in
    d) 
       if ! check "$OPTARG"; then
	 echo "invalid argument -d $OPTARG"
	 exit 1
       fi
       ;;
    i) IMAGE_NAME=$OPTARG;;
    c) CONTAINER_NAME=$OPTARG;;
    v) VOLUME_NAME=$OPTARG;;
    \?) usage;;
  esac
done

shift $((OPTIND-1))

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"

echo "$PROJECT_DIR"

