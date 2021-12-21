#!/bin/bash

# fail on unset variables
set -u

abort() {
    printf "%s\n" "$@"
    exit 1
}

# prompt $1=default-value $2... prompt
prompt() {
    local ANSWER
    local DEFAULT="$1"
    shift

    if "${NOTERM:-false}"; then
        echo "no terminal available -- assuming ${DEFAULT} for $*"
        echo "${DEFAULT}"
        return 0
    fi

    read -er -p "$* [${DEFAULT}]: " ANSWER
    if [ -z "${ANSWER}" ]; then
        ANSWER="${DEFAULT}"
    fi
    echo "${ANSWER}"
}

push_dir() {
    pushd "${1}" >/dev/null || abort "could not change to ${1}"
}

pop_dir() {
    popd || abort "could not pop dir"
}

installed() {
    local BINARY="$1"
    hash "${BINARY}" 2> /dev/null
    return $?
}

reboot_required() {
    # TODO
    echo "scheduling reboot"
}

check_stage() {
    local STAGE_NAME="$1"
    local STATE_FILE="${STATE_DIR}/${STAGE_NAME}"
    if [[ ! -f "${STATE_FILE}" ]]; then
        return 1
    fi

    NOW=$(date "+%s")
    TS="$( grep -E '^[0-9]+$' "${STATE_FILE}" )"

    if [[ -z "${TS}" ||  "${TS}" -gt "${NOW}" ]]; then
        echo "state file is too new or invalid, rerunning stage ${STAGE_NAME}"
        return 1
    fi

    if "${FORCE}"; then
        echo "rerunning stage ${STAGE_NAME}"
        return 1
    fi

    return 0
}

start_stage() {
    local STAGE_NAME="$1"
    rm -f "${STATE_DIR}/${STAGE_NAME}"
    echo "stage ${STAGE_NAME}"
}

complete_stage() {
    local STAGE_NAME="$1"
    date "+%s" >"${STATE_DIR}/${STAGE_NAME}"
}

report() {
    printf "  %s: %s\n" "${STAGE_NAME}" "$@"
}

SCRIPT_DIR="$(cd "$(dirname "$0")" || exit; pwd)"
if [[ "${BDR_DIR}" != "${SCRIPT_DIR}" ]]; then
    abort "update.sh should not be run directly; use setup.sh"
fi

TEST=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --test)
            TEST=true
            ;;
        --force)
            FORCE=true
            ;;
        *)
            abort "unknown argument $1"
            ;;
    esac
    shift
done

if "${TEST}"; then
    echo "*** TEST MODE ***"
fi
export TEST

# Check if stdin is a terminal
NOTERM=false
if [ ! -t 0 ]; then
    NOTERM=true
fi
export NOTERM

SETUP_USER="${SUDO_USER:-$(who -m | awk '{ print $1 }')}"
export SETUP_USER

STATE_DIR="${BDR_DIR}/state"
mkdir -p "${STATE_DIR}" || abort "could not create state dir ${STATE_DIR}"

declare -a STAGES
while IFS= read -r STAGE; do
    STAGES+=("$STAGE")
done < <(find "${BDR_DIR}/stages" -type f -print | sort)

if [[ "${#STAGES[@]}" == 0 ]]; then
    abort "no installation stages found"
fi

for STAGE in "${STAGES[@]}"; do
    STAGE_NAME="$(basename -s .sh "${STAGE}")"

    if check_stage "${STAGE_NAME}"; then
        echo "skipping ${STAGE_NAME}, already complete"
        continue
    fi

    start_stage "${STAGE_NAME}"
    # shellcheck disable=SC1090
    source "${STAGE}"
    run_stage || abort "stage ${STAGE_NAME} failed"
    complete_stage "${STAGE_NAME}"
done
