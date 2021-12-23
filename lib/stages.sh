#!/bin/bash

#{{begin_exclude}}#
if [[ -n "${_STAGES_SH_INCLUDED}" ]]; then
    return
fi
_STAGES_SH_INCLUDED=1
_STAGES_SH="${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}"
_STAGES_LIB_DIR="$(cd "$(dirname "${_STAGES_SH}")" )"
source "${_STAGES_LIB_DIR}/io.sh"
#{{end_exclude}}#

check_stage() {
    local STAGE_NAME="$1"
    local STATE_FILE="${STATE_DIR}/${STAGE_NAME}"
    if [[ ! -f "${STATE_FILE}" ]]; then
        return 1
    fi

    NOW=$(date "+%s")
    TS="$( grep -E '^[0-9]+$' "${STATE_FILE}" )"

    if [[ -z "${TS}" ||  "${TS}" -gt "${NOW}" ]]; then
        abort "state file is too new or invalid, rerunning stage ${STAGE_NAME}"
    fi

    if "${FORCE}"; then
        abort "rerunning stage ${STAGE_NAME}"
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
