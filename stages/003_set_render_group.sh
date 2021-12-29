#!/bin/bash

run_stage() {
    report "adding user ${SETUP_USER} to group render"

    adduser "${SETUP_USER}" render || abort "failed to add ${SETUP_USER} to group render"
}
