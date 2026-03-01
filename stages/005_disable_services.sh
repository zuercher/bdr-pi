#!/bin/bash

_systemctl_disble() {
    local GROUP="$1"
    shift

    report "disabling and masking ${GROUP}"

    local UNIT
    for UNIT in "$@"; do
        systemctl disable --now "${UNIT}"

        # block activation
        systemctl mask "${UNIT}"
    done
}

run_stage() {
    _systemctl_disable "man-db timer" man-db.service man-db.timer

    _systemctl_disable "bluetooth services" hciuart.service bluetooth.service

    _systemctl_disable "unattended upgrades" \
                       apt-daily.service \
                       apt-daily-upgrade.service \
                       apt-daily.timer \
                       apt-daily-upgrade.timer

    _systemctl_disble "modem manager" ModemManager.service

    _systemctl_disable "network wait" NetworkManager-wait-online.service
    _systemctl_disable "network dispatcher" NetworkManager-dispatcher.service

    _systemctl_disable "cloud init services" \
                       cloud-init-main.service \
                       cloud-init-network.service \
                       cloud-init-local.service

    report "removing boot dep on NetworkManager"
    rm /etc/systemd/system/multi-user.target.wants/NetworkManager.service

    sytemctl daemon-reload
}
