#!/bin/bash

run_stage() {
    local LOG_DIR="${SETUP_HOME}/logs"
    local KIVY_DIR="${SETUP_HOME}/.kivy"
    local RC_CONFIG_DIR="${SETUP_HOME}/.config/racecapture"

    sudo -u "${SETUP_USER}" \
         mkdir -p "${LOG_DIR}" "${KIVY_DIR}" "${RC_CONFIG_DIR}"
}
