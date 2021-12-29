#!/bin/bash

run_stage() {
    if service ssh status | grep -q inactive; then
        report "ssh service not active"
        report "checking if initial key generation is in process..."
        while [[ -e /var/log/regen_ssh_keys.log ]] && ! grep -q "^finished" /var/log/regen_ssh_keys.log; do
            report "... not yet, will check again in 30 seconds"
            sleep 30
        done
        report "OK: enabling SSH server"
        ssh-keygen -A || abort "error generating host keys"
        update-rc.d ssh enable || abort "unable to enable ssh service"
        update-rc.d ssh start || abort "unable to start ssh service"
    else
        report "ssh service already active, skipping"
    fi
}
