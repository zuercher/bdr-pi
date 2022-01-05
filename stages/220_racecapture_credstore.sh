#!/bin/bash

run_stage() {
    if [[ ! -d "${SETUP_HOME}/.ssh" ]]; then
        # Create the ssh keys if they don't exist
        # shellcheck disable=2002
        cat /dev/zero | sudo -u "${SETUP_USER}" ssh-keygen -q -N ""
    fi
}
