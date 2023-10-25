#!/bin/bash

run_stage() {
    local TIMEZONE="${BDRPI_TIMEZONE:-America/Los_Angeles}"

    report "setting timezone to ${TIMEZONE}"

    timedatectl set-timezone "${TIMEZONE}" || abort "failed to set timezone to ${TIMEZONE}"
}
