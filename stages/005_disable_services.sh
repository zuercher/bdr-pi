#!/bin/bash

run_stage() {
    report "disabling man-db timer"
    systemctl disable man-db.timer

    report "disabling bluetooth services"
    systemctl disable hciuart.service
    systemctl disable bluetooth.service
}
