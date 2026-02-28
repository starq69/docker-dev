#!/usr/bin/env bash
set -euo pipefail


create_directory() {
  local _tag="[create_directory]"
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
    echo "$_tag WARNING: $BASE/$A does not exist" >&2
    echo "$_tag Please select one of the following available project types:"
    echo "$P_TYPES"
    return 1
  fi

  if [ -n "$B" ]; then
    # mkdir only if not exist 
    if [ ! -d "$(readlink -f "$BASE/$A/$B")" ]; then
      echo "$_tag mkdir -p $BASE/$A/$B"
      #mkdir -p "$BASE/$A/$B"
    else
      echo "$_tag directory already exist"
    fi
    PROJECT_DIR="$BASE/$A/$B"
  fi

  return 0
}

is_absolute() {
  local _tag="[is_absolute]"
  if [[ "$1" =~ ^/ ]]; then
    echo "$_tag test : absolute path?"
    return 0
  fi
    echo "$_tag test: relative path?"
    return 1
}

check() {
  #
  # TODO convert $1 in readlink ?
  #
  local _tag="[check]"
  _resolved="$(readlink -f "$1")" # NEW

  #if [ -d "$1" ]; then
  #if [ -d "$(readlink -f "$1")" ]; then
  if [ -d "$_resolved" ]; then
    #echo "$_tag $1 exist"
    #if [ -r "$1" ] && [ -w "$1" ]; then
    if [ -r "$_resolved" ] && [ -w "$_resolved" ]; then
      echo "$_tag $1 is valid"
      PROJECT_DIR="$_resolved" 
      return 0
    else
      echo "$_tag missing rw permission on $_resolved"
      return 1
    fi
  else
    #
    # TODO inglobare il controllo is_absolute in is_valid ?
    # fattibile ma si perde il msg informativo...
    #
    if is_absolute "$1"; then   
      echo "$_tag cannot create new absolute path $1"
      echo "$_tag use relative path instead"  
      return 1
    else
      echo "$_tag relative path passed: $1"
    fi

    # check for invalid characters 
    #
    if ! is_valid $1; then
      echo "$_tag $1 is NOT valid"
      exit 1
    else
      echo "$_tag $1 is valid"
    fi

    if ! create_directory "$1"; then
      echo "$_tag Error creating $1" >&2
      return 1
    fi
    return 0
  fi
}

__check() {
  local _tag="[check]"
  local _resolved

  # Resolve symlinks 
  #_resolved="$(readlink -f "$1")" || {
  #  echo "$_tag cannot resolve path: $1" >&2
  #  return 1
  #}

  _resolved="$(readlink -m "$1")" 
  echo "$_tag resolved: $_resolved"

  if [ -d "$_resolved" ]; then
    if [ -r "$_resolved" ] && [ -w "$_resolved" ]; then
      echo "$_tag $1 is valid"
      PROJECT_DIR="$_resolved"  # Store the resolved path
      return 0
    else
      echo "$_tag missing rw permission on $1"
      return 1
    fi
  else
    if is_absolute "$_resolved"; then
      echo "$_tag cannot create new absolute path $1"
      echo "$_tag use relative path instead"
      return 1
    else
      echo "$_tag relative path passed: $_resolved"
    fi

    if ! is_valid "$_resolved"; then
      echo "$_tag $_resolved is NOT valid" >&2
      return 1  
    fi

    if ! create_directory "$_resolved"; then
      echo "$_tag Error creating $_resolved" >&2
      return 1
    fi

    PROJECT_DIR="$_resolved"
    return 0
  fi
}


is_valid() {

    local _tag="[is_valid]"
    local input="$1"

    # Condition 1: Only allow a-zA-Z0-9-_/. characters
    if [[ ! "$input" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
	echo "$_tag Condition 1 FAIL"
        return 1
    fi

    # Condition 2: Can't contain two consecutive dots or slashes
    if [[ "$input" =~ \.\. ]] || [[ "$input" =~ //// ]]; then
	echo "$_tag Condition 2 FAIL"
        return 1
    fi

    # Condition 3: Can't contain the sequence '/.'
    if [[ "$input" =~ //. ]]; then
	echo "$_tag Condition 3 FAIL"
        return 1
    fi

    # Condition 4: Can't begin or end with a dot or slash
    if [[ "$input" =~ ^[.//] ]] || [[ "$input" =~ [.//]$ ]]; then
	echo "$_tag Condition 4 FAIL"
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

