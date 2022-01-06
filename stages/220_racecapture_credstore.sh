#!/bin/bash

run_stage() {
    if [[ ! -d "${SETUP_HOME}/.ssh" ]]; then
        # Create the ssh keys if they don't exist
        report "generating ssh keys for podium live credential store"

        # shellcheck disable=2002
        cat /dev/zero | sudo -u "${SETUP_USER}" ssh-keygen -q -N "" >/dev/null
    fi
}
