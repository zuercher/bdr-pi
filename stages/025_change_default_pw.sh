#!/bin/bash

run_stage() {
    # check if sshd is ready -- generally an indication that the check that generates /run/sshwarn
    # has completed.
    report "checking for running sshd"
    local IDENT
    local SSH_RUNNING="false"
    local N="0"
    while true; do
        IDENT="$(nc -w 5 localhost 22 <<< "\0" )"
        if [[ "${IDENT}" =~ "SSH" ]]; then
            SSH_RUNNING="true"
            break
        fi
        N=$((N+1))
        if [[ "${N}" -gt 30 ]]; then
            report "didn't find sshd after 30 seconds, giving up"
            break
        fi
        sleep 1
    done

    if ! "${SSH_RUNNING}"; then
        report "ssh isn't running, skipping default password check"
        return 0
    fi

    if [[ ! -e /run/sshwarn ]]; then
        report "default password was already changed, skipping"
        return 0
    fi

    report "default password is set, let's change it"

    if ! passwd "${SETUP_USER}"; then
        echo "password unchanged"
    fi
}
