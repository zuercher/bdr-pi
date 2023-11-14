#!/bin/bash

run_stage() {
    local LAYOUT="${BDRPI_KEYBOARD_LAYOUT:-us}"
    local CTRL_OPT="ctrl:nocaps"
    local CONFIG="/etc/default/keyboard"

    if (source "${CONFIG}"; [[ "${XKBLAYOUT}" == "${LAYOUT}" ]]) &&
           (source "${CONFIG}"; echo "${XKBOPTIONS}" | grep -q "${CTRL_OPT}"); then
        report "keyboard layout and options are already set"
        return 0
    fi

    report "setting keyboard layout to ${LAYOUT}"

    sed_inplace "s/^\s*XKBLAYOUT=\S*/XKBLAYOUT=\"${LAYOUT}\"/" "${CONFIG}"

    report "setting ${CTRL_OPT} (caps lock is control)"

    local OPTIONS="$(source "${CONFIG}"; echo "${XKBOPTIONS}")"
    if [[ -z "${OPTIONS}" ]]; then
        OPTIONS="${CTRL_OPT}"
    else
        OPTIONS="${OPTIONS},${CTRL_OPT}"
    fi
    sed_inplace "s/^\s*XKBOPTIONS=\S*/XKBOPTIONS=\"${OPTIONS}\"/" "${CONFIG}"

    reboot_required
}
