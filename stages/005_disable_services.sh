#!/bin/bash

run_stage() {
    report "disabling and masking man-db timer"
    systemctl disable man-db.service
    systemctl disable man-db.timer
    systemctl mask man-db.service

    report "disabling bluetooth services"
    systemctl disable hciuart.service
    systemctl disable bluetooth.service

    report "disabling and masking unattended upgrades"
    systemctl disable apt-daily.service apt-daily-upgrade.service
    systemctl disable apt-daily.timer apt-daily-upgrade.timer
    systemctl mask apt-daily.service apt-daily-upgrade.service
}
