#!/bin/bash

run_stage() {
    local REBOOT_FILE="${SETUP_HOME}/.bdrpi-reboot-on-first-boot"
    if [[ -f "${REBOOT_FILE}" ]]; then
        rm -f "${REBOOT_FILE}"

        reboot_required

        perror "Rebooting after imaging."
    else
        perror "No reboot scheduled after imaging."
    fi
}
