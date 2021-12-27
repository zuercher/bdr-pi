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

source "${SCRIPT_DIR}/lib/stages.sh"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            stage_force_all
            ;;
        *)
            abort "unknown argument $1"
            ;;
    esac
    shift
done

export SETUP_USER
export SETUP_HOME

stage_run
