#!/bin/bash

run_stage() {
    report "adding user ${SETUP_USER} to group render"

    local GROUPS=(render video input dialout)
    for GROUP in "${GROUPS[@]}"; do
        adduser "${SETUP_USER}" "${GROUP}" \
            || abort "failed to add ${SETUP_USER} to group ${GROUP}"
    done
}
