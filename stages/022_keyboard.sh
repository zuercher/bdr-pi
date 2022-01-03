#!/bin/bash

run_stage() {
    local LAYOUT="${BDRPI_KEYBOARD_LAYOUT:-us}"

    local CONFIG="/etc/default/keyboard"

    if grep -q -F "XKBLAYOUT=\"${LAYOUT}\"" "${CONFIG}"; then
        return 0
    fi

    report "setting keyboard layout to ${LAYOUT}"

    sed -i "s/^\s*XKBLAYOUT=\S*/XKBLAYOUT=\"${LAYOUT}\"/" "${CONFIG}"

    reboot_required
}
