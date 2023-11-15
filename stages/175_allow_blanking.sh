#!/bin/bash

run_stage() {
    perror "configuring backlight for user-level access"

    # make it so any user can enable/disable the backlight
    echo "SUBSYSTEM==\"backlight\", RUN+=\"/bin/chmod 0666 /sys/class/backlight/%k/brightness /sys/class/backlight/%k/bl_power\"" > /etc/udev/rules.d/99-backlight.rules

    reboot_required
}
