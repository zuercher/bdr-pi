#!/bin/bash

#{{begin_exclude}}#
if [[ -n "${_STAGES_SH_INCLUDED:-}" ]]; then
    return
fi
_STAGES_SH_INCLUDED=1
_STAGES_SH="${BASH_SOURCE[0]}"
_STAGES_LIB_DIR="$(cd "$(dirname "${_STAGES_SH}")" && pwd)"
source "${_STAGES_LIB_DIR}/io.sh"
source "${_STAGES_LIB_DIR}/reboot.sh"
#{{end_exclude}}#

_FORCE_STAGES=false
_STATE_DIR="${BDR_DIR}/.state"

# stage_force_all forces all stages to be executed even if the state
# directory indicates it's already been run.
stage_force_all() {
    _FORCE_STAGES=true
}

# _stage_init initializes stages
_stage_init() {
    mkdir -p "${_STATE_DIR}" || abort "could not create state dir ${_STATE_DIR}"
}

# stage_list lists all stages, in order.
_stage_list() {
    NUM_STAGES="$(find "${BDR_DIR}/stages" -type f -print | wc -l)"
    if [[ "$NUM_STAGES" -eq 0 ]]; then
        abort "no installation stages found"
    fi

    find "${BDR_DIR}/stages" -type f -print | sort
}

# stage_name $1 extracts the stage's name from its path.
_stage_name() {
    local STAGE="$1"
    basename -s .sh "${STAGE}"
}

_stage_check() {
    local STAGE_NAME="$1"
    local STATE_FILE="${_STATE_DIR}/${STAGE_NAME}"
    if [[ ! -f "${STATE_FILE}" ]]; then
        return 1
    fi

    NOW=$(date "+%s")
    TS="$( grep -E '^[0-9]+$' "${STATE_FILE}" )"

    if [[ -z "${TS}" ||  "${TS}" -gt "${NOW}" ]]; then
        abort "state file is too new or invalid, rerunning stage ${STAGE_NAME}"
    fi

    if "${_FORCE_STAGES}"; then
        report "rerunning stage ${STAGE_NAME}"
    fi

    return 0
}

_stage_start() {
    local STAGE_NAME="$1"
    rm -f "${_STATE_DIR}/${STAGE_NAME}"
    echo "stage ${STAGE_NAME}"
}

_stage_complete() {
    local STAGE_NAME="$1"
    date "+%s" >"${_STATE_DIR}/${STAGE_NAME}"
}

stage_run() {
    declare -a _STAGES
    while IFS= read -r _STAGE; do
        _STAGES+=("${_STAGE}")
    done < <(_stage_list)

    for _STAGE in "${_STAGES[@]}"; do
        STAGE_NAME="$(_stage_name "${_STAGE}")"

        if _stage_check "${STAGE_NAME}"; then
            echo "skipping ${STAGE_NAME}, already complete"
            continue
        fi

        _stage_start "${STAGE_NAME}"

        # shellcheck disable=SC1090
        source "${_STAGE}"
        run_stage || abort "stage ${STAGE_NAME} failed"
        _stage_complete "${STAGE_NAME}"

        if reboot_is_required; then
            # shellcheck disable=2162
            read -t 5 -p "rebooting in 5s (press ENTER to reboot immediately) " || echo
            report "rebooting now"
            shutdown -r now
            exit 0
        fi
    done
}
