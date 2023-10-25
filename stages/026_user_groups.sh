#!/bin/bash

run_stage() {
    report "adding user ${SETUP_USER} to groups"

    local GROUP_NAMES=(render video input dialout)
    for GROUP_NAME in "${GROUP_NAMES[@]}"; do
        adduser "${SETUP_USER}" "${GROUP_NAME}" \
            || abort "failed to add ${SETUP_USER} to group ${GROUP_NAME}"
    done
}
