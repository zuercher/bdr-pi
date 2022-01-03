#!/bin/bash

run_stage() {
    if [[ ! -e /run/sshwarn ]]; then
        report "default password was already changed, skipping"
        return 0
    fi

    report "default password is set, let's change it"

    if ! passwd "${SETUP_USER}"; then
        echo "password unchanged"
    fi
}
