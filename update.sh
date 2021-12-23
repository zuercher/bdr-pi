#!/bin/bash

# fail on unset variables
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" || exit; pwd)"

source "${SCRIPT_DIR}/lib/io.sh"

if [[ "${BDR_DIR}" != "${SCRIPT_DIR}" ]]; then
    abort "update.sh should not be run directly; use setup.sh"
fi

# We expect these to be passed in by setup.sh
if [[ -z "${SETUP_USER}" || -z "${SETUP_HOME}" || ! -d "${SETUP_HOME}" ]]; then
    abort "update.sh should not be run directly; use setup.sh"
fi

# Check if stdin is a terminal
if [ ! -t 0 ]; then
    abort "scripts must be run from a terminal (use bash -c \"$(curl ...)\" instead of curl ... | bash)"
fi

source "${SCRIPT_DIR}/lib/reboot.sh"

if reboot_configured; then
    reboot_clear
fi

FORCE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=true
            ;;
        *)
            abort "unknown argument $1"
            ;;
    esac
    shift
done

export SETUP_USER
export SETUP_HOME

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

    if "${REBOOT_REQUIRED}"; then
        report "rebooting..."
        shutdown -r now
        exit 0
    fi
done
